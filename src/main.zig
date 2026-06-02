const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const obt = @import("orbits");
const state = @import("state.zig");
const ui = @import("ui.zig");
const planner_2d = @import("views/planner_2d.zig");
const planner_3d = @import("views/planner_3d.zig");

const font_data = @embedFile("assets/fonts/nasalization/Nasalization.otf");
const atmo2d_shader_src = @embedFile("assets/shaders/atmo2d.fs");
const atmo3d_shader_src = @embedFile("assets/shaders/atmo3d.fs");
const backdrop_shader_src = @embedFile("assets/shaders/backdrop.fs");
const latlong_frag_shader_src = @embedFile("assets/shaders/latlong.fs");
const latlong_vert_shader_src = @embedFile("assets/shaders/latlong.vs");

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    _ = io;

    var screen_width: i32 = 1920;
    var screen_height: i32 = 1080;

    const _sw: struct { w: i32, h: i32 } = blk: {
        rl.setConfigFlags(.{ .window_hidden = true });
        rl.initWindow(0, 0, "");
        const monitor = rl.getCurrentMonitor();
        const width = rl.getMonitorWidth(monitor);
        const height = rl.getMonitorHeight(monitor);
        rl.closeWindow();
        break :blk .{ .w = width, .h = height };
    };

    screen_height = _sw.h;
    screen_width = _sw.w;

    rl.setConfigFlags(.{ .msaa_4x_hint = true, .borderless_windowed_mode = true, .fullscreen_mode = false });
    rl.initWindow(screen_width, screen_height, "Resonant Orbit Planner");
    defer rl.closeWindow();

    const font = rl.loadFontFromMemory(".otf", font_data, 32, null) catch @panic("Failed to load Font");
    defer rl.unloadFont(font);

    const atmo2d_shader = rl.loadShaderFromMemory(null, atmo2d_shader_src) catch @panic("Failed to load atmosphere 2D shader");
    defer rl.unloadShader(atmo2d_shader);
    const atmo3d_shader = rl.loadShaderFromMemory(null, atmo3d_shader_src) catch @panic("Failed to load atmosphere 3D shader");
    defer rl.unloadShader(atmo3d_shader);
    const backdrop_shader = rl.loadShaderFromMemory(null, backdrop_shader_src) catch @panic("Failed to load backdrop shader");
    defer rl.unloadShader(backdrop_shader);
    const latlong_shader = rl.loadShaderFromMemory(latlong_vert_shader_src, latlong_frag_shader_src) catch @panic("Failed to load latlong shader");
    defer rl.unloadShader(latlong_shader);

    rl.setTargetFPS(60);
    rg.loadStyleDefault();
    rg.setFont(font);

    const original_size = rg.getStyle(.default, .{ .default = .text_size });
    rg.setStyle(.default, .{ .default = .text_size }, 24);
    defer rg.setStyle(.default, .{ .default = .text_size }, original_size);

    var s = state.AppState.init(font, atmo2d_shader, atmo3d_shader, backdrop_shader, latlong_shader, screen_width, screen_height);

    while (!rl.windowShouldClose()) {
        // Update active view
        switch (s.view_mode) {
            .planner_2d => planner_2d.update(&s),
            .planner_3d => planner_3d.update(&s),
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.black);

        // Draw active view
        switch (s.view_mode) {
            .planner_2d => try planner_2d.drawView(&s),
            .planner_3d => try planner_3d.drawView(&s),
        }

        // ── Tab bar (always on top) ───────────────────────────────────────
        ui.drawTabBar(&s);

        // ── Settings (always on top) ──────────────────────────────────────
        ui.drawSettings(&s);
    }
}
