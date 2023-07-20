const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const ztg = @import("init.zig");
const ea = @import("entity_array.zig");
const ca = @import("component_array.zig");

const Allocator = std.mem.Allocator;
const TypeMap = ztg.meta.TypeMap;
const TypeBuilder = ztg.meta.TypeBuilder;

pub const CommandsGiveEntError = error{UnregisteredComponent} || ca.Error;

const WorldInfo = struct {
    const use_c_alloc = false;

    alloc: std.mem.Allocator,
    frame_arena: std.heap.ArenaAllocator = undefined,
    rng: std.rand.DefaultPrng,

    fn init(alloc: std.mem.Allocator) !*WorldInfo {
        var self = try alloc.create(WorldInfo);
        self.* = .{
            .alloc = alloc,
            .rng = std.rand.DefaultPrng.init(@bitCast(std.time.milliTimestamp())),
        };
        self.frame_arena = std.heap.ArenaAllocator.init(self.allocator());
        return self;
    }

    fn deinit(self: *WorldInfo) void {
        self.frame_arena.deinit();
        self.alloc.destroy(self);
    }

    inline fn allocator(self: *WorldInfo) std.mem.Allocator {
        return if (comptime use_c_alloc) std.heap.c_allocator else self.alloc;
    }
};

pub fn World(comptime wb: WorldBuilder) type {
    if (wb.max_entities == 0) @compileError("Cannot have max_ents == 0.");

    const Resources = wb.resources.Build();
    const MinEntityIndex = std.meta.Int(.unsigned, @typeInfo(std.math.IntFittingRange(0, wb.max_entities)).Int.bits + 1);
    const comp_types_len = wb.comp_types.types.len;

    return struct {
        const Self = @This();

        const StagesList = @import("stages.zig").Init(wb.stage_defs, Self);

        const ComponentArray = ca.ComponentArray(MinEntityIndex, wb.max_entities);
        const EntityArray = ea.EntityArray(wb.max_entities);

        info: *WorldInfo,

        alloc: Allocator,
        frame_arena: *std.heap.ArenaAllocator,
        frame_alloc: Allocator,
        rand: std.rand.Random,

        next_ent: ztg.Entity = 0,
        entities: EntityArray,

        comp_arrays: [comp_types_len]ComponentArray = undefined,
        resources: Resources = .{},

        event_pools: EventPools(wb.event_types),
        changes_list: ChangesList,
        changes_queue: ChangeQueue,

        /// User must call `.deinit()` once the world is to be descoped. (in a defer block preferrably)
        /// All systems that request an `Allocator` will get the one passed here.
        ///
        /// Also runs the `.init` stage, useful for things that will only run once and need to be done before
        /// anything else, without relying on most anything else (Allocator and Random are available).
        ///
        /// Example:
        /// ```zig
        /// var world = MyWorld.init(alloc);
        /// defer world.deinit();
        /// ```
        pub fn init(allocator: std.mem.Allocator) !Self {
            if (comptime builtin.mode == .Debug) {
                //std.debug.print("Entity has utp {}\n", .{ztg.meta.uniqueTypePtr(ztg.Entity)});
                //inline for (wb.comp_types.types) |T| {
                //    @setEvalBranchQuota(20_000);
                //    std.debug.print("{s} has utp {}\n", .{ @typeName(T), ztg.meta.uniqueTypePtr(T) });
                //}

                if (wb.warnings.len > 0)
                    ztg.log.warn("\n====== World was constructed with warnings: ======\n" ++ wb.warnings, .{});
            }

            var info = try WorldInfo.init(allocator);

            const alloc = info.allocator();
            const frame_alloc = info.frame_arena.allocator();

            var self: Self = .{
                .alloc = alloc,
                .info = info,
                .frame_arena = &info.frame_arena,
                .frame_alloc = frame_alloc,
                .rand = info.rng.random(),

                .entities = EntityArray.init(),

                .event_pools = EventPools(wb.event_types).init(),
                .changes_list = ChangesList.init(frame_alloc),
                .changes_queue = ChangeQueue.init(frame_alloc),
            };

            if (comptime wb.comp_types.types.len > 0) {
                var last_successful_init_loop: usize = 0;
                errdefer {
                    for (0..last_successful_init_loop) |i| {
                        self.comp_arrays[i].deinit();
                    }
                }

                inline for (wb.comp_types.types, 0..) |CT, i| {
                    @setEvalBranchQuota(20_000);
                    self.comp_arrays[i] = try ComponentArray.init(alloc, CT);
                    last_successful_init_loop = i;
                }
            }

            self.getResPtr(Allocator).* = allocator;
            self.getResPtr(std.rand.Random).* = info.rng.random();

            try self.runStage(.init);

            return self;
        }

        fn deinit_errCallback(comptime msg: []const u8) fn (anyerror) void {
            return struct {
                fn f(err: anyerror) void {
                    ztg.log.err(msg, .{err});
                }
            }.f;
        }

        pub fn deinit(self: *Self) void {
            self.postSystemUpdate() catch |err| {
                ztg.log.err("Found error {} while trying to clean up world for deinit.", .{err});
            };
            self.cleanForNextFrame();

            self.runStageCatchErrors(.deinit, deinit_errCallback("Encountered error {} in cleanup stage")) catch |err| switch (err) {
                error.OutOfMemory => {
                    ztg.log.err("Encountered OOM error in deinit stage. Some systems may not have been run!", .{});
                },
                else => {},
            };

            self.event_pools.deinit(self.frame_alloc);
            self.changes_queue.deinit();
            self.changes_list.deinit();

            inline for (wb.comp_types.types, &self.comp_arrays) |CT, *comp_arr| {
                if (comptime @hasDecl(CT, "onRemove")) {
                    if (comptime @sizeOf(CT) > 0) {
                        var comp_iter = comp_arr.iterator();
                        while (comp_iter.nextAs(CT)) |comp| self.invokeOnRemoveForComponent(CT, comp);
                    } else {
                        for (0..comp_arr.len()) |_| self.invokeOnRemoveForComponent(CT, &CT{});
                    }
                }
                comp_arr.deinit();
            }

            self.info.deinit();
        }

        /// If you are going to run multiple stages in a row, consider `.runStageList()`
        ///
        /// Example:
        /// ```zig
        /// try world.runStage(.render);
        /// ```
        pub inline fn runStage(self: *Self, comptime stage_id: StagesList.StageField) anyerror!void {
            try StagesList.runStage(self, stage_id, false, void{});
        }

        /// For discarding errors in systems so that every system runs. Useful for stages
        /// that are run at the end to free resources.
        /// Calls errCallback whenever an error occurs and passes it the error.
        ///
        /// Example:
        /// ```zig
        /// try world.runStage(.render);
        /// ```
        pub inline fn runStageCatchErrors(self: *Self, comptime stage_id: StagesList.StageField, comptime errCallback: fn (anyerror) void) !void {
            return StagesList.runStage(self, stage_id, true, errCallback);
        }

        /// If you are going to run multiple stages in a row, consider `.runStageNameList()`
        ///
        /// Example:
        /// ```zig
        /// world.runStageByName("render");
        /// ```
        pub inline fn runStageByName(self: *Self, stage_name: []const u8) anyerror!void {
            try StagesList.runStageRuntime(self, stage_name);
        }

        fn commands_runStageFn(ptr: *anyopaque, stage_name: []const u8) anyerror!void {
            try commandsCast(ptr).runStageByName(stage_name);
        }

        /// Example:
        /// ```zig
        /// try world.runStageList(&.{ .ping_send, .ping_receive, .ping_read });
        /// ```
        pub fn runStageList(self: *Self, comptime stage_ids: []const StagesList.StageField) anyerror!void {
            inline for (stage_ids) |sid| {
                try runStage(self, sid);
            }
        }

        /// Example:
        /// ```zig
        /// try world.runStageList(&.{ "ping_send", "ping_receive", "ping_read" });
        /// ```
        pub fn runStageNameList(self: *Self, stage_ids: []const []const u8) anyerror!void {
            for (stage_ids) |sid| {
                try runStageByName(self, sid);
            }
        }

        /// For internal use, do not call
        pub fn postSystemUpdate(self: *Self) anyerror!void {
            if (comptime comp_types_len == 0) return;

            for (self.changes_queue.items) |rem| {
                switch (rem) {
                    .added_component => |comp| {
                        var arr = &self.comp_arrays[comp.component_id];
                        try arr.assignData(comp.ent, comp.data);
                    },
                    .removed_ent => |ent| try self.removeEntAndAssociatedComponents(ent),
                    .removed_component => |rem_comp| {
                        const utp = self.comp_arrays[rem_comp.component_id].component_utp;
                        const comp = self.comp_arrays[rem_comp.component_id].get(rem_comp.ent) orelse {
                            ztg.log.err("Trying to remove a component of type {s} from ent {} when ent does not have that component", .{ wb.comp_types.nameFromUtp(utp), rem_comp.ent });
                            continue;
                        };
                        try self.invokeOnRemoveForComponentByUtp(comp, utp);
                        self.comp_arrays[rem_comp.component_id].swapRemove(rem_comp.ent);
                    },
                }
            }

            self.changes_queue.clearAndFree();
        }

        pub fn removeEntAndAssociatedComponents(self: *Self, ent: ztg.Entity) anyerror!void {
            const res = self.entities.swapRemoveEnt(ent);
            if (res == false) {
                ztg.log.warn("Tried to remove ent {} which does not exist.", .{ent});
                return;
            }

            for (&self.comp_arrays) |*list| {
                if (list.get(ent)) |comp| {
                    try self.invokeOnRemoveForComponentByUtp(comp, list.component_utp);
                    _ = list.swapRemove(ent);
                }
            }
        }

        fn invokeOnRemoveForComponent(self: *Self, comptime T: type, comp: *T) anyerror!void {
            const member_fn_type = comptime util.isMemberFn(T, T.onRemove);
            const fn_params = @typeInfo(@TypeOf(T.onRemove)).Fn.params;
            const params = self.initParamsForSystem(if (comptime member_fn_type != .non_member) fn_params[1..] else fn_params) catch {
                @panic("Failed to get args for deinit system for type `" ++ @typeName(T) ++ "`.");
            };

            const member_params = comptime switch (member_fn_type) {
                .non_member => .{},
                .by_value => .{comp.*},
                .by_ptr => .{comp},
            };

            if (comptime ztg.meta.canReturnError(T.onRemove)) {
                try @call(.auto, T.onRemove, member_params ++ params);
            } else {
                @call(.auto, T.onRemove, member_params ++ params);
            }
        }

        fn invokeOnRemoveForComponentByUtp(self: *Self, comp: *anyopaque, comp_utp: ztg.meta.UniqueTypePtr) anyerror!void {
            inline for (wb.comp_types.types) |CT| {
                if (comptime @hasDecl(CT, "onRemove") and ztg.meta.uniqueTypePtr(CT) == comp_utp) {
                    try invokeOnRemoveForComponent(self, CT, if (comptime @sizeOf(CT) == 0) &CT{} else @ptrCast(@alignCast(comp)));
                }
            }
        }

        /// Call when a "frame" of your game loop has completed, most commonly after the draw call
        ///
        /// Example:
        ///
        /// ```zig
        /// try world.runLoadStages();
        ///
        /// while(game.isRunning) {
        ///   try world.runUpdateStages();
        ///   try world.runDrawStages();
        ///   world.cleanForNextFrame();
        /// }
        /// ```
        pub fn cleanForNextFrame(self: *Self) void {
            self.changes_list.clearAndFree();
            self.event_pools.clear();
            if (!self.frame_arena.reset(.free_all)) ztg.log.err("Failed to reset frame arena.", .{});
        }

        /// Returns the next free index for components. Invalidated after hitting the entity limit,
        /// in which all entity ID's are reassigned and condensed. You shouldnt need to store this.
        ///
        /// If the entity limit is exceeded and the list cannot be condensed, there are a few outcomes
        /// depending on your `WorldBuilder.on_ent_overflow` option:
        ///
        /// `.crash` => (default) invokes the crash function, which will most likely panic.
        /// `.overwrite_last` => returns the last entity in the entity list, after removing all of its components.
        /// `.overwrite_first` => returns the first entity in the entity list, after removing all of its components
        pub fn newEnt(self: *Self) Allocator.Error!ztg.Entity {
            if (self.next_ent + 1 > wb.max_entities) {
                const new_next_ent = cleanEntList(&self.comp_arrays, &self.entities, &self.changes_list);

                if (new_next_ent) |ne| {
                    self.entities.append(ne);
                    self.next_ent = ne + 1;
                    return ne;
                } else {
                    return handleEntOverflow(self);
                }
            }

            try self.changes_list.append(.{ .added_ent = self.next_ent });
            self.entities.append(self.next_ent);
            self.next_ent += 1;
            return self.next_ent - 1;
        }

        inline fn handleEntOverflow(self: *Self) ztg.Entity {
            switch (wb.on_ent_overflow) {
                .crash => self.crash(std.fmt.comptimePrint("Exceeded entity limit of {}.", .{wb.max_entities}), .hit_ent_limit),
                .overwrite_last => {
                    const ent = self.entities.getEntityAt(self.entities.len - 1);
                    try self.reuseEntity(ent);
                    return ent;
                },
                .overwrite_first => {
                    const ent = self.entities.getEntityAt(0);
                    try self.reuseEntity(ent);
                    return ent;
                },
            }
        }

        fn reuseEntity(self: *Self, ent: ztg.Entity) !void {
            self.removeEntAndAssociatedComponents(ent);
            try self.changes_list.append(.{ .added_ent = self.next_ent });
            self.entities.append(ent);
        }

        fn commands_newEnt(ptr: *anyopaque) Allocator.Error!ztg.Entity {
            return commandsCast(ptr).newEnt();
        }

        fn cleanEntList(comp_arrays: []ComponentArray, entities: *EntityArray, changes_list: *ChangesList) ?usize {
            if (entities.len + 1 > wb.max_entities) {
                return null;
            }

            var old_ents = entities.*;
            entities.reset();

            var next_ent: ztg.Entity = 0;
            for (old_ents.constSlice(), 0..) |ent_en, i| {
                const ent = @intFromEnum(ent_en);

                if (ent == next_ent) {
                    entities.append(next_ent);
                    next_ent += 1;
                    continue;
                }

                // TODO: make sure this works.
                // if next entity was added this frame
                if (entities.len - i == changes_list.items.len) {
                    // update changes list to reflect new entity ids
                    for (changes_list.items, 0..) |*cl, j| {
                        switch (cl.*) {
                            .added_ent => |*ae| ae.* = next_ent + j,
                            else => {},
                        }
                    }
                }

                for (comp_arrays) |*arr| {
                    if (arr.contains(ent)) arr.reassign(ent, next_ent);
                }

                entities.append(next_ent);
                next_ent += 1;
            }

            return next_ent;
        }

        /// Queues the removal of all components in lists correlated with `ent`
        pub fn removeEnt(self: *Self, ent: ztg.Entity) Allocator.Error!void {
            try self.changes_queue.append(.{ .removed_ent = ent });
            try self.changes_list.append(.{ .removed_ent = ent });
        }

        fn commands_removeEnt(ptr: *anyopaque, ent: ztg.Entity) Allocator.Error!void {
            try commandsCast(ptr).removeEnt(ent);
        }

        /// Registers a component to the entity `ent`
        pub fn giveEnt(self: *Self, ent: ztg.Entity, comp: anytype) anyerror!void {
            if (comptime wb.comp_types.types.len == 0) return;
            const Component = @TypeOf(comp);
            const idx = comptime wb.comp_types.indexOf(Component) orelse @compileError("Tried to add Component " ++ @typeName(Component) ++ ", which was not registred.");

            try self.comp_arrays[idx].assign(ent, comp);
            try self.changes_list.append(.{ .added_component = .{
                .ent = ent,
                .component_utp = ztg.meta.uniqueTypePtr(Component),
            } });

            if (comptime @hasDecl(Component, "onAdded")) {
                const OnAddedFn = @TypeOf(Component.onAdded);

                const args = blk: {
                    const params = @typeInfo(OnAddedFn).Fn.params;
                    const params_start = if (comptime params[0].type.? == ztg.Entity) 1 else 0;
                    break :blk self.initParamsForSystem(params[params_start..]);
                };

                if (ztg.util.canReturnError(OnAddedFn)) {
                    try @call(.auto, Component.onAdded, args);
                } else {
                    @call(.auto, Component.onAdded, args);
                }
            }
        }

        /// Adds every field in the components object to its component list at the Entity index
        pub fn giveEntMany(self: *Self, ent: ztg.Entity, components: anytype) !void {
            if (comptime wb.comp_types.types.len == 0) return;
            inline for (std.meta.fields(@TypeOf(components))) |field| {
                try self.giveEnt(ent, @field(components, field.name));
            }
        }

        /// Returns true or false depending on whether `ent` has been assigned a component of type `Component`
        pub inline fn checkEntHas(self: *Self, ent: ztg.Entity, comptime Component: type) bool {
            return self.getEntsComponent(ent, Component) != null;
        }

        /// Returns an optional pointer to the component assigned to `ent`
        pub inline fn getEntsComponent(self: *Self, ent: ztg.Entity, comptime Component: type) ?*anyopaque {
            return self.comp_arrays[comptime wb.comp_types.indexOf(Component)].get(ent);
        }

        fn commands_giveEnt(ptr: *anyopaque, ent: ztg.Entity, component_utp: ztg.meta.UniqueTypePtr, data: *const anyopaque) CommandsGiveEntError!void {
            if (comptime wb.comp_types.types.len == 0) return;
            var self = commandsCast(ptr);
            const idx = wb.comp_types.fromUtp(component_utp) orelse return error.UnregisteredComponent;

            var arr = &self.comp_arrays[idx];

            if (arr.willResize()) {
                // we cant add the component right now, because then the pointers in the calling system will become invalid,
                // so we place the data on the heap and queue for its addition.
                var alloced_data = try self.frame_alloc.alloc(u8, arr.components_data.entry_size);
                @memcpy(alloced_data, @as([*]const u8, @ptrCast(data))[0..arr.components_data.entry_size]);
                try self.changes_queue.append(.{ .added_component = .{
                    .ent = ent,
                    .component_id = idx,
                    .data = alloced_data.ptr,
                } });
            } else {
                try arr.assignData(ent, data);
            }

            try self.changes_list.append(.{ .added_component = .{
                .ent = ent,
                .component_utp = component_utp,
            } });
        }

        fn commands_checkEntHas(ptr: *anyopaque, ent: ztg.Entity, component_utp: ztg.meta.UniqueTypePtr) bool {
            if (comptime wb.comp_types.types.len == 0) return false;
            var self = commandsCast(ptr);
            const idx = wb.comp_types.fromUtp(component_utp) orelse std.debug.panic("Tried to give an entity a component with utp {} but a component with that utp was not registered.", .{component_utp});
            return self.comp_arrays[idx].contains(ent);
        }

        /// Removes component of type `Component` from entity `ent`
        pub fn removeComponent(self: *Self, ent: ztg.Entity, comptime Component: type) ca.Error!void {
            if (comptime wb.comp_types.types.len == 0) return;
            try self.changes_queue.append(.{ .removed_component = .{ .ent = ent, .component_id = wb.comp_types.indexOf(Component) } });
        }

        /// Returns a copy of the resource T in this world
        pub fn getRes(self: Self, comptime T: type) T {
            if (comptime !wb.added_resources.has(T)) @compileError("World does not have resource of type " ++ @typeName(T));
            return @field(self.resources, std.fmt.comptimePrint("{}", .{wb.added_resources.indexOf(T).?}));
        }

        /// Returns a pointer to the resource T in this world
        pub fn getResPtr(self: *Self, comptime T: type) *T {
            if (comptime !wb.added_resources.has(T)) @compileError("World does not have resource of type " ++ @typeName(T));
            return &@field(self.resources, std.fmt.comptimePrint("{}", .{wb.added_resources.indexOf(T).?}));
        }

        fn commands_getResPtr(ptr: *anyopaque, utp: ztg.meta.UniqueTypePtr) *anyopaque {
            inline for (wb.added_resources.types, 0..) |T, i| {
                if (ztg.meta.uniqueTypePtr(T) == utp) return &@field(commandsCast(ptr).resources, std.fmt.comptimePrint("{}", .{i}));
            }
            std.debug.panic("Resource with utp {} is not in world.", .{utp});
        }

        pub fn commands(self: *Self) ztg.Commands {
            return .{
                .ctx = self,
                .vtable = &.{
                    .add_component_fn = Self.commands_giveEnt,
                    .remove_ent_fn = Self.commands_removeEnt,
                    .new_ent_fn = Self.commands_newEnt,
                    .run_stage_fn = Self.commands_runStageFn,
                    .get_res_fn = Self.commands_getResPtr,
                    .check_ent_has_fn = Self.commands_checkEntHas,
                },
            };
        }

        /// The method used for generating queries for systems
        ///
        /// Example:
        /// ```zig
        /// const q = try world.query(ztg.Query(.{ztg.base.Transform});
        /// for (q.items(0)) |tr| std.debug.print("{d:0.1}\n", .{tr.pos.x});
        /// ```
        pub fn query(self: *Self, alloc: std.mem.Allocator, comptime QT: type) !QT {
            if (QT.has_entities and QT.req_types.types.len == 0) return self.queryJustEntities(alloc, QT);

            var ents_qlists = try self.initQueryLists(
                alloc,
                QT.req_utps,
                QT.opt_utps,
                QT.with_utps,
                QT.without_utps,
            );
            const ents = ents_qlists[0];
            var qlists = ents_qlists[1];
            defer alloc.free(qlists);

            var out = try QT.init(alloc, ents.len);

            // Link qlists and the result query
            for (qlists) |*list| {
                switch (list.*) {
                    .required => list.required.out = out.comp_ptrs[list.required.out_idx],
                    .optional => list.optional.out = if (comptime QT.opt_types.types.len > 0) .{ .opt = out.opt_ptrs[list.optional.out_idx] } else unreachable,
                    else => {},
                }
            }

            out.len = fillQuery(
                ents,
                qlists,
                if (comptime QT.has_entities) out.entities else null,
            );

            return out;
        }

        // For queries which the only required type is Entity
        fn queryJustEntities(self: *Self, alloc: std.mem.Allocator, comptime QT: type) !QT {
            var out = try QT.init(alloc, self.entities.len);
            for (out.entities, self.entities.constSlice(), 0..) |*o, ent, i| {
                if (!self.checkEntAgainstOptions(@intFromEnum(ent), QT.options)) continue;
                o.* = @intFromEnum(ent);
                inline for (out.opt_ptrs, QT.opt_types.types) |opt_ptrs, O| opt_ptrs[i] = self.getListOf(O).get(@intFromEnum(ent));
            }
            out.len = self.entities.len;
            return out;
        }

        fn checkEntAgainstOptions(self: *Self, ent: ztg.Entity, options: anytype) bool {
            inline for (options) |OT| {
                if (@hasDecl(OT, "QueryWith")) {
                    if (!self.getListOf(OT.QueryWith).contains(ent)) return false;
                } else if (@hasDecl(OT, "QueryWithout")) {
                    if (self.getListOf(OT.QueryWithout).contains(ent)) return false;
                }
            }
            return true;
        }

        const QueryList = union(enum) {
            required: struct {
                array: *const ComponentArray,
                out_idx: usize,
                out: []*anyopaque = undefined,
            },
            optional: struct {
                array: *const ComponentArray,
                out_idx: usize,
                out: []?*anyopaque = undefined,
            },
            with: *const ComponentArray,
            without: *const ComponentArray,

            pub inline fn appendEnt(self: *QueryList, idx: usize, ent: usize) bool {
                switch (self.*) {
                    .required => |req| {
                        req.out[idx] = req.array.get(ent) orelse return false;
                        return true;
                    },
                    .optional => |opt| {
                        opt.out[idx] = opt.array.get(ent);
                        return true;
                    },
                    .with => |array| return array.contains(ent),
                    .without => |array| return !array.contains(ent),
                }
            }
        };

        fn initQueryLists(
            self: *Self,
            alloc: std.mem.Allocator,
            req_utps: []const ztg.meta.UniqueTypePtr,
            opt_utps: []const ztg.meta.UniqueTypePtr,
            with_utps: []const ztg.meta.UniqueTypePtr,
            without_utps: []const ztg.meta.UniqueTypePtr,
        ) !struct { []const ztg.Entity, []QueryList } {
            var smallest: *ComponentArray = self.assertListFromUtp(req_utps[0]);

            var lists = try std.ArrayList(QueryList).initCapacity(alloc, req_utps.len + opt_utps.len + with_utps.len + without_utps.len);
            lists.appendAssumeCapacity(QueryList{ .required = .{
                .array = smallest,
                .out_idx = 0,
            } });

            for (req_utps[1..], 1..) |utp, i| {
                const check = self.assertListFromUtp(utp);
                lists.appendAssumeCapacity(QueryList{ .required = .{
                    .array = check,
                    .out_idx = i,
                } });

                if (check.len() < smallest.len()) smallest = check;
            }

            for (opt_utps, 0..) |utp, i| {
                lists.appendAssumeCapacity(QueryList{ .optional = .{
                    .array = self.assertListFromUtp(utp),
                    .out_idx = i,
                } });
            }

            for (with_utps) |utp| {
                const check = self.assertListFromUtp(utp);
                lists.appendAssumeCapacity(QueryList{ .with = check });

                if (check.len() < smallest.len()) smallest = check;
            }

            for (without_utps) |utp| {
                const check = self.assertListFromUtp(utp);
                lists.appendAssumeCapacity(QueryList{ .without = check });
            }

            return .{ smallest.entities.items, try lists.toOwnedSlice() };
        }

        fn fillQuery(checked_entities: []const ztg.Entity, qlists: []QueryList, entities_out: ?[]ztg.Entity) usize {
            var len: usize = 0;
            ents_loop: for (checked_entities) |ent| {
                for (qlists) |*list| {
                    if (!list.appendEnt(len, ent)) continue :ents_loop;
                    if (entities_out) |eout| eout[len] = ent;
                }
                len += 1;
            }
            return len;
        }

        fn InitParamsForSystemOut(comptime params: []const std.builtin.Type.Fn.Param) type {
            var types: []const type = &.{};
            for (params) |p| types = types ++ .{p.type.?};
            return std.meta.Tuple(types);
        }

        /// Generates the arguments tuple for a desired system based on its parameters.
        /// You shouldn't need to use this, just add the function to the desired stage.
        ///
        /// Example:
        /// ```zig
        /// const params = try world.initParamsForSystem(@typeInfo(@TypeOf(myFunction)).Fn.params);
        /// defer world.deinitParamsForSystem(params);
        ///
        /// @call(.auto, myFunction, params);
        /// ```
        pub fn initParamsForSystem(self: *Self, comptime params: []const std.builtin.Type.Fn.Param) !InitParamsForSystemOut(params) {
            if (comptime params.len == 0) return .{};
            var out: InitParamsForSystemOut(params) = undefined;
            inline for (out, 0..) |param, i| {
                out[i] = try self.initParam(@TypeOf(param));
            }
            return out;
        }

        inline fn initParam(self: *Self, comptime T: type) !T {
            const is_container = comptime std.meta.trait.isContainer(T);

            if (comptime T == ztg.Commands) {
                return self.commands();
            } else if (comptime is_container and @hasDecl(T, "IsQueryType")) {
                return self.query(self.frame_alloc, T);
            } else if (comptime is_container and @hasDecl(T, "EventSendType")) {
                return .{
                    .alloc = self.frame_alloc,
                    .event_pool = self.event_pools.getPtr(T.EventSendType),
                };
            } else if (comptime is_container and @hasDecl(T, "EventRecvType")) {
                return .{
                    .items = self.event_pools.getPtr(T.EventRecvType).items,
                };
            } else if (comptime wb.added_resources.has(ztg.meta.DerefType(T))) {
                if (comptime std.meta.trait.isSingleItemPtr(T)) {
                    return self.getResPtr(@typeInfo(T).Pointer.child);
                } else if (comptime wb.added_resources.has(T)) {
                    return self.getRes(T);
                }
            }

            @compileError("Argument " ++ @typeName(T) ++ " not allowed in system. If it is a resource remember to add it to the WorldBuilder.");
        }

        pub fn deinitParamsForSystem(self: *Self, args: anytype) void {
            _ = args;
            _ = self;
            //inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
            //    if (comptime @typeInfo(args_field.type) == .Struct and @hasDecl(args_field.type, "query_types")) {
            //        @field(args, args_field.name).deinit(self.alloc);
            //    }
            //}
        }

        inline fn getListOf(self: *Self, comptime T: type) *ComponentArray {
            const idx = comptime wb.comp_types.indexOf(T) orelse @compileError("Tried to get list of Component " ++ @typeName(T) ++ ", which was not registred.");
            return &self.comp_arrays[idx];
        }

        inline fn getListFromUtp(self: *Self, utp: ztg.meta.UniqueTypePtr) ?*ComponentArray {
            const idx = wb.comp_types.fromUtp(utp) orelse return null;
            return &self.comp_arrays[idx];
        }

        inline fn assertListFromUtp(self: *Self, utp: ztg.meta.UniqueTypePtr) *ComponentArray {
            return self.getListFromUtp(utp) orelse std.debug.panic("Type with utp {} was not registered to world.", .{utp});
        }

        inline fn commandsCast(ptr: *anyopaque) *Self {
            return @ptrCast(@alignCast(ptr));
        }

        fn crash(self: *Self, comptime crash_msg: []const u8, r: ztg.CrashReason) noreturn {
            _ = wb.on_crash_fn(self.commands(), r) catch |err| std.debug.panic("onCrashFn errored due to {}", .{err});
            @panic(crash_msg);
        }
    };
}

