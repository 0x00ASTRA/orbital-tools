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

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    _ = io;

    const screen_width: i32 = 1920;
    const screen_height: i32 = 1080;

    rl.setConfigFlags(.{ .msaa_4x_hint = true });
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

    rl.setTargetFPS(60);
    rg.loadStyleDefault();
    rg.setFont(font);

    const original_size = rg.getStyle(.default, .{ .default = .text_size });
    rg.setStyle(.default, .{ .default = .text_size }, 24);
    defer rg.setStyle(.default, .{ .default = .text_size }, original_size);

    var s = state.AppState.init(font, atmo2d_shader, atmo3d_shader, backdrop_shader);

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
        drawTabBar(&s);

        // ── Settings (always on top) ──────────────────────────────────────
        ui.drawSettings(&s);
    }
}

fn drawTabBar(s: *state.AppState) void {
    const tab_w: f32 = 120;
    const tab_h: f32 = 32;
    const tab_y: f32 = 10;
    const start_x: f32 = @as(f32, @floatFromInt(s.screen_width)) * 0.75;

    const active_color = rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
    const inactive_color = rl.Color{ .r = 30, .g = 30, .b = 30, .a = 255 };
    const border_color = rl.Color{ .r = 120, .g = 120, .b = 120, .a = 255 };
    const text_color = rl.Color{ .r = 220, .g = 220, .b = 220, .a = 255 };

    const tabs = [_]struct { label: [:0]const u8, mode: state.ViewMode }{
        .{ .label = "2D", .mode = .planner_2d },
        .{ .label = "3D", .mode = .planner_3d },
    };

    for (tabs, 0..) |tab, i| {
        const x = start_x + @as(f32, @floatFromInt(i)) * (tab_w + 4);
        const rect = rl.Rectangle{ .x = x, .y = tab_y, .width = tab_w, .height = tab_h };
        const is_active = s.view_mode == tab.mode;

        rl.drawRectangleRec(rect, if (is_active) active_color else inactive_color);
        rl.drawRectangleLinesEx(rect, 1, border_color);
        rl.drawTextEx(s.font, tab.label, .{ .x = x + tab_w / 2 - 16, .y = tab_y + 6 }, 20, 1, text_color);

        if (rl.checkCollisionPointRec(rl.getMousePosition(), rect) and
            rl.isMouseButtonPressed(.left))
        {
            s.view_mode = tab.mode;
        }
    }
}
