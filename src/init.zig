const std = @import("std");

/// Vendored version of https://github.com/michal-z/zig-gamedev
pub const zmath = @import("zmath");

/// A unique ID that is assigned to each entity
pub const Entity = @import("entity.zig").Entity;

/// An Entity and a Commands grouped together for acting on a specific entity
pub const EntityHandle = @import("entity_handle.zig");

pub const events = @import("events.zig");
pub const EventSender = events.EventSender;
pub const EventReceiver = events.EventReceiver;

pub const query = @import("query.zig");
pub const Query = query.Query;
pub const With = query.With;
pub const Without = query.Without;

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

pub const from2 = Vec2.from;
pub const from3 = Vec3.from;
pub const from4 = Vec4.from;

pub const vec2 = @compileError("Use .init");
pub const splat2 = @compileError("Use .splat");

pub const vec3 = @compileError("Use .init");
pub const splat3 = @compileError("Use .splat");

pub const vec4 = @compileError("Use .init");
pub const splat4 = @compileError("Use .splat");

pub const WorldBuilder = @import("worldbuilder.zig");
pub const Commands = @import("commands.zig");

pub const base = @import("mods/base/init.zig");
pub const anim = @import("mods/anim.zig");
pub const input = @import("mods/input.zig");

/// Zentig's scoped logging functions
pub const log = std.log.scoped(.zentig);

pub const meta = @import("etc/meta.zig");
pub const profiler = @import("etc/profiler.zig");

pub const Mask = @import("mask.zig").Mask;

pub const Array2d = @import("etc/dimensional_array.zig").Array2d;
pub const Array3d = @import("etc/dimensional_array.zig").Array3d;
pub const array_nd = @import("etc/dimensional_array.zig");

/// A resource that can be requested, represents an arena allocator that gets reset each frame
pub const FrameAlloc = struct { std.mem.Allocator };

/// Reason for an internal world crash
pub const CrashReason = enum { hit_ent_limit };

test {
    _ = @import("events.zig");
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
