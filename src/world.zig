const std = @import("std");
const builtin = @import("builtin");
const util = @import("util.zig");
const ztg = @import("init.zig");
const ea = @import("entity_array.zig");
const ca = @import("component_array.zig");
const WorldBuilder = @import("worldbuilder.zig");

const Allocator = std.mem.Allocator;
const TypeMap = ztg.meta.TypeMap;
const TypeBuilder = ztg.meta.TypeBuilder;

/// Used for storing pointer-stable objects on the heap
const WorldInfo = struct {
    frame_arena: std.heap.ArenaAllocator,
    rng: std.Random.DefaultPrng,

    fn init(alloc: std.mem.Allocator) !*WorldInfo {
        const self = try alloc.create(WorldInfo);
        self.* = .{
            .rng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp())),
            .frame_arena = std.heap.ArenaAllocator.init(alloc),
        };
        return self;
    }

    fn deinit(self: *WorldInfo, alloc: std.mem.Allocator) void {
        self.frame_arena.deinit();
        alloc.destroy(self);
    }
};

pub fn World(
    comptime max_entities: usize,
    comptime Resources: type,
    comptime comp_types: anytype,
    comptime StagesList: type,
    comptime EventPool: type,
    comptime added_resources: anytype,
    comptime included: anytype,
    comptime on_ent_overflow: WorldBuilder.OnEntOverflow,
    comptime on_crash_fn: WorldBuilder.OnCrashFn,
    comptime warnings: anytype,
) type {
    if (max_entities == 0) @compileError("Cannot have max_ents == 0.");

    const comp_types_len = comp_types.len;

    const MinEntityIndex = std.math.IntFittingRange(0, max_entities);
    const ComponentArray = ca.ComponentArray(MinEntityIndex);
    const ComponentMask = std.bit_set.StaticBitSet(comp_types_len);
    const EntityArray = ea.EntityArray(ComponentMask, max_entities);

    return struct {
        const Self = @This();

        info: *WorldInfo,

        alloc: Allocator,
        frame_arena: *std.heap.ArenaAllocator,
        frame_alloc: Allocator,
        rand: std.Random,

        next_ent: ztg.Entity = @enumFromInt(0),
        entities: *EntityArray = undefined,

        comp_arrays: [comp_types_len]ComponentArray = undefined,
        resources: *Resources = undefined,

        event_pools: EventPool,
        changes_queue: ChangeQueue,

        on_added_fns: [comp_types_len]*const fn (*Self, *anyopaque, ztg.Entity) anyerror!void = undefined,
        on_removed_fns: [comp_types_len]*const fn (*Self, *anyopaque, ztg.Entity) anyerror!void = undefined,

        /// User must call `.deinit()` once the world is to be descoped. (in a defer block preferrably)
        /// All systems that request an `Allocator` will get the one passed here.
        pub fn init(user_allocator: std.mem.Allocator) !Self {
            if (comptime builtin.mode == .Debug) {
                if (warnings.len > 0)
                    ztg.log.warn("\n====== World was constructed with warnings: ======\n{s}", .{warnings});

                if (max_entities > 500_000) ztg.log.warn("It isn't recommended to have a max_entities count over 500,000 as it could cause unstable performance.");
            }

            var info = try WorldInfo.init(user_allocator);
            errdefer info.deinit(user_allocator);

            try StagesList.init(user_allocator);
            errdefer StagesList.deinit();

            const frame_alloc = info.frame_arena.allocator();

            var self = Self{
                .alloc = user_allocator,
                .info = info,
                .frame_arena = &info.frame_arena,
                .frame_alloc = frame_alloc,
                .rand = info.rng.random(),

                .event_pools = .{},
                .changes_queue = ChangeQueue.init(frame_alloc),
            };

            self.resources = try user_allocator.create(Resources);
            self.resources.* = .{};
            errdefer user_allocator.destroy(self.resources);

            self.entities = try user_allocator.create(EntityArray);
            self.entities.* = .{};
            errdefer user_allocator.destroy(self.entities);

            if (comptime comp_types_len > 0) {
                var last_successful_init_loop: usize = 0;
                errdefer for (self.comp_arrays[0..last_successful_init_loop]) |*arr| {
                    arr.deinit(user_allocator);
                };

                util.resetCompIds();
                util.allow_new_ids = true;
                inline for (comp_types, 0..) |CT, i| {
                    @setEvalBranchQuota(20_000);
                    const comp_id = util.compId(CT);
                    self.comp_arrays[comp_id] = ComponentArray.init(CT);
                    self.on_added_fns[comp_id] = generateAddRemSystem(CT, "onAdded");
                    self.on_removed_fns[comp_id] = generateAddRemSystem(CT, "onRemoved");
                    last_successful_init_loop = i;
                }
                util.allow_new_ids = false;
            }

            self.getResPtr(Allocator).* = user_allocator;
            self.getResPtr(ztg.FrameAlloc).* = .{frame_alloc};
            self.getResPtr(std.Random).* = info.rng.random();

            ztg.profiler.init(user_allocator);

            try self.runStage(.init);

            return self;
        }

        fn deinit_errCallback(err: anyerror) void {
            ztg.log.err("Encountered error {} in deinit stage", .{err});
        }

        pub fn deinit(self: *Self) void {
            StagesList.deinit();
            ztg.profiler.deinit();

            self.postSystemUpdate() catch |err| {
                ztg.log.err("Found error {} while trying to clean up world for deinit.", .{err});
            };

            inline for (comp_types, &self.comp_arrays) |CT, *comp_arr| {
                if (comptime @sizeOf(CT) > 0) {
                    for (comp_arr.entities.items) |ent| self.invokeOnRemoveForComponent(CT, comp_arr.getAs(CT, ent).?, ent) catch |err| {
                        std.log.err("Caught error {} while deinit'ing component list of type {s}", .{ err, @typeName(CT) });
                    };
                } else {
                    for (comp_arr.entities.items) |ent| self.invokeOnRemoveForComponent(CT, undefined, ent) catch |err| {
                        std.log.err("Caught error {} while deinit'ing component list of type {s}", .{ err, @typeName(CT) });
                    };
                }
                comp_arr.deinit(self.alloc);
            }

            self.runStageCatchErrors(.deinit, deinit_errCallback) catch |err| switch (err) {
                error.OutOfMemory => ztg.log.err("Encountered OOM error in deinit stage. Some systems may not have been run!", .{}),
            };

            self.event_pools.deinit(self.frame_alloc);
            self.changes_queue.deinit();

            self.alloc.destroy(self.entities);
            self.alloc.destroy(self.resources);
            self.info.deinit(self.alloc);
        }

        fn generateAddRemSystem(comptime CT: type, comptime fn_name: []const u8) *const fn (*Self, *anyopaque, ztg.Entity) anyerror!void {
            return struct {
                fn f(self: *Self, comp_ptr_aop: *anyopaque, ent: ztg.Entity) anyerror!void {
                    if (comptime !util.isContainer(CT) or !@hasDecl(CT, fn_name)) return;

                    const comp: *CT = @ptrCast(@alignCast(comp_ptr_aop));
                    const func = @field(CT, fn_name);

                    const member_fn_type = comptime ztg.meta.memberFnType(CT, fn_name);
                    const fn_params = @typeInfo(@TypeOf(func)).@"fn".params;
                    const maybe_ent_param_idx = if (comptime member_fn_type == .non_member) 0 else 1;
                    const has_ent_param = comptime maybe_ent_param_idx < fn_params.len and fn_params[maybe_ent_param_idx].type.? == ztg.Entity;

                    const params_offset = comptime blk: {
                        var offset = if (has_ent_param) 1 else 0;
                        if (member_fn_type != .non_member) offset += 1;
                        break :blk offset;
                    };

                    const params = self.initParamsForSystem(self.frame_alloc, fn_params[params_offset..]) catch |err| {
                        std.debug.panic("Failed to get args for deinit system for type `{}`. Error: {}", .{ CT, err });
                    };

                    const member_params = switch (member_fn_type) {
                        .non_member => .{},
                        .by_value => .{comp.*},
                        .by_ptr => .{comp},
                        .by_const_ptr => .{comp},
                    } ++ (if (has_ent_param) .{ent} else .{});

                    if (comptime ztg.meta.canReturnError(@TypeOf(func))) {
                        try @call(.auto, func, member_params ++ params);
                    } else {
                        @call(.auto, func, member_params ++ params);
                    }
                }
            }.f;
        }

        /// If you are going to run multiple stages in a row, consider `.runStageList()`
        pub fn runStage(self: *Self, comptime stage_id: StagesList.StageField) anyerror!void {
            try StagesList.runStage(self, stage_id, false, void{});
        }

        pub fn runStageInParallel(self: *Self, comptime stage_id: StagesList.StageField) anyerror!void {
            try StagesList.runStageInParallel(self, stage_id, false, void{});
        }

        /// Runs a stage and catches every error ensures every system in the stage is run. Useful for stages
        /// that are run at the end to free resources.
        /// Calls errCallback whenever an error occurs and passes it the error.
        pub fn runStageCatchErrors(self: *Self, comptime stage_id: StagesList.StageField, comptime errCallback: fn (anyerror) void) error{OutOfMemory}!void {
            StagesList.runStage(self, stage_id, true, errCallback) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory, // this is from allocating slices for queries
                else => unreachable, // all other errors are sent to errCallback
            };
        }

        /// If you are going to run multiple stages in a row, consider `.runStageNameList()`
        pub fn runStageByName(self: *Self, stage_name: []const u8) anyerror!void {
            StagesList.runStageByName(self, stage_name, false, void{}) catch |err| switch (err) {
                error.UnknownStage => std.debug.panic("Cannot find stage {s} in stage list.", .{stage_name}),
                else => |e| return e,
            };
        }

        fn commands_runStageFn(ptr: *anyopaque, stage_name: []const u8) anyerror!void {
            try commandsCast(ptr).runStageByName(stage_name);
        }

        pub fn runStageList(self: *Self, comptime stage_ids: []const StagesList.StageField) anyerror!void {
            inline for (stage_ids) |sid| {
                try runStage(self, sid);
            }
        }

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

        pub fn runUpdateStagesIp(self: *Self) anyerror!void {
            inline for (&.{ .pre_update, .update, .post_update }) |stage| {
                try runStageInParallel(self, stage);
            }
        }

        /// For forcing the evaluation of the change queue,
        /// you shouldn't have to call this.
        pub fn postSystemUpdate(self: *Self) anyerror!void {
            if (comptime comp_types_len == 0) return;

            // using a while loop since the changes_queue.items can be realloced
            // inside the loop.
            var i: usize = 0;
            while (i < self.changes_queue.items.len) : (i += 1) {
                // skip bounds check, length cant change
                const rem = (@as([*]const ChangeQueueItem, @ptrCast(self.changes_queue.items)) + i)[0];

                switch (rem) {
                    .added_component => |comp| {
                        var arr = &self.comp_arrays[comp.component_id];
                        const comp_ptr = try arr.assignData(self.alloc, comp.ent, comp.data);
                        try self.on_added_fns[comp.component_id](self, comp_ptr, comp.ent);
                    },
                    .removed_ent => |ent| try self.removeEntAndAssociatedComponents(ent),
                    .removed_component => |rem_comp| {
                        const comp = self.comp_arrays[rem_comp.component_id].get(rem_comp.ent) orelse {
                            if (builtin.mode == .Debug) {
                                ztg.log.err("Trying to remove a component of type {s} from ent {} when ent does not have that component", .{
                                    util.nameFromTypeArrayIndex(comp_types, rem_comp.component_id),
                                    rem_comp.ent,
                                });
                            }
                            continue;
                        };
                        try self.invokeOnRemoveForComponentById(comp, rem_comp.component_id, rem_comp.ent);
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

            inline for (comp_types, &self.comp_arrays) |CT, *list| {
                if (list.getAs(CT, ent)) |comp| {
                    try self.invokeOnRemoveForComponent(CT, comp, ent);
                    _ = list.swapRemove(ent);
                }
            }

            _ = self.entities.swapRemoveEnt(ent);
        }

        fn invokeOnRemoveForComponent(self: *Self, comptime T: type, comp: *T, ent: ztg.Entity) anyerror!void {
            try self.invokeOnRemoveForComponentById(comp, util.compId(T), ent);
        }

        fn invokeOnRemoveForComponentById(self: *Self, comp: *anyopaque, comp_id: util.CompId, ent: ztg.Entity) anyerror!void {
            try self.on_removed_fns[comp_id](self, comp, ent);
        }

        /// Call when a "frame" of your game loop has completed, most commonly after the draw call
        pub fn cleanForNextFrame(self: *Self) void {
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
        pub fn newEnt(self: *Self) ztg.Entity {
            const ent = blk: {
                if (self.next_ent.toInt() >= max_entities) {
                    break :blk getOpenEntityId(self.entities, @enumFromInt(0)) orelse self.handleEntOverflow();
                } else if (!self.entities.hasEntity(self.next_ent)) {
                    break :blk self.next_ent;
                } else {
                    break :blk getOpenEntityId(self.entities, @enumFromInt(self.next_ent.toInt() + 1)) orelse self.handleEntOverflow();
                }
            };

            self.entities.append(ent);
            self.entities.setParent(ent, null) catch unreachable;
            self.next_ent = @enumFromInt(self.next_ent.toInt() + 1);

            return ent;
        }

        /// Creates a new entity and gives it `component`
        pub fn newEntWith(self: *Self, components: anytype) !ztg.Entity {
            const ent = self.newEnt();
            try self.giveComponents(ent, components);
            return ent;
        }

        fn getOpenEntityId(entities: *const EntityArray, from: ztg.Entity) ?ztg.Entity {
            for (from.toInt()..max_entities) |e| if (!entities.hasEntity(@enumFromInt(e))) return @enumFromInt(e);
            for (0..from.toInt()) |e| if (!entities.hasEntity(@enumFromInt(e))) return @enumFromInt(e);
            return null;
        }

        fn handleEntOverflow(self: *Self) ztg.Entity {
            return switch (on_ent_overflow) {
                .crash => self.crash(std.fmt.comptimePrint("Exceeded entity limit of {}.", .{max_entities}), .hit_ent_limit),
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
            self.entities.append(ent);
        }

        fn commands_newEnt(ptr: *anyopaque) ztg.Entity {
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
        }

        fn commands_removeEnt(ptr: *anyopaque, ent: ztg.Entity) Allocator.Error!void {
            try commandsCast(ptr).removeEnt(ent);
        }

        fn giveComponentSingle(self: *Self, ent: ztg.Entity, comp: anytype) anyerror!void {
            if (comptime comp_types.len == 0) @compileError("World has no registered components and cannot add components");
            if (!self.entities.hasEntity(ent)) return error.EntityDoesntExist;

            const Component = @TypeOf(comp);
            const comp_id = comptime util.indexOfType(comp_types, Component) orelse
                util.compileError("Tried to give entity Component of type `{s}`, which was not registred.", .{@typeName(Component)});

            self.entities.comp_masks[ent.toInt()].set(comp_id);
            const comp_ptr = try self.comp_arrays[comp_id].assign(self.alloc, ent, comp);
            try self.on_added_fns[comp_id](self, comp_ptr, ent);
        }

        /// Adds the components to the entity `ent`.
        ///
        /// Possible types for `components`:
        /// + tuple { T, V, ... }, where types within the tuple are registered components
        /// + struct { t: T, v: V, ... }, where types within the struct are registered components,
        ///     and the struct itself has an `is_component_bundle` public decl
        ///
        /// If any of the types passed in the tuple/struct components have the `is_component_bundle`
        /// public decl, they will be treated as component bundles and recursively added
        ///
        /// This has a chance to invalidate component pointers
        pub fn giveComponents(self: *Self, ent: ztg.Entity, components: anytype) !void {
            if (comptime comp_types.len == 0) @compileError("World has no registered components and cannot add components");
            const Components = @TypeOf(components);

            if (@typeInfo(Components) == .@"struct" and
                !@typeInfo(Components).@"struct".is_tuple and
                !@hasDecl(Components, "is_component_bundle"))
            {
                @compileError(
                    \\Struct passed to giveComponents does not have a public is_component_bundle decl,
                    \\if it is not a bundle wrap it in an anonymous tuple."
                );
            }

            inline for (std.meta.fields(Components)) |field| {
                if (comptime util.isContainer(field.type) and @hasDecl(field.type, "is_component_bundle")) {
                    try giveComponents(self, ent, @field(components, field.name));
                } else {
                    try giveComponentSingle(self, ent, @field(components, field.name));
                }
            }
        }

        fn commands_giveComponent(
            ptr: *anyopaque,
            ent: ztg.Entity,
            component_id: util.CompId,
            alignment: u29,
            data: *const anyopaque,
        ) anyerror!void {
            if (comptime comp_types.len == 0) @compileError("World has no registered components and cannot add components");
            var self = commandsCast(ptr);

            if (component_id >= comp_types.len) return error.UnregisteredComponent;
            if (!self.entities.hasEntity(ent)) return error.EntityDoesntExist;

            self.entities.comp_masks[ent.toInt()].set(component_id);
            var arr = try self.getListById(component_id);

            if (self.getComponentPtr_fromCompId(ent, component_id)) |comp_ptr| {
                // entity already has this component, so just overwrite it
                @memcpy(@as([*]u8, @ptrCast(@alignCast(comp_ptr))), @as([*]const u8, @ptrCast(data))[0..arr.components_data.entry_size]);
                try self.on_added_fns[component_id](self, comp_ptr, ent);
            } else if (arr.willResize()) {
                // we cant add the component right now, because then the pointers in the calling system will become invalid,
                // so we place the data on the heap and queue for its addition.
                //
                // also, probably unsafe :)
                // only because we have an alignment at runtime instead of comptime :,(
                //
                // TODO: amortize this
                const alloced_data = self.frame_alloc.rawAlloc(arr.components_data.entry_size, .fromByteUnits(alignment), @returnAddress()) orelse return error.OutOfMemory;
                @memcpy(alloced_data, @as([*]const u8, @ptrCast(data))[0..arr.components_data.entry_size]);
                try self.changes_queue.append(.{ .added_component = .{
                    .ent = ent,
                    .component_id = component_id,
                    .data = alloced_data,
                } });
            } else {
                const comp_ptr = try arr.assignData(self.alloc, ent, data);
                try self.on_added_fns[component_id](self, comp_ptr, ent);
            }
        }

        /// Removes component of type `Component` from entity `ent`
        pub fn removeComponent(
            self: *Self,
            ent: ztg.Entity,
            comptime Component: type,
        ) (error{EntityDoesntExist} || Allocator.Error)!void {
            try self.removeComponent_fromCompId(ent, comptime util.indexOfType(comp_types, Component) orelse
                util.compileError("Component of type `{s}` was not registered and cannot be removed", .{@typeName(Component)}));
        }

        fn commands_removeComponent(
            ptr: *anyopaque,
            ent: ztg.Entity,
            comp_id: util.CompId,
        ) ztg.Commands.RemoveComponentError!void {
            if (comp_id >= comp_types.len) return error.UnregisteredComponent;
            try commandsCast(ptr).removeComponent_fromCompId(ent, comp_id);
        }

        fn removeComponent_fromCompId(
            self: *Self,
            ent: ztg.Entity,
            comp_id: util.CompId,
        ) ztg.Commands.RemoveComponentError!void {
            if (comptime comp_types.len == 0) @compileError("World has no registered components to remove.");
            if (!self.entities.hasEntity(ent)) return error.EntityDoesntExist;

            try self.changes_queue.append(.{ .removed_component = .{
                .ent = ent,
                .component_id = comp_id,
            } });
        }

        /// Returns true or false depending on whether `ent` has been assigned a component of type `Component`
        pub fn checkEntHas(self: *Self, ent: ztg.Entity, comptime Component: type) bool {
            return self.comp_arrays[
                comptime util.indexOfType(comp_types, Component) orelse
                    util.compileError("Component of type `{s}` was not registered", .{@typeName(Component)})
            ].contains(ent);
        }

        fn commands_checkEntHas(ptr: *anyopaque, ent: ztg.Entity, component_id: util.CompId) ztg.Commands.ComponentError!bool {
            if (comptime comp_types.len == 0) @compileError("World has no registered components to check for.");
            const self = commandsCast(ptr);
            for (self.changes_queue.items) |ch| switch (ch) {
                .added_component => |added| if (added.ent == ent and added.component_id == component_id) return true,
                else => {},
            };
            return self.comp_arrays[component_id].contains(ent);
        }

        /// Returns an optional pointer to the component assigned to `ent`
        pub fn getComponentPtr(self: *Self, ent: ztg.Entity, comptime Component: type) ?*anyopaque {
            return self.getComponentPtr_fromCompId(ent, comptime util.indexOfType(comp_types, Component) orelse
                util.compileError("Component of type `{s}` was not registered and no pointer can be obtained.", .{@typeName(Component)}));
        }

        fn commands_getComponentPtr(ptr: *anyopaque, ent: ztg.Entity, comp_id: util.CompId) ztg.Commands.ComponentError!?*anyopaque {
            return commandsCast(ptr).getComponentPtr_fromCompId(ent, comp_id);
        }

        fn getComponentPtr_fromCompId(self: *Self, ent: ztg.Entity, comp_id: util.CompId) ?*anyopaque {
            if (comptime comp_types.len == 0) @compileError("World has no registered components to get the pointer of.");
            for (self.changes_queue.items) |ch| switch (ch) {
                .added_component => |added| if (added.ent == ent and added.component_id == comp_id) return added.data,
                else => {},
            };
            return self.comp_arrays[comp_id].get(ent);
        }

        /// Returns a copy of the resource T in this world
        pub fn getRes(self: Self, comptime T: type) T {
            if (comptime !util.typeArrayHas(added_resources, T)) util.compileError("World does not have resource of type `{s}`", .{@typeName(T)});
            return @field(self.resources, std.fmt.comptimePrint("{}", .{util.indexOfType(added_resources, T).?}));
        }

        /// Returns a pointer to the resource T in this world
        pub fn getResPtr(self: *Self, comptime T: type) *T {
            if (comptime !util.typeArrayHas(added_resources, T)) util.compileError("World does not have resource of type `{s}`", .{@typeName(T)});
            return &@field(self.resources, std.fmt.comptimePrint("{}", .{util.indexOfType(added_resources, T).?}));
        }

        fn commands_getResPtr(ptr: *anyopaque, utp: ztg.meta.Utp) error{UnregisteredResource}!*anyopaque {
            inline for (added_resources, 0..) |T, i| {
                if (ztg.meta.utpOf(T) == utp) return @ptrCast(&@field(commandsCast(ptr).resources, std.fmt.comptimePrint("{}", .{i})));
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
        pub fn query(self: *Self, alloc: std.mem.Allocator, comptime QT: type) !QT {
            if (comptime QT.has_entities and QT.req_types.types.len == 0) return self.queryJustEntities(alloc, QT);

            const req_ids = util.idsFromTypes(QT.req_types.types);
            const opt_ids = util.idsFromTypes(QT.opt_types.types);
            const with_ids = util.idsFromTypes(QT.with_types.types);
            const without_ids = util.idsFromTypes(QT.without_types.types);

            var qlists: [req_ids.len + opt_ids.len]QueryList = undefined;
            const checked_entities = try self.initQueryLists(&req_ids, &opt_ids, &with_ids, &qlists);

            var out = try QT.init(alloc, checked_entities.len);
            if (checked_entities.len == 0) return out;

            const comp_mask, const negative_mask = getCompMasks(&.{ &req_ids, &with_ids }, &.{&without_ids});

            // Link qlists and the result query
            for (&qlists) |*list| {
                switch (list.out) {
                    .required => |*req| req.* = out.comp_ptrs[list.out_idx],
                    .optional => |*opt| opt.* = if (comptime QT.opt_types.types.len > 0) out.opt_ptrs[list.out_idx] else unreachable,
                }
            }

            out.len = self.fillQuery(
                checked_entities,
                &qlists,
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

                out.entities[len] = ent.toEntity();
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
            req_ids: []const util.CompId,
            opt_ids: []const util.CompId,
            with_ids: []const util.CompId,
            lists: []QueryList,
        ) ![]const ztg.Entity {
            var idx: usize = 0;

            const first_arr = self.getListById(req_ids[0]) catch unreachable;
            var smallest: []const ztg.Entity = first_arr.entities.items;
            lists[0] = QueryList.init(first_arr, 0, .required);

            for (req_ids[1..], 1..) |id, i| {
                const check = self.getListById(id) catch unreachable;
                idx += 1;
                lists[idx] = QueryList.init(check, i, .required);

                if (check.len() < smallest.len) smallest = check.entities.items;
            }

            for (opt_ids, 0..) |id, i| {
                const check = self.getListById(id) catch unreachable;
                idx += 1;
                lists[idx] = QueryList.init(check, i, .optional);
            }

            for (with_ids) |id| {
                const check = self.getListById(id) catch unreachable;
                if (check.len() < smallest.len) smallest = check.entities.items;
            }

            return smallest;
        }

        fn getCompMasks(
            comp_ids_list: []const []const util.CompId,
            negative_ids_list: []const []const util.CompId,
        ) struct { ComponentMask, ComponentMask } {
            var comp_mask = ComponentMask.initEmpty();
            var negative_mask = ComponentMask.initEmpty();

            for (comp_ids_list) |ids| for (ids) |id| comp_mask.set(id);
            for (negative_ids_list) |ids| for (ids) |id| {
                if (builtin.mode == .Debug and id >= comp_types.len)
                    std.debug.panic("Trying to query without ID {}, which isn't registered", .{id});
                negative_mask.set(id);
            };

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
                const ent_mask = self.entities.comp_masks[@intFromEnum(ent)];

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

        fn entPassesCompMasks(ent_mask: ComponentMask, comp_mask: ComponentMask, negative_mask: ComponentMask) bool {
            return ent_mask.supersetOf(comp_mask) and ent_mask.intersectWith(negative_mask).eql(ComponentMask.initEmpty());
        }

        fn ParamsForSystem(comptime params: []const std.builtin.Type.Fn.Param) type {
            var types: [params.len]type = undefined;
            for (params, &types) |p, *t| t.* = p.type.?;
            return std.meta.Tuple(&types);
        }

        /// Generates the arguments tuple for a desired system based on its parameters.
        /// You shouldn't need to use this, just add the function to the desired stage.
        pub fn initParamsForSystem(self: *Self, alloc: std.mem.Allocator, comptime params: []const std.builtin.Type.Fn.Param) !ParamsForSystem(params) {
            if (comptime params.len == 0) return ParamsForSystem(params){};

            var out: ParamsForSystem(params) = undefined;
            inline for (out, 0..) |param, i| {
                out[i] = try self.initParam(alloc, @TypeOf(param));
            }
            return out;
        }

        fn initParam(self: *Self, alloc: std.mem.Allocator, comptime T: type) !T {
            if (comptime T == ztg.Commands) {
                return self.commands();
            } else if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "IsQueryType")) {
                return self.query(alloc, T);
            } else if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "EventSendType")) {
                return .{
                    .alloc = alloc,
                    .event_pool = self.event_pools.getPtr(T.EventSendType),
                };
            } else if (comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "EventRecvType")) {
                return .{
                    .events = self.event_pools.getPtr(T.EventRecvType),
                };
            } else if (comptime util.typeArrayHas(added_resources, ztg.meta.DerefType(T)) or util.typeArrayHas(added_resources, T)) {
                if (comptime util.typeArrayHas(added_resources, T)) {
                    return self.getRes(T);
                } else if (comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) {
                    return self.getResPtr(@typeInfo(T).pointer.child);
                }
            }

            util.compileError("Argument `{s}` not allowed in system. If it is a resource remember to add it to the WorldBuilder.", .{@typeName(T)});
        }

        pub fn deinitParamsForSystem(self: *Self, alloc: std.mem.Allocator, args: anytype) void {
            _ = self;
            inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
                if (comptime @typeInfo(args_field.type) == .@"struct" and @hasDecl(args_field.type, "query_types")) {
                    @field(args, args_field.name).deinit(alloc);
                }
            }
        }

        /// Returns whether the underlying WorldBuilder included a namespace
        /// while it was being built.
        pub fn hasIncluded(comptime Namespace: type) bool {
            comptime return included.has(Namespace);
        }

        fn commands_hasIncluded(type_utp: ztg.meta.Utp) bool {
            return util.typeArrayHasUtp(included, type_utp);
        }

        fn getListOf(self: *Self, comptime T: type) *ComponentArray {
            const idx = comptime util.indexOfType(comp_types, T) orelse util.compileError("Tried to get list of Component `{s}`, which was not registred.", .{@typeName(T)});
            return &self.comp_arrays[idx];
        }

        fn getListById(self: *Self, id: util.CompId) !*ComponentArray {
            if (comptime builtin.mode == .Debug) if (id >= self.comp_arrays.len) return error.UnregisteredComponent;
            return &self.comp_arrays[id];
        }

        fn commandsCast(ptr: *anyopaque) *Self {
            return @ptrCast(@alignCast(ptr));
        }

        fn commandsCastConst(ptr: *const anyopaque) *const Self {
            return @ptrCast(@alignCast(ptr));
        }

        fn crash(self: *Self, comptime crash_msg: []const u8, r: ztg.CrashReason) noreturn {
            on_crash_fn(self.commands(), r) catch |err| ztg.log.err("onCrashFn errored due to {}", .{err});
            @panic(crash_msg);
        }
    };
}

const ComponentChange = struct {
    ent: ztg.Entity,
    component_id: util.CompId,
};

/// For internal queueing of commands. Cleared after a stage is completed.
const ChangeQueue = std.ArrayList(ChangeQueueItem);
const ChangeQueueItem = union(enum) {
    added_component: struct {
        ent: ztg.Entity,
        component_id: util.CompId,
        data: *anyopaque,
    },
    removed_ent: ztg.Entity,
    removed_component: ComponentChange,
};

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

    const MyEmpty = struct {};

    pub fn include(comptime wb: *WorldBuilder) void {
        // Registering components
        wb.addComponents(&.{ MyComponent, MyEmpty });

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
        for (q.items(MyComponent)) |mc| {
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
    const world = MyWorld.init(std.testing.failing_allocator);
    try std.testing.expectError(error.OutOfMemory, world);
}

test "adding/removing entities" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    // Generally, youd do this by requesting a Commands argument in your system
    const ent = world.newEnt();
    try world.giveComponents(ent, .{
        my_file.MyComponent{
            .position = 0,
            .speed = 100,
        },
        my_file.MyEmpty{},
    });

    try world.runStage(.update);

    var q = try world.query(std.testing.allocator, ztg.Query(.{my_file.MyComponent}));
    defer q.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 0), q.single(my_file.MyComponent).score);

    try world.runStage(.update);

    try testing.expectEqual(@as(usize, 1), q.single(my_file.MyComponent).score);

    try world.removeEntAndAssociatedComponents(ent);

    var q2 = try world.query(std.testing.allocator, ztg.Query(.{my_file.MyComponent}));
    defer q2.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 0), q2.len);
}

