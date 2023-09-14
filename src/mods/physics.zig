//! Based on and adapted from: Box2D-Lite Zig
//! https://github.com/jakubtomsu/box2d-lite-zig
//! Version of Box2D-Lite (https://github.com/erincatto/box2d-lite) rewritten in Zig (https://ziglang.org/)
//!
//! Everything is in single file for ease of use (and also because it's small).
//! There aren't any dependencies (except zig's std library)
//! Original copyright from Box2D-Lite:
// Copyright (c) 2006-2009 Erin Catto http://www.gphysics.com
//
// Permission to use, copy, modify, distribute and sell this software
// and its documentation for any purpose is hereby granted without fee,
// provided that the above copyright notice appear in all copies.
// Erin Catto makes no representations about the suitability
// of this software for any purpose.
// It is provided "as is" without express or implied warranty.

const std = @import("std");
const ztg = @import("../init.zig");
const print = std.debug.print;

pub const World = struct {
    // options
    gravity: Vec2,
    iterations: i32,
    accumulate_impulses: bool,
    warm_starting: bool,
    position_correction: bool,
    // data
    bodies: BodyMap,
    arbiters: ArbiterMap,
    body_handle_counter: BodyHandle = 0,

    delete_queue: std.ArrayListUnmanaged(BodyHandle),

    pub const BodyMap = std.AutoArrayHashMap(BodyHandle, Body);
    pub const ArbiterMap = std.ArrayHashMap(ArbiterKey, Arbiter, ArbiterHashMapContext, false);

    const ArbiterHashMapContext = struct {
        ///   eql(self, K, K, usize) bool
        pub fn eql(self: ArbiterHashMapContext, k1: ArbiterKey, k2: ArbiterKey, i: usize) bool {
            _ = self;
            _ = i;
            return k1.body1 == k2.body1 and k1.body2 == k2.body2;
        }
        ///   hash(self, K) u32
        pub fn hash(self: ArbiterHashMapContext, key: ArbiterKey) u32 {
            _ = self;
            return @as(u32, @intCast(@intFromPtr(key.body1) ^ @intFromPtr(key.body2)));
        }
    };

    pub fn addBody(self: *@This(), body: Body) error{ OutOfMemory, Overflow }!BodyHandle {
        // self.bodies.append(body);
        // std.ArrayList(Body).append(&self.bodies, body) catch return BodyHandleInvalid;
        const handle = self.body_handle_counter;
        try self.bodies.put(handle, body);
        self.body_handle_counter = try std.math.add(BodyHandle, self.body_handle_counter, 1);
        return handle;
    }

    // pub fn deleteBody(self: *@This(), handle: BodyHandle) void { }

    pub fn clear(self: *@This()) void {
        self.bodies.clear();
        self.arbiters.clear();
    }

    fn broadPhase(self: *@This()) void {
        print("World.broadPhase\n", .{});

        // O(n^2) broad-phase
        for (self.bodies.values(), 0..) |*bi, i| {
            // for (int j = i + 1; j < (int)bodies.size(); ++j) {
            for (self.bodies.values()[i + 1 ..]) |*bj| {
                if (bi.invMass == 0.0 and bj.invMass == 0.0) continue;

                const newArb = Arbiter.init(bi, bj);
                const key = ArbiterKey{ .body1 = bi, .body2 = bj };

                if (newArb.numContacts > 0) {
                    var prev = self.arbiters.getPtr(key);
                    if (prev) |arb| {
                        arb.update(self, newArb.contacts, newArb.numContacts);
                    } else {
                        self.arbiters.put(key, newArb) catch unreachable;
                    }
                } else {
                    _ = self.arbiters.swapRemove(key);
                }
            }
        }
    }

    pub fn step(self: *@This(), dt: f32) void {
        //print("World.step\n", .{});
        const inv_dt = if (dt > 0.0) 1.0 / dt else 0.0;

        // Determine overlapping bodies and update contact points.
        self.broadPhase();

        // Integrate forces.
        //print("World.step: Integrate forces\n", .{});
        for (self.bodies.values()) |*b| {
            if (b.invMass == 0.0) continue;

            b.velocity = b.velocity.add(self.gravity.add(b.force.mulF32(b.invMass)).mulF32(dt));
            b.angularVelocity += b.invInertia * b.torque * dt;
        }

        // Perform pre-steps.
        //print("World.step: Perform pre-steps\n", .{});
        for (self.arbiters.values()) |*arb| {
            arb.preStep(self, inv_dt);
        }

        // Perform iterations
        //print("World.step: Perform iterations\n", .{});
        //print("num arbiters {}\n", .{self.arbiters.values().len});
        var i: i32 = 0;
        while (i < self.iterations) : (i += 1) {
            for (self.arbiters.values()) |*arb| {
                arb.applyImpulse(self);
            }
        }

        // Integrate Velocities
        //print("World.step: Integrate Velocities\n", .{});
        for (self.bodies.values()) |*b| {
            b.position = b.position.add(b.velocity.mulF32(dt));
            b.rotation += b.angularVelocity * dt;

            b.force = ztg.Vec2{ .x = 0, .y = 0 };
            b.torque = 0.0;
        }
    }
};

