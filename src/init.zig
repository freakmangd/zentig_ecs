const std = @import("std");

/// Vendored version of https://github.com/michal-z/zig-gamedev
pub const zmath = @import("zmath");

/// A unique ID that is assigned to each entity
pub const Entity = usize;

/// An Entity and a Commands grouped together for acting on a specific entity
pub const EntityHandle = @import("entity_handle.zig");

pub const events = @import("events.zig");
pub const EventSender = events.EventSender;
pub const EventReceiver = events.EventReceiver;

pub const query_modifiers = @import("query_modifiers.zig");
pub const With = query_modifiers.With;
pub const Without = query_modifiers.Without;

pub const query = @import("query.zig");
pub const Query = query.Query;
pub const QueryOpts = query.QueryOpts;

pub const system_order = @import("system_order.zig");
pub const after = system_order.after;
pub const before = system_order.before;
pub const during = system_order.during;
pub const ordered = system_order.ordered;
pub const orderGroup = system_order.orderGroup;
pub const SystemOrder = system_order.SystemOrder;

pub const math = @import("math/init.zig");

pub const Timer = @import("etc/timer.zig");
pub const ComptimeList = @import("etc/comptime_list.zig").ComptimeList;
pub const EnumValueSpace = @import("etc/enum_value_space.zig").EnumValueSpace;

pub const Vec2 = @import("math/vec2.zig").Vec2;
pub const Vec3 = @import("math/vec3.zig").Vec3;
pub const Vec4 = @import("math/vec4.zig").Vec4;

/// Shorthand for ztg.Vec2.init
pub inline fn vec2(x: anytype, y: anytype) Vec2 {
    return Vec2.init(x, y);
}
/// Shorthand for ztg.Vec3.init
pub const vec3 = Vec3.init;
/// Shorthand for ztg.Vec4.init
pub const vec4 = Vec4.init;

//pub const Mat3 = @import("math/mat3.zig");

pub const WorldBuilder = @import("worldbuilder.zig");
pub const Commands = @import("commands.zig");

pub const base = @import("mods/base/init.zig");
pub const anim = @import("mods/anim.zig");
pub const input = @import("mods/input.zig");
//pub const physics = @import("mods/physics.zig");

/// Zentig's scoped logging functions
pub const log = std.log.scoped(.zentig);

pub const meta = @import("etc/meta.zig");
pub const profiler = @import("etc/profiler.zig");

/// A resource that can be requested, represents an arena allocator that gets reset each frame
pub const FrameAlloc = struct { std.mem.Allocator };

/// Reason for an internal world crash
pub const CrashReason = enum { hit_ent_limit };

test {
    _ = @import("events.zig");
    _ = @import("query_modifiers.zig");
    _ = @import("query.zig");
    _ = @import("system_order.zig");
    _ = math;
    _ = WorldBuilder;
    _ = Commands;
    _ = base;
    _ = input;
    _ = meta;
    _ = profiler;
    _ = ComptimeList;
}