test "adding/removing components" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    const com = world.commands();

    const ent = try com.newEntWith(.{
        my_file.MyComponent{
            .position = 10,
            .speed = 20,
        },
        my_file.MyEmpty{},
    });

    try world.postSystemUpdate();

    try testing.expectEqual(@as(i32, 10), ent.getComponentPtr(my_file.MyComponent).?.position);
    try testing.expect(ent.checkHas(my_file.MyComponent));
    try testing.expect(!world.checkEntHas(ent.ent, ztg.base.Transform));

    try ent.removeComponent(my_file.MyComponent);

    try world.postSystemUpdate();

    try testing.expect(!ent.checkHas(my_file.MyComponent));

    try std.testing.expectError(error.EntityDoesntExist, world.giveComponents(@enumFromInt(512), .{ztg.base.Name{"bad"}}));
}

test "overwriting components" {
    var world = try MyWorld.init(std.testing.allocator);
    defer world.deinit();

    const com = world.commands();

    const ent = try com.newEntWith(.{
        my_file.MyComponent{
            .position = 10,
            .speed = 20,
        },
        my_file.MyEmpty{},
    });

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
        ztg.base.Transform{},
        my_file.MyComponent{
            .position = 30,
            .speed = 1,
        },
    });

    var q = try world.query(std.testing.allocator, ztg.Query(.{ my_file.MyComponent, ?ztg.base.Lifetime, ztg.Without(ztg.base.Transform), ztg.With(ztg.base.Name) }));
    defer q.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 1), q.len);

    var q2 = try world.query(std.testing.allocator, ztg.Query(.{ ztg.Entity, ztg.Without(ztg.base.Transform), ztg.With(ztg.base.Name) }));
    defer q2.deinit(std.testing.allocator);

    try testing.expectEqual(@as(usize, 1), q.len);
}

