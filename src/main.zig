const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const obt = @import("orbits");

const font_data = @embedFile("assets/fonts/nasalization/Nasalization.otf");
const atmo_shader_src = @embedFile("assets/shaders/atmo.fs");

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;
    _ = io;
    const kerbal_bodies_str: [:0]const u8 = "Kerbol;Moho;Eve;Gilly;Kerbin;Mun;Minmus;Duna;Ike;Dres;Jool;Laythe;Vall;Tylo;Bop;Pol;Eeloo";
    const real_bodies_str: [:0]const u8 = "Sol;Mercury;Venus;Earth;Luna;Mars;Phobos;Deimos;Jupiter;Io;Europa;Ganymede;Callisto;Saturn;Titan;Enceladus;Mimas;Tethys;Dione;Rhea;Uranus;Miranda;Ariel;Umbriel;Titania;Oberon;Neptune;Triton;Pluto";
    const systems_str: [:0]const u8 = "Kerbal;Real";
    var selected_system: i32 = 0; // kerbal
    var last_selected_system: i32 = selected_system;
    var selected_body: i32 = 4; //kerbin;
    var body: obt.CelestialBody = body_id_to_body(selected_system, selected_body) catch .kerbin;

    //--------------------------------------------------------------------------------------
    var screen_width: i32 = 1920;
    var screen_height: i32 = 1080;
    var scr_w = screen_width;
    var scr_h = screen_height;
    var width_edit = false;
    var height_edit = false;

    // Body display is centered in the left half
    const screen_half: i32 = @divTrunc(screen_width, 2);
    const body_center = centered(i32, screen_half, screen_height);

    rl.setConfigFlags(.{ .msaa_4x_hint = true });

    var show_settings: bool = false;
    var scale_factor: f32 = 10.0;

    const original_size = rg.getStyle(.default, .{ .default = .text_size });
    var soi_radius: ?f32 = null;

    var targ_alt: f32 = 95_000.0;
    var vbf_txt: [256:0]u8 = std.mem.zeroes([256:0]u8);
    var edit_mode = false;
    var ps_edit_mode = false;

    var t_antecedent: f32 = 3.0;
    var consequent_txt: [3:0]u8 = std.mem.zeroes([3:0]u8);
    var edit_consequent: bool = false;
    var edit_antecedent: bool = false;
    var antecedent_txt: [3:0]u8 = std.mem.zeroes([3:0]u8);
    var t_consequent: f32 = 2.0;

    var dive_orbit: bool = false;

    var apo_txt_buf: [256:0]u8 = undefined;
    var apo_str_buf: [256:0]u8 = undefined;
    var res_p_buf: [128:0]u8 = undefined;

    _ = std.fmt.bufPrintSentinel(&vbf_txt, "{d:.1}", .{targ_alt}, 0) catch {};
    _ = std.fmt.bufPrintSentinel(&antecedent_txt, "{d:.0}", .{t_antecedent}, 0) catch {};
    _ = std.fmt.bufPrintSentinel(&consequent_txt, "{d:.0}", .{t_consequent}, 0) catch {};

    rl.initWindow(screen_width, screen_height, "Resonant Orbit Planner");
    defer rl.closeWindow();
    std.debug.print("window initialized\n", .{});

    var font_size: f32 = 32.0;
    var font_size_edit: bool = false;
    var font_size_txt: [3:0]u8 = undefined;
    var font_spacing: f32 = 2.0;
    var font_spacing_edit: bool = false;
    var font_spacing_txt: [3:0]u8 = undefined;

    _ = std.fmt.bufPrintSentinel(&font_size_txt, "{d:.0}", .{font_size}, 0) catch {};
    _ = std.fmt.bufPrintSentinel(&font_spacing_txt, "{d:.0}", .{font_spacing}, 0) catch {};

    rl.setTargetFPS(60);
    std.debug.print("Set Target FPS to 60\n", .{});
    rg.loadStyleDefault();
    std.debug.print("Default Style Loaded\n", .{});
    const font = rl.loadFontFromMemory(".otf", font_data, 32, null) catch @panic("Failed to load Font");
    std.debug.print("\x1b[32mfont loaded: glyphs={d}\x1b[0m\n", .{font.glyphCount});
    defer rl.unloadFont(font);
    rg.setFont(font);

    const atmo_shader = rl.loadShaderFromMemory(null, atmo_shader_src) catch @panic("Failed to load atmosphere shader");
    defer rl.unloadShader(atmo_shader);

    rg.setStyle(.default, .{ .default = .text_size }, 24);
    defer rg.setStyle(.default, .{ .default = .text_size }, original_size);

    while (!rl.windowShouldClose()) {
        // Zoom
        const mwm = rl.getMouseWheelMove();
        if (mwm != 0) {
            const zoom_speed = 0.08;
            const multiplier = std.math.exp(zoom_speed * -mwm);
            scale_factor *= multiplier;
            scale_factor = @max(4.0, @min(500.0, scale_factor));
        }

        // Per-frame layout anchors
        const sw: f32 = @floatFromInt(screen_width);
        const sh: f32 = @floatFromInt(screen_height);

        // Right panel: inputs, anchored to right half
        const rp_x: f32 = sw * 0.75;
        const rp_y: f32 = sh * 0.25;
        const row: f32 = 48.0;

        // Bottom bar: output data
        const bot_y: i32 = screen_height - 160;
        const col: i32 = @intFromFloat(sw * 0.05);
        const col2: i32 = @intFromFloat(sw * 0.3);
        const col3: i32 = @intFromFloat(sw * 0.55);

        const bodies_str = switch (selected_system) {
            1 => real_bodies_str,
            else => kerbal_bodies_str,
        };

        const params = obt.CelestialBody.params(body);
        const scale = body.scaled(@as(f64, @floatFromInt(@divTrunc(screen_width, @as(i32, 2)))) / scale_factor);
        const radius: f32 = @floatCast(params.radius * scale);
        const atmo_radius: f32 = if (params.atmosphere_height) |atm_h| @floatCast((params.radius * scale) + (atm_h * scale)) else 0;
        var segments: i32 = 0;

        const t_orbit = obt.OrbitalParams.initSimple(body, @as(f64, @floatCast(targ_alt)), @as(f64, @floatCast(targ_alt)), 0);
        const res_orbit = t_orbit.resonant(.{
            .antecedent = @max(1, @as(u32, @intFromFloat(@abs(t_antecedent)))),
            .consequent = @max(1, @as(u32, @intFromFloat(@abs(t_consequent)))),
        }, dive_orbit);

        const loc_center = rl.getShaderLocation(atmo_shader, "center");
        const loc_radius = rl.getShaderLocation(atmo_shader, "radius");
        const loc_atmo_size = rl.getShaderLocation(atmo_shader, "atmo_size");
        const loc_atmo_color = rl.getShaderLocation(atmo_shader, "atmo_color");
        const loc_resolution = rl.getShaderLocation(atmo_shader, "resolution");

        rl.setShaderValue(atmo_shader, loc_resolution, &[2]f32{
            @floatFromInt(screen_width),
            @floatFromInt(screen_height),
        }, .vec2);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.black);

        // ── Settings ─────────────────────────────────────────────────────────
        if (rg.checkBox(.init(10, 10, 24, 24), "Settings", &show_settings)) {}
        if (show_settings) {
            if (rg.valueBox(.init(200, 40, 100, 28), "Width: ", &scr_w, 500, 65000, width_edit) == 1) {
                width_edit = !width_edit;
            }
            if (rg.valueBox(.init(200, 75, 100, 28), "Height: ", &scr_h, 500, 65000, height_edit) == 1) {
                height_edit = !height_edit;
            }
            if (rg.button(.init(200, 110, 100, 28), "Apply")) {
                screen_width = std.math.clamp(scr_w, 100, 10_000);
                screen_height = std.math.clamp(scr_h, 100, 10_000);
                rl.setWindowSize(screen_width, screen_height);
            }

            if (rg.valueBoxFloat(.init(200, 145, 100, 28), "Font Size: ", &font_size_txt, &font_size, font_size_edit) == 1) {
                font_size_edit = !font_size_edit;
            }

            if (rg.valueBoxFloat(.init(200, 175, 100, 28), "Font Spacing: ", &font_spacing_txt, &font_spacing, font_spacing_edit) == 1) {
                font_spacing_edit = !font_spacing_edit;
            }
        }

        // ── Right Panel — Inputs ──────────────────────────────────────────────

        if (rg.valueBoxFloat(.init(rp_x, rp_y + row, 200, 32), "Target Orbit (m): ", &vbf_txt, &targ_alt, edit_mode) == 1 and !ps_edit_mode) {
            edit_mode = !edit_mode;
        }

        if (rg.valueBoxFloat(.init(rp_x, rp_y + row * 2, 80, 32), "Antecedent: ", &antecedent_txt, &t_antecedent, edit_antecedent) == 1 and !ps_edit_mode) {
            edit_antecedent = !edit_antecedent;
        }

        if (rg.valueBoxFloat(.init(rp_x, rp_y + row * 3, 80, 32), "Consequent: ", &consequent_txt, &t_consequent, edit_consequent) == 1 and !ps_edit_mode) {
            edit_consequent = !edit_consequent;
            if (t_consequent >= t_antecedent) {
                t_consequent = t_antecedent - 1;
                _ = std.fmt.bufPrintSentinel(&consequent_txt, "{d:.0}", .{t_consequent}, 0) catch "";
            }
            if (t_consequent < 1) {
                t_consequent = 1;
                _ = std.fmt.bufPrintSentinel(&consequent_txt, "{d:.0}", .{t_consequent}, 0) catch "";
            }
        }

        if (rg.checkBox(.init(rp_x, rp_y + row * 4, 24, 24), "Dive Orbit", &dive_orbit)) {}

        if (rg.dropdownBox(.init(rp_x, rp_y, 150, 32), bodies_str, &selected_body, ps_edit_mode) == 1) {
            body = try body_id_to_body(selected_system, selected_body);
            ps_edit_mode = !ps_edit_mode;
        }

        _ = rg.comboBox(.init(rp_x + 165, rp_y, 150, 32), systems_str, &selected_system);
        if (last_selected_system != selected_system) {
            last_selected_system = selected_system;
            selected_body = if (selected_system != 0) 3 else 4;
            body = body_id_to_body(selected_system, selected_body) catch switch (selected_system) {
                0 => .kerbin,
                else => .earth,
            };
        }

        // ── Planet ───────────────────────────────────────────────────────────
        const body_center_rl = body_center.asRaylibVec();

        segments = calculateSegments(radius);
        rl.drawCircleSector(body_center_rl, radius, 0.0, 360.0, segments, bodyColor(body));

        if (params.atmosphere_height != null and atmo_radius > radius) {
            const center_val = [2]f32{ body_center_rl.x, body_center_rl.y };
            const atmo_size_val = atmo_radius - radius;
            const color = atmoColor(body);
            const color_val = [4]f32{
                @as(f32, @floatFromInt(color.r)) / 255.0,
                @as(f32, @floatFromInt(color.g)) / 255.0,
                @as(f32, @floatFromInt(color.b)) / 255.0,
                0.6,
            };

            rl.setShaderValue(atmo_shader, loc_center, &center_val, .vec2);
            rl.setShaderValue(atmo_shader, loc_radius, &radius, .float);
            rl.setShaderValue(atmo_shader, loc_atmo_size, &atmo_size_val, .float);
            rl.setShaderValue(atmo_shader, loc_atmo_color, &color_val, .vec4);

            rl.beginShaderMode(atmo_shader);
            rl.drawRectangle(0, 0, screen_width, screen_height, .white);
            rl.endShaderMode();
        }

        // ── SOI ──────────────────────────────────────────────────────────────
        if (obt.CelestialBody.soi(body)) |soi| {
            soi_radius = @as(f32, @floatCast(soi * scale - radius));
            drawDashedCircle(body_center.x, body_center.y, soi_radius.?, .med, 1, .ray_white);
        }

        // ── Target Orbit ──────────────────────────────────────────────────────
        const targ_color: rl.Color = if ((radius + (@as(f32, @floatCast(targ_alt * scale))) <= atmo_radius) or (blk: {
            if (soi_radius) |soi| {
                break :blk @as(f32, @floatCast(targ_alt * scale)) > soi;
            } else break :blk false;
        })) .red else .green;
        const t_radius = @as(f32, @floatCast(radius + (targ_alt * scale)));
        segments = calculateSegments(t_radius);
        const thickness = 2.5;
        rl.drawRing(body_center_rl, t_radius, t_radius + thickness, 0.0, 360.0, segments, targ_color);

        // ── Resonant Orbit ────────────────────────────────────────────────────
        const res_offset = res_orbit.semi_major_axis * res_orbit.eccentricity;
        const res_y: f32 = @floatCast(res_offset * scale);
        const res_center: rl.Vector2 = .init(body_center_rl.x, body_center_rl.y + res_y);
        const res_semi_min: f32 = @floatCast(res_orbit.semi_major_axis * std.math.sqrt(1.0 - (res_orbit.eccentricity * res_orbit.eccentricity)) * scale);
        segments = calculateSegments(@as(f32, @floatCast(res_orbit.semi_major_axis * scale)));

        const res_color: rl.Color = if ((targ_color.toInt() == rl.Color.red.toInt()) or (blk: {
            if (soi_radius) |soi| {
                break :blk (@as(f32, @floatCast(res_orbit.apoapsis() * scale)) > soi) or
                    (radius + @as(f32, @floatCast(scale * res_orbit.periapsis())) < atmo_radius);
            } else break :blk false;
        })) .red else .orange;

        drawEllipseLines(res_center, res_semi_min, @as(f32, @floatCast(res_orbit.semi_major_axis * scale)), segments, res_color);

        // ── Bottom Bar — Output Data ──────────────────────────────────────────
        const apo_str = formatWithCommas(&apo_str_buf, res_orbit.apoapsis()) catch "N/A";
        const apo_txt = try std.fmt.bufPrintSentinel(&apo_txt_buf, "Ap: {s} m", .{apo_str}, 0);
        const apo_txt_pos: rl.Vector2 = .init(@as(f32, @floatFromInt(col)), @as(f32, @floatFromInt(bot_y)));
        rl.drawTextEx(font, apo_txt, apo_txt_pos, font_size, font_spacing, .ray_white);

        const peri_str = formatWithCommas(&apo_str_buf, res_orbit.periapsis()) catch "N/A";
        const peri_txt = try std.fmt.bufPrintSentinel(&apo_txt_buf, "Pe: {s} m", .{peri_str}, 0);
        const peri_txt_pos: rl.Vector2 = .init(@as(f32, @floatFromInt(col2)), @as(f32, @floatFromInt(bot_y)));
        rl.drawTextEx(font, peri_txt, peri_txt_pos, font_size, font_spacing, .ray_white);

        const transfer_dv = t_orbit.transferDv(res_orbit, dive_orbit);
        const transfer_dv_txt = std.fmt.bufPrintSentinel(&res_p_buf, "Burn DeltaV: {d:.1} m/s", .{transfer_dv}, 0) catch "N/A";
        const transfer_dv_pos: rl.Vector2 = .init(@as(f32, @floatFromInt(col3)), @as(f32, @floatFromInt(bot_y)));
        rl.drawTextEx(font, transfer_dv_txt, transfer_dv_pos, font_size, font_spacing, .magenta);

        const res_hms = periodToHMS(res_orbit.period());
        const res_p_txt = std.fmt.bufPrintSentinel(&res_p_buf, "Resonant: {d}h {d}m {d}s", .{ res_hms.hours, res_hms.minutes, res_hms.seconds }, 0) catch "N/A";
        const res_p_pos: rl.Vector2 = .init(@as(f32, @floatFromInt(col)), @as(f32, @floatFromInt(bot_y + 50)));
        rl.drawTextEx(font, res_p_txt, res_p_pos, font_size, font_spacing, res_color);

        const targ_hms = periodToHMS(t_orbit.period());
        const targ_p_txt = std.fmt.bufPrintSentinel(&res_p_buf, "Target: {d}h {d}m {d}s", .{ targ_hms.hours, targ_hms.minutes, targ_hms.seconds }, 0) catch "N/A";
        const targ_p_pos: rl.Vector2 = .init(@as(f32, @floatFromInt(col2)), @as(f32, @floatFromInt(bot_y + 50)));
        rl.drawTextEx(font, targ_p_txt, targ_p_pos, font_size, font_spacing, targ_color);
    }
}

pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,
        fn asRaylibVec(self: @This()) rl.Vector2 {
            return switch (@typeInfo(T)) {
                .float => .init(@as(f32, @floatCast(self.x)), @as(f32, @floatCast(self.y))),
                .int => .init(@as(f32, @floatFromInt(self.x)), @as(f32, @floatFromInt(self.y))),
                else => @compileError("Invalid type conversion: " ++ @typeName(T) ++ " -> f32"),
            };
        }
    };
}

fn centered(T: type, w: T, h: T) Vec2(T) {
    return Vec2(T){
        .x = @divExact(w, @as(T, 2)),
        .y = @divExact(h, @as(T, 2)),
    };
}

fn body_id_to_body(system: i32, id: i32) !obt.CelestialBody {
    return switch (system) {
        0 => switch (id) {
            0 => .kerbol,
            1 => .moho,
            2 => .eve,
            3 => .gilly,
            4 => .kerbin,
            5 => .mun,
            6 => .minmus,
            7 => .duna,
            8 => .ike,
            9 => .dres,
            10 => .jool,
            11 => .laythe,
            12 => .vall,
            13 => .tylo,
            14 => .bop,
            15 => .pol,
            16 => .eeloo,
            else => error.IndexOutOfRange,
        },
        else => switch (id) {
            0 => .sol,
            1 => .mercury,
            2 => .venus,
            3 => .earth,
            4 => .luna,
            5 => .mars,
            6 => .phobos,
            7 => .deimos,
            8 => .jupiter,
            9 => .io,
            10 => .europa,
            11 => .ganymede,
            12 => .callisto,
            13 => .saturn,
            14 => .titan,
            15 => .enceladus,
            16 => .mimas,
            17 => .tethys,
            18 => .dione,
            19 => .rhea,
            20 => .uranus,
            21 => .miranda,
            22 => .ariel,
            23 => .umbriel,
            24 => .titania,
            25 => .oberon,
            26 => .neptune,
            27 => .triton,
            28 => .pluto,
            else => error.IndexOutOfRange,
        },
    };
}

