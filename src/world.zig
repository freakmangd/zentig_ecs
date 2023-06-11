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

pub fn World(comptime wb: WorldBuilder) type {
    if (wb.max_entities == 0) @compileError("Cannot have max_ents == 0.");
    if (wb.max_entities > 100_000) @compileError("Max entities cannot exceed 100,000.");

    const Resources = wb.resources.Build();
    const StagesList = @import("stages.zig").Init(wb.stage_defs);
    const MinEntityIndex = std.meta.Int(.unsigned, @typeInfo(std.math.IntFittingRange(0, wb.max_entities)).Int.bits + 1);
    const ComponentArray = ca.ComponentArray(MinEntityIndex, wb.max_entities);
    const EntityArray = ea.EntityArray(wb.max_entities);

    const comp_types_len = wb.comp_types.types.len;

    return struct {
        const Self = @This();
        const stages_list = StagesList{ .inner = .{} };

        alloc: Allocator,

        frame_arena: std.heap.ArenaAllocator,
        frame_alloc: Allocator = undefined,

        next_ent: ecs.Entity = 0,
        entities: EntityArray,

        comp_arrays_buffers: [comp_types_len][]u8 = undefined,
        comp_arrays_fbas: [comp_types_len]std.heap.FixedBufferAllocator = undefined,
        comp_arrays: [comp_types_len]ComponentArray = undefined,

        resources: Resources = .{},
        event_pools: EventPools(wb.event_types),
        commands_vtable: Commands.Vtable,

        changes_list: ChangesList = undefined,
        remove_queue: RemoveQueue = undefined,

        /// User must call `.deinit()` once the world is to be descoped. (in a defer block preferrably)
        /// All systems that request an `Allocator` will get the one passed here.
        pub fn init(alloc: Allocator) !*Self {
            if (builtin.mode == .Debug and wb.warnings.len > 0) {
                std.log.warn("\n====== World was constructed with warnings: ======\n" ++ wb.warnings, .{});
            }

            std.debug.print("Entity has utp {}\n", .{TypeMap.uniqueTypePtr(ecs.Entity)});
            inline for (wb.comp_types.types) |T| {
                std.debug.print("{s} has utp {}\n", .{ @typeName(T), TypeMap.uniqueTypePtr(T) });
            }

            var self = try alloc.create(Self);
            self.* = Self{
                .alloc = alloc,

                .frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .entities = EntityArray.init(),

                .commands_vtable = .{
                    .add_component_fn = Self.commands_addComponent,
                    .remove_ent_fn = Self.commands_removeEnt,
                    .new_ent_fn = Self.commands_newEnt,
                    .run_stage_fn = Self.commands_runStageFn,
                    .get_entities_fn = Self.commands_getEntities,
                },

                .event_pools = EventPools(wb.event_types){},
            };

            self.frame_alloc = self.frame_arena.allocator();
            self.changes_list = ChangesList.init(self.frame_alloc);
            self.remove_queue = RemoveQueue.init(self.frame_alloc);

            // CHANGE: Component data should not be pre-allocated.
            inline for (wb.comp_types.types, 0..) |CT, i| {
                const max_cap = comptime blk: {
                    if (@hasDecl(CT, "max_entities")) break :blk CT.max_entities;
                    break :blk wb.max_entities;
                };
                var buf = try alloc.alloc(u8, (@sizeOf(CT) + @sizeOf(MinEntityIndex) + @sizeOf(ecs.Entity)) * wb.max_entities);
                self.comp_arrays_buffers[i] = buf;
                self.comp_arrays_fbas[i] = std.heap.FixedBufferAllocator.init(buf);
                self.comp_arrays[i] = try ComponentArray.init(self.comp_arrays_fbas[i].allocator(), CT, max_cap);
            }

            self.getResPtr(Allocator).* = alloc;

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.event_pools.deinit(self.alloc);
            self.remove_queue.deinit();
            self.changes_list.deinit();
            self.frame_arena.deinit();

            inline for (wb.comp_types.types, &self.comp_arrays, self.comp_arrays_buffers) |CT, *c, buf| {
                if (comptime @hasDecl(CT, "onDestroy")) self.deinit_items(c, CT);
                c.deinit();
                self.alloc.free(buf);
            }

            inline for (std.meta.fields(Resources)) |res_field| {
                var res = @field(self.resources, std.fmt.comptimePrint("{}", .{wb.added_resources.indexOf(res_field.type).?}));
                if (@hasDecl(res_field.type, "deinit")) {
                    res.deinit();
                }
            }

            self.alloc.destroy(self);
        }

        fn deinit_items(self: *Self, comp_arr: *ComponentArray, comptime T: type) void {
            const member_fn_type = comptime util.isMemberFn(T, T.onDestroy);
            const args = self.initArgsForSystem(@TypeOf(T.onDestroy), if (member_fn_type != .non_member) .member_fn else .static_fn) catch {
                @panic("Failed to get args for deinit system for type `" ++ @typeName(T) ++ "`.");
            };

            if (comptime @sizeOf(T) > 0) {
                var comp_iter = comp_arr.iterator();
                while (comp_iter.nextAs(T)) |comp| @call(.auto, T.onDestroy, blk: {
                    break :blk if (comptime member_fn_type != .non_member) .{if (member_fn_type == .by_value) comp.* else comp} ++ args else args;
                });
            } else {
                for (0..comp_arr.len()) |_| @call(.auto, T.onDestroy, blk: {
                    break :blk if (comptime member_fn_type != .non_member) .{T{}} ++ args else args;
                });
            }
        }

        /// If you are going to run multiple stages in a row, consider `.runStageList()`
        ///
        /// Example:
        /// ```zig
        /// world.runStage(.render);
        /// ```
        pub fn runStage(self: *Self, comptime stage_id: StagesList.StageField) anyerror!void {
            try stages_list.runStage(self, stage_id);
            try self.postStageCleanup();
        }

        pub fn runStageByName(self: *Self, stage_name: []const u8) anyerror!void {
            try stages_list.runStageRuntime(self, stage_name);
            try self.postStageCleanup();
        }

        fn commands_runStageFn(ptr: *anyopaque, stage_name: []const u8) anyerror!void {
            try commandsCast(ptr).runStageByName(stage_name);
        }

        /// If you are going to run built in pre_X, X, post_X stages, consider `.runInitStages()`, `.runUpdateStages()`, or `.runDrawStages()`
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

        fn postStageCleanup(self: *Self) anyerror!void {
            if (comptime comp_types_len == 0) return;

            for (self.remove_queue.items) |rem| {
                switch (rem) {
                    .removed_ent => |ent| self.postStageCleanup_removeEnt(ent),
                    .removed_component => |comp| _ = self.comp_arrays[comp.component_id].swapRemove(comp.ent),
                }
            }

            self.remove_queue.clearAndFree();
        }

        inline fn postStageCleanup_removeEnt(self: *Self, ent: ecs.Entity) void {
            const res = self.entities.swapRemoveEnt(ent);
            if (res == false) return;

            for (&self.comp_arrays) |*list| {
                if (list.contains(ent)) _ = list.swapRemove(ent);
            }
        }

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
        /// `.crash` => (default) invokes the crash function, which will most likely panic. See `WorldBuilder.setCrashFn`
        /// `.overwrite_last` => returns the last entity in the entity list, after removing all of its components.
        /// `.overwrite_first` => returns the first entity in the entity list, after removing all of its components
        pub fn newEnt(self: *Self) Allocator.Error!ecs.Entity {
            if (self.next_ent + 1 > wb.max_entities) {
                const res = cleanEntList(self);
                if (res == .failure) {
                    switch (wb.on_ent_overflow) {
                        .crash => self.crash(std.fmt.comptimePrint("Exceeded entity limit of {}.", .{wb.max_entities}), .hit_ent_limit),
                        .overwrite_last => {
                            const ent = self.entities.getEntityAt(self.entities.len - 1);
                            self.postStageCleanup_removeEnt(ent);
                            self.entities.append(ent);
                            return ent;
                        },
                        .overwrite_first => {
                            const ent = self.entities.getEntityAt(0);
                            self.postStageCleanup_removeEnt(ent);
                            self.entities.append(ent);
                            return ent;
                        },
                    }
                }
            }

            try self.changes_list.append(.{ .added_ent = self.next_ent });
            self.entities.append(self.next_ent);
            self.next_ent += 1;
            return self.next_ent - 1;
        }

        fn commands_newEnt(ptr: *anyopaque) Allocator.Error!ecs.Entity {
            return commandsCast(ptr).newEnt();
        }

        fn cleanEntList(self: *Self) ecs.Status {
            if (self.entities.len + 1 > wb.max_entities) {
                return .failure;
            }

            self.entities.reset();

            self.next_ent = 0;
            for (self.entities.constSlice(), 0..) |ent, i| {
                defer {
                    self.entities.append(self.next_ent);
                    self.next_ent += 1;
                }

                if (ent == self.next_ent) {
                    continue;
                }

                // TODO: make sure this works.
                // if next entity was added this frame
                if (self.entities.len - i == self.changes_list.items.len) {
                    // update changes list to reflect new entity ids
                    for (self.changes_list.items, 0..) |*cl, j| {
                        switch (cl.*) {
                            .added_ent => |*ae| ae.* = self.next_ent + j,
                            else => {},
                        }
                    }
                }

                for (&self.comp_arrays) |*arr| {
                    arr.reassign(ent, self.next_ent);
                }
            }

            return .success;
        }

        /// Queues the removal of all components in lists correlated with `ent`
        pub fn removeEnt(self: *Self, ent: ecs.Entity) Allocator.Error!void {
            try self.remove_queue.append(.{ .removed_ent = ent });
            try self.changes_list.append(.{ .removed_ent = ent });
        }

        fn commands_removeEnt(ptr: *anyopaque, ent: ecs.Entity) Allocator.Error!void {
            try commandsCast(ptr).removeEnt(ent);
        }

        fn commands_getEntities(ptr: *anyopaque) []const ecs.Entity {
            return commandsCast(ptr).entities.constSlice();
        }

        /// Adds a component at the Entity indexworld
        pub fn giveEnt(self: *Self, ent: ecs.Entity, comptime Component: type, comp: Component) void {
            const idx = comptime wb.comp_types.indexOf(Component) orelse @compileError("Tried to add Component " ++ @typeName(Component) ++ ", which was not registred.");
            self.comp_arrays[idx].assign(ent, comp);
            try self.changes_list.append(.{ .added_component = idx });
        }

        /// Adds every field in the components object to its component list at the Entity index
        pub fn giveEntMany(self: *Self, ent: ecs.Entity, components: anytype) void {
            inline for (std.meta.fields(@TypeOf(components))) |field| {
                self.giveEnt(ent, field.type, @field(components, field.name));
            }
        }

        pub fn removeComponent(self: *Self, ent: ecs.Entity, comptime Component: type) ca.Error!void {
            try self.remove_queue.append(.{ .removed_component = .{ .ent = ent, .component_id = wb.comp_types.indexOf(Component) } });
        }

        fn commands_addComponent(ptr: *anyopaque, ent: ecs.Entity, component_utp: TypeMap.UniqueTypePtr, data: *const anyopaque) ca.Error!void {
            if (comptime wb.comp_types.types.len == 0) return;
            const idx = wb.comp_types.fromUtp(component_utp) orelse std.debug.panic("Tried to add unregistered Component with UTP {}, to ent {}.", .{ component_utp, ent });
            commandsCast(ptr).comp_arrays[idx].assignData(ent, data);
        }

        pub fn getRes(self: Self, comptime T: type) T {
            if (comptime !wb.added_resources.has(T)) std.debug.panic("World does not have resource of type {s}", .{@typeName(T)});
            return @field(self.resources, std.fmt.comptimePrint("{}", .{wb.added_resources.indexOf(T).?}));
        }

        pub fn getResPtr(self: *Self, comptime T: type) *T {
            if (comptime !wb.added_resources.has(T)) std.debug.panic("World does not have resource of type {s}", .{@typeName(T)});
            return &@field(self.resources, std.fmt.comptimePrint("{}", .{wb.added_resources.indexOf(T).?}));
        }

        fn query(self: *Self, comptime QT: type) !QT {
            _ = self;
            @compileError("unimplemented");
        }

        fn queryComptime(self: *Self, comptime QT: type) !QT {
            _ = self;
            @compileError("unimplemented");
        }

        fn queryWithOptionsComptime(
            self: *Self,
            comptime query_types: []const type,
            comptime options: []const type,
            smallest_list: *ComponentArray,
            smallest_list_idx: usize,
            components_out: [][]*anyopaque,
            comptime has_entities: bool,
            entities_out: []ecs.Entity,
        ) !void {
            @setRuntimeSafety(false); // TODO: replace with @optimizeFor(.ReleaseFast);
            _ = options;

            var lists: [query_types.len - 1]*ComponentArray = undefined;
            inline for (query_types, &lists, 0..) |QT, *ol, i| {
                if (i != smallest_list_idx) ol.* = self.getListOf(QT);
            }

            smallest_list_ents_loop: for (smallest_list.id_lookup.written_indexes.constSlice(), 0..) |ent, ent_idx| {
                components_out[smallest_list_idx][ent_idx] = smallest_list.get(ent).?;

                for (lists, 0..) |list, i| {
                    if (list.get(ent)) |comp| {
                        components_out[i][ent_idx] = comp;
                    } else {
                        continue :smallest_list_ents_loop;
                    }
                }

                if (comptime has_entities) entities_out[ent_idx] = ent;
            }
        }

        fn queryWithOptions(
            query_lists: []const *ComponentArray,
            smallest_list: *ComponentArray,
            smallest_list_idx: usize,
            components_out: [][]*anyopaque,
            entities_out: ?[]ecs.Entity,
            comptime options: []const type,
        ) !void {
            //@setRuntimeSafety(false); // TODO: replace with @optimizeFor(.ReleaseFast);
            _ = options;

            smallest_list_ents_loop: for (smallest_list.entities.items, 0..) |ent, ent_idx| {
                components_out[smallest_list_idx][ent_idx] = smallest_list.get(ent).?;

                for (query_lists, 0..) |list, i| {
                    if (list.get(ent)) |comp| {
                        const comp_list_idx = if (i < smallest_list_idx) i else i + 1;
                        components_out[comp_list_idx][ent_idx] = comp;
                    } else {
                        continue :smallest_list_ents_loop; // skip to checking next entity in smallest_list's entities, skips adding the entity
                    }
                }

                if (entities_out) |eout| eout[ent_idx] = ent;
            }
        }

        const ArgsFnType = enum {
            static_fn,
            member_fn,
        };

        fn InitArgsOut(comptime SysFn: type, comptime fn_type: ArgsFnType) type {
            var params = @typeInfo(SysFn).Fn.params;
            if (fn_type == .member_fn) params = params[1..];
            return std.meta.Tuple(typeArrayFromParams(params));
        }

        pub fn initArgsForSystem(self: *Self, comptime SysFn: type, comptime fn_type: ArgsFnType) anyerror!InitArgsOut(SysFn, fn_type) {
            if (comptime @typeInfo(SysFn) != .Fn) @compileError("SysFn's type should be a function");
            if (comptime @typeInfo(SysFn).Fn.params.len == 0) return .{};

            var out: InitArgsOut(SysFn, fn_type) = undefined;

            inline for (out, 0..) |param, i| {
                const Param = @TypeOf(param);

                if (Param == Commands) {
                    out[i] = Commands{
                        .ctx = self,
                        .vtable = &self.commands_vtable,
                    };
                    continue;
                } else if (comptime @typeInfo(Param) == .Struct and @hasDecl(Param, "query_types")) {
                    var smallest = getSmallestListFrom(self, &Param.type_utps);
                    out[i] = try Param.init(self.frame_alloc, smallest[0].len());

                    try queryWithOptions(
                        smallest[2].constSlice(),
                        smallest[0],
                        smallest[1],
                        &out[i].comp_ptrs,
                        if (comptime Param.has_entities) out[i].entities else null,
                        Param.OptionsType,
                    );

                    continue;
                } else if (comptime @typeInfo(Param) == .Struct and @hasDecl(Param, "EventSendType")) {
                    out[i] = .{
                        .alloc = self.alloc,
                        .event_pool = self.event_pools.getPtr(Param.EventSendType),
                    };
                    continue;
                } else if (comptime @typeInfo(Param) == .Struct and @hasDecl(Param, "EventRecvType")) {
                    out[i] = .{
                        .items = self.event_pools.getPtr(Param.EventRecvType).items,
                    };
                    continue;
                } else if (comptime std.meta.trait.isSingleItemPtr(Param)) {
                    out[i] = self.getResPtr(std.meta.Child(Param));
                    continue;
                } else {
                    out[i] = self.getRes(Param);
                    continue;
                }

                @compileError("Argument " ++ @typeName(Param) ++ " not allowed in system. If it is a resource remember to add it to the WorldBuilder.");
            }

            return out;
        }

        fn getSmallestListFrom(
            self: *Self,
            utps: []const TypeMap.UniqueTypePtr,
        ) struct {
            *ComponentArray,
            usize,
            std.BoundedArray(*ComponentArray, 30),
        } {
            var smallest_idx: usize = 0;
            var smallest = self.getListFromUtp(utps[0]);

            var others = std.BoundedArray(*ComponentArray, 30).init(0) catch unreachable;
            others.append(smallest) catch unreachable;

            for (utps[1..], 1..) |qutp, i| {
                var check = self.getListFromUtp(qutp);
                others.append(check) catch unreachable;
                if (check.len() < smallest.len()) {
                    smallest = check;
                    smallest_idx = i;
                }
            }

            _ = others.swapRemove(smallest_idx);
            return .{ smallest, smallest_idx, others };
        }

        fn typeArrayFromParams(comptime params: []const std.builtin.Type.Fn.Param) []const type {
            var types: []const type = &.{};
            for (params) |p| types = types ++ .{p.type.?};
            return types;
        }

        pub fn deinitArgsForSystem(self: *Self, args: anytype) void {
            _ = args;
            _ = self;
            //inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
            //    if (comptime @typeInfo(args_field.type) == .Struct and @hasDecl(args_field.type, "query_types")) {
            //        @field(args, args_field.name).deinit(self.alloc);
            //    }
            //}
        }

        pub fn getListOf(self: *Self, comptime T: type) *ComponentArray {
            const idx = comptime wb.comp_types.indexOf(T) orelse @compileError("Tried to query Component " ++ @typeName(T) ++ ", which was not registred.");
            return &self.comp_arrays[idx];
        }

        fn getListFromUtp(self: *Self, utp: TypeMap.UniqueTypePtr) *ComponentArray {
            const idx = wb.comp_types.fromUtp(utp) orelse std.debug.panic("Tried to query Component with utp {}, which was not registred.", .{utp});
            return &self.comp_arrays[idx];
        }

        inline fn commandsCast(ptr: *anyopaque) *Self {
            return @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        }

        fn crash(self: *Self, comptime crash_msg: []const u8, r: ecs.CrashReason) void {
            const res = wb.on_crash_fn(.{ .ctx = self, .vtable = &self.commands_vtable }, r) catch |err| std.debug.panic("onCrashFn errored due to {}", .{err});
            if (res == .failure) @panic(crash_msg);
        }
    };
}