pub const BodyHandle = u32;

pub const Body = struct {
    position: Vec2,
    rotation: f32,
    velocity: Vec2,
    angularVelocity: f32,
    force: Vec2,
    torque: f32,
    width: Vec2,
    friction: f32,
    mass: f32,
    invMass: f32,
    inertia: f32,
    invInertia: f32,

    pub fn init(pos: Vec2, w: Vec2, m: f32) Body {
        var result: Body = Body{
            .position = pos,
            .rotation = 0.0,
            .velocity = .{ .x = 0.0, .y = 0.0 },
            .angularVelocity = 0.0,
            .force = .{ .x = 0.0, .y = 0.0 },
            .torque = 0.0,
            .friction = 0.2,
            .width = w,
            .mass = m,

            .invMass = undefined,
            .inertia = undefined,
            .invInertia = undefined,
        };

        if (result.mass < std.math.f32_max) {
            result.invMass = 1.0 / result.mass;
            result.inertia = result.mass * (result.width.x * result.width.x + result.width.y * result.width.y) / 12.0;
            result.invInertia = 1.0 / result.inertia;
        } else {
            result.invMass = 0.0;
            result.inertia = std.math.f32_max;
            result.invInertia = 0.0;
        }

        return result;
    }

    pub fn addForce(self: *Body, f: Vec2) void {
        self.force += f;
    }
};

// Box vertex and edge numbering:
//
//        ^ y
//        |
//        e1
//   v2 ------ v1
//    |        |
// e2 |        | e4  -. x
//    |        |
//   v3 ------ v4
//        e3

const Axis = enum {
    FACE_A_X,
    FACE_A_Y,
    FACE_B_X,
    FACE_B_Y,
};

const EdgeNum_NO_EDGE = 0;
const EdgeNum_EDGE1 = 1;
const EdgeNum_EDGE2 = 2;
const EdgeNum_EDGE3 = 3;
const EdgeNum_EDGE4 = 4;

const ClipVertex = struct {
    v: Vec2,
    fp: FeaturePair,
};

pub fn flipFeaturePair(fp: *FeaturePair) void {
    std.mem.swap(u8, &fp.e.inEdge1, &fp.e.inEdge2);
    std.mem.swap(u8, &fp.e.outEdge1, &fp.e.outEdge2);
}