fn bodyColor(body: obt.CelestialBody) rl.Color {
    return switch (body) {
        // KSP
        .kerbol => .orange,
        .moho => .init(100, 80, 70, 255), // dark reddish-brown
        .eve => .purple,
        .gilly => .init(210, 180, 140, 255), // light brown/clay
        .kerbin => .blue,
        .mun => .gray,
        .minmus => .init(128, 224, 160, 255), // mint green
        .duna => .init(180, 80, 40, 255), // deep rust red
        .ike => .init(90, 90, 90, 255), // dark ash gray
        .dres => .init(130, 120, 110, 255), // dull gray-brown
        .jool => .init(80, 180, 80, 255), // slime green
        .laythe => .init(0, 100, 180, 255), // deep ocean blue
        .vall => .init(140, 200, 220, 255), // cyanish ice blue
        .tylo => .init(210, 210, 215, 255), // bright chalky white-gray
        .bop => .init(100, 85, 75, 255), // dark reddish-brown potato
        .pol => .init(210, 210, 150, 255), // dusty yellow-green
        .eeloo => .init(220, 230, 240, 255), // icy blue-white
        // Real
        .sol => .init(255, 200, 50, 255), // golden yellow
        .mercury => .init(150, 140, 130, 255), // warm gray
        .venus => .init(220, 190, 100, 255), // pale yellow-orange
        .earth => .init(30, 100, 200, 255), // ocean blue
        .luna => .init(180, 180, 175, 255), // pale gray
        .mars => .init(180, 80, 40, 255), // rust red
        .phobos => .init(110, 100, 90, 255), // dark grayish-brown
        .deimos => .init(120, 110, 100, 255), // slightly lighter brown-gray
        .jupiter => .init(200, 160, 110, 255), // tan/amber banded
        .io => .init(220, 200, 60, 255), // sulfurous yellow
        .europa => .init(200, 195, 180, 255), // pale icy white
        .ganymede => .init(130, 120, 110, 255), // dark gray-brown
        .callisto => .init(90, 85, 80, 255), // very dark gray
        .saturn => .init(210, 190, 140, 255), // pale gold
        .titan => .init(200, 140, 60, 255), // orange haze
        .enceladus => .init(230, 240, 255, 255), // bright icy white-blue
        .mimas => .init(190, 185, 180, 255), // pale gray
        .tethys => .init(200, 200, 195, 255), // light gray
        .dione => .init(185, 180, 175, 255), // gray
        .rhea => .init(175, 170, 165, 255), // slightly darker gray
        .uranus => .init(130, 210, 220, 255), // cyan-teal
        .miranda => .init(160, 155, 150, 255), // gray
        .ariel => .init(170, 165, 160, 255), // gray
        .umbriel => .init(80, 78, 75, 255), // very dark gray
        .titania => .init(155, 150, 145, 255), // medium gray
        .oberon => .init(100, 95, 90, 255), // dark gray
        .neptune => .init(40, 80, 200, 255), // deep blue
        .triton => .init(180, 210, 200, 255), // pale greenish-white
        .pluto => .init(180, 160, 130, 255), // tan/beige
        else => .red,
    };
}

