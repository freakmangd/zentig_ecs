const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const ztg = @import("init.zig");
const ea = @import("entity_array.zig");
const ca = @import("component_array.zig");
const EventPools = @import("event_pools.zig").EventPools;
const WorldBuilder = @import("worldbuilder.zig");

const Allocator = std.mem.Allocator;
const TypeMap = ztg.meta.TypeMap;
const TypeBuilder = ztg.meta.TypeBuilder;

pub const CommandsComponentError = error{UnregisteredComponent};
pub const CommandsGiveRemoveComponentError = CommandsComponentError || error{EntityDoesntExist} || Allocator.Error;

/// Used for storing pointer-stable objects on the heap
const WorldInfo = struct {
    alloc: std.mem.Allocator,
    frame_arena: std.heap.ArenaAllocator = undefined,
    rng: std.rand.DefaultPrng,

    fn init(alloc: std.mem.Allocator) !*WorldInfo {
        var self = try alloc.create(WorldInfo);
        self.* = .{
            .alloc = alloc,
            .rng = std.rand.DefaultPrng.init(@bitCast(std.time.milliTimestamp())),
        };
        self.frame_arena = std.heap.ArenaAllocator.init(alloc);
        return self;
    }

    fn deinit(self: *WorldInfo) void {
        self.frame_arena.deinit();
        self.alloc.destroy(self);
    }
};