pub fn clipSegmentToLine(vOut: *[2]ClipVertex, vIn: [2]ClipVertex, normal: Vec2, offset: f32, clipEdge: u8) i32 {
    // Start with no output points
    var numOut: i32 = 0;

    // Calculate the distance of end points to the line
    const distance0 = dot(normal, vIn[0].v) - offset;
    const distance1 = dot(normal, vIn[1].v) - offset;

    // If the points are behind the plane
    if (distance0 <= 0.0) {
        vOut[@as(usize, @intCast(numOut))] = vIn[0];
        numOut += 1;
    }
    if (distance1 <= 0.0) {
        vOut[@as(usize, @intCast(numOut))] = vIn[1];
        numOut += 1;
    }

    // If the points are on different sides of the plane
    if (distance0 * distance1 < 0.0) {
        // Find intersection point of edge and plane
        const interp = distance0 / (distance0 - distance1);
        vOut[@as(usize, @intCast(numOut))].v = vIn[0].v.add(vIn[1].v.sub(vIn[0].v).mulF32(interp));
        if (distance0 > 0.0) {
            vOut[@as(usize, @intCast(numOut))].fp = vIn[0].fp;
            vOut[@as(usize, @intCast(numOut))].fp.e.inEdge1 = clipEdge;
            vOut[@as(usize, @intCast(numOut))].fp.e.inEdge2 = EdgeNum_NO_EDGE;
        } else {
            vOut[@as(usize, @intCast(numOut))].fp = vIn[1].fp;
            vOut[@as(usize, @intCast(numOut))].fp.e.outEdge1 = clipEdge;
            vOut[@as(usize, @intCast(numOut))].fp.e.outEdge2 = EdgeNum_NO_EDGE;
        }
        numOut += 1;
    }

    return numOut;
}

pub fn computeIncidentEdge(c: *[2]ClipVertex, h: Vec2, pos: Vec2, Rot: Mat22, normal: Vec2) void {
    // The normal is from the reference box. Convert it
    // to the incident boxe's frame and flip sign.
    const RotT = Rot.transpose();
    const n = RotT.mulVec2(normal).negate();
    const nAbs = n.abs();

    if (nAbs.x > nAbs.y) {
        if (sign(n.x) > 0.0) {
            c[0].v = .{ .x = h.x, .y = -h.y };
            c[0].fp.e.inEdge2 = EdgeNum_EDGE3;
            c[0].fp.e.outEdge2 = EdgeNum_EDGE4;

            c[1].v = .{ .x = h.x, .y = h.y };
            c[1].fp.e.inEdge2 = EdgeNum_EDGE4;
            c[1].fp.e.outEdge2 = EdgeNum_EDGE1;
        } else {
            c[0].v = .{ .x = -h.x, .y = h.y };
            c[0].fp.e.inEdge2 = EdgeNum_EDGE1;
            c[0].fp.e.outEdge2 = EdgeNum_EDGE2;

            c[1].v = .{ .x = -h.x, .y = -h.y };
            c[1].fp.e.inEdge2 = EdgeNum_EDGE2;
            c[1].fp.e.outEdge2 = EdgeNum_EDGE3;
        }
    } else {
        if (sign(n.y) > 0.0) {
            c[0].v = .{ .x = h.x, .y = h.y };
            c[0].fp.e.inEdge2 = EdgeNum_EDGE4;
            c[0].fp.e.outEdge2 = EdgeNum_EDGE1;

            c[1].v = .{ .x = -h.x, .y = h.y };
            c[1].fp.e.inEdge2 = EdgeNum_EDGE1;
            c[1].fp.e.outEdge2 = EdgeNum_EDGE2;
        } else {
            c[0].v = .{ .x = -h.x, .y = -h.y };
            c[0].fp.e.inEdge2 = EdgeNum_EDGE2;
            c[0].fp.e.outEdge2 = EdgeNum_EDGE3;

            c[1].v = .{ .x = h.x, .y = -h.y };
            c[1].fp.e.inEdge2 = EdgeNum_EDGE3;
            c[1].fp.e.outEdge2 = EdgeNum_EDGE4;
        }
    }

    c[0].v = pos.add(Rot.mulVec2(c[0].v));
    c[1].v = pos.add(Rot.mulVec2(c[1].v));
}