const RemoveQueue = std.ArrayList(union(enum) {
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

const ChangesList = std.ArrayList(union(enum) {
    added_ent: ecs.Entity,
    removed_ent: ecs.Entity,
    added_component: ComponentChange,
    removed_component: ComponentChange,
});

fn EventPools(comptime event_tm: TypeMap) type {
    const Inner = blk: {
        var tb = TypeBuilder.new(false, .Auto);
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
const MyWorld = WorldBuilder.new(.{
    base, physics, struct {
        pub fn include(comptime wb: *WorldBuilder) void {
            wb.addUpdateSystems(.{test_worldUpdate});
        }
    },
}).Build();

test "decls" {
    std.testing.refAllDecls(MyWorld);
}

test "resources" {
    var world = try MyWorld.init(testing.allocator);
    defer world.deinit();

    try testing.expectEqual(@as(usize, 0), world.getRes(base.Time).frameCount);

    try world.runUpdateStages();

    try testing.expectEqual(@as(usize, 1), world.getRes(base.Time).frameCount);

    var time = world.getResPtr(base.Time);
    time.frameCount = 100;

    try testing.expectEqual(@as(usize, 100), world.getRes(base.Time).frameCount);
}

fn test_worldUpdate(time: *base.Time) void {
    time.frameCount += 1;
}
