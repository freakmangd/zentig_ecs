const std = @import("std");
const testing = std.testing;
const util = @import("util.zig");
const ca = @import("component_array.zig");
const base = @import("mods/base.zig");
const physics = @import("mods/physics.zig");
const TypeMap = @import("type_map.zig");
const TypeBuilder = @import("type_builder.zig");
const Commands = @import("commands.zig");
const Allocator = std.mem.Allocator;
const ecs = @import("ecs.zig");

const ComponentChange = struct {
    ent: ecs.Entity,
    component_id: usize,
};

const RemoveQueue = std.ArrayListUnmanaged(union(enum) {
    removed_ent: ecs.Entity,
    removed_component: ComponentChange,
});

const ChangesList = std.ArrayListUnmanaged(union(enum) {
    added_ent: ecs.Entity,
    removed_ent: ecs.Entity,
    added_component: ComponentChange,
    removed_component: ComponentChange,
});

pub fn World(
    comptime max_ents: usize,
    comptime component_tm: TypeMap,
    comptime Resources: type,
    comptime resources_tm: TypeMap,
    comptime events_tm: TypeMap,
    comptime StagesList: type,
    comptime warnings: []const u8,
) type {
    return struct {
        const Self = @This();
        const stages_list = StagesList{ .inner = .{} };

        gpa: ?std.heap.GeneralPurposeAllocator(.{}),
        alloc: Allocator,

        frame_arena: std.heap.ArenaAllocator,
        frame_alloc: Allocator,

        rng: ?std.rand.DefaultPrng,

        next_ent: ecs.Entity = 0,

        entities: *std.BoundedArray(ecs.Entity, max_ents),

        comp_arrays: [component_tm.types.len]ca.ComponentArray(max_ents),
        resources: Resources = .{},
        event_pools: EventPools(events_tm),
        commands_vtable: Commands.Vtable,

        changes_list: ChangesList,
        remove_queue: RemoveQueue,

        /// User must call `.deinit()` once the world is to be descoped. (in a defer block preferrably)
        /// All systems that request a `WorldGpa` will get the one passed here, or if null get a GeneralPurposeAllocator.
        pub inline fn init() !Self {
            return initWith(null, null);
        }

        pub fn initWith(alloc_opt: ?Allocator, rand_opt: ?std.rand.Random) !Self {
            if (warnings.len > 0) {
                std.log.warn("World was constructed with warnings: " ++ warnings, .{});
            }

            var gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;

            const alloc: Allocator = blk: {
                if (alloc_opt) |alloc| {
                    break :blk alloc;
                } else {
                    gpa = std.heap.GeneralPurposeAllocator(.{}){};
                    break :blk gpa.?.allocator();
                }
            };

            var rng: ?std.rand.DefaultPrng = null;

            const rand: std.rand.Random = blk: {
                if (rand_opt) |rand| {
                    break :blk rand;
                } else {
                    const epoch = std.time.timestamp();
                    rng = std.rand.DefaultPrng.init(@bitCast(u64, epoch));
                    break :blk rng.?.random();
                }
            };

            var entities = try alloc.create(std.BoundedArray(ecs.Entity, max_ents));
            entities.* = try std.BoundedArray(ecs.Entity, max_ents).init(0);

            var frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

            var self = Self{
                .alloc = alloc,
                .gpa = gpa,

                .frame_arena = frame_arena,
                .frame_alloc = frame_arena.allocator(),

                .rng = rng,

                .entities = entities,
                .comp_arrays = undefined,
                .commands_vtable = .{
                    .add_component_fn = Self.commands_addComponent,
                    .new_ent_fn = Self.commands_newEnt,
                    .run_stage_fn = Self.commands_runStageFn,
                },

                .event_pools = EventPools(events_tm).init(),

                .changes_list = ChangesList{},
                .remove_queue = RemoveQueue{},
            };

            inline for (component_tm.types) |CT| {
                var buf = try alloc.alloc(u8, @sizeOf(CT) * max_ents);
                self.comp_arrays[comptime component_tm.indexOf(CT).?] = try ca.ComponentArray(max_ents).init(buf, CT);
            }

            self.getResPtr(Allocator).* = alloc;
            self.getResPtr(std.rand.Random).* = rand;

            return self;
        }

        pub fn deinit(self: *Self) void {
            if (comptime component_tm.types.len > 0) {
                self.alloc.destroy(self.entities);
            }

            self.remove_queue.deinit(self.frame_alloc);
            self.changes_list.deinit(self.frame_alloc);
            self.event_pools.deinit();

            inline for (component_tm.types, &self.comp_arrays) |CT, *c| {
                var buf = c.deinit(self, CT);
                self.alloc.free(buf);
            }

            inline for (std.meta.fields(Resources)) |res_field| {
                var res = @field(self.resources, std.fmt.comptimePrint("{}", .{resources_tm.indexOf(res_field.type).?}));
                if (@hasDecl(res_field.type, "deinit")) {
                    res.deinit();
                }
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
            if (self.comp_arrays.len == 0) return;

            for (self.remove_queue.items) |rem| {
                switch (rem) {
                    .removed_ent => |ent| self.postStageCleanup_removeEnt(ent),
                    .removed_component => |comp| self.comp_arrays[comp.component_id].swapRemove(comp.ent),
                }
            }
        }

        inline fn postStageCleanup_removeEnt(self: *Self, ent: ecs.Entity) void {
            for (&self.comp_arrays) |*list| {
                list.swapRemove(ent);
            }
        }

        pub fn cleanForNextFrame(self: *Self) void {
            self.remove_queue.clearAndFree(self.frame_alloc);
            self.changes_list.clearAndFree(self.frame_alloc);
            self.event_pools.clear();
        }

        /// Returns the next free index for components
        pub fn newEnt(self: *Self) error{Overflow}!ecs.Entity {
            self.next_ent = try std.math.add(ecs.Entity, self.next_ent, 1);
            return self.next_ent - 1;
        }

        fn commands_newEnt(ptr: *anyopaque) error{Overflow}!ecs.Entity {
            return try commandsCast(ptr).newEnt();
        }

        /// Queues the removal of all components in lists correlated with `ent`
        pub fn removeEnt(self: *Self, ent: ecs.Entity) Allocator.Error!void {
            try self.remove_queue.append(.{ ent, std.math.maxInt(usize) });
        }

        /// Adds a component at the Entity index
        pub fn giveEnt(self: *Self, ent: ecs.Entity, comptime Component: type, comp: Component) ca.Error!void {
            const idx = comptime component_tm.indexOf(Component) orelse @compileError("Tried to add Component " ++ @typeName(Component) ++ ", which was not registred.");
            try self.comp_arrays[idx].assign(ent, comp);
        }

        /// Adds every field in the components object to its component list at the Entity index
        pub fn giveEntMany(self: *Self, ent: ecs.Entity, components: anytype) ca.Error!void {
            inline for (std.meta.fields(@TypeOf(components))) |field| {
                try self.giveEnt(ent, field.type, @field(components, field.name));
            }
        }

        pub fn removeComponent(self: *Self, ent: ecs.Entity, comptime Component: type) ca.Error!void {
            try self.remove_queue.append(.{ ent, TypeMap.of(Component) });
        }

        fn commands_addComponent(ptr: *anyopaque, ent: ecs.Entity, component_utp: TypeMap.UniqueTypePtr, data: *const anyopaque) ca.Error!void {
            if (comptime component_tm.types.len == 0) return;
            const idx = component_tm.fromUtp(component_utp) orelse std.debug.panic("Tried to add Component with UTP {}, which was not registred, to ent {}.", .{ component_utp, ent });
            try commandsCast(ptr).comp_arrays[idx].assignData(ent, data);
        }

        pub fn getRes(self: Self, comptime T: type) T {
            if (comptime !resources_tm.has(T)) std.debug.panic("World does not have resource of type {s}", .{@typeName(T)});
            return @field(self.resources, std.fmt.comptimePrint("{}", .{resources_tm.indexOf(T).?}));
        }

        pub fn getResPtr(self: *Self, comptime T: type) *T {
            if (comptime !resources_tm.has(T)) std.debug.panic("World does not have resource of type {s}", .{@typeName(T)});
            return &@field(self.resources, std.fmt.comptimePrint("{}", .{resources_tm.indexOf(T).?}));
        }

        pub fn query(self: *Self, comptime query_types: anytype, comptime options: anytype) !ecs.Query(query_types, options) {
            var result = ecs.Query(query_types, options){};
            var smallest_idx: usize = 0;

            var comp0s = blk: {
                const start_list = if (comptime query_types[0] == ecs.Entity) 1 else 0;
                var smallest = self.getListOf(query_types[start_list]);
                inline for (query_types, 0..) |Q, i| {
                    if (comptime Q == ecs.Entity or i == start_list) continue;

                    var check = self.getListOf(Q);
                    if (check.len < smallest.len) {
                        smallest = check;
                        smallest_idx = i;
                    }
                }
                break :blk smallest;
            };

            comp0_ents_loop: for (comp0s.id_lookup.written_indexes.constSlice()) |ent| {
                var res_item: util.MultiArrayListElem(ecs.Query(query_types, options)) = undefined;

                inline for (query_types, 0..) |Q, i| {
                    const res_item_field = std.fmt.comptimePrint("{c}", .{@intCast(u8, 'a' + i)});

                    // no need to check if the smallest of the Query lists has the same entity as itself...
                    if (i == smallest_idx) {
                        @field(res_item, res_item_field) = comp0s.getAs(Q, ent).?;
                    } else {
                        var other_q = self.getListOf(Q);
                        if (!other_q.contains(ent)) continue :comp0_ents_loop; // skip to checking next entity in component 0's entities, skips result.append

                        @field(res_item, res_item_field) = other_q.getAs(Q, ent).?;
                    }
                }

                try result.append(self.frame_alloc, res_item);
            }

            return result;
        }

        pub fn query2(self: *Self, query_tids: []const usize, comptime options: anytype) !ecs.QueryFromTids(query_types, options) {
            var result = ecs.Query(query_types, options){};
            var smallest_idx: usize = 0;

            var comp0s = blk: {
                const start_list = if (comptime query_types[0] == ecs.Entity) 1 else 0;
                var smallest = self.getListOf(query_types[start_list]);
                inline for (query_types, 0..) |Q, i| {
                    if (comptime Q == ecs.Entity or i == start_list) continue;

                    var check = self.getListOf(Q);
                    if (check.len < smallest.len) {
                        smallest = check;
                        smallest_idx = i;
                    }
                }
                break :blk smallest;
            };

            comp0_ents_loop: for (comp0s.id_lookup.written_indexes.constSlice()) |ent| {
                var res_item: util.MultiArrayListElem(ecs.Query(query_types, options)) = undefined;

                inline for (query_types, 0..) |Q, i| {
                    const res_item_field = std.fmt.comptimePrint("{c}", .{@intCast(u8, 'a' + i)});

                    // no need to check if the smallest of the Query lists has the same entity as itself...
                    if (i == smallest_idx) {
                        @field(res_item, res_item_field) = comp0s.getAs(Q, ent).?;
                    } else {
                        var other_q = self.getListOf(Q);
                        if (!other_q.contains(ent)) continue :comp0_ents_loop; // skip to checking next entity in component 0's entities, skips result.append

                        @field(res_item, res_item_field) = other_q.getAs(Q, ent).?;
                    }
                }

                try result.append(self.frame_alloc, res_item);
            }

            return result;
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
                } else if (comptime @typeInfo(Param) == .Struct and @hasDecl(Param, "Field")) {
                    const query_ti = std.meta.fieldInfo(util.MultiArrayListElem(Param), .QueryType);
                    const opts_ti = std.meta.fieldInfo(util.MultiArrayListElem(Param), .OptionsType);

                    out[i] = try self.query(
                        @ptrCast(
                            *const query_ti.type,
                            query_ti.default_value.?,
                        ).*,
                        @ptrCast(
                            *const opts_ti.type,
                            opts_ti.default_value.?,
                        ).*,
                    );
                    continue;
                } else if (comptime @typeInfo(Param) == .Struct and @hasDecl(Param, "EventSendType")) {
                    out[i] = .{
                        .alloc = self.event_pools.alloc,
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

        fn typeArrayFromParams(comptime params: []const std.builtin.Type.Fn.Param) []const type {
            var types: []const type = &.{};
            for (params) |p| types = types ++ .{p.type.?};
            return types;
        }

        pub fn deinitArgsForSystem(self: *Self, args: anytype, alloc: Allocator) void {
            _ = self;

            inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
                if (args_field.type == Allocator) continue;

                if (comptime @typeInfo(args_field.type) == .Struct and @hasDecl(args_field.type, "pop") and @hasField(util.MultiArrayListElem(args_field.type), "QueryType")) {
                    @field(args, args_field.name).deinit(alloc);
                }

                // if (comptime std.meta.trait.isContainer(args_field.type) and @hasDecl(args_field.type, "deinit")) {
                //     const fn_params = @typeInfo(@TypeOf(@TypeOf(@field(args, args_field.name)).deinit)).Fn.params;

                //     if (comptime fn_params.len > 1 and fn_params[1].type.? == Allocator) {
                //         @field(args, args_field.name).deinit(alloc);
                //     } else if (comptime fn_params.len == 1) {
                //         @field(args, args_field.name).deinit();
                //     }
                // }
            }
        }

        fn getListOf(self: *Self, comptime T: type) *ca.ComponentArray(max_ents) {
            const idx = comptime component_tm.indexOf(T) orelse @compileError("Tried to query Component " ++ @typeName(T) ++ ", which was not registred.");
            return &self.comp_arrays[idx];
        }

        inline fn commandsCast(ptr: *anyopaque) *Self {
            return @ptrCast(*Self, @alignCast(@alignOf(Self), ptr));
        }
    };
}

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

        arena: std.heap.ArenaAllocator,
        alloc: Allocator,
        inner: Inner = .{},

        pub fn init() Self {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

            return .{
                .arena = arena,
                .alloc = arena.allocator(),
            };
        }

        pub fn append(self: *Self, comptime EventType: type, data: EventType) Allocator.Error!void {
            if (comptime !event_tm.has(EventType)) @compileError("Event `" ++ @typeName(EventType) ++ "` was not registered.");
            try @field(self.inner, Inner_fieldNameOf(EventType)).append(self.alloc, data);
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

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        inline fn Inner_fieldNameOf(comptime T: type) []const u8 {
            return std.fmt.comptimePrint("{}", .{event_tm.indexOf(T).?});
        }
    };
}

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