/// For internal queueing of commands. Cleared after a stage is completed.
const ChangeQueue = std.ArrayList(union(enum) {
    added_component: struct {
        ent: ztg.Entity,
        component_id: usize,
        data: *const anyopaque,
    },
    removed_ent: ztg.Entity,
    removed_component: struct {
        ent: ztg.Entity,
        component_id: usize,
    },
});

const ComponentChange = struct {
    ent: ztg.Entity,
    component_utp: ztg.meta.UniqueTypePtr,
};

/// For public callback use, e.g. getting added entities this frame. Cleared each frame.
const ChangesList = std.ArrayList(union(enum) {
    added_ent: ztg.Entity,
    removed_ent: ztg.Entity,
    added_component: ComponentChange,
    removed_component: ComponentChange,
});

fn EventPools(comptime event_tm: TypeMap) type {
    const Inner = blk: {
        var tb = TypeBuilder{ .is_tuple = true };
        inline for (event_tm.types) |T| {
            tb.appendTupleField(std.ArrayListUnmanaged(T), null);
        }
        break :blk tb.Build();
    };

    return struct {
        const Self = @This();

        inner: Inner,

        pub fn init() Self {
            var inner: Inner = undefined;
            inline for (std.meta.fields(Inner), event_tm.types) |field, T| {
                @field(inner, field.name) = std.ArrayListUnmanaged(T){};
            }
            return .{ .inner = inner };
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).deinit(alloc);
            }
        }

        pub fn getPtr(self: *Self, comptime EventType: type) *std.ArrayListUnmanaged(EventType) {
            const field_name = comptime std.fmt.comptimePrint("{}", .{event_tm.indexOf(EventType) orelse @compileError("Event `" ++ @typeName(EventType) ++ "` was not registered.")});
            return &@field(self.inner, field_name);
        }

        pub fn clear(self: *Self) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).clearRetainingCapacity();
            }
        }
    };
}

