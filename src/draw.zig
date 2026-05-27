const std = @import("std");
const rl = @import("raylib");
const obt = @import("orbits");

pub const DashSpacing = enum {
    xsmall, // 48 dashes
    small, // 32 dashes
    med, // 20 dashes
    large, // 12 dashes
    xlarge, //  6 dashes

    pub fn count(self: DashSpacing) f32 {
        return switch (self) {
            .xsmall => 48,
            .small => 32,
            .med => 20,
            .large => 12,
            .xlarge => 6,
        };
    }
};

pub fn calculateSegments(radius: f32) i32 {
    if (!std.math.isFinite(radius)) return 32;
    const min_segments: i32 = 32;
    const max_segments: i32 = 256;
    var segments: i32 = @trunc(radius * 0.65);
    segments = @max(min_segments, segments);
    segments = @min(max_segments, segments);
    return segments;
}

pub fn drawEllipseLines(center: rl.Vector2, radius_x: f32, radius_y: f32, segments: i32, color: rl.Color) void {
    if (segments < 4 or !std.math.isFinite(radius_x) or !std.math.isFinite(radius_y)) return;
    const step = std.math.tau / @as(f32, @floatFromInt(segments));
    var angle: f32 = 0.0;
    var i: i32 = 0;
    while (i < segments) : (i += 1) {
        const next = angle + step;
        rl.drawLine(
            @floor(center.x + @cos(angle) * radius_x),
            @floor(center.y + @sin(angle) * radius_y),
            @floor(center.x + @cos(next) * radius_x),
            @floor(center.y + @sin(next) * radius_y),
            color,
        );
        angle = next;
    }
}

pub fn drawDashedCircle(
    center_x: i32,
    center_y: i32,
    radius: f32,
    spacing: DashSpacing,
    thickness: f32,
    color: rl.Color,
) void {
    const cx: f32 = @floatFromInt(center_x);
    const cy: f32 = @floatFromInt(center_y);
    const dash_count = spacing.count();
    const step = (std.math.pi * 2.0) / dash_count;
    const dash = step * 0.6;
    var i: i32 = 0;
    while (i < @as(i32, @trunc(dash_count))) : (i += 1) {
        const angle_start = @as(f32, @floatFromInt(i)) * step;
        const angle_end = angle_start + dash;
        const segs = 8;
        var s: i32 = 0;
        while (s < segs) : (s += 1) {
            const t0 = angle_start + (@as(f32, @floatFromInt(s)) / segs) * (angle_end - angle_start);
            const t1 = angle_start + (@as(f32, @floatFromInt(s + 1)) / segs) * (angle_end - angle_start);
            rl.drawLineEx(
                .{ .x = cx + radius * @cos(t0), .y = cy + radius * @sin(t0) },
                .{ .x = cx + radius * @cos(t1), .y = cy + radius * @sin(t1) },
                thickness,
                color,
            );
        }
    }
}

/// Draw an orbit ellipse in 3D space, rotated by inclination and LAN.
pub fn drawOrbit3D(
    sma: f64,
    ecc: f64,
    incl: f64,
    lan: f64,
    aop: f64,
    scale: f64,
    color: rl.Color,
    segments: i32,
) void {
    if (segments < 4) return;
    const n = segments;
    const step = std.math.tau / @as(f64, @floatFromInt(n));

    // Precompute rotation angles
    const ci = @cos(incl);
    const si = @sin(incl);
    const cl = @cos(lan);
    const sl = @sin(lan);
    const cw = @cos(aop);
    const sw = @sin(aop);

    var prev: ?rl.Vector3 = null;
    var j: i32 = 0;
    while (j <= n) : (j += 1) {
        const nu = @as(f64, @floatFromInt(j)) * step;
        // Perifocal coords
        const r = sma * (1.0 - ecc * ecc) / (1.0 + ecc * @cos(nu));
        const px = r * @cos(nu);
        const py = r * @sin(nu);

        // Rotate by AoP, inclination, LAN
        const x1 = cw * px - sw * py;
        const y1 = sw * px + cw * py;
        // Inclination rotation (around x-axis)
        const x2 = x1;
        const y2 = ci * y1;
        const z2 = si * y1;
        // LAN rotation (around z-axis)
        const x3 = cl * x2 - sl * y2;
        const y3 = sl * x2 + cl * y2;
        const z3 = z2;

        const pt = rl.Vector3{
            .x = @floatCast(x3 * scale),
            .y = @floatCast(z3 * scale), // y-up in raylib
            .z = @floatCast(y3 * scale),
        };

        if (prev) |p| {
            rl.drawLine3D(p, pt, color);
        }
        prev = pt;
    }
}