// The normal points from A to B
pub fn collide(contacts: *[MAX_POINTS]Contact, bodyA: *const Body, bodyB: *const Body) i32 {
    // Setup
    const hA = bodyA.width.mulF32(0.5);
    const hB = bodyB.width.mulF32(0.5);

    const posA = bodyA.position;
    const posB = bodyB.position;

    const RotA = Mat22.initAngle(bodyA.rotation);
    const RotB = Mat22.initAngle(bodyB.rotation);

    const RotAT = RotA.transpose();
    const RotBT = RotB.transpose();

    const dp = posB.sub(posA);
    const dA = RotAT.mulVec2(dp);
    const dB = RotBT.mulVec2(dp);

    const C = RotAT.mul(RotB);
    const absC = C.abs();
    const absCT = absC.transpose();

    // Box A faces
    const faceA = dA.abs().sub(hA).sub(absC.mulVec2(hB));
    if (faceA.x > 0.0 or faceA.y > 0.0)
        return 0;

    // Box B faces
    const faceB = dB.abs().sub(absCT.mulVec2(hA)).sub(hB);
    if (faceB.x > 0.0 or faceB.y > 0.0)
        return 0;

    // Find best axis
    // Box A faces
    var axis: Axis = .FACE_A_X;
    var separation = faceA.x;
    var normal = if (dA.x > 0.0) RotA.col1 else RotA.col1.negate();

    const relativeTol = 0.95;
    const absoluteTol = 0.01;

    if (faceA.y > relativeTol * separation + absoluteTol * hA.y) {
        axis = .FACE_A_Y;
        separation = faceA.y;
        normal = if (dA.y > 0.0) RotA.col2 else RotA.col2.negate();
    }

    // Box B faces
    if (faceB.x > relativeTol * separation + absoluteTol * hB.x) {
        axis = .FACE_B_X;
        separation = faceB.x;
        normal = if (dB.x > 0.0) RotB.col1 else RotB.col1.negate();
    }

    if (faceB.y > relativeTol * separation + absoluteTol * hB.y) {
        axis = .FACE_B_Y;
        separation = faceB.y;
        normal = if (dB.y > 0.0) RotB.col2 else RotB.col2.negate();
    }

    // Setup clipping plane data based on the separating axis
    var frontNormal = Vec2Zero;
    var sideNormal = Vec2Zero;
    var incidentEdge: [2]ClipVertex = undefined;
    var front: f32 = 0;
    var negSide: f32 = 0;
    var posSide: f32 = 0;
    var negEdge: u8 = 0;
    var posEdge: u8 = 0;

    // Compute the clipping lines and the line segment to be clipped.
    switch (axis) {
        .FACE_A_X => {
            frontNormal = normal;
            front = dot(posA, frontNormal) + hA.x;
            sideNormal = RotA.col2;
            const side = dot(posA, sideNormal);
            negSide = -side + hA.y;
            posSide = side + hA.y;
            negEdge = EdgeNum_EDGE3;
            posEdge = EdgeNum_EDGE1;
            computeIncidentEdge(&incidentEdge, hB, posB, RotB, frontNormal);
        },

        .FACE_A_Y => {
            frontNormal = normal;
            front = dot(posA, frontNormal) + hA.y;
            sideNormal = RotA.col1;
            const side = dot(posA, sideNormal);
            negSide = -side + hA.x;
            posSide = side + hA.x;
            negEdge = EdgeNum_EDGE2;
            posEdge = EdgeNum_EDGE4;
            computeIncidentEdge(&incidentEdge, hB, posB, RotB, frontNormal);
        },

        .FACE_B_X => {
            frontNormal = normal.negate();
            front = dot(posB, frontNormal) + hB.x;
            sideNormal = RotB.col2;
            const side = dot(posB, sideNormal);
            negSide = -side + hB.y;
            posSide = side + hB.y;
            negEdge = EdgeNum_EDGE3;
            posEdge = EdgeNum_EDGE1;
            computeIncidentEdge(&incidentEdge, hA, posA, RotA, frontNormal);
        },

        .FACE_B_Y => {
            frontNormal = normal.negate();
            front = dot(posB, frontNormal) + hB.y;
            sideNormal = RotB.col1;
            const side = dot(posB, sideNormal);
            negSide = -side + hB.x;
            posSide = side + hB.x;
            negEdge = EdgeNum_EDGE2;
            posEdge = EdgeNum_EDGE4;
            computeIncidentEdge(&incidentEdge, hA, posA, RotA, frontNormal);
        },
    }

    // clip other face with 5 box planes (1 face plane, 4 edge planes)

    var clipPoints1: [2]ClipVertex = undefined;
    var clipPoints2: [2]ClipVertex = undefined;
    var np: i32 = 0;

    // Clip to box side 1
    np = clipSegmentToLine(&clipPoints1, incidentEdge, sideNormal.negate(), negSide, negEdge);

    if (np < 2)
        return 0;

    // Clip to negative box side 1
    np = clipSegmentToLine(&clipPoints2, clipPoints1, sideNormal, posSide, posEdge);

    if (np < 2)
        return 0;

    // Now clipPoints2 contains the clipping points.
    // Due to roundoff, it is possible that clipping removes all points.

    var numContacts: i32 = 0;
    var i: i32 = 0;
    while (i < 2) : (i += 1) {
        const contactSeparation = dot(frontNormal, clipPoints2[@as(usize, @intCast(i))].v) - front;

        if (contactSeparation <= 0) {
            contacts[@as(usize, @intCast(numContacts))].separation = contactSeparation;
            contacts[@as(usize, @intCast(numContacts))].normal = normal;
            // slide contact point onto reference face (easy to cull)
            contacts[@as(usize, @intCast(numContacts))].position = clipPoints2[@as(usize, @intCast(i))].v.sub(frontNormal.mulF32(contactSeparation));
            contacts[@as(usize, @intCast(numContacts))].feature = clipPoints2[@as(usize, @intCast(i))].fp;
            if (axis == .FACE_B_X or axis == .FACE_B_Y)
                flipFeaturePair(&contacts[@as(usize, @intCast(numContacts))].feature);
            numContacts += 1;
        }
    }

    return numContacts;
}

