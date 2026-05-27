const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const obt = @import("orbits");
const state = @import("../state.zig");
const draw = @import("../draw.zig");
const ui = @import("../ui.zig");

pub fn update(s: *state.AppState) void {
    s.updateCamera();
}

pub fn drawView(s: *state.AppState) !void {
    const sw: f32 = @floatFromInt(s.screen_width);
    const sh: f32 = @floatFromInt(s.screen_height);

    const rp_x: f32 = sw * 0.75;
    const rp_y: f32 = sh * 0.25;
    const row: f32 = 48.0;
    const bot_y: i32 = s.screen_height - 160;
    const col: i32 = @intFromFloat(sw * 0.05);
    const col2: i32 = @intFromFloat(sw * 0.3);
    const col3: i32 = @intFromFloat(sw * 0.55);

    const params = obt.CelestialBody.params(s.body);
    const planet_r: f32 = 10.0; // normalized display radius
    const scale = planet_r / @as(f32, @floatCast(params.radius));

    const t_orbit = s.targetOrbit();
    const res_orbit = s.resonantOrbit();

    // ── 3D Scene ──────────────────────────────────────────────────────────
    rl.beginMode3D(s.camera);

    // Planet
    const planet_pos: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 };
    rl.drawSphereEx(planet_pos, planet_r, 64, 64, draw.bodyColor(s.body));
    if (s.show_lines) rl.drawSphereWires(planet_pos, planet_r + 0.1, 32, 32, .black);

    // Atmosphere
    if (params.atmosphere_height) |atm_h| {
        const atmo_r = planet_r + @as(f32, @floatCast(atm_h)) * scale;
        const ac = draw.atmoColor(s.body);
        const atmo_color = rl.Color{ .r = ac.r, .g = ac.g, .b = ac.b, .a = 60 };
        rl.drawSphereEx(.{ .x = 0, .y = 0, .z = 0 }, atmo_r, 64, 64, atmo_color);
    }

    // SOI
    // if (obt.CelestialBody.soi(s.body)) |soi| {
    //     const soi_r = @as(f32, @floatCast(soi)) * scale;
    //     rl.drawSphereWires(.{ .x = 0, .y = 0, .z = 0 }, soi_r, 32, 32, rl.Color{ .r = 255, .g = 255, .b = 255, .a = 40 });
    // }

    // Target orbit (circular, no inclination)
    const targ_r = @as(f64, @floatCast(planet_r)) + @as(f64, s.targ_alt) * @as(f64, scale);
    draw.drawOrbit3D(targ_r, 0.0, 0.0, 0.0, 0.0, 1.0, .green, 128);

    rl.drawLine3D(.{ .x = 0.0, .y = planet_r, .z = 0.0 }, .{ .x = 0.0, .y = planet_r + 5.0, .z = 0.0 }, .red);
    rl.drawLine3D(.{ .x = 0.0, .y = -planet_r, .z = 0.0 }, .{ .x = 0.0, .y = -planet_r - 5.0, .z = 0.0 }, .blue);

    // Resonant orbit
    const incl = res_orbit.inclination;
    const lan = res_orbit.lan orelse 0.0;
    const aop = res_orbit.arg_of_periapsis orelse 0.0;
    draw.drawOrbit3D(
        res_orbit.semi_major_axis * @as(f64, scale),
        res_orbit.eccentricity,
        incl,
        lan,
        aop,
        1.0,
        .orange,
        128,
    );

    rl.endMode3D();

    // ── Overlay UI (same right panel + bottom bar) ────────────────────────
    try ui.drawRightPanel(s, rp_x, rp_y, row);

    // Determine colors for bottom bar (simplified, no SOI check in 3D yet)
    const targ_color: rl.Color = .green;
    const res_color: rl.Color = .orange;
    try ui.drawBottomBar(s, res_color, targ_color, col, col2, col3, bot_y);

    _ = t_orbit;
}
