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
    atmo2d_shader: rl.Shader,
    atmo3d_shader: rl.Shader,
    backdrop_shader: rl.Shader,
    billboard_img: rl.Image,
    billboard_tex: rl.Texture,

    // Body selection
    selected_system: i32,
    last_selected_system: i32,
    selected_body: i32,
    body: obt.CelestialBody,
    ps_edit_mode: bool,

    // Orbit inputs
    ap: f32,
    pe: f32,
    incl: f32,
    incl_txt: [6:0]u8,
    ap_txt: [256:0]u8,
    pe_txt: [256:0]u8,
    edit_ap: bool,
    edit_pe: bool,
    t_antecedent: f32,
    t_consequent: f32,
    antecedent_txt: [3:0]u8,
    consequent_txt: [3:0]u8,
    edit_antecedent: bool,
    edit_consequent: bool,
    edit_incl: bool,
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
    is_panning: bool,
    pan_last: rl.Vector2,
    cam_pos_x: f32,
    cam_pos_y: f32,

    pub fn init(font: rl.Font, atmo2d_shader: rl.Shader, atmo3d_shader: rl.Shader, backdrop_shader: rl.Shader) AppState {
        const img = rl.genImageColor(256, 256, .white);
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
            .atmo2d_shader = atmo2d_shader,
            .atmo3d_shader = atmo3d_shader,
            .backdrop_shader = backdrop_shader,
            .billboard_img = img,
            .billboard_tex = rl.Texture.fromImage(img) catch @panic("failed to load billboard texture"),

            .selected_system = 0,
            .last_selected_system = 0,
            .selected_body = 4,
            .body = .kerbin,
            .ps_edit_mode = false,

            .ap = 95_000.0,
            .pe = 95_000.0,
            .incl = 0.0,
            .incl_txt = std.mem.zeroes([6:0]u8),
            .ap_txt = std.mem.zeroes([256:0]u8),
            .pe_txt = std.mem.zeroes([256:0]u8),
            .edit_ap = false,
            .edit_pe = false,
            .t_antecedent = 3.0,
            .t_consequent = 2.0,
            .antecedent_txt = std.mem.zeroes([3:0]u8),
            .consequent_txt = std.mem.zeroes([3:0]u8),
            .edit_antecedent = false,
            .edit_consequent = false,
            .edit_incl = false,
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
            .is_panning = false,
            .pan_last = .{ .x = 0, .y = 0 },
            .cam_pos_x = 0,
            .cam_pos_y = 0,
        };

        _ = std.fmt.bufPrintSentinel(&state.ap_txt, "{d:.1}", .{state.ap}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.pe_txt, "{d:.1}", .{state.pe}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.antecedent_txt, "{d:.0}", .{state.t_antecedent}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.consequent_txt, "{d:.0}", .{state.t_consequent}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.font_size_txt, "{d:.0}", .{state.font_size}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.font_spacing_txt, "{d:.0}", .{state.font_spacing}, 0) catch {};
        _ = std.fmt.bufPrintSentinel(&state.incl_txt, "{d:.0}", .{state.incl}, 0) catch {};

        return state;
    }

    pub fn targetOrbit(self: *const AppState) obt.OrbitalParams {
        return obt.OrbitalParams.initSimple(
            self.body,
            @as(f64, @floatCast(self.ap)),
            @as(f64, @floatCast(self.pe)),
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
        const left_mouse_btn = rl.isMouseButtonDown(.left);
        const right_mouse_btn = rl.isMouseButtonDown(.right);

        if (left_mouse_btn) {
            if (!self.is_dragging) {
                self.is_dragging = true;
                self.drag_last = mouse;
            } else {
                const gain: f32 = 0.005;
                const dx = (mouse.x - self.drag_last.x) * gain;
                const dy = (mouse.y - self.drag_last.y) * gain;
                self.cam_yaw += dx;
                const max_pitch = std.math.pi / 2.0 - 0.01; // sub 0.01 prevents gimbal lock / view flip
                self.cam_pitch = std.math.clamp(self.cam_pitch - dy, -max_pitch, max_pitch);
                self.drag_last = mouse;
            }
        } else {
            self.is_dragging = false;
        }

        if (right_mouse_btn) {
            if (!self.is_panning) {
                self.is_panning = true;
                self.pan_last = mouse;
            } else {
                const gain: f32 = 0.0005;
                const dx = (mouse.x - self.pan_last.x) * gain;
                const dy = (mouse.y - self.pan_last.y) * gain;
                self.cam_pos_x -= dx * self.cam_distance;
                self.cam_pos_y += dy * self.cam_distance;
                self.pan_last = mouse;
            }
        } else {
            self.is_panning = false;
        }

        const mwm = rl.getMouseWheelMove();
        if (mwm != 0) {
            const zoom_speed: f32 = 0.08;
            self.cam_distance *= std.math.exp(zoom_speed * -mwm);
            self.cam_distance = @max(5.0, @min(5000.0, self.cam_distance));
        }

        self.camera.target = .{
            .x = self.cam_pos_x,
            .y = self.cam_pos_y,
            .z = 0,
        };

        self.camera.position = .{
            .x = self.cam_distance * @cos(self.cam_pitch) * @sin(self.cam_yaw) + self.cam_pos_x,
            .y = self.cam_distance * @sin(self.cam_pitch) + self.cam_pos_y,
            .z = self.cam_distance * @cos(self.cam_pitch) * @cos(self.cam_yaw),
        };
    }
};