fn atmoColor(body: obt.CelestialBody) rl.Color {
    return switch (body) {
        // KSP
        .kerbin => .init(100, 149, 237, 255), // cornflower blue
        .eve => .init(140, 80, 200, 255), // purple
        .duna => .init(210, 120, 60, 255), // rusty orange
        .laythe => .init(80, 130, 200, 255), // ocean blue
        .jool => .init(80, 180, 80, 255), // green haze
        // Real
        .earth => .init(100, 149, 237, 255), // cornflower blue
        .venus => .init(220, 180, 80, 255), // thick yellow-orange
        .mars => .init(200, 120, 60, 255), // red-orange dust
        .titan => .init(200, 140, 60, 255), // orange haze
        .jupiter => .init(180, 150, 100, 255), // amber haze
        .saturn => .init(200, 180, 130, 255), // pale gold haze
        .uranus => .init(130, 210, 220, 255), // cyan
        .neptune => .init(40, 80, 200, 255), // deep blue
        else => .init(150, 180, 255, 255), // generic blue
    };
}

const DashSpacing = enum {
    xsmall,
    small,
    med,
    large,
    xlarge,

    fn count(self: DashSpacing) f32 {
        return switch (self) {
            .xsmall => 48,
            .small => 32,
            .med => 20,
            .large => 12,
            .xlarge => 6,
        };
    }
};

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