test "callbacks" {
    const systems = struct {
        var run: bool = false;

        fn load() void {
            run = true;
        }

        fn addAndRemove(com: ztg.Commands) !void {
            try std.testing.expect(run);

            const ent = try com.newEntWith(.{Thing{}});
            try com.removeEnt(ent.ent);
        }

        const Thing = struct {
            var run_on_added: bool = false;
            var run_on_removed: bool = false;

            pub fn onAdded(_: ztg.Entity, _: ztg.Commands) void {
                run_on_added = true;
            }
            pub fn onRemoved() void {
                run_on_removed = true;
            }
        };
    };

    const EmptyCbWorld = comptime blk: {
        var wb = WorldBuilder.init(&.{});
        wb.addComponents(&.{systems.Thing});
        wb.addSystemsToStage(.load, .{ systems.load, ztg.after(.body, systems.addAndRemove) });
        break :blk wb.Build();
    };

    var world = try EmptyCbWorld.init(std.testing.allocator);
    defer world.deinit();

    try world.runStage(.load);

    const ent = try world.newEntWith(.{systems.Thing{}});
    try world.removeEnt(ent);

    try world.postSystemUpdate();

    try std.testing.expect(systems.run);
    try std.testing.expect(systems.Thing.run_on_added);
    try std.testing.expect(systems.Thing.run_on_removed);

    const q = try world.query(std.testing.allocator, ztg.Query(.{ztg.Entity}));
    defer q.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), q.len);
}
