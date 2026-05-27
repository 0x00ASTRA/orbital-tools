const std = @import("std");
const rl = @import("raylib");
const obt = @import("orbits");

pub const ViewMode = enum {
    planner_2d,
    planner_3d,
};

pub const AppState = struct {
    // Window
    screen_width: i32 = 1920,
    screen_height: i32 = 1080,
    scr_w: i32 = 1920,
    scr_h: i32 = 1080,
    width_edit: bool,
    height_edit: bool,
    show_settings: bool,

    // View
    view_mode: ViewMode,
    show_lines: bool,

    // Assets
    font: rl.Font,
    font_size: f32,
    font_spacing: f32,
    font_size_edit: bool,
    font_spacing_edit: bool,
    font_size_txt: [3:0]u8,
    font_spacing_txt: [3:0]u8,
    atmo_shader: rl.Shader,

    // Body selection
    selected_system: i32,
    last_selected_system: i32,
    selected_body: i32,
    body: obt.CelestialBody,
    ps_edit_mode: bool,

    // Orbit inputs
    targ_alt: f32,
    vbf_txt: [256:0]u8,
    edit_mode: bool,
    t_antecedent: f32,
    t_consequent: f32,
    antecedent_txt: [3:0]u8,
    consequent_txt: [3:0]u8,
    edit_antecedent: bool,
    edit_consequent: bool,
    dive_orbit: bool,

    // Zoom (2D)
    scale_factor: f32,
    soi_radius: ?f32,

    // Camera (3D)
    camera: rl.Camera3D,
    cam_yaw: f32,
    cam_pitch: f32,
    cam_distance: f32,
    is_dragging: bool,
    drag_last: rl.Vector2,

    pub fn init(font: rl.Font, atmo_shader: rl.Shader) AppState {
        var state = AppState{
            .width_edit = false,
            .height_edit = false,
            .show_settings = false,

            .view_mode = .planner_2d,
            .show_lines = true,

            .font = font,
            .font_size = 28.0,
            .font_spacing = 2.0,
            .font_size_edit = false,
            .font_spacing_edit = false,
            .font_size_txt = std.mem.zeroes([3:0]u8),
            .font_spacing_txt = std.mem.zeroes([3:0]u8),
            .atmo_shader = atmo_shader,

            .selected_system = 0,
            .last_selected_system = 0,
            .selected_body = 4,
            .body = .kerbin,
            .ps_edit_mode = false,

            .targ_alt = 95_000.0,
            .vbf_txt = std.mem.zeroes([256:0]u8),
            .edit_mode = false,
            .t_antecedent = 3.0,
            .t_consequent = 2.0,
            .antecedent_txt = std.mem.zeroes([3:0]u8),
            .consequent_txt = std.mem.zeroes([3:0]u8),
            .edit_antecedent = false,
            .edit_consequent = false,
            .dive_orbit = false,

            .scale_factor = 10.0,
            .soi_radius = null,

            .camera = .{
                .position = .{ .x = 0, .y = 0, .z = 50 },
                .target = .{ .x = 0, .y = 0, .z = 0 },
                .up = .{ .x = 0, .y = 1, .z = 0 },
                .fovy = 45.0,
                .projection = .perspective,
            },
            .cam_yaw = 0.0,
            .cam_pitch = 0.3,
            .cam_distance = 50.0,
            .is_dragging = false,
            .drag_last = .{ .x = 0, .y = 0 },
        };

        _ = std.fmt.bufPrintSentinel(&state.vbf_txt, "{d:.1}", .{state.targ_alt}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.antecedent_txt, "{d:.0}", .{state.t_antecedent}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.consequent_txt, "{d:.0}", .{state.t_consequent}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.font_size_txt, "{d:.0}", .{state.font_size}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.font_spacing_txt, "{d:.0}", .{state.font_spacing}, 0) catch {};

        return state;
    }

    pub fn targetOrbit(self: *const AppState) obt.OrbitalParams {
        return obt.OrbitalParams.initSimple(
            self.body,
            @as(f64, @floatCast(self.targ_alt)),
            @as(f64, @floatCast(self.targ_alt)),
            0,
        );
    }

    pub fn resonantOrbit(self: *const AppState) obt.OrbitalParams {
        return self.targetOrbit().resonant(.{
            .antecedent = @max(1, @as(u32, @intFromFloat(@abs(self.t_antecedent)))),
            .consequent = @max(1, @as(u32, @intFromFloat(@abs(self.t_consequent)))),
        }, self.dive_orbit);
    }

    pub fn updateCamera(self: *AppState) void {
        const mouse = rl.getMousePosition();
        const mouse_btn = rl.isMouseButtonDown(.left);

        if (mouse_btn) {
            if (!self.is_dragging) {
                self.is_dragging = true;
                self.drag_last = mouse;
            } else {
                const dx = (mouse.x - self.drag_last.x) * 0.005;
                const dy = (mouse.y - self.drag_last.y) * 0.005;
                self.cam_yaw += dx;
                self.cam_pitch = std.math.clamp(self.cam_pitch - dy, -1.4, 1.4);
                self.drag_last = mouse;
            }
        } else {
            self.is_dragging = false;
        }

        const mwm = rl.getMouseWheelMove();
        if (mwm != 0) {
            const zoom_speed: f32 = 0.08;
            self.cam_distance *= std.math.exp(zoom_speed * -mwm);
            self.cam_distance = @max(5.0, @min(5000.0, self.cam_distance));
        }

        self.camera.position = .{
            .x = self.cam_distance * @cos(self.cam_pitch) * @sin(self.cam_yaw),
            .y = self.cam_distance * @sin(self.cam_pitch),
            .z = self.cam_distance * @cos(self.cam_pitch) * @cos(self.cam_yaw),
        };
    }
};