fn drawDashedCircle(
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

fn calculateSegments(radius: f32) i32 {
    if (!std.math.isFinite(radius)) return 32;
    const min_segments: i32 = 32;
    const max_segments: i32 = 256;
    var segments: i32 = @trunc(radius * 0.65);
    segments = @max(min_segments, segments);
    segments = @min(max_segments, segments);
    return segments;
}

fn formatWithCommas(buf: []u8, value: anytype) ![]const u8 {
    var temp_buf: [64]u8 = undefined;
    const raw = try std.fmt.bufPrint(&temp_buf, "{d:.2}", .{value});
    const dec_pos = std.mem.indexOfScalar(u8, raw, '.') orelse raw.len;
    const int_part = raw[0..dec_pos];

    var w = std.Io.Writer.fixed(buf);
    var i: usize = 0;
    while (i < int_part.len) : (i += 1) {
        if (i > 0 and (int_part.len - i) % 3 == 0) {
            try w.writeByte(',');
        }
        try w.writeByte(int_part[i]);
    }
    if (dec_pos < raw.len) {
        try w.writeAll(raw[dec_pos..]);
    }
    return w.buffered();
}

pub const HoursMinutesSeconds = struct {
    hours: u32,
    minutes: u8,
    seconds: u8,
};

pub fn periodToHMS(period: f64) HoursMinutesSeconds {
    if (!std.math.isFinite(period)) return .{ .hours = 0, .minutes = 0, .seconds = 0 };
    const total_secs: u64 = @intFromFloat(@abs(period));
    return .{
        .hours = @intCast(total_secs / 3600),
        .minutes = @intCast((total_secs % 3600) / 60),
        .seconds = @intCast(total_secs % 60),
    };
}
