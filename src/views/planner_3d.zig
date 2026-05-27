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
    var atmo_r: f32 = 0;
    const scale = planet_r / @as(f32, @floatCast(params.radius));
    if (params.atmosphere_height) |atm_h| {
        atmo_r = planet_r + @as(f32, @floatCast(atm_h)) * scale;
    }

    const t_orbit = s.targetOrbit();
    const res_orbit = s.resonantOrbit();

    const targ_color: rl.Color = if ((planet_r + (@as(f32, @floatCast(s.targ_alt * scale))) <= atmo_r) or (blk: {
        if (s.soi_radius) |soi| break :blk @as(f32, @floatCast(s.targ_alt * scale)) > soi;
        break :blk false;
    })) .red else .green;
    const res_color: rl.Color = if ((targ_color.toInt() == rl.Color.red.toInt()) or (blk: {
        if (s.soi_radius) |soi| {
            break :blk (@as(f32, @floatCast(res_orbit.apoapsis() * scale)) > soi) or
                (planet_r + @as(f32, @floatCast(scale * res_orbit.periapsis())) < atmo_r);
        }
        break :blk false;
    })) .red else .orange;

    // ── 3D Scene ──────────────────────────────────────────────────────────
    rl.beginMode3D(s.camera);

    // Planet
    const planet_pos: rl.Vector3 = .{ .x = 0, .y = 0, .z = 0 };
    rl.drawSphereEx(planet_pos, planet_r, 64, 64, draw.bodyColor(s.body));
    if (s.show_lines) rl.drawSphereWires(planet_pos, planet_r + 0.1, 32, 32, .black);

    const targ_r = @as(f64, @floatCast(planet_r)) + @as(f64, s.targ_alt) * @as(f64, scale);
    draw.drawOrbit3D(targ_r, 0.0, 0.0, 0.0, 0.0, 1.0, targ_color, 128);

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
        res_color,
        128,
    );

    // Atmosphere
    if (params.atmosphere_height) |atm_h| {
        _ = atm_h;
        const ac = draw.atmoColor(s.body);

        const atmo_thickness_ratio = (atmo_r - planet_r) / atmo_r;
        const color_normalized = [4]f32{
            @as(f32, @floatFromInt(ac.r)) / 255.0,
            @as(f32, @floatFromInt(ac.g)) / 255.0,
            @as(f32, @floatFromInt(ac.b)) / 255.0,
            0.7,
        };

        const loc_ratio = rl.getShaderLocation(s.atmo3d_shader, "atmo_ratio");
        const loc_color = rl.getShaderLocation(s.atmo3d_shader, "atmo_color");
        rl.setShaderValue(s.atmo3d_shader, loc_ratio, &atmo_thickness_ratio, .float);
        rl.setShaderValue(s.atmo3d_shader, loc_color, &color_normalized, .vec4);

        rl.beginBlendMode(.additive);
        rl.beginShaderMode(s.atmo3d_shader);

        const source_rec = rl.Rectangle{ .x = 0, .y = 0, .width = 256, .height = 256 };
        const atmo_size_vec2 = rl.Vector2{ .x = atmo_r * 2.0, .y = atmo_r * 2.0 };
        const origin = rl.Vector2{ .x = atmo_r, .y = atmo_r };

        // Calculate dynamic camera-relative up vector for pitch/yaw invariance
        const forward = rl.Vector3.normalize(rl.Vector3.subtract(s.camera.target, s.camera.position));
        const right = rl.Vector3.normalize(rl.Vector3.crossProduct(forward, .{ .x = 0, .y = 1, .z = 0 }));
        const cam_up = rl.Vector3.normalize(rl.Vector3.crossProduct(right, forward));

        rl.drawBillboardPro(
            s.camera,
            s.billboard_tex,
            source_rec,
            planet_pos,
            cam_up,
            atmo_size_vec2,
            origin,
            0.0,
            .white,
        );

        rl.endBlendMode();
        rl.endShaderMode();
    }

    rl.endMode3D();

    try ui.drawRightPanel(s, rp_x, rp_y, row);

    try ui.drawBottomBar(s, res_color, targ_color, col, col2, col3, bot_y);

    _ = t_orbit;
}
