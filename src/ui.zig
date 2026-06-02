const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const state = @import("state.zig");

pub const kerbal_bodies_str: [:0]const u8 = "Kerbol;Moho;Eve;Gilly;Kerbin;Mun;Minmus;Duna;Ike;Dres;Jool;Laythe;Vall;Tylo;Bop;Pol;Eeloo";
pub const real_bodies_str: [:0]const u8 = "Sol;Mercury;Venus;Earth;Luna;Mars;Phobos;Deimos;Jupiter;Io;Europa;Ganymede;Callisto;Saturn;Titan;Enceladus;Mimas;Tethys;Dione;Rhea;Uranus;Miranda;Ariel;Umbriel;Titania;Oberon;Neptune;Triton;Pluto";
pub const systems_str: [:0]const u8 = "Kerbal;Real";

pub fn bodiesStr(system: i32) [:0]const u8 {
    return if (system == 1) real_bodies_str else kerbal_bodies_str;
}

pub fn bodyIdToBody(system: i32, id: i32) !@import("orbits").CelestialBody {
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

pub fn drawSettings(s: *state.AppState) void {
    const ui_scale = s.ui_scale;
    const check_box_w: f32 = 24 * ui_scale;
    const check_box_x: f32 = 10;
    const check_box_y: f32 = check_box_x;
    const rect_h: f32 = s.font_size + 4;
    const rect_w: f32 = 100 * ui_scale;
    const rect_x: f32 = 200;
    const row_sep: f32 = 10 * ui_scale;
    var row_iter: Iter = .init(0);
    const row_y: f32 = rect_h + row_sep;

    if (rg.checkBox(.init(check_box_x, check_box_y, check_box_w, check_box_w), "Settings", &s.show_settings)) {}
    if (!s.show_settings) return;

    if (rg.valueBox(.init(rect_x, row_y * row_iter.next(f32), rect_w, rect_h), "Width: ", &s.scr_w, 500, 65000, s.width_edit) == 1) {
        s.width_edit = !s.width_edit;
    }
    if (rg.valueBox(.init(rect_x, row_y * row_iter.next(f32), rect_w, rect_h), "Height: ", &s.scr_h, 500, 65000, s.height_edit) == 1) {
        s.height_edit = !s.height_edit;
    }
    if (rg.button(.init(rect_x, row_y * row_iter.next(f32), rect_w, rect_h), "Apply")) {
        s.screen_width = std.math.clamp(s.scr_w, @as(i32, @trunc(rect_w)), 10_000);
        s.screen_height = std.math.clamp(s.scr_h, @as(i32, @trunc(rect_w)), 10_000);
        rl.setWindowSize(s.screen_width, s.screen_height);
    }
    if (rg.valueBoxFloat(.init(rect_x, row_y * row_iter.next(f32), rect_w, rect_h), "Font Size: ", &s.font_size_txt, &s.font_size, s.font_size_edit) == 1) {
        s.font_size_edit = !s.font_size_edit;
        rg.setStyle(.default, .{ .default = .text_size }, @as(i32, @trunc(s.font_size)));
    }
    if (rg.valueBoxFloat(.init(rect_x, row_y * row_iter.next(f32), rect_w, rect_h), "Font Spacing: ", &s.font_spacing_txt, &s.font_spacing, s.font_spacing_edit) == 1) {
        s.font_spacing_edit = !s.font_spacing_edit;
    }
    if (rg.valueBoxFloat(.init(rect_x, row_y * row_iter.next(f32), rect_w, rect_h), "UI Scale: ", &s.ui_scale_txt, &s.ui_scale, s.ui_scale_edit) == 1) {
        s.ui_scale_edit = !s.ui_scale_edit;
    }
}

const Iter = struct {
    val: usize,
    start_val: usize,

    pub fn init(start_val: usize) Iter {
        return .{
            .val = 0,
            .start_val = start_val,
        };
    }

    pub fn next(self: *Iter, T: type) T {
        const init_val: usize = self.val;
        const new_val: usize = init_val + 1;
        self.val = new_val;
        errdefer self.val = init_val;
        return switch (@typeInfo(T)) {
            .int => @as(T, @intCast(new_val)),
            .float => @as(T, @floatFromInt(new_val)),
            else => @compileError("Invalid Type Conversion"),
        };
    }

    pub fn reset(self: *Iter) void {
        self.val = self.start_val;
    }
};

pub fn drawRightPanel(s: *state.AppState, rp_x: f32, rp_y: f32, row: f32) !void {
    const bs = bodiesStr(s.selected_system);
    var row_num: Iter = .init(0);
    const ui_scale = s.ui_scale;
    const font_size = s.font_size;
    const rect_h = font_size + 4;
    const sys_dd_w: f32 = 150 * ui_scale;
    const sys_cb_w: f32 = 120 * ui_scale;
    const long_inp_w: f32 = 200 * ui_scale;
    const short_inp_w: f32 = 80 * ui_scale;
    const check_box_w: f32 = 24 * ui_scale;
    const elem_space: f32 = 10 * ui_scale; //px

    _ = rg.comboBox(.init(rp_x + sys_dd_w + elem_space, rp_y, sys_cb_w, rect_h), systems_str, &s.selected_system);
    if (s.selected_system != s.last_selected_system) {
        s.selected_body = 0;
        s.last_selected_system = s.selected_system;
        s.body = try bodyIdToBody(s.selected_system, s.selected_body);
    }

    if (rg.valueBoxFloat(
        .init(rp_x, rp_y + row * row_num.next(f32), long_inp_w, rect_h),
        "Target Ap (m): ",
        &s.ap_txt,
        &s.ap,
        s.edit_ap,
    ) == 1 and !s.ps_edit_mode) {
        s.edit_ap = !s.edit_ap;
        if (s.edit_ap) std.debug.print("\x1b[33mtrue\x1b[0m\n", .{});
        if (s.ap < s.pe) {
            s.pe = s.ap;
            _ = std.fmt.bufPrintSentinel(
                &s.pe_txt,
                "{d:.0}",
                .{s.pe},
                0,
            ) catch "";
        }
    }
    if (rg.valueBoxFloat(
        .init(rp_x, rp_y + row * row_num.next(f32), long_inp_w, rect_h),
        "Target Pe (m): ",
        &s.pe_txt,
        &s.pe,
        s.edit_pe,
    ) == 1 and !s.ps_edit_mode) {
        s.edit_pe = !s.edit_pe;
        if (s.pe > s.ap) {
            s.pe = s.ap;
            _ = std.fmt.bufPrintSentinel(
                &s.pe_txt,
                "{d:.0}",
                .{s.pe},
                0,
            ) catch "";
        }
    }

    if (rg.valueBoxFloat(
        .init(rp_x, rp_y + row * row_num.next(f32), short_inp_w, rect_h),
        "Antecedent: ",
        &s.antecedent_txt,
        &s.t_antecedent,
        s.edit_antecedent,
    ) == 1 and !s.ps_edit_mode) {
        s.edit_antecedent = !s.edit_antecedent;
    }

    if (rg.valueBoxFloat(
        .init(rp_x, rp_y + row * row_num.next(f32), long_inp_w, rect_h),
        "Consequent: ",
        &s.consequent_txt,
        &s.t_consequent,
        s.edit_consequent,
    ) == 1 and !s.ps_edit_mode) {
        s.edit_consequent = !s.edit_consequent;
        if (s.t_consequent >= s.t_antecedent) {
            s.t_consequent = s.t_antecedent - 1;
            _ = std.fmt.bufPrintSentinel(
                &s.consequent_txt,
                "{d:.0}",
                .{s.t_consequent},
                0,
            ) catch "";
        }
        if (s.t_consequent < 1) {
            s.t_consequent = 1;
            _ = std.fmt.bufPrintSentinel(
                &s.consequent_txt,
                "{d:.0}",
                .{s.t_consequent},
                0,
            ) catch "";
        }
    }

    if (rg.checkBox(
        .init(rp_x, rp_y + row * row_num.next(f32), check_box_w, check_box_w),
        "Dive Orbit",
        &s.dive_orbit,
    )) {}

    if (s.view_mode == .planner_3d) {
        if (rg.valueBoxFloat(
            .init(rp_x, rp_y + row * row_num.next(f32), long_inp_w, rect_h),
            "Inclination",
            &s.incl_txt,
            &s.incl,
            s.edit_incl,
        ) == 1 and !s.ps_edit_mode) {
            s.edit_incl = !s.edit_incl;
            if (s.incl < -359.99 or s.incl > 359.99) {
                s.incl = 0;
                _ = std.fmt.bufPrintSentinel(
                    &s.incl_txt,
                    "{d:.0}",
                    .{s.incl},
                    0,
                ) catch "";
            }
        }
        if (rg.valueBoxFloat(
            .init(rp_x, rp_y + row * row_num.next(f32), long_inp_w, rect_h),
            "Arg. of Peri",
            &s.arg_pe_txt,
            &s.arg_pe,
            s.edit_arg_pe,
        ) == 1 and !s.ps_edit_mode) {
            s.edit_arg_pe = !s.edit_arg_pe;
            if (s.arg_pe < 0 or s.arg_pe > 359.999) {
                s.arg_pe = 0;
                _ = std.fmt.bufPrintSentinel(
                    &s.arg_pe_txt,
                    "{d:.0}",
                    .{s.arg_pe},
                    0,
                ) catch 0;
            }
        }
        if (rg.checkBox(
            .init(rp_x, rp_y + row * row_num.next(f32), check_box_w, check_box_w),
            "Show Lines",
            &s.show_lines,
        )) {}
    }

    // Keep this as last element to avoid draw overlap
    if (rg.dropdownBox(
        .init(rp_x, rp_y, sys_dd_w, rect_h),
        bs,
        &s.selected_body,
        s.ps_edit_mode,
    ) == 1) {
        s.body = try bodyIdToBody(s.selected_system, s.selected_body);
        s.ps_edit_mode = !s.ps_edit_mode;
    }
}

pub fn drawBottomBar(
    s: *const state.AppState,
    res_color: rl.Color,
    targ_color: rl.Color,
    col: i32,
    col2: i32,
    col3: i32,
    bot_y: i32,
) !void {
    const obt = @import("orbits");
    const res_orbit = s.resonantOrbit();
    const t_orbit = s.targetOrbit();

    var apo_str_buf: [256]u8 = undefined;
    var txt_buf: [256:0]u8 = undefined;
    var p_buf: [128:0]u8 = undefined;

    const apo_str = formatWithCommas(&apo_str_buf, res_orbit.apoapsis()) catch "N/A";
    const apo_txt = std.fmt.bufPrintSentinel(
        &txt_buf,
        "Ap: {s} m",
        .{apo_str},
        0,
    ) catch "N/A";
    rl.drawTextEx(
        s.font,
        apo_txt,
        .init(@floatFromInt(col), @floatFromInt(bot_y)),
        s.font_size,
        s.font_spacing,
        .ray_white,
    );

    const peri_str = formatWithCommas(&apo_str_buf, res_orbit.periapsis()) catch "N/A";
    @memset(&txt_buf, undefined);
    const peri_txt = std.fmt.bufPrintSentinel(
        &txt_buf,
        "Pe: {s} m",
        .{peri_str},
        0,
    ) catch "N/A";
    rl.drawTextEx(
        s.font,
        peri_txt,
        .init(@floatFromInt(col2), @floatFromInt(bot_y)),
        s.font_size,
        s.font_spacing,
        .ray_white,
    );

    const transfer_dv = t_orbit.transferDv(res_orbit, s.dive_orbit);
    const dv_txt = std.fmt.bufPrintSentinel(
        &p_buf,
        "Burn DeltaV: {d:.1} m/s",
        .{transfer_dv},
        0,
    ) catch "N/A";
    rl.drawTextEx(
        s.font,
        dv_txt,
        .init(@floatFromInt(col3), @floatFromInt(bot_y)),
        s.font_size,
        s.font_spacing,
        .magenta,
    );

    const res_hms = periodToHMS(res_orbit.period());
    const res_p_txt = std.fmt.bufPrintSentinel(
        &p_buf,
        "Resonant: {d}h {d}m {d}s",
        .{ res_hms.hours, res_hms.minutes, res_hms.seconds },
        0,
    ) catch "N/A";
    rl.drawTextEx(
        s.font,
        res_p_txt,
        .init(@floatFromInt(col), @floatFromInt(bot_y + 50)),
        s.font_size,
        s.font_spacing,
        res_color,
    );

    const targ_hms = periodToHMS(t_orbit.period());
    const targ_p_txt = std.fmt.bufPrintSentinel(
        &p_buf,
        "Target: {d}h {d}m {d}s",
        .{ targ_hms.hours, targ_hms.minutes, targ_hms.seconds },
        0,
    ) catch "N/A";
    rl.drawTextEx(
        s.font,
        targ_p_txt,
        .init(@floatFromInt(col2), @floatFromInt(bot_y + 50)),
        s.font_size,
        s.font_spacing,
        targ_color,
    );

    _ = obt;
}

pub fn formatWithCommas(buf: []u8, value: anytype) ![]const u8 {
    var temp_buf: [64]u8 = undefined;
    const raw = try std.fmt.bufPrint(&temp_buf, "{d:.2}", .{value});
    const dec_pos = std.mem.indexOfScalar(u8, raw, '.') orelse raw.len;
    const int_part = raw[0..dec_pos];
    var w = std.Io.Writer.fixed(buf);
    var i: usize = 0;
    while (i < int_part.len) : (i += 1) {
        if (i > 0 and (int_part.len - i) % 3 == 0) try w.writeByte(',');
        try w.writeByte(int_part[i]);
    }
    if (dec_pos < raw.len) try w.writeAll(raw[dec_pos..]);
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
