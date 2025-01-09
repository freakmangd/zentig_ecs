//! This file is part of a tutorial in docs/hello_world.md
//! It can be run with `zig build hello_world`

const std = @import("std");
const ztg = @import("zentig");

const World = ztg.WorldBuilder.init(&.{@This()}).Build();

const Name = struct { []const u8 };
const Score = struct { total: usize = 0 };

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addSystemsToStage(.load, spawnEntities);
    wb.addSystemsToStage(.update, .{ mySystem, updateScore });
    wb.addComponents(&.{ Name, Score });
}

fn mySystem(q: ztg.Query(.{Name})) void {
    for (q.items(Name)) |name| {
        // Here we use name[0] because Name is a single item tuple
        std.debug.print("Hello {s}!\n", .{name[0]});
    }
}

fn updateScore(q: ztg.Query(.{ Name, Score })) void {
    for (q.items(Name), q.items(Score)) |name, score| {
        score.total += 1;
        std.debug.print("{s}'s score is {}\n", .{ name[0], score.total });
    }
}

fn spawnEntities(com: ztg.Commands) !void {
    _ = try com.newEntWith(.{ Name{"Mark"}, Score{} });
    _ = try com.newEntWith(.{ Name{"Steve"}, Score{} });
    _ = try com.newEntWith(.{ Name{"Alice"}, Score{} });
}

pub fn main() !void {
    // Standard allocator setup
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var world = try World.init(alloc);
    defer world.deinit();

    try world.runStage(.load);
    try world.runStage(.update);
    try world.runStage(.update);
    try world.runStage(.update);
}