const testing = std.testing;
const WorldBuilder = @import("worldbuilder.zig");

const my_file = struct {
    const MyResource = struct {
        finish_line: usize,
        win_message: []const u8,

        frames: usize = 0,

        fn ini_MyResource(mr: *MyResource) void {
            mr.win_message = "You did it!";
        }

        fn up_MyResource(mr: *MyResource) void {
            mr.frames += 1;
        }
    };

    const MyComponent = struct {
        position: i32,
        speed: i32,

        score: usize = 0,
    };

    pub fn include(comptime wb: *WorldBuilder) void {
        // Registering components
        wb.addComponents(&.{MyComponent});

        // Adding systems
        wb.addUpdateSystems(.{up_MyComponent});

        // Registering/initing resources
        wb.addSystems(.{
            .init = .{MyResource.ini_MyResource},
            .update = .{MyResource.up_MyResource},
        });
        wb.addResource(MyResource, .{ .finish_line = 200, .win_message = undefined });
    }

    // systems that error will bubble up the error to the run*Stage call
    fn up_MyComponent(q: ztg.Query(.{MyComponent}), mr: MyResource) !void {
        for (q.items(0)) |mc| {
            mc.position = try std.math.add(i32, mc.position, mc.speed);

            if (mc.position >= mr.finish_line) mc.score += 1;
        }
    }
};