pub fn World(comptime wb: WorldBuilder) type {
    if (wb.max_entities == 0) @compileError("Cannot have max_ents == 0.");

    const Resources = wb.resources.Build();
    const MinEntityIndex = std.math.IntFittingRange(0, wb.max_entities);
    const comp_types_len = wb.comp_types.types.len;

    return struct {
        const Self = @This();

        const StagesList = @import("stages.zig").Init(wb.stage_defs.items, Self);

        const ComponentArray = ca.ComponentArray(MinEntityIndex);
        const ComponentMask = std.bit_set.StaticBitSet(wb.comp_types.types.len);
        const EntityArray = ea.EntityArray(ComponentMask, wb.max_entities);

        info: *WorldInfo,

        alloc: Allocator,
        frame_arena: *std.heap.ArenaAllocator,
        frame_alloc: Allocator,
        rand: std.rand.Random,

        next_ent: ztg.Entity = 0,
        entities: *EntityArray = undefined,

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
        pub fn init(user_allocator: std.mem.Allocator) !Self {
            if (comptime builtin.mode == .Debug) {
                //std.debug.print("Entity has utp {}\n", .{util.compId(ztg.Entity)});
                //inline for (wb.comp_types.types) |T| {
                //    @setEvalBranchQuota(20_000);
                //    std.debug.print("{s} has utp {}\n", .{ @typeName(T), util.compId(T) });
                //}

                if (wb.warnings.len > 0)
                    ztg.log.warn("\n====== World was constructed with warnings: ======\n{s}", .{wb.warnings});

                if (wb.max_entities > 500_000) ztg.log.warn("It isn't recommended to have a max_entities count over 500,000 as it could cause unstable performance.");
            }

            var info = try WorldInfo.init(user_allocator);
            errdefer info.deinit();

            try StagesList.init(info.alloc);
            errdefer StagesList.deinit();

            const frame_alloc = info.frame_arena.allocator();

            var self = Self{
                .alloc = info.alloc,
                .info = info,
                .frame_arena = &info.frame_arena,
                .frame_alloc = frame_alloc,
                .rand = info.rng.random(),

                .event_pools = EventPools(wb.event_types).init(),
                .changes_list = ChangesList.init(frame_alloc),
                .changes_queue = ChangeQueue.init(frame_alloc),
            };

            self.entities = try info.alloc.create(EntityArray);
            self.entities.* = EntityArray.init();
            errdefer info.alloc.destroy(self.entities);

            if (comptime wb.comp_types.types.len > 0) {
                var last_successful_init_loop: usize = 0;
                errdefer for (self.comp_arrays[0..last_successful_init_loop]) |*arr| {
                    arr.deinit(info.alloc);
                };

                util.resetCompIds();
                inline for (wb.comp_types.types, 0..) |CT, i| {
                    @setEvalBranchQuota(20_000);
                    self.comp_arrays[util.compId(CT)] = ComponentArray.init(CT);
                    last_successful_init_loop = i;
                }
            }

            self.getResPtr(Allocator).* = user_allocator;
            self.getResPtr(ztg.FrameAlloc).* = .{frame_alloc};
            self.getResPtr(std.rand.Random).* = info.rng.random();

            ztg.profiler.init(user_allocator);

            try self.runStage(.init);

            return self;
        }

        fn deinit_errCallback(err: anyerror) void {
            ztg.log.err("Encountered error {} in deinit stage", .{err});
        }

        pub fn deinit(self: *Self) void {
            ztg.profiler.deinit();

            self.postSystemUpdate() catch |err| {
                ztg.log.err("Found error {} while trying to clean up world for deinit.", .{err});
            };

            inline for (wb.comp_types.types, &self.comp_arrays) |CT, *comp_arr| {
                if (comptime @hasDecl(CT, "onRemoved")) {
                    if (comptime @sizeOf(CT) > 0) {
                        var comp_iter = comp_arr.iterator();
                        while (comp_iter.nextAs(CT)) |comp| self.invokeOnRemoveForComponent(CT, comp) catch |err| {
                            std.log.err("Caught error {} while deinit'ing component list of type {s}", .{ err, @typeName(CT) });
                        };
                    } else {
                        for (0..comp_arr.len()) |_| self.invokeOnRemoveForComponent(CT, undefined) catch |err| {
                            std.log.err("Caught error {} while deinit'ing component list of type {s}", .{ err, @typeName(CT) });
                        };
                    }
                }
                comp_arr.deinit(self.alloc);
            }

            self.runStageCatchErrors(.deinit, deinit_errCallback) catch |err| switch (err) {
                error.OutOfMemory => ztg.log.err("Encountered OOM error in deinit stage. Some systems may not have been run!", .{}),
            };

            StagesList.deinit();

            self.event_pools.deinit(self.frame_alloc);
            self.changes_queue.deinit();
            self.changes_list.deinit();

            self.info.alloc.destroy(self.entities);
            self.info.deinit();
            //self.alloc.destroy(self);
        }

        /// If you are going to run multiple stages in a row, consider `.runStageList()`
        ///
        /// Example:
        /// ```zig
        /// try world.runStage(.render);
        /// ```
        pub fn runStage(self: *Self, comptime stage_id: StagesList.StageField) anyerror!void {
            try StagesList.runStage(self, stage_id, false, void{});
        }

        //pub fn runStageInParallel(self: *Self, comptime stage_id: StagesList.StageField) anyerror!void {
        //    try StagesList.runStageInParallel(self, stage_id, false, void{});
        //}

        /// For discarding errors in systems so that every system runs. Useful for stages
        /// that are run at the end to free resources.
        /// Calls errCallback whenever an error occurs and passes it the error.
        ///
        /// Example:
        /// ```zig
        /// try world.runStage(.render);
        /// ```
        pub fn runStageCatchErrors(self: *Self, comptime stage_id: StagesList.StageField, comptime errCallback: fn (anyerror) void) error{OutOfMemory}!void {
            StagesList.runStage(self, stage_id, true, errCallback) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => unreachable, // all other errors are sent to errCallback
            };
        }

        /// If you are going to run multiple stages in a row, consider `.runStageNameList()`
        ///
        /// Example:
        /// ```zig
        /// world.runStageByName("render");
        /// ```
        pub fn runStageByName(self: *Self, stage_name: []const u8) anyerror!void {
            StagesList.runStageByName(self, stage_name, false, void{}) catch |err| switch (err) {
                error.UnknownStage => std.debug.panic("Cannot find stage {s} in stage list.", .{stage_name}),
                else => |e| return e,
            };
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

        /// Runs the .pre_update, .update, and .post_update systems
        pub fn runUpdateStages(self: *Self) anyerror!void {
            inline for (&.{ .pre_update, .update, .post_update }) |stage| {
                try runStage(self, stage);
            }
        }

        /// For forcing the evaluation of the change queue,
        /// you shouldn't have to call this.
        pub fn postSystemUpdate(self: *Self) anyerror!void {
            if (comptime comp_types_len == 0) return;

            for (self.changes_queue.items) |rem| {
                switch (rem) {
                    .added_component => |comp| {
                        var arr = &self.comp_arrays[comp.component_id];
                        try arr.assignData(self.alloc, comp.ent, comp.data);
                    },
                    .removed_ent => |ent| try self.removeEntAndAssociatedComponents(ent),
                    .removed_component => |rem_comp| {
                        const id = self.comp_arrays[rem_comp.component_id].component_id;
                        const comp = self.comp_arrays[rem_comp.component_id].get(rem_comp.ent) orelse {
                            ztg.log.err("Trying to remove a component of type {s} from ent {} when ent does not have that component", .{ wb.comp_types.nameFromIndex(id), rem_comp.ent });
                            continue;
                        };
                        try self.invokeOnRemoveForComponentById(comp, id);
                        self.comp_arrays[rem_comp.component_id].swapRemove(rem_comp.ent);
                    },
                }
            }

            self.changes_queue.clearAndFree();
        }

        fn removeEntAndAssociatedComponents(self: *Self, ent: ztg.Entity) anyerror!void {
            if (!self.entities.hasEntity(ent)) return;

            const children = try self.getEntChildren(self.frame_alloc, ent);
            defer self.frame_alloc.free(children);

            for (children) |c| try self.removeEntAndAssociatedComponents(c);

            for (&self.comp_arrays) |*list| {
                if (list.get(ent)) |comp| {
                    try self.invokeOnRemoveForComponentById(comp, list.component_id);
                    _ = list.swapRemove(ent);
                }
            }

            _ = self.entities.swapRemoveEnt(ent);
        }

        fn invokeOnRemoveForComponent(self: *Self, comptime T: type, comp: *T) anyerror!void {
            const member_fn_type = comptime ztg.meta.memberFnType(T, "onRemoved");
            const fn_params = @typeInfo(@TypeOf(T.onRemoved)).Fn.params;
            const params = self.initParamsForSystem(self.frame_alloc, if (comptime member_fn_type != .non_member) fn_params[1..] else fn_params) catch |err| {
                std.debug.panic("Failed to get args for deinit system for type `{s}`. Error: {}", .{ @typeName(T), err });
            };

            const member_params = switch (member_fn_type) {
                .non_member => .{},
                .by_value => .{comp.*},
                .by_ptr => .{comp},
                .by_const_ptr => .{comp},
            };

            if (comptime ztg.meta.canReturnError(@TypeOf(T.onRemoved))) {
                try @call(.auto, T.onRemoved, member_params ++ params);
            } else {
                @call(.auto, T.onRemoved, member_params ++ params);
            }
        }

        fn invokeOnRemoveForComponentById(self: *Self, comp: *anyopaque, comp_id: util.CompId) anyerror!void {
            inline for (wb.comp_types.types, 0..) |CT, i| {
                if (comptime @hasDecl(CT, "onRemoved")) if (i == comp_id) {
                    try invokeOnRemoveForComponent(self, CT, if (comptime @sizeOf(CT) == 0) undefined else @as(*CT, @ptrCast(@alignCast(comp))));
                };
            }
        }

        /// Call when a "frame" of your game loop has completed, most commonly after the draw call
        ///
        /// Example:
        ///
        /// ```zig
        /// try world.runStage(.load);
        ///
        /// while(game.isRunning) {
        ///   try world.runUpdateStages();
        ///   try world.runStage(.draw);
        ///   world.cleanForNextFrame();
        /// }
        /// ```
        pub fn cleanForNextFrame(self: *Self) void {
            self.changes_list.clearAndFree();
            self.event_pools.clear();
            if (!self.frame_arena.reset(.{ .retain_with_limit = 5_000_000 })) ztg.log.err("Failed to reset frame arena.", .{});
        }

        /// Returns the next free index for components. This will be valid for the entity's lifetime.
        ///
        /// If the entity limit is exceeded and no open spaces can be found, there are a few outcomes
        /// depending on your `WorldBuilder.on_ent_overflow` option:
        ///
        /// `.crash` => (default) invokes the crash function, which will most likely panic.
        /// `.overwrite_last` => returns the last entity in the entity list, after removing all of its components.
        /// `.overwrite_first` => returns the first entity in the entity list, after removing all of its components
        pub fn newEnt(self: *Self) Allocator.Error!ztg.Entity {
            const ent = blk: {
                if (self.next_ent >= wb.max_entities) {
                    break :blk getOpenEntityId(self.entities, 0) orelse self.handleEntOverflow();
                } else if (!self.entities.hasEntity(self.next_ent)) {
                    break :blk self.next_ent;
                } else {
                    break :blk getOpenEntityId(self.entities, self.next_ent + 1) orelse self.handleEntOverflow();
                }
            };

            try self.changes_list.append(.{ .added_ent = ent });
            self.entities.append(ent);
            self.entities.setParent(ent, null) catch unreachable;
            self.next_ent += 1;

            return ent;
        }

        /// Creates a new entity and gives it `component`
        pub fn newEntWith(self: *Self, components: anytype) !ztg.Entity {
            const ent = try self.newEnt();
            try self.giveComponents(ent, components);
            return ent;
        }

        fn getOpenEntityId(entities: *const EntityArray, from: ztg.Entity) ?ztg.Entity {
            for (from..wb.max_entities) |e| if (!entities.hasEntity(e)) return @intCast(e);
            for (0..from) |e| if (!entities.hasEntity(e)) return @intCast(e);
            return null;
        }

        fn handleEntOverflow(self: *Self) ztg.Entity {
            return switch (wb.on_ent_overflow) {
                .crash => self.crash(std.fmt.comptimePrint("Exceeded entity limit of {}.", .{wb.max_entities}), .hit_ent_limit),
                .overwrite_last => blk: {
                    const ent = self.entities.getEntityAt(self.entities.len - 1);
                    try self.reuseEntity(ent);
                    break :blk ent;
                },
                .overwrite_first => blk: {
                    const ent = self.entities.getEntityAt(0);
                    try self.reuseEntity(ent);
                    break :blk ent;
                },
            };
        }

        fn reuseEntity(self: *Self, ent: ztg.Entity) !void {
            self.removeEntAndAssociatedComponents(ent);
            try self.changes_list.append(.{ .added_ent = self.next_ent });
            self.entities.append(ent);
        }

        fn commands_newEnt(ptr: *anyopaque) Allocator.Error!ztg.Entity {
            return commandsCast(ptr).newEnt();
        }

        /// Set the entity's parent. If null, the entity will no longer have a parent.
        /// Can error if either the entity or parent don't exist.
        pub fn setEntParent(self: *Self, ent: ztg.Entity, parent: ?ztg.Entity) !void {
            return self.entities.setParent(ent, parent);
        }

        fn commands_setEntParent(ptr: *anyopaque, ent: ztg.Entity, parent: ?ztg.Entity) !void {
            return commandsCast(ptr).setEntParent(ent, parent);
        }

        /// Get the entity's parent. Can error if the entity associated with `ent`
        /// doesn't exist.
        pub fn getEntParent(self: *const Self, ent: ztg.Entity) !?ztg.Entity {
            return self.entities.getParent(ent);
        }

        fn commands_getEntParent(ptr: *const anyopaque, ent: ztg.Entity) !?ztg.Entity {
            return commandsCastConst(ptr).getEntParent(ent);
        }

        /// Returns a caller-owned slice of the entity's children.
        pub fn getEntChildren(self: *const Self, alloc: std.mem.Allocator, ent: ztg.Entity) ![]const ztg.Entity {
            return self.entities.getChildren(alloc, ent);
        }

        fn commands_getEntChildren(ptr: *const anyopaque, ent: ztg.Entity) ![]const ztg.Entity {
            const self = commandsCastConst(ptr);
            return self.getEntChildren(self.frame_alloc, ent);
        }

        /// Set's the entity `child`'s parent to `ent`
        pub fn giveEntChild(self: *Self, ent: ztg.Entity, child: ztg.Entity) !void {
            return self.setEntParent(child, ent);
        }

        /// Queues the removal of all components in lists correlated with `ent` and `ent` itself
        pub fn removeEnt(self: *Self, ent: ztg.Entity) Allocator.Error!void {
            try self.changes_queue.append(.{ .removed_ent = ent });
            try self.changes_list.append(.{ .removed_ent = ent });
        }

        fn commands_removeEnt(ptr: *anyopaque, ent: ztg.Entity) Allocator.Error!void {
            try commandsCast(ptr).removeEnt(ent);
        }

        fn giveComponentSingle(self: *Self, ent: ztg.Entity, comp: anytype) !void {
            if (comptime wb.comp_types.types.len == 0) @compileError("World has no registered components and cannot add components");

            if (!self.entities.hasEntity(ent)) return error.EntityDoesntExist;

            const Component = @TypeOf(comp);
            const idx = comptime wb.comp_types.indexOf(Component) orelse util.compileError("Tried to give entity Component of type `{s}`, which was not registred.", .{@typeName(Component)});

            const has_onAdded = comptime @hasDecl(Component, "onAdded");

            if (comptime has_onAdded) util.assertOkOnAddedFunction(Component);

            const member_type: if (has_onAdded) ztg.meta.MemberFnType else void = comptime if (has_onAdded) ztg.meta.memberFnType(Component, "onAdded") else void{};
            const needs_mut: bool = comptime if (has_onAdded) member_type == .by_ptr else false;
            const can_err = comptime has_onAdded and ztg.meta.canReturnError(@TypeOf(Component.onAdded));
            var mutable_comp: if (has_onAdded and needs_mut) Component else void = if (comptime has_onAdded and needs_mut) comp else void{};

            if (comptime has_onAdded) {
                if (comptime member_type == .non_member) {
                    if (comptime can_err) try Component.onAdded(ent, self.commands()) else Component.onAdded(ent, self.commands());
                } else {
                    var c = if (comptime needs_mut) mutable_comp else comp;
                    if (comptime can_err) try c.onAdded(ent, self.commands()) else c.onAdded(ent, self.commands());
                }
            }

            self.entities.comp_masks[ent].set(idx);
            try self.comp_arrays[idx].assign(self.alloc, ent, if (has_onAdded and needs_mut) mutable_comp else comp);
            try self.changes_list.append(.{ .added_component = .{
                .ent = ent,
                .component_id = util.compId(Component),
            } });
        }

        /// Adds the components to the entity `ent`.
        ///
        /// Possible types for components:
        /// + tuple { T, V, ... }, where types within the tuple are registered components
        /// + struct { t: T, v: V, ... }, where types within the struct are registered components,
        ///     and the struct itself has an `is_component_bundle` public decl
        ///
        /// If any of the types passed in the tuple/struct components have the `is_component_bundle`
        /// public decl, they will be treated as component bundles and recursively added
        ///
        /// Example:
        /// ```zig
        /// giveComponents(my_ent, .{
        ///     SpriteBundle.init(), // every component within SpriteBundle will be added individually
        ///     Transform.default(),
        ///     Name{"Entity"},
        /// });
        /// ```
        pub fn giveComponents(self: *Self, ent: ztg.Entity, components: anytype) !void {
            const Components = @TypeOf(components);

            if (comptime wb.comp_types.types.len == 0) @compileError("World has no registered components and cannot add components");

            if (comptime !std.meta.trait.isContainer(Components))
                @compileError("Non-container type passed to giveComponents, if you want to give an entity a single component wrap it in an anonymous tuple.");

            if (comptime !std.meta.trait.isTuple(Components) and !@hasDecl(Components, "is_component_bundle"))
                @compileError("Struct passed to giveComponents does not have a public is_component_bundle decl, if it is not a bundle wrap it in an anonymous tuple.");

            inline for (std.meta.fields(Components)) |field| {
                if (comptime std.meta.trait.isContainer(field.type) and @hasDecl(field.type, "is_component_bundle")) {
                    try giveComponents(self, ent, @field(components, field.name));
                } else {
                    try giveComponentSingle(self, ent, @field(components, field.name));
                }
            }
        }

        fn commands_giveComponent(ptr: *anyopaque, ent: ztg.Entity, component_id: util.CompId, alignment: u29, data: *const anyopaque) CommandsGiveRemoveComponentError!void {
            if (comptime wb.comp_types.types.len == 0) @compileError("World has no registered components and cannot add components");
            var self = commandsCast(ptr);

            if (component_id >= wb.comp_types.types.len) return error.UnregisteredComponent;
            if (!self.entities.hasEntity(ent)) return error.EntityDoesntExist;

            self.entities.comp_masks[ent].set(component_id);
            var arr = try self.getListById(component_id);

            if (arr.willResize()) {
                // we cant add the component right now, because then the pointers in the calling system will become invalid,
                // so we place the data on the heap and queue for its addition.
                //
                // also, probably unsafe :)
                // only because we have an alignment at runtime instead of comptime :,(
                var alloced_data = self.frame_alloc.rawAlloc(arr.components_data.entry_size, std.math.log2_int(u29, alignment), @returnAddress()) orelse return error.OutOfMemory;
                @memcpy(alloced_data, @as([*]const u8, @ptrCast(data))[0..arr.components_data.entry_size]);
                try self.changes_queue.append(.{ .added_component = .{
                    .ent = ent,
                    .component_id = component_id,
                    .data = alloced_data,
                } });
            } else {
                try arr.assignData(self.alloc, ent, data);
            }

            try self.changes_list.append(.{ .added_component = .{
                .ent = ent,
                .component_id = component_id,
            } });
        }

        /// Removes component of type `Component` from entity `ent`
        pub fn removeComponent(self: *Self, ent: ztg.Entity, comptime Component: type) (error{EntityDoesntExist} || Allocator.Error)!void {
            try self.removeComponent_fromCompId(
                ent,
                comptime wb.comp_types.indexOf(Component) orelse util.compileError("Component of type `{s}` was not registered and cannot be removed", .{@typeName(Component)}),
            );
        }

        fn commands_removeComponent(ptr: *anyopaque, ent: ztg.Entity, comp_id: util.CompId) CommandsGiveRemoveComponentError!void {
            if (comp_id >= wb.comp_types.types.len) return error.UnregisteredComponent;
            try commandsCast(ptr).removeComponent_fromCompId(ent, comp_id);
        }

        inline fn removeComponent_fromCompId(self: *Self, ent: ztg.Entity, comp_id: util.CompId) CommandsGiveRemoveComponentError!void {
            if (comptime wb.comp_types.types.len == 0) @compileError("World has no registered components to remove.");
            if (!self.entities.hasEntity(ent)) return error.EntityDoesntExist;

            try self.changes_queue.append(.{ .removed_component = .{
                .ent = ent,
                .component_id = comp_id,
            } });
        }

        /// Returns true or false depending on whether `ent` has been assigned a component of type `Component`
        pub fn checkEntHas(self: *Self, ent: ztg.Entity, comptime Component: type) bool {
            return self.comp_arrays[comptime wb.comp_types.indexOf(Component) orelse util.compileError("Component of type `{s}` was not registered", .{@typeName(Component)})].contains(ent);
        }

        fn commands_checkEntHas(ptr: *anyopaque, ent: ztg.Entity, component_id: util.CompId) CommandsComponentError!bool {
            if (comptime wb.comp_types.types.len == 0) @compileError("World has no registered components to check for.");
            return commandsCast(ptr).comp_arrays[component_id].contains(ent);
        }

        /// Returns an optional pointer to the component assigned to `ent`
        pub fn getComponentPtr(self: *Self, ent: ztg.Entity, comptime Component: type) ?*anyopaque {
            return self.getComponentPtr_fromCompId(
                ent,
                comptime wb.comp_types.indexOf(Component) orelse util.compileError("Component of type `{s}` was not registered and no pointer can be obtained.", .{@typeName(Component)}),
            );
        }

        fn commands_getComponentPtr(ptr: *anyopaque, ent: ztg.Entity, comp_id: util.CompId) CommandsComponentError!?*anyopaque {
            if (comptime wb.comp_types.types.len == 0) @compileError("World has no registered components to get the pointer of.");
            return commandsCast(ptr).getComponentPtr_fromCompId(ent, comp_id);
        }

        fn getComponentPtr_fromCompId(self: *Self, ent: ztg.Entity, comp_id: util.CompId) ?*anyopaque {
            for (self.changes_queue.items) |ch| switch (ch) {
                .added_component => |added| if (added.ent == ent and added.component_id == comp_id) return added.data,
                else => {},
            };
            return self.comp_arrays[comp_id].get(ent);
        }

        /// Returns a copy of the resource T in this world
        pub fn getRes(self: Self, comptime T: type) T {
            if (comptime !wb.added_resources.has(T)) util.compileError("World does not have resource of type `{s}`", .{@typeName(T)});
            return @field(self.resources, std.fmt.comptimePrint("{}", .{wb.added_resources.indexOf(T).?}));
        }

        /// Returns a pointer to the resource T in this world
        pub fn getResPtr(self: *Self, comptime T: type) *T {
            if (comptime !wb.added_resources.has(T)) util.compileError("World does not have resource of type `{s}`", .{@typeName(T)});
            return &@field(self.resources, std.fmt.comptimePrint("{}", .{wb.added_resources.indexOf(T).?}));
        }

        fn commands_getResPtr(ptr: *anyopaque, utp: ztg.meta.Utp) error{UnregisteredResource}!*anyopaque {
            inline for (wb.added_resources.types, 0..) |T, i| {
                if (ztg.meta.utpOf(T) == utp) return &@field(commandsCast(ptr).resources, std.fmt.comptimePrint("{}", .{i}));
            }
            return error.UnregisteredResource;
        }

        /// Returns a commands interface to this world type
        pub fn commands(self: *Self) ztg.Commands {
            return .{
                .ctx = self,
                .vtable = &.{
                    .add_component = Self.commands_giveComponent,
                    .remove_component = Self.commands_removeComponent,
                    .get_component_ptr = Self.commands_getComponentPtr,
                    .remove_ent = Self.commands_removeEnt,
                    .new_ent = Self.commands_newEnt,
                    .get_ent_parent = Self.commands_getEntParent,
                    .set_ent_parent = Self.commands_setEntParent,
                    .run_stage = Self.commands_runStageFn,
                    .get_res = Self.commands_getResPtr,
                    .check_ent_has = Self.commands_checkEntHas,
                    .has_included = Self.commands_hasIncluded,
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
            if (comptime QT.has_entities and QT.req_types.types.len == 0) return self.queryJustEntities(alloc, QT);

            const req_ids = util.idsFromTypes(QT.req_types.types);
            const opt_ids = util.idsFromTypes(QT.opt_types.types);
            const with_ids = util.idsFromTypes(QT.with_types.types);
            const without_ids = util.idsFromTypes(QT.without_types.types);

            var queryInfo = try self.initQueryLists(alloc, &req_ids, &opt_ids, &with_ids);
            defer alloc.free(queryInfo.qlists);

            const comp_mask, const negative_mask = getCompMasks(&.{ &req_ids, &with_ids }, &.{&without_ids});

            var out = try QT.init(alloc, queryInfo.checked_entities.len);

            // Link qlists and the result query
            for (queryInfo.qlists) |*list| {
                switch (list.out) {
                    .required => list.out.required = out.comp_ptrs[list.out_idx],
                    .optional => list.out.optional = if (comptime QT.opt_types.types.len > 0) out.opt_ptrs[list.out_idx] else unreachable,
                }
            }

            out.len = self.fillQuery(
                queryInfo.checked_entities,
                queryInfo.qlists,
                comp_mask,
                negative_mask,
                if (comptime QT.has_entities) out.entities else null,
            );

            return out;
        }

        // For queries which the only required type is Entity
        fn queryJustEntities(self: *Self, alloc: std.mem.Allocator, comptime QT: type) !QT {
            const comp_mask, const negative_mask = getCompMasks(
                &.{&util.idsFromTypes(QT.with_types.types)},
                &.{&util.idsFromTypes(QT.without_types.types)},
            );

            var len: usize = 0;
            var out = try QT.init(alloc, self.entities.len);

            for (self.entities.constSlice(), 0..) |ent, i| {
                if (!entPassesCompMasks(self.entities.comp_masks[@intFromEnum(ent)], comp_mask, negative_mask)) continue;
                inline for (out.opt_ptrs, QT.opt_types.types) |opt_ptrs, O| opt_ptrs[i] = self.getListOf(O).get(@intFromEnum(ent));

                out.entities[len] = @intFromEnum(ent);
                len += 1;
            }

            out.len = len;
            return out;
        }

        const QueryList = struct {
            array: *const ComponentArray,
            out_idx: usize,
            out: Out,

            const Out = union(OutType) {
                required: []*anyopaque,
                optional: []?*anyopaque,
            };
            const OutType = enum { required, optional };

            fn init(array: *const ComponentArray, out_idx: usize, comptime out_type: OutType) QueryList {
                return .{
                    .array = array,
                    .out_idx = out_idx,
                    .out = @unionInit(Out, @tagName(out_type), undefined),
                };
            }
        };

        fn initQueryLists(
            self: *Self,
            alloc: std.mem.Allocator,
            req_ids: []const util.CompId,
            opt_ids: []const util.CompId,
            with_ids: []const util.CompId,
        ) !struct {
            checked_entities: []const ztg.Entity,
            qlists: []QueryList,
        } {
            var lists = try alloc.alloc(QueryList, req_ids.len + opt_ids.len);
            var idx: usize = 0;

            var smallest: *ComponentArray = self.assertListById(req_ids[0]);
            lists[0] = QueryList.init(smallest, 0, .required);

            for (req_ids[1..], 1..) |id, i| {
                const check = self.assertListById(id);
                idx += 1;
                lists[idx] = QueryList.init(check, i, .required);

                if (check.len() < smallest.len()) smallest = check;
            }

            for (opt_ids, 0..) |id, i| {
                idx += 1;
                lists[idx] = QueryList.init(self.assertListById(id), i, .optional);
            }

            for (with_ids) |id| {
                const check = self.assertListById(id);
                if (check.len() < smallest.len()) smallest = check;
            }

            return .{
                .checked_entities = smallest.entities.items,
                .qlists = lists,
            };
        }

        fn getCompMasks(
            comp_ids_list: []const []const util.CompId,
            negative_ids_list: []const []const util.CompId,
        ) struct { ComponentMask, ComponentMask } {
            var comp_mask = ComponentMask.initEmpty();
            var negative_mask = ComponentMask.initEmpty();

            for (comp_ids_list) |ids| for (ids) |id| comp_mask.set(id);
            for (negative_ids_list) |ids| for (ids) |id| negative_mask.set(id);

            return .{ comp_mask, negative_mask };
        }

        fn fillQuery(
            self: Self,
            checked_entities: []const ztg.Entity,
            qlists: []QueryList,
            comp_mask: ComponentMask,
            negative_mask: ComponentMask,
            entities_out: ?[]ztg.Entity,
        ) usize {
            var len: usize = 0;
            for (checked_entities) |ent| {
                const ent_mask = self.entities.comp_masks[ent];

                if (entPassesCompMasks(ent_mask, comp_mask, negative_mask)) {
                    for (qlists) |*list| {
                        switch (list.out) {
                            .required => |req| req[len] = list.array.get(ent).?,
                            .optional => |opt| opt[len] = list.array.get(ent),
                        }
                    }

                    if (entities_out) |eout| eout[len] = ent;
                    len += 1;
                }
            }
            return len;
        }

        inline fn entPassesCompMasks(ent_mask: ComponentMask, comp_mask: ComponentMask, negative_mask: ComponentMask) bool {
            return ent_mask.supersetOf(comp_mask) and ent_mask.intersectWith(negative_mask).eql(ComponentMask.initEmpty());
        }

        pub fn ParamsForSystem(comptime params: []const std.builtin.Type.Fn.Param) type {
            var types: [params.len]type = undefined;
            for (params, &types) |p, *t| t.* = p.type.?;
            return std.meta.Tuple(&types);
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
        pub fn initParamsForSystem(self: *Self, alloc: std.mem.Allocator, comptime params: []const std.builtin.Type.Fn.Param) !ParamsForSystem(params) {
            if (comptime params.len == 0) @compileError("Use an empty tuple if the params list is empty.");
            var out: ParamsForSystem(params) = undefined;
            inline for (out, 0..) |param, i| {
                out[i] = try self.initParam(alloc, @TypeOf(param));
            }
            return out;
        }

        inline fn initParam(self: *Self, alloc: std.mem.Allocator, comptime T: type) !T {
            const is_container = comptime std.meta.trait.isContainer(T);

            if (comptime T == ztg.Commands) {
                return self.commands();
            } else if (comptime is_container and @hasDecl(T, "IsQueryType")) {
                return self.query(alloc, T);
            } else if (comptime is_container and @hasDecl(T, "EventSendType")) {
                return .{
                    .alloc = alloc,
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

            util.compileError("Argument `{s}` not allowed in system. If it is a resource remember to add it to the WorldBuilder.", .{@typeName(T)});
        }

        pub fn deinitParamsForSystem(self: *Self, alloc: std.mem.Allocator, args: anytype) void {
            _ = self;
            inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
                if (comptime @typeInfo(args_field.type) == .Struct and @hasDecl(args_field.type, "query_types")) {
                    @field(args, args_field.name).deinit(alloc);
                }
            }
        }

        /// Returns whether the underlying WorldBuilder included a namespace
        /// while it was being built.
        pub fn hasIncluded(comptime Namespace: type) bool {
            comptime return wb.included.has(Namespace);
        }

        fn commands_hasIncluded(type_utp: ztg.meta.Utp) bool {
            return wb.included.hasUtp(type_utp);
        }

        inline fn getListOf(self: *Self, comptime T: type) *ComponentArray {
            const idx = comptime wb.comp_types.indexOf(T) orelse util.compileError("Tried to get list of Component `{s}`, which was not registred.", .{@typeName(T)});
            return &self.comp_arrays[idx];
        }

        inline fn getListById(self: *Self, id: util.CompId) !*ComponentArray {
            if (builtin.mode == .Debug) if (id >= self.comp_arrays.len) return CommandsComponentError.UnregisteredComponent;
            return &self.comp_arrays[id];
        }

        inline fn assertListById(self: *Self, id: util.CompId) *ComponentArray {
            return self.getListById(id) catch std.debug.panic("Tried to get list of Component with ID {}, which was not registered.", .{id});
        }

        inline fn commandsCast(ptr: *anyopaque) *Self {
            return @ptrCast(@alignCast(ptr));
        }

        inline fn commandsCastConst(ptr: *const anyopaque) *const Self {
            return @ptrCast(@alignCast(ptr));
        }

        fn crash(self: *Self, comptime crash_msg: []const u8, r: ztg.CrashReason) noreturn {
            wb.on_crash_fn(self.commands(), r) catch |err| ztg.log.err("onCrashFn errored due to {}", .{err});
            @panic(crash_msg);
        }
    };
}

const ComponentChange = struct {
    ent: ztg.Entity,
    component_id: util.CompId,
};

/// For internal queueing of commands. Cleared after a stage is completed.
const ChangeQueue = std.ArrayList(union(enum) {
    added_component: struct {
        ent: ztg.Entity,
        component_id: util.CompId,
        data: *anyopaque,
    },
    removed_ent: ztg.Entity,
    removed_component: ComponentChange,
});

/// For public callback use, e.g. getting added entities this frame. Cleared each frame.
const ChangesList = std.ArrayList(union(enum) {
    added_ent: ztg.Entity,
    removed_ent: ztg.Entity,
    added_component: ComponentChange,
    removed_component: ComponentChange,
});

const testing = std.testing;

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
        wb.addSystemsToStage(.update, .{up_MyComponent});

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
    ztg.base, my_file,
}).Build();

test "creation" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();
}

test "bad alloc" {
    var world = MyWorld.init(std.testing.failing_allocator);
    try std.testing.expectError(error.OutOfMemory, world);
}

test "adding/removing entities" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    // Generally, youd do this by requesting a Commands argument in your system
    const ent = try world.newEnt();
    try world.giveComponents(ent, .{my_file.MyComponent{
        .position = 0,
        .speed = 100,
    }});

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

test "adding/removing components" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    const com = world.commands();

    const ent = try com.newEntWith(.{my_file.MyComponent{
        .position = 10,
        .speed = 20,
    }});

    try world.postSystemUpdate();

    try testing.expectEqual(@as(i32, 10), ent.getComponentPtr(my_file.MyComponent).?.position);
    try testing.expect(ent.checkHas(my_file.MyComponent));
    try testing.expect(!world.checkEntHas(ent.ent, ztg.base.Transform));

    try ent.removeComponent(my_file.MyComponent);

    try world.postSystemUpdate();

    try testing.expect(!ent.checkHas(my_file.MyComponent));

    try std.testing.expectError(error.EntityDoesntExist, world.giveComponents(512, .{ztg.base.Name{"bad"}}));
}

