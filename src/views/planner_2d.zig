const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const obt = @import("orbits");
const state = @import("../state.zig");
const draw = @import("../draw.zig");
const ui = @import("../ui.zig");

pub fn update(s: *state.AppState) void {
    const mwm = rl.getMouseWheelMove();
    if (mwm != 0) {
        const zoom_speed: f32 = 0.08;
        const multiplier = std.math.exp(zoom_speed * -mwm);
        s.scale_factor *= multiplier;
        s.scale_factor = @max(4.0, @min(500.0, s.scale_factor));
    }
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

    const screen_half: i32 = @divTrunc(s.screen_width, 2);
    const body_center = Vec2(i32){
        .x = @divTrunc(screen_half, 2),
        .y = @divTrunc(s.screen_height, 2),
    };
    const body_center_rl = rl.Vector2{
        .x = @floatFromInt(body_center.x),
        .y = @floatFromInt(body_center.y),
    };

    const params = obt.CelestialBody.params(s.body);
    const scale = s.body.scaled(@as(f64, @floatFromInt(screen_half)) / s.scale_factor);
    const radius: f32 = @floatCast(params.radius * scale);
    const atmo_radius: f32 = if (params.atmosphere_height) |atm_h|
        @floatCast((params.radius * scale) + (atm_h * scale))
    else
        0;

    const t_orbit = s.targetOrbit();
    const res_orbit = s.resonantOrbit();

    // ── Shader uniforms ───────────────────────────────────────────────────
    const loc_center = rl.getShaderLocation(s.atmo2d_shader, "center");
    const loc_radius = rl.getShaderLocation(s.atmo2d_shader, "radius");
    const loc_atmo_size = rl.getShaderLocation(s.atmo2d_shader, "atmo_size");
    const loc_atmo_color = rl.getShaderLocation(s.atmo2d_shader, "atmo_color");
    const loc_resolution = rl.getShaderLocation(s.atmo2d_shader, "resolution");

    rl.setShaderValue(s.atmo2d_shader, loc_resolution, &[2]f32{
        @floatFromInt(s.screen_width),
        @floatFromInt(s.screen_height),
    }, .vec2);

    // ── Background Starfield ──────────────────────────────────────────────
    const cam_forward = rl.Vector3.normalize(rl.Vector3.subtract(s.camera.target, s.camera.position));

    const base_right = rl.Vector3.normalize(rl.Vector3.crossProduct(cam_forward, .{ .x = 0, .y = 1, .z = 0 }));
    const dynamic_up = rl.Vector3.normalize(rl.Vector3.crossProduct(base_right, cam_forward));

    const star_res_loc = rl.getShaderLocation(s.backdrop_shader, "resolution");
    const star_fwd_loc = rl.getShaderLocation(s.backdrop_shader, "cam_forward");
    const star_up_loc = rl.getShaderLocation(s.backdrop_shader, "cam_up");

    rl.setShaderValue(s.backdrop_shader, star_res_loc, &[2]f32{ sw, sh }, .vec2);
    rl.setShaderValue(s.backdrop_shader, star_fwd_loc, &[3]f32{ cam_forward.x, cam_forward.y, cam_forward.z }, .vec3);
    rl.setShaderValue(s.backdrop_shader, star_up_loc, &[3]f32{ dynamic_up.x, dynamic_up.y, dynamic_up.z }, .vec3);

    rl.beginShaderMode(s.backdrop_shader);
    rl.drawRectangle(0, 0, s.screen_width, s.screen_height, .white);
    rl.endShaderMode();

    // ── Planet ────────────────────────────────────────────────────────────
    var segments = draw.calculateSegments(radius);
    rl.drawCircleSector(body_center_rl, radius, 0.0, 360.0, segments, draw.bodyColor(s.body));

    if (params.atmosphere_height != null and atmo_radius > radius) {
        const center_val = [2]f32{ body_center_rl.x, body_center_rl.y };
        const atmo_size_val = atmo_radius - radius;
        const color = draw.atmoColor(s.body);
        const color_val = [4]f32{
            @as(f32, @floatFromInt(color.r)) / 255.0,
            @as(f32, @floatFromInt(color.g)) / 255.0,
            @as(f32, @floatFromInt(color.b)) / 255.0,
            0.6,
        };
        rl.setShaderValue(s.atmo2d_shader, loc_center, &center_val, .vec2);
        rl.setShaderValue(s.atmo2d_shader, loc_radius, &radius, .float);
        rl.setShaderValue(s.atmo2d_shader, loc_atmo_size, &atmo_size_val, .float);
        rl.setShaderValue(s.atmo2d_shader, loc_atmo_color, &color_val, .vec4);
        rl.beginShaderMode(s.atmo2d_shader);
        rl.drawRectangle(0, 0, s.screen_width, s.screen_height, .white);
        rl.endShaderMode();
    }

    // ── SOI ───────────────────────────────────────────────────────────────
    if (obt.CelestialBody.soi(s.body)) |soi| {
        s.soi_radius = @as(f32, @floatCast(soi * scale - radius));
        draw.drawDashedCircle(body_center.x, body_center.y, s.soi_radius.?, .med, 1, .ray_white);
    }

    // ── Target Orbit ──────────────────────────────────────────────────────
    const targ_color: rl.Color = if (t_orbit.isValid()) .green else .red;

    const t_offset = t_orbit.semi_major_axis * t_orbit.eccentricity;
    const t_y: f32 = @floatCast(t_offset * scale);
    const t_center = rl.Vector2{ .x = body_center_rl.x, .y = body_center_rl.y + t_y };
    const t_semi_min: f32 = @floatCast(t_orbit.semi_major_axis * std.math.sqrt(1.0 - t_orbit.eccentricity * t_orbit.eccentricity) * scale);
    segments = draw.calculateSegments(@as(f32, @floatCast(t_orbit.semi_major_axis * scale)));
    draw.drawEllipseLines(t_center, t_semi_min, @as(f32, @floatCast(t_orbit.semi_major_axis * scale)), segments, targ_color);

    // ── Resonant Orbit ────────────────────────────────────────────────────
    const res_offset = res_orbit.semi_major_axis * res_orbit.eccentricity;
    const res_y: f32 = @floatCast(res_offset * scale);
    const res_center = rl.Vector2{ .x = body_center_rl.x, .y = body_center_rl.y + res_y };
    const res_semi_min: f32 = @floatCast(res_orbit.semi_major_axis * std.math.sqrt(1.0 - res_orbit.eccentricity * res_orbit.eccentricity) * scale);
    segments = draw.calculateSegments(@as(f32, @floatCast(res_orbit.semi_major_axis * scale)));

    const res_color: rl.Color = if (res_orbit.isValid()) .orange else .red;

    draw.drawEllipseLines(res_center, res_semi_min, @as(f32, @floatCast(res_orbit.semi_major_axis * scale)), segments, res_color);

    // ── Right Panel ───────────────────────────────────────────────────────
    try ui.drawRightPanel(s, rp_x, rp_y, row);

    // ── Bottom Bar ────────────────────────────────────────────────────────
    try ui.drawBottomBar(s, res_color, targ_color, col, col2, col3, bot_y);
}

fn Vec2(comptime T: type) type {
    return struct { x: T, y: T };
}