const MyWorld = WorldBuilder.init(&.{
    ztg.base, ztg.physics, my_file,
}).Build();

test "creation" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();
}

test "adding/removing entities" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    // Generally, youd do this by requesting a Commands argument in your system
    const ent = try world.newEnt();
    try world.giveEnt(ent, my_file.MyComponent{
        .position = 0,
        .speed = 100,
    });

    try world.runStage(.update);

    var q = try world.query(std.testing.allocator, ztg.Query(.{my_file.MyComponent}));
    defer q.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 0), q.single(0).score);

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 1), q.single(0).score);

    try world.removeEntAndAssociatedComponents(ent);

    var q2 = try world.query(std.testing.allocator, ztg.Query(.{my_file.MyComponent}));
    defer q2.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 0), q2.len);
}

test "resources" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    try testing.expectEqual(@as(usize, 0), world.getRes(my_file.MyResource).frames);

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 1), world.getRes(my_file.MyResource).frames);

    var time = world.getResPtr(my_file.MyResource);
    time.frames = 100;

    try testing.expectEqual(@as(usize, 100), world.getRes(my_file.MyResource).frames);
}

fn test_addEnt(comp_arrs: []MyWorld.ComponentArray, ent_list: *MyWorld.EntityArray, next_ent: *usize, data: u8) !void {
    ent_list.append(next_ent.*);
    try comp_arrs[0].assign(next_ent.*, @as(u8, data));
    if (data % 2 == 0) {
        try comp_arrs[1].assign(next_ent.*, @as(u8, data * 10));
    }
    next_ent.* += 1;
}