const ALLOWED_PENETRATION = 0.01;

pub const FeaturePair = struct {
    const Edges = struct {
        inEdge1: u8,
        outEdge1: u8,
        inEdge2: u8,
        outEdge2: u8,
    };
    e: Edges,

    // pub fn setI32(self: @This(), value: i32) void {
    //     @ptrCast(*i32, &self.e).* = value;
    // }
    pub fn getI32Value(self: @This()) i32 {
        var val: Edges align(4) = self.e;
        return @as(*i32, @ptrCast(&val)).*;
    }
};

pub const Contact = struct {
    position: Vec2,
    normal: Vec2,
    r1: Vec2,
    r2: Vec2,
    separation: f32,
    Pn: f32, // accumulated normal impulse
    Pt: f32, // accumulated tangent impulse
    Pnb: f32, // accumulated normal impulse for position bias
    massNormal: f32,
    massTangent: f32,
    bias: f32,
    feature: FeaturePair,
};

pub const ArbiterKey = struct {
    body1: *Body,
    body2: *Body,

    pub fn init(body1: *Body, body2: *Body) ArbiterKey {
        var result: ArbiterKey = 0;
        if (body1 < body2) {
            result.body1 = body1;
            result.body2 = body2;
        } else {
            result.body1 = body2;
            result.body2 = body1;
        }
        return result;
    }
};

pub const MAX_POINTS = 2;