test "overwriting components" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    const com = world.commands();

    const ent = try com.newEntWith(.{my_file.MyComponent{
        .position = 10,
        .speed = 20,
    }});

    try ent.giveComponents(.{my_file.MyComponent{
        .position = -10,
        .speed = -20,
    }});

    try world.postSystemUpdate();

    try testing.expectEqual(@as(i32, -10), ent.getComponentPtr(my_file.MyComponent).?.position);
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

test "querying" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    _ = try world.newEntWith(.{
        ztg.base.Name{"ok"},
        my_file.MyComponent{
            .position = 10,
            .speed = 20,
        },
    });

    _ = try world.newEntWith(.{
        ztg.base.Name{"bad"},
        ztg.base.Transform.identity(),
        my_file.MyComponent{
            .position = 30,
            .speed = 1,
        },
    });

    var q = try world.query(std.testing.allocator, ztg.QueryOpts(.{ my_file.MyComponent, ?ztg.base.Lifetime }, .{ ztg.Without(ztg.base.Transform), ztg.With(ztg.base.Name) }));
    defer q.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 1), q.len);

    var q2 = try world.query(std.testing.allocator, ztg.QueryOpts(.{ztg.Entity}, .{ ztg.Without(ztg.base.Transform), ztg.With(ztg.base.Name) }));
    defer q2.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 1), q.len);
}