fn test_removeEnt(comp_arrs: []MyWorld.ComponentArray, ent_list: *MyWorld.EntityArray, ent: ztg.Entity) void {
    const res = ent_list.swapRemoveEnt(ent);
    if (res == false) return;

    for (comp_arrs) |*list| {
        if (list.contains(ent)) _ = list.swapRemove(ent);
    }
}

test "cleanEntList" {
    var changes_list = ChangesList.init(std.testing.allocator);
    var list = MyWorld.EntityArray.init();

    var next_ent: usize = 0;

    var comp_arrs: [2]MyWorld.ComponentArray = undefined;
    defer for (&comp_arrs) |*c| {
        c.deinit();
    };

    {
        var i: usize = 0;

        errdefer {
            for (comp_arrs[0..i]) |*c| {
                c.deinit();
            }
        }

        while (i < comp_arrs.len) : (i += 1) {
            comp_arrs[i] = try MyWorld.ComponentArray.init(std.testing.allocator, u8);
        }
    }

    try test_addEnt(&comp_arrs, &list, &next_ent, 0);
    try test_addEnt(&comp_arrs, &list, &next_ent, 1);
    try test_addEnt(&comp_arrs, &list, &next_ent, 2);
    try test_addEnt(&comp_arrs, &list, &next_ent, 3);
    try test_addEnt(&comp_arrs, &list, &next_ent, 4);

    test_removeEnt(&comp_arrs, &list, 4);
    next_ent = MyWorld.cleanEntList(&comp_arrs, &list, &changes_list) orelse return error.FailedToClean;

    try test_addEnt(&comp_arrs, &list, &next_ent, 4);

    const Index = MyWorld.EntityArray.Index;

    try testing.expectEqualSlices(MyWorld.EntityArray.Index, &.{
        @as(Index, @enumFromInt(0)),
        @as(Index, @enumFromInt(1)),
        @as(Index, @enumFromInt(2)),
        @as(Index, @enumFromInt(3)),
        @as(Index, @enumFromInt(4)),
    }, list.constSlice());
    try testing.expectEqual(@as(?ztg.Entity, 5), next_ent);

    try testing.expect(comp_arrs[0].contains(0));
    try testing.expectEqual(@as(u8, 0), comp_arrs[0].getAs(u8, 0).?.*);

    try testing.expect(comp_arrs[0].contains(4));
    try testing.expectEqual(@as(u8, 4), comp_arrs[0].getAs(u8, 4).?.*);
}

test "events" {}