pub const Arbiter = struct {
    contacts: [MAX_POINTS]Contact,
    numContacts: i32,
    body1: *Body,
    body2: *Body,
    friction: f32, // Combined friction

    pub fn init(body1: *Body, body2: *Body) Arbiter {
        var result: Arbiter = Arbiter{
            .body1 = undefined,
            .body2 = undefined,
            .contacts = undefined,
            .numContacts = 0,
            .friction = 0.5,
        };

        if (@intFromPtr(body1) < @intFromPtr(body2)) {
            result.body1 = body1;
            result.body2 = body2;
        } else {
            result.body1 = body2;
            result.body2 = body1;
        }

        result.numContacts = collide(&result.contacts, body1, body2);
        result.friction = @sqrt(body1.friction * body1.friction);

        return result;
    }

    pub fn update(self: *@This(), world: *World, newContacts: [MAX_POINTS]Contact, numNewContacts: i32) void {
        var mergedContacts: [MAX_POINTS]Contact = undefined;

        var i: isize = 0;
        while (i < numNewContacts) : (i += 1) {
            var cNew = &newContacts[@as(usize, @intCast(i))];
            var k: isize = -1;
            var j: isize = 0;
            while (j < self.numContacts) : (j += 1) {
                var cOld = &self.contacts[@as(usize, @intCast(j))];
                if (cNew.feature.getI32Value() == cOld.feature.getI32Value()) {
                    k = j;
                    break;
                }
            }

            if (k > -1) {
                var c = &mergedContacts[@as(usize, @intCast(i))];
                var cOld = &self.contacts[@as(usize, @intCast(k))];
                c.* = cNew.*;
                if (world.warm_starting) {
                    c.Pn = cOld.Pn;
                    c.Pt = cOld.Pt;
                    c.Pnb = cOld.Pnb;
                } else {
                    c.Pn = 0.0;
                    c.Pt = 0.0;
                    c.Pnb = 0.0;
                }
            } else {
                mergedContacts[@as(usize, @intCast(i))] = newContacts[@as(usize, @intCast(i))];
            }
        }

        i = 0;
        while (i < numNewContacts) : (i += 1)
            self.contacts[@as(usize, @intCast(i))] = mergedContacts[@as(usize, @intCast(i))];

        self.numContacts = numNewContacts;
    }

    pub fn preStep(self: *@This(), world: *World, inv_dt: f32) void {
        const k_biasFactor: f32 = if (world.position_correction) 0.2 else 0.0;

        var body1 = self.body1;
        var body2 = self.body2;

        for (self.contacts) |*c| {
            const r1 = c.position.sub(body1.position);
            const r2 = c.position.sub(body2.position);

            // Precompute normal mass, tangent mass, and bias.
            const rn1 = dot(r1, c.normal);
            const rn2 = dot(r2, c.normal);
            const kNormal = body1.invMass + body2.invMass + body1.invInertia * (dot(r1, r1) - rn1 * rn1) + body2.invInertia * (dot(r2, r2) - rn2 * rn2);
            c.massNormal = 1.0 / kNormal;

            const tangent = crossF32(c.normal, 1.0);
            const rt1 = dot(r1, tangent);
            const rt2 = dot(r2, tangent);
            const kTangent = body1.invMass + body2.invMass + body1.invInertia * (dot(r1, r1) - rt1 * rt1) + body2.invInertia * (dot(r2, r2) - rt2 * rt2);
            c.massTangent = 1.0 / kTangent;

            c.bias = -k_biasFactor * inv_dt * @min(0.0, c.separation + ALLOWED_PENETRATION);

            if (world.accumulate_impulses) {
                // Apply normal + friction impulse
                const P = c.normal.mulF32(c.Pn).add(tangent.mulF32(c.Pt));

                body1.velocity = body1.velocity.sub(P.mulF32(body1.invMass));
                body1.angularVelocity -= body1.invInertia * cross(r1, P);

                body2.velocity = body2.velocity.add(P.mulF32(body2.invMass));
                body2.angularVelocity += body2.invInertia * cross(r2, P);
            }
        }
    }

    pub fn applyImpulse(self: *@This(), world: *World) void {
        var body1 = self.body1;
        var body2 = self.body2;

        for (self.contacts) |*c| {
            c.r1 = c.position.sub(body1.position);
            c.r2 = c.position.sub(body2.position);

            // Relative velocity at contact
            var dv = body2.velocity.add(crossF32(c.r2, body2.angularVelocity)).sub(body1.velocity.add(crossF32(c.r1, body1.angularVelocity)));

            // Compute normal impulse
            const vn = dot(dv, c.normal);

            var dPn = c.massNormal * (-vn + c.bias);

            if (world.accumulate_impulses) {
                // clamp the accumulated impulse
                const Pn0 = c.Pn;
                c.Pn = max(Pn0 + dPn, 0.0);
                dPn = c.Pn - Pn0;
            } else {
                dPn = max(dPn, 0.0);
            }

            // Apply contact impulse
            const Pn = c.normal.mulF32(dPn);

            body1.velocity = body1.velocity.sub(Pn.mulF32(body1.invMass));
            body1.angularVelocity -= body1.invInertia * cross(c.r1, Pn);

            body2.velocity = body2.velocity.add(Pn.mulF32(body2.invMass));
            body2.angularVelocity += body2.invInertia * cross(c.r2, Pn);

            // Relative velocity at contact
            dv = body2.velocity.add(crossF32(c.r2, body2.angularVelocity).sub(body1.velocity).sub(crossF32(c.r1, body1.angularVelocity)));

            const tangent = crossF32(c.normal, 1.0);
            const vt = dot(dv, tangent);
            var dPt = c.massTangent * (-vt);

            if (world.accumulate_impulses) {
                // Compute friction impulse
                const maxPt = self.friction * c.Pn;

                // clamp friction
                const oldTangentImpulse = c.Pt;
                c.Pt = clamp(oldTangentImpulse + dPt, -maxPt, maxPt);
                dPt = c.Pt - oldTangentImpulse;
            } else {
                const maxPt = self.friction * dPn;
                dPt = clamp(dPt, -maxPt, maxPt);
            }

            // Apply contact impulse
            const Pt = tangent.mulF32(dPt);

            body1.velocity = body1.velocity.sub(Pt.mulF32(body1.invMass));
            body1.angularVelocity -= body1.invInertia * cross(c.r1, Pt);

            body2.velocity = body2.velocity.add(Pt.mulF32(body2.invMass));
            body2.angularVelocity += body2.invInertia * cross(c.r2, Pt);
        }
    }
};