pub fn bodyColor(body: obt.CelestialBody) rl.Color {
    return switch (body) {
        // KSP
        .kerbol => .orange,
        .moho => .init(100, 80, 70, 200),
        .eve => .purple,
        .gilly => .init(210, 180, 140, 200),
        .kerbin => .blue,
        .mun => .gray,
        .minmus => .init(128, 224, 160, 200),
        .duna => .init(180, 80, 40, 200),
        .ike => .init(90, 90, 90, 200),
        .dres => .init(130, 120, 110, 200),
        .jool => .init(80, 180, 80, 200),
        .laythe => .init(0, 100, 180, 200),
        .vall => .init(140, 200, 220, 200),
        .tylo => .init(210, 210, 215, 200),
        .bop => .init(100, 85, 75, 200),
        .pol => .init(210, 210, 150, 200),
        .eeloo => .init(220, 230, 240, 200),
        // Real
        .sol => .init(255, 200, 50, 200),
        .mercury => .init(150, 140, 130, 200),
        .venus => .init(220, 190, 100, 200),
        .earth => .init(30, 100, 200, 200),
        .luna => .init(180, 180, 175, 200),
        .mars => .init(180, 80, 40, 200),
        .phobos => .init(110, 100, 90, 200),
        .deimos => .init(120, 110, 100, 200),
        .jupiter => .init(200, 160, 110, 200),
        .io => .init(220, 200, 60, 200),
        .europa => .init(200, 195, 180, 200),
        .ganymede => .init(130, 120, 110, 200),
        .callisto => .init(90, 85, 80, 200),
        .saturn => .init(210, 190, 140, 200),
        .titan => .init(200, 140, 60, 200),
        .enceladus => .init(230, 240, 255, 200),
        .mimas => .init(190, 185, 180, 200),
        .tethys => .init(200, 200, 195, 200),
        .dione => .init(185, 180, 175, 200),
        .rhea => .init(175, 170, 165, 200),
        .uranus => .init(130, 210, 220, 200),
        .miranda => .init(160, 155, 150, 200),
        .ariel => .init(170, 165, 160, 200),
        .umbriel => .init(80, 78, 75, 200),
        .titania => .init(155, 150, 145, 200),
        .oberon => .init(100, 95, 90, 200),
        .neptune => .init(40, 80, 200, 200),
        .triton => .init(180, 210, 200, 200),
        .pluto => .init(180, 160, 130, 200),
        else => .red,
    };
}

pub fn atmoColor(body: obt.CelestialBody) rl.Color {
    return switch (body) {
        .kerbin => .init(100, 149, 237, 200),
        .eve => .init(140, 80, 200, 200),
        .duna => .init(210, 120, 60, 200),
        .laythe => .init(80, 130, 200, 200),
        .jool => .init(80, 180, 80, 200),
        .earth => .init(100, 149, 237, 200),
        .venus => .init(220, 180, 80, 200),
        .mars => .init(200, 120, 60, 200),
        .titan => .init(200, 140, 60, 200),
        .jupiter => .init(180, 150, 100, 200),
        .saturn => .init(200, 180, 130, 200),
        .uranus => .init(130, 210, 220, 200),
        .neptune => .init(40, 80, 200, 200),
        else => .init(150, 180, 255, 200),
    };
}
