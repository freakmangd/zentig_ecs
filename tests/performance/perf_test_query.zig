const std = @import("std");
const ztg = @import("zentig");

const World = ztg.WorldBuilder.init(&.{
    @This(),
}).Build();

const Comp1 = struct { a: i32 = 0 };
const Comp2 = struct { b: f32 = 0.0 };
const Comp3 = struct { c: bool = false };
const Comp4 = struct { d: void = void{} };
const Comp5 = struct { e: enum { a, b, c } = .a };
const Comp6 = struct { f: struct { a: i32, b: i32 } = .{ .a = 1, .b = 2 } };
const Comp7 = struct { g: union { a: f32, b: i32 } = .{ .a = 3 } };
const Comp8 = struct { h: u1 = 0 };
const Comps = &.{ Comp1, Comp3, Comp2, Comp4, Comp5, Comp6, Comp7, Comp8 };

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.max_entities = 300_000;
    wb.addComponents(Comps);
    wb.addStage(.get_ents);
    wb.addSystems(.{ .get_ents = getEntsLen, .update = system });
}

var collected_ents: usize = 0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var w = try World.init(alloc);
    defer w.deinit();

    for (0..1_000) |_| {
        inline for (0..256) |i| try entWithComponents(w, i);
    }

    std.debug.print("Entity count: {}\n", .{w.entities.len});

    for (0..200) |_| {
        var perf = ztg.profiler.startSection("Query For System");
        defer perf.end();

        try w.runStage(.update);
    }

    ztg.profiler.report(std.io.getStdOut().writer(), 1);

    try w.runStage(.get_ents);
    std.debug.print("collected: {}, expected: 1000\n", .{collected_ents});
}

fn entWithComponents(w: *World, comptime comps_bitmask: u8) !void {
    const ent = try w.newEnt();
    inline for (0..8) |i| {
        if ((comps_bitmask & 1 << @intCast(i)) != 0) _ = try w.giveEnt(ent, Comps[i]{});
    }
}

fn getEntsLen(q: ztg.Query(.{ Comp1, Comp2, Comp3, Comp4, Comp5, Comp6, Comp7, Comp8 })) void {
    collected_ents = q.len;
}

fn system(q: ztg.Query(.{ Comp1, Comp2, Comp3, Comp4, Comp5, Comp6, Comp7, Comp8 })) void {
    _ = q;
}