pub fn clamp(a: f32, low: f32, high: f32) f32 {
    return @max(low, @min(a, high));
}
pub fn sign(x: f32) f32 {
    return if (x < 0.0) -1.0 else 1.0;
}
pub fn absF32(x: f32) f32 {
    return if (x >= 0.0) x else -x;
}
pub fn min(a: f32, b: f32) f32 {
    return if (a < b) a else b;
}
pub fn max(a: f32, b: f32) f32 {
    return if (a > b) a else b;
}

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn negate(a: Vec2) Vec2 {
        return .{ .x = -a.x, .y = -a.y };
    }
    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }
    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }
    pub fn mul(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x * b.x, .y = a.y * b.y };
    }
    pub fn mulF32(a: Vec2, b: f32) Vec2 {
        return .{ .x = a.x * b, .y = a.y * b };
    }
    pub fn abs(a: Vec2) Vec2 {
        return .{ .x = absF32(a.x), .y = absF32(a.y) };
    }
};

pub const Vec2Zero = Vec2{ .x = 0.0, .y = 0.0 };

pub fn dot(a: Vec2, b: Vec2) f32 {
    return (a.x * b.x) + (a.y * b.y);
}
pub fn cross(a: Vec2, b: Vec2) f32 {
    return (a.x * b.y) - (a.y * b.x);
}
pub fn crossF32(a: Vec2, s: f32) Vec2 {
    return Vec2{ .x = -s * a.y, .y = s * a.x };
}

pub const Mat22 = struct {
    col1: Vec2,
    col2: Vec2,

    pub fn initAngle(angle: f32) Mat22 {
        const c = @cos(angle);
        const s = @sin(angle);
        return .{
            .col1 = .{ .x = c, .y = s },
            .col2 = .{ .x = -s, .y = c },
        };
    }

    pub fn transpose(self: @This()) Mat22 {
        return .{
            .col1 = .{ .x = self.col1.x, .y = self.col2.x },
            .col2 = .{ .x = self.col1.y, .y = self.col2.y },
        };
    }

    pub fn mulVec2(A: Mat22, v: Vec2) Vec2 {
        return .{ .x = A.col1.x * v.x + A.col2.x * v.y, .y = A.col1.y * v.x + A.col2.y * v.y };
    }
    pub fn mul(A: Mat22, B: Mat22) Mat22 {
        return .{ .col1 = A.mulVec2(B.col1), .col2 = A.mulVec2(B.col2) };
    }
    pub fn abs(A: Mat22) Mat22 {
        return .{ .col1 = Vec2.abs(A.col1), .col2 = Vec2.abs(A.col2) };
    }
};
