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
const profiler = @import("profiler.zig");

const tracy = @import("../nogit/zig-tracy/src/lib.zig");

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
    if (max_ents > 100_000) @compileError("Max entities cannot exceed 100,000.");

    return struct {
        const Self = @This();
        const stages_list = StagesList{ .inner = .{} };

        alloc: Allocator,
        rng: ?std.rand.DefaultPrng,

        frame_arena: std.heap.ArenaAllocator,
        frame_alloc: Allocator,

        next_ent: ecs.Entity = 0,

        comp_arrays: [component_tm.types.len]ca.ComponentArray(max_ents),
        resources: Resources = .{},
        event_pools: EventPools(events_tm),
        commands_vtable: Commands.Vtable,

        changes_list: ChangesList,
        remove_queue: RemoveQueue,

        /// User must call `.deinit()` once the world is to be descoped. (in a defer block preferrably)
        /// All systems that request an `Allocator` will get the one passed here.
        pub inline fn init(alloc: Allocator) !*Self {
            return initWith(alloc, null);
        }

        pub fn initWith(alloc: Allocator, rand_opt: ?std.rand.Random) !*Self {
            if (warnings.len > 0) {
                std.log.warn("World was constructed with warnings: " ++ warnings, .{});
            }

            std.debug.print("Entity has utp {s}\n", .{TypeMap.uniqueTypePtr(ecs.Entity)});
            inline for (component_tm.types) |T| {
                std.debug.print("{s} has utp {}\n", .{ @typeName(T), TypeMap.uniqueTypePtr(T) });
            }

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

            var self = try alloc.create(Self);
            self.* = Self{
                .alloc = alloc,
                .rng = rng,

                .frame_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
                .frame_alloc = undefined,

                .comp_arrays = undefined,
                .commands_vtable = .{
                    .add_component_fn = Self.commands_addComponent,
                    .new_ent_fn = Self.commands_newEnt,
                    .run_stage_fn = Self.commands_runStageFn,
                },

                .event_pools = EventPools(events_tm){},

                .changes_list = ChangesList{},
                .remove_queue = RemoveQueue{},
            };

            self.frame_alloc = self.frame_arena.allocator();

            inline for (component_tm.types) |CT| {
                var buf = try alloc.alloc(u8, @sizeOf(CT) * max_ents);
                self.comp_arrays[comptime component_tm.indexOf(CT).?] = try ca.ComponentArray(max_ents).init(buf, CT);
            }

            self.getResPtr(Allocator).* = alloc;
            self.getResPtr(std.rand.Random).* = rand;

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.event_pools.deinit(self.alloc);
            self.remove_queue.deinit(self.alloc);
            self.changes_list.deinit(self.alloc);
            self.frame_arena.deinit();

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

            self.alloc.destroy(self);
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
            self.remove_queue.clearAndFree(self.alloc);
            self.changes_list.clearAndFree(self.alloc);
            self.event_pools.clear();
            if (!self.frame_arena.reset(.free_all)) std.log.err("Failed to reset frame arena.", .{});
        }

        /// Returns the next free index for components
        pub fn newEnt(self: *Self) error{ Overflow, HitMaxEntities }!ecs.Entity {
            if (self.next_ent + 1 >= max_ents) return error.HitMaxEntities;
            self.next_ent = try std.math.add(ecs.Entity, self.next_ent, 1);
            return self.next_ent - 1;
        }

        fn commands_newEnt(ptr: *anyopaque) error{ Overflow, HitMaxEntities }!ecs.Entity {
            return commandsCast(ptr).newEnt();
        }

        /// Queues the removal of all components in lists correlated with `ent`
        pub fn removeEnt(self: *Self, ent: ecs.Entity) Allocator.Error!void {
            try self.remove_queue.append(.{ ent, std.math.maxInt(usize) });
        }

        /// Adds a component at the Entity indexworld
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

        pub fn getSmallestListFrom(self: *Self, utps: []const TypeMap.UniqueTypePtr) struct { *ca.ComponentArray(max_ents), usize } {
            var smallest_idx: usize = 0;
            var smallest = self.getListFromUtp(utps[0]);
            for (utps[1..], 1..) |qutp, i| {
                var check = self.getListFromUtp(qutp);
                if (check.len < smallest.len) {
                    smallest = check;
                    smallest_idx = i;
                }
            }
            return .{ smallest, smallest_idx };
        }

        fn query(self: *Self, comptime QT: type) !QT {
            _ = self;
            @compileError("unimplemented");
        }

        fn queryWithOptionsComptime(
            self: *Self,
            comptime query_types: []const type,
            comptime options: []const type,
            comp0s: *ca.ComponentArray(max_ents),
            comp0_idx: usize,
            components_out: [][]*anyopaque,
            comptime has_entities: bool,
            entities_out: []ecs.Entity,
        ) !void {
            @setRuntimeSafety(false);
            _ = options;

            var other_lists: [query_types.len]*ca.ComponentArray(max_ents) = undefined;
            inline for (query_types, &other_lists) |QT, *ol| ol.* = self.getListOf(QT);

            comp0_ents_loop: for (comp0s.id_lookup.written_indexes.constSlice(), 0..) |ent, ent_idx| {
                components_out[comp0_idx][ent_idx] = comp0s.get(ent).?;

                inline for (query_types, 0..) |QT, i| {
                    _ = QT;
                    // no need to check if the smallest of the Query lists has the same entity as itself
                    if (i != comp0_idx) {
                        const other_q = other_lists[i];
                        if (!other_q.contains(ent)) continue :comp0_ents_loop; // skip to checking next entity in component 0's entities, skips adding the entity

                        components_out[i][ent_idx] = other_q.get(ent).?;
                    }
                }

                if (comptime has_entities) entities_out[ent_idx] = ent;
            }
        }

        fn queryWithOptions(
            self: *Self,
            query_utps: []const TypeMap.UniqueTypePtr,
            comptime options: []const type,
            comp0s: *ca.ComponentArray(max_ents),
            comp0_idx: usize,
            components_out: [][]*anyopaque,
            entities_out: ?[]ecs.Entity,
        ) !void {
            _ = options;

            comp0_ents_loop: for (comp0s.id_lookup.written_indexes.constSlice(), 0..) |ent, ent_idx| {
                components_out[comp0_idx][ent_idx] = comp0s.get(ent).?;

                for (query_utps, 0..) |qutp, i| {
                    // no need to check if the smallest of the Query lists has the same entity as itself...
                    if (i == comp0_idx) continue;

                    var other_q = self.getListFromUtp(qutp);
                    if (!other_q.contains(ent)) continue :comp0_ents_loop; // skip to checking next entity in component 0's entities, skips adding the entity

                    components_out[i][ent_idx] = other_q.get(ent).?;
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

                    out[i] = try Param.init(self.frame_alloc, smallest[0].len);

                    try self.queryWithOptions(
                        &Param.type_utps,
                        Param.OptionsType,
                        smallest[0],
                        smallest[1],
                        &out[i].comp_ptrs,
                        if (comptime Param.has_entities) &out[i].entities else null,
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

        fn typeArrayFromParams(comptime params: []const std.builtin.Type.Fn.Param) []const type {
            var types: []const type = &.{};
            for (params) |p| types = types ++ .{p.type.?};
            return types;
        }

        pub fn deinitArgsForSystem(self: *Self, args: anytype) void {
            _ = self;
            inline for (std.meta.fields(@TypeOf(args.*))) |args_field| {
                if (comptime @typeInfo(args_field.type) == .Struct and @hasDecl(args_field.type, "query_types")) {
                    //@field(args, args_field.name).deinit(self.alloc);
                }
            }
        }

        pub fn getListOf(self: *Self, comptime T: type) *ca.ComponentArray(max_ents) {
            const idx = comptime component_tm.indexOf(T) orelse @compileError("Tried to query Component " ++ @typeName(T) ++ ", which was not registred.");
            return &self.comp_arrays[idx];
        }

        fn getListFromUtp(self: *Self, utp: TypeMap.UniqueTypePtr) *ca.ComponentArray(max_ents) {
            const idx = component_tm.fromUtp(utp) orelse std.debug.panic("Tried to query Component with utp {}, which was not registred.", .{utp});
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
