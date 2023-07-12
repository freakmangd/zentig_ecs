const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const TypeMap = @import("type_map.zig");
const TypeBuilder = @import("type_builder.zig");
const ecs = @import("ecs.zig");
const Commands = @import("commands.zig");
const ea = @import("entity_array.zig");
const ca = @import("component_array.zig");
const profiler = @import("profiler.zig");
const Allocator = std.mem.Allocator;

// Level Management:
// Store component by type name and have lookup table in file?
// Comptime string hashmap to convert names into compontent_utps

const WorldInfo = struct {
    main_alloc: if (builtin.mode == .Debug) std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 12 }) else void,
    arena: std.heap.ArenaAllocator,
    rand: std.rand.DefaultPrng,

    fn deinit(self: *WorldInfo) void {
        if (comptime builtin.mode == .Debug) _ = self.main_alloc.deinit();
        self.arena.deinit();
    }
};

pub fn worldInfo() WorldInfo {
    return .{
        .main_alloc = blk: {
            if (comptime builtin.mode == .Debug) {
                break :blk std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 12 }){};
            } else {
                break :blk void{};
            }
        },
        .arena = undefined,
        .rand = std.rand.DefaultPrng.init(@bitCast(std.time.milliTimestamp())),
    };
}

pub fn World(comptime wb: WorldBuilder) type {
    comptime {
        if (wb.max_entities == 0) @compileError("Cannot have max_ents == 0.");
    }

    const Resources = wb.resources.Build();
    const MinEntityIndex = std.meta.Int(.unsigned, @typeInfo(std.math.IntFittingRange(0, wb.max_entities)).Int.bits + 1);

    const comp_types_len = wb.comp_types.types.len;

    return struct {
        const Self = @This();

        const StagesList = @import("stages.zig").Init(wb.stage_defs, Self);
        const stages_list = StagesList{ .inner = .{} };

        const ComponentArray = ca.ComponentArray(MinEntityIndex, wb.max_entities);
        const EntityArray = ea.EntityArray(wb.max_entities);

        alloc: Allocator,
        info: *WorldInfo,

        frame_arena: *std.heap.ArenaAllocator,
        frame_alloc: Allocator = undefined,

        next_ent: ecs.Entity = 0,
        entities: EntityArray,

        comp_arrays: [comp_types_len]ComponentArray = undefined,

        resources: Resources = .{},
        event_pools: EventPools(wb.event_types),
        commands_vtable: Commands.Vtable,

        changes_list: ChangesList = undefined,
        changes_queue: ChangeQueue = undefined,

        /// User must call `.deinit()` once the world is to be descoped. (in a defer block preferrably)
        /// All systems that request an `Allocator` will get the one passed here.
        ///
        /// Also runs the `.setup` stage, useful for things that will only run once and need to be done before
        /// anything else, without relying on most anything else (Allocator and Random are available).
        ///
        /// Example:
        /// ```zig
        /// var wi = ztg.worldInfo();
        /// var world = MyWorld.init(&wi);
        /// defer world.deinit();
        /// ```
        pub fn init(info: *WorldInfo) !Self {
            if (comptime builtin.mode == .Debug) {
                //std.debug.print("Entity has utp {}\n", .{TypeMap.uniqueTypePtr(ecs.Entity)});
                //inline for (wb.comp_types.types) |T| {
                //    @setEvalBranchQuota(20_000);
                //    std.debug.print("{s} has utp {}\n", .{ @typeName(T), TypeMap.uniqueTypePtr(T) });
                //}

                if (wb.warnings.len > 0)
                    std.log.warn("\n====== World was constructed with warnings: ======\n" ++ wb.warnings, .{});
            }

            const alloc = blk: {
                break :blk if (comptime builtin.mode == .Debug) info.main_alloc.allocator() else std.heap.c_allocator;
            };
            info.arena = std.heap.ArenaAllocator.init(alloc);

            var self = Self{
                .alloc = alloc,
                .info = info,
                .frame_arena = &info.arena,
                .frame_alloc = info.arena.allocator(),

                .entities = EntityArray.init(),

                .commands_vtable = .{
                    .add_component_fn = Self.commands_giveEnt,
                    .remove_ent_fn = Self.commands_removeEnt,
                    .new_ent_fn = Self.commands_newEnt,
                    .run_stage_fn = Self.commands_runStageFn,
                    .get_res_fn = Self.commands_getResPtr,
                    .check_ent_has_fn = Self.commands_checkEntHas,
                },

                .event_pools = EventPools(wb.event_types){},
            };

            self.changes_list = ChangesList.init(self.frame_alloc);
            self.changes_queue = ChangeQueue.init(self.frame_alloc);

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

            self.getResPtr(Allocator).* = alloc;
            self.getResPtr(std.rand.Random).* = info.rand.random();

            try self.runStage(.setup);

            return self;
        }

        fn deinit_errCallback(comptime msg: []const u8) fn (anyerror) void {
            return struct {
                fn f(err: anyerror) void {
                    std.log.err(msg, .{err});
                }
            }.f;
        }

        pub fn deinit(self: *Self) void {
            self.cleanForNextFrame();

            self.runStageCatchErrors(.shutdown, deinit_errCallback("Encountered error {} in shutdown stage.")) catch |err| switch (err) {
                error.OutOfMemory => {
                    std.log.err("Encountered OOM error in shutdown stage. Some systems may not have been run!", .{});
                },
            };

            self.runStageCatchErrors(.cleanup, deinit_errCallback("Encountered error {} in cleanup stage")) catch |err| switch (err) {
                error.OutOfMemory => {
                    std.log.err("Encountered OOM error in cleanup stage. Some systems may not have been run!", .{});
                },
            };

            self.event_pools.deinit(self.alloc);
            self.changes_queue.deinit();
            self.changes_list.deinit();

            inline for (wb.comp_types.types, &self.comp_arrays) |CT, *c| {
                if (comptime @hasDecl(CT, "onDestroy")) self.invokeOnDestroyForArray(c, CT);
                c.deinit();
            }

            self.info.deinit();
        }

        /// If you are going to run multiple stages in a row, consider `.runStageList()`
        ///
        /// Example:
        /// ```zig
        /// world.runStage(.render);
        /// ```
        pub inline fn runStage(self: *Self, comptime stage_id: StagesList.StageField) anyerror!void {
            try stages_list.runStage(self, stage_id);
        }

        /// For discarding errors in systems so that every system runs. Useful for stages
        /// that are run at the end to free resources.
        /// Calls errCallback whenever an error occurs and passes it the error.
        ///
        /// Example:
        /// ```zig
        /// world.runStage(.render);
        /// ```
        pub inline fn runStageCatchErrors(self: *Self, comptime stage_id: StagesList.StageField, comptime errCallback: fn (anyerror) void) !void {
            return stages_list.runStageCatchErrors(self, stage_id, errCallback);
        }

        /// If you are going to run multiple stages in a row, consider `.runStageNameList()`
        ///
        /// Example:
        /// ```zig
        /// world.runStageByName("render");
        /// ```
        pub inline fn runStageByName(self: *Self, stage_name: []const u8) anyerror!void {
            try stages_list.runStageRuntime(self, stage_name);
        }

        fn commands_runStageFn(ptr: *anyopaque, stage_name: []const u8) anyerror!void {
            try commandsCast(ptr).runStageByName(stage_name);
        }

        /// If you are going to run builtin pre_X, X, post_X stages, consider `.runInitStages()`, `.runUpdateStages()`, or `.runDrawStages()`
        ///
        /// Example:
        /// ```zig
        /// world.runStageList(&.{ .ping_send, .ping_receive, .ping_read });
        /// ```
        pub fn runStageList(self: *Self, comptime stage_ids: []const StagesList.StageField) anyerror!void {
            inline for (stage_ids) |sid| {
                try runStage(self, sid);
            }
        }

        /// If you are going to run builtin pre_X, X, post_X stages, consider `.runInitStages()`, `.runUpdateStages()`, or `.runDrawStages()`
        ///
        /// Example:
        /// ```zig
        /// world.runStageList(&.{ "ping_send", "ping_receive", "ping_read" });
        /// ```
        pub fn runStageNameList(self: *Self, stage_ids: []const []const u8) anyerror!void {
            for (stage_ids) |sid| {
                try runStageByName(self, sid);
            }
        }

        /// Runs the stages: .pre_init, .init, .post_init
        pub fn runInitStages(self: *Self) anyerror!void {
            inline for (.{ .pre_init, .init, .post_init }) |stage| {
                try runStage(self, stage);
            }
        }

        /// Runs the stages: .pre_update, .update, .post_update
        pub fn runUpdateStages(self: *Self) anyerror!void {
            inline for (.{ .pre_update, .update, .post_update }) |stage| {
                try runStage(self, stage);
            }
        }

        /// Runs the stages .pre_draw, .draw, .post_draw
        pub fn runDrawStages(self: *Self) anyerror!void {
            inline for (.{ .pre_draw, .draw, .post_draw }) |stage| {
                try runStage(self, stage);
            }
        }

        pub fn postSystemCleanup(self: *Self) !void {
            if (comptime comp_types_len == 0) return;

            for (self.changes_queue.items) |rem| {
                switch (rem) {
                    .added_component => |comp| {
                        var arr = &self.comp_arrays[comp.component_id];
                        try arr.assignData(comp.ent, comp.data);
                    },
                    .removed_ent => |ent| self.removeEntAndAssociatedComponents(ent),
                    .removed_component => |comp| _ = self.comp_arrays[comp.component_id].swapRemove(comp.ent),
                }
            }

            self.changes_queue.clearAndFree();
        }

        fn removeEntAndAssociatedComponents(self: *Self, ent: ecs.Entity) void {
            const res = self.entities.swapRemoveEnt(ent);
            if (res == false) return;

            for (&self.comp_arrays) |*list| {
                if (list.get(ent)) |comp| {
                    self.invokeOnDestroyForComponentByUtp(comp, list.component_utp);
                    _ = list.swapRemove(ent);
                }
            }
        }

        fn invokeOnDestroyForComponent(self: *Self, comptime T: type, comp: if (@sizeOf(T) == 0) void else *T) void {
            const member_fn_type = comptime util.isMemberFn(T, T.onDestroy);
            const fn_params = @typeInfo(@TypeOf(T.onDestroy)).Fn.params;
            const params = self.initParamsForSystem(if (comptime member_fn_type != .non_member) fn_params[1..] else fn_params) catch {
                @panic("Failed to get args for deinit system for type `" ++ @typeName(T) ++ "`.");
            };

            if (comptime @sizeOf(T) > 0) {
                const member_params = if (comptime member_fn_type != .non_member)
                    .{if (comptime member_fn_type == .by_value) comp.* else comp}
                else
                    .{};

                @call(.auto, T.onDestroy, member_params ++ params);
            } else {
                if (comptime member_fn_type != .non_member) {
                    var dummy = T{};
                    @call(.auto, T.onDestroy, .{&dummy} ++ params);
                } else {
                    @call(.auto, T.onDestroy, params);
                }
            }
        }

        fn invokeOnDestroyForComponentByUtp(self: *Self, comp: *anyopaque, comp_utp: TypeMap.UniqueTypePtr) void {
            inline for (wb.comp_types.types) |CT| {
                if (comptime @hasDecl(CT, "onDestroy") and TypeMap.uniqueTypePtr(CT) == comp_utp) {
                    invokeOnDestroyForComponent(self, CT, if (comptime @sizeOf(CT) == 0) void{} else @ptrCast(@alignCast(comp)));
                }
            }
        }

        fn invokeOnDestroyForArray(self: *Self, comp_arr: *ComponentArray, comptime T: type) void {
            if (comptime @sizeOf(T) > 0) {
                var comp_iter = comp_arr.iterator();
                while (comp_iter.nextAs(T)) |comp| self.invokeOnDestroyForComponent(T, comp);
            } else {
                for (0..comp_arr.len()) |_| self.invokeOnDestroyForComponent(T, void{});
            }
        }

        /// Call when a "frame" of your game loop has completed, most commonly after the draw call
        ///
        /// Example:
        ///
        /// ```zig
        /// try world.runInitStages();
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
            if (!self.frame_arena.reset(.free_all)) std.log.err("Failed to reset frame arena.", .{});
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
        pub fn newEnt(self: *Self) Allocator.Error!ecs.Entity {
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

        inline fn handleEntOverflow(self: *Self) ecs.Entity {
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

        fn reuseEntity(self: *Self, ent: ecs.Entity) !void {
            self.removeEntAndAssociatedComponents(ent);
            try self.changes_list.append(.{ .added_ent = self.next_ent });
            self.entities.append(ent);
        }

        fn commands_newEnt(ptr: *anyopaque) Allocator.Error!ecs.Entity {
            return commandsCast(ptr).newEnt();
        }

        fn cleanEntList(comp_arrays: []ComponentArray, entities: *EntityArray, changes_list: *ChangesList) ?usize {
            if (entities.len + 1 > wb.max_entities) {
                return null;
            }

            var old_ents = entities.*;
            entities.reset();

            var next_ent: ecs.Entity = 0;
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
        pub fn removeEnt(self: *Self, ent: ecs.Entity) Allocator.Error!void {
            try self.changes_queue.append(.{ .removed_ent = ent });
            try self.changes_list.append(.{ .removed_ent = ent });
        }

        fn commands_removeEnt(ptr: *anyopaque, ent: ecs.Entity) Allocator.Error!void {
            try commandsCast(ptr).removeEnt(ent);
        }

        /// Adds a component to the entity `ent`
        pub fn giveEnt(self: *Self, ent: ecs.Entity, comp: anytype) !void {
            if (comptime wb.comp_types.types.len == 0) return;
            const Component = @TypeOf(comp);
            const idx = comptime wb.comp_types.indexOf(Component) orelse @compileError("Tried to add Component " ++ @typeName(Component) ++ ", which was not registred.");

            try self.comp_arrays[idx].assign(ent, comp);
            try self.changes_list.append(.{ .added_component = .{
                .ent = ent,
                .component_utp = TypeMap.uniqueTypePtr(Component),
            } });
        }

        /// Adds every field in the components object to its component list at the Entity index
        pub fn giveEntMany(self: *Self, ent: ecs.Entity, components: anytype) !void {
            if (comptime wb.comp_types.types.len == 0) return;
            inline for (std.meta.fields(@TypeOf(components))) |field| {
                try self.giveEnt(ent, @field(components, field.name));
            }
        }

        /// Returns true or false depending on whether `ent` has been assigned a component of type `Component`
        pub inline fn checkEntHas(self: *Self, ent: ecs.Entity, comptime Component: type) bool {
            return self.getEntsComponent(ent, Component) != null;
        }

        /// Returns an optional pointer to the component assigned to `ent`
        pub inline fn getEntsComponent(self: *Self, ent: ecs.Entity, comptime Component: type) ?*anyopaque {
            return self.comp_arrays[comptime wb.comp_types.indexOf(Component)].get(ent);
        }

        fn commands_giveEnt(ptr: *anyopaque, ent: ecs.Entity, component_utp: TypeMap.UniqueTypePtr, data: *const anyopaque) ca.Error!void {
            if (comptime wb.comp_types.types.len == 0) return;
            var self = commandsCast(ptr);
            const idx = getIndexFromUtp(component_utp) orelse std.debug.panic("Tried to give an entity a component with utp {} but a component with that utp was not registered.", .{component_utp});

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

        fn commands_checkEntHas(ptr: *anyopaque, ent: ecs.Entity, component_utp: TypeMap.UniqueTypePtr) bool {
            _ = component_utp;
            _ = ent;
            if (comptime wb.comp_types.types.len == 0) return false;
            var self = commandsCast(ptr);
            _ = self;

            return false;
        }

        /// Removes component of type `Component` from entity `ent`
        pub fn removeComponent(self: *Self, ent: ecs.Entity, comptime Component: type) ca.Error!void {
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

        fn commands_getResPtr(ptr: *anyopaque, utp: TypeMap.UniqueTypePtr) *anyopaque {
            inline for (wb.added_resources.types, 0..) |T, i| {
                if (TypeMap.uniqueTypePtr(T) == utp) return &@field(commandsCast(ptr).resources, std.fmt.comptimePrint("{}", .{i}));
            }
            std.debug.panic("Resource with utp {} is not in world.", .{utp});
        }

        const QueryList = struct {
            array: *ComponentArray,
            out_idx: usize,
            is_optional: bool = false,
            out: union(enum) {
                req: []*anyopaque,
                opt: []?*anyopaque,
            } = undefined,
        };

        /// The method used for generating queries for systems
        ///
        /// Example:
        /// ```zig
        /// const q = world.query(ztg.Query(.{ ztg.base.Transform });
        /// ```
        pub fn query(self: *Self, comptime QT: type) !QT {
            if (QT.has_entities and QT.req_types.types.len == 0) return queryJustEntities(self);

            var qlists = try self.initQueryLists(QT.req_utps, QT.opt_utps);
            var out = try QT.init(self.frame_alloc, qlists[0].array.len());
            registerQListsOut(qlists, &out);

            out.len = fillQuery(
                qlists,
                if (comptime QT.has_entities) out.entities else null,
                QT.options,
            );

            return out;
        }

        fn initQueryLists(self: *Self, req_utps: []const TypeMap.UniqueTypePtr, opt_utps: []const TypeMap.UniqueTypePtr) ![]QueryList {
            var smallest: *ComponentArray = self.getListFromUtp(req_utps[0]) orelse std.debug.panic("AKFIJAWF", .{});
            var smallest_idx: usize = 0;

            var lists = try std.ArrayList(QueryList).initCapacity(self.frame_alloc, req_utps.len + opt_utps.len);
            lists.appendAssumeCapacity(QueryList{ .array = smallest, .out_idx = 0 });

            for (req_utps[1..], 1..) |utp, i| {
                const check = self.getListFromUtp(utp) orelse std.debug.panic("FJAWIFJAOWF", .{});
                lists.appendAssumeCapacity(QueryList{ .array = check, .out_idx = i });

                if (check.len() < smallest.len()) {
                    smallest = check;
                    smallest_idx = i;
                }
            }

            for (opt_utps, 0..) |utp, i| {
                lists.appendAssumeCapacity(QueryList{ .array = self.getListFromUtp(utp) orelse std.debug.panic("FAJIOFWJWA", .{}), .out_idx = i, .is_optional = true });
            }

            // move smallest list to front of list
            const smallest_qlist = lists.swapRemove(smallest_idx);
            lists.insertAssumeCapacity(0, smallest_qlist);

            return lists.toOwnedSlice();
        }

        fn registerQListsOut(qlists: []QueryList, query_out: anytype) void {
            const QT = std.meta.Child(@TypeOf(query_out));

            for (qlists) |*list| {
                list.out = blk: {
                    if (list.is_optional) {
                        if (comptime QT.opt_types.types.len > 0) break :blk .{ .opt = query_out.opt_ptrs[list.out_idx] } else unreachable;
                    } else {
                        break :blk .{ .req = query_out.comp_ptrs[list.out_idx] };
                    }
                };
            }
        }

        fn fillQuery(qlists: []const QueryList, entities_out: ?[]ecs.Entity, comptime options: anytype) usize {
            _ = options;

            var len: usize = 0;
            ents_loop: for (qlists[0].array.entities.items) |ent| {
                qlists[0].out.req[len] = qlists[0].array.get(ent) orelse {
                    std.debug.panic("Component list {s} has entity {} registered but has no corresponding component.", .{ wb.comp_types.nameFromUtp(qlists[0].array.component_utp), ent });
                };

                for (qlists[1..]) |list| {
                    switch (list.out) {
                        .req => |o| {
                            if (list.array.get(ent)) |comp_ptr| {
                                o[len] = comp_ptr;
                            } else {
                                continue :ents_loop;
                            }
                        },
                        .opt => |o| {
                            o[len] = list.array.get(ent);
                        },
                    }
                }

                if (entities_out) |eout| eout[len] = ent;
                len += 1;
            }

            return len;
        }

        fn queryJustEntities(self: *Self) !ecs.Query(.{ecs.Entity}) {
            var out = try ecs.Query(.{ecs.Entity}).init(self.frame_alloc, self.entities.len);
            for (out.entities, self.entities.constSlice()) |*o, ent| o.* = @intFromEnum(ent);
            out.len = self.entities.len;
            return out;
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
        /// const params = try world.initParamsForSystem(@typeInfo(myFunction).Fn.params);
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

            if (comptime T == Commands) {
                return Commands{
                    .ctx = self,
                    .vtable = &self.commands_vtable,
                };
            } else if (comptime is_container and @hasDecl(T, "IsQueryType")) {
                return self.query(T);
            } else if (comptime is_container and @hasDecl(T, "EventSendType")) {
                return .{
                    .alloc = self.frame_alloc,
                    .event_pool = self.event_pools.getPtr(T.EventSendType),
                };
            } else if (comptime is_container and @hasDecl(T, "EventRecvType")) {
                return .{
                    .items = self.event_pools.getPtr(T.EventRecvType).items,
                };
            } else if (comptime wb.added_resources.has(util.DerefType(T))) {
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

        inline fn getIndexFromUtp(utp: TypeMap.UniqueTypePtr) ?usize {
            return wb.comp_types.fromUtp(utp);
        }

        inline fn getListFromUtp(self: *Self, utp: TypeMap.UniqueTypePtr) ?*ComponentArray {
            const idx = getIndexFromUtp(utp) orelse return null;
            return &self.comp_arrays[idx];
        }

        inline fn commandsCast(ptr: *anyopaque) *Self {
            return @ptrCast(@alignCast(ptr));
        }

        fn crash(self: *Self, comptime crash_msg: []const u8, r: ecs.CrashReason) noreturn {
            _ = wb.on_crash_fn(.{ .ctx = self, .vtable = &self.commands_vtable }, r) catch |err| std.debug.panic("onCrashFn errored due to {}", .{err});
            @panic(crash_msg);
        }
    };
}

/// For internal queueing of commands. Cleared after a stage is completed.
const ChangeQueue = std.ArrayList(union(enum) {
    added_component: struct {
        ent: ecs.Entity,
        component_id: usize,
        data: *const anyopaque,
    },
    removed_ent: ecs.Entity,
    removed_component: struct {
        ent: ecs.Entity,
        component_id: usize,
    },
});

const ComponentChange = struct {
    ent: ecs.Entity,
    component_utp: TypeMap.UniqueTypePtr,
};

/// For public callback use, e.g. getting added entities this frame. Cleared each frame.
const ChangesList = std.ArrayList(union(enum) {
    added_ent: ecs.Entity,
    removed_ent: ecs.Entity,
    added_component: ComponentChange,
    removed_component: ComponentChange,
});

fn EventPools(comptime event_tm: TypeMap) type {
    const Inner = blk: {
        var tb = TypeBuilder.init(false, .Auto);
        for (event_tm.types, 0..) |T, i| {
            tb.addField(std.fmt.comptimePrint("{}", .{i}), std.ArrayListUnmanaged(T), &std.ArrayListUnmanaged(T){});
        }
        break :blk tb.Build();
    };

    return struct {
        const Self = @This();

        inner: Inner = .{},

        pub fn deinit(self: *Self, alloc: Allocator) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).deinit(alloc);
            }
        }

        pub fn getPtr(self: *Self, comptime EventType: type) *std.ArrayListUnmanaged(EventType) {
            if (comptime !event_tm.has(EventType)) @compileError("Event `" ++ @typeName(EventType) ++ "` was not registered.");
            return &@field(self.inner, Inner_fieldNameOf(EventType));
        }

        pub fn clear(self: *Self) void {
            inline for (std.meta.fields(Inner)) |field| {
                @field(self.inner, field.name).clearRetainingCapacity();
            }
        }

        inline fn Inner_fieldNameOf(comptime T: type) []const u8 {
            return std.fmt.comptimePrint("{}", .{event_tm.indexOf(T).?});
        }
    };
}

const testing = std.testing;
const base = @import("mods/base.zig");
const physics = @import("mods/physics.zig");
const WorldBuilder = @import("worldbuilder.zig");

const my_file = struct {
    const MyResource = struct {
        finish_line: usize,
        win_message: []const u8,

        frames: usize = 0,
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
        wb.addSystemsToStage(.setup, .{setup_MyResource});
        wb.addUpdateSystems(.{up_MyResource});
        wb.addResource(MyResource, .{ .finish_line = 200, .win_message = undefined });
    }

    fn setup_MyResource(mr: *MyResource) void {
        mr.win_message = "You did it!";
    }

    fn up_MyResource(mr: *MyResource) void {
        mr.frames += 1;
    }

    // systems that error will bubble up the error to the run*Stage call
    fn up_MyComponent(q: ecs.Query(.{MyComponent}), mr: MyResource) !void {
        for (q.items(0)) |mc| {
            mc.position = try std.math.add(i32, mc.position, mc.speed);

            if (mc.position >= mr.finish_line) mc.score += 1;
        }
    }
};

const MyWorld = WorldBuilder.init(&.{
    base, physics, my_file,
}).Build();

test "creation" {
    var wi = worldInfo();
    var world = try MyWorld.init(&wi);
    defer world.deinit();
}

test "adding entities" {
    var wi = worldInfo();
    var world = try MyWorld.init(&wi);
    defer world.deinit();

    // Generally, youd do this by requesting a Commands argument in your system
    const ent = try world.newEnt();
    try world.giveEnt(ent, my_file.MyComponent{
        .position = 0,
        .speed = 100,
    });

    try world.runUpdateStages();

    var q = try world.query(ecs.Query(.{my_file.MyComponent}));

    try testing.expectEqual(@as(usize, 0), q.items(0)[0].score);

    try world.runUpdateStages();

    try testing.expectEqual(@as(usize, 1), q.items(0)[0].score);

    try world.removeEnt(ent);
    try world.postSystemCleanup();

    var q2 = try world.query(ecs.Query(.{my_file.MyComponent}));

    try testing.expectEqual(@as(usize, 0), q2.len);
}

test "resources" {
    var wi = worldInfo();
    var world = try MyWorld.init(&wi);
    defer world.deinit();

    try testing.expectEqual(@as(usize, 0), world.getRes(my_file.MyResource).frames);

    try world.runUpdateStages();

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

fn test_removeEnt(comp_arrs: []MyWorld.ComponentArray, ent_list: *MyWorld.EntityArray, ent: ecs.Entity) void {
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

    try testing.expectEqualSlices(MyWorld.EntityArray.Index, &.{ 0, 1, 2, 3, 4 }, list.constSlice());
    try testing.expectEqual(@as(?ecs.Entity, 5), next_ent);

    try testing.expect(comp_arrs[0].contains(0));
    try testing.expectEqual(@as(u8, 0), comp_arrs[0].getAs(u8, 0).?.*);

    try testing.expect(comp_arrs[0].contains(4));
    try testing.expectEqual(@as(u8, 4), comp_arrs[0].getAs(u8, 4).?.*);
}
