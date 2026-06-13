const std = @import("std");
const rl = @import("raylib");
const rg = @import("raygui");
const obt = @import("orbits");
const state = @import("state.zig");
const ui = @import("ui.zig");
const planner_2d = @import("views/planner_2d.zig");
const planner_3d = @import("views/planner_3d.zig");

extern fn GuiSetStyle(control: c_int, property: c_int, value: c_int) void;

const font_data = @embedFile("assets/fonts/nasalization/Nasalization.otf");
const atmo2d_shader_src = @embedFile("assets/shaders/atmo2d.fs");
const atmo3d_shader_src = @embedFile("assets/shaders/atmo3d.fs");
const backdrop_shader_src = @embedFile("assets/shaders/backdrop.fs");
const latlong_frag_shader_src = @embedFile("assets/shaders/latlong.fs");
const latlong_vert_shader_src = @embedFile("assets/shaders/latlong.vs");
const style_src = @embedFile("assets/styles/orbits.rgs");

pub fn main(init: std.process.Init) anyerror!void {
    const io = init.io;

    var screen_width: i32 = 1920;
    var screen_height: i32 = 1080;

    const c_alloc = std.heap.c_allocator;

    var arena: std.heap.ArenaAllocator = .init(c_alloc);
    defer arena.deinit();
    const gpa = arena.allocator();

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
    loadStyleFromMemory(gpa, style_src) catch |err| {
        var std_err_buf: [128]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &std_err_buf);
        defer stderr_writer.flush() catch {};

        const stderr = &stderr_writer.interface;
        stderr.print("\n\x1b[31m[ERROR]:\x1b[0m Failed to load custom style from memory: \x1b[4;31m{s}\x1b[0m\n\n", .{@errorName(err)}) catch {};
    };
    // rg.loadStyle("src/assets/styles/orbits.rgs");
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

// RGS binary format constants
const RGS_SIGNATURE = "rGS ";
const RAYGUI_MAX_PROPS_BASE = 16;
const RAYGUI_MAX_CONTROLS = 16;

const StyleLoadError = error{
    TooShort,
    BadSignature,
    BufferOverrun,
};

/// Reads a comptime-known integer type from `data` at `offset`, advances offset.
inline fn readInt(comptime T: type, data: []const u8, offset: *usize) StyleLoadError!T {
    const size = @sizeOf(T);
    if (offset.* + size > data.len) return StyleLoadError.BufferOverrun;
    const val = std.mem.readInt(T, data[offset.*..][0..size], .little);
    offset.* += size;
    return val;
}

/// Reads `count` raw bytes from `data` at `offset` into `dest`, advances offset.
inline fn readBytes(dest: []u8, data: []const u8, offset: *usize) StyleLoadError!void {
    if (offset.* + dest.len > data.len) return StyleLoadError.BufferOverrun;
    @memcpy(dest, data[offset.*..][0..dest.len]);
    offset.* += dest.len;
}

pub fn loadStyleFromMemory(allocator: std.mem.Allocator, data: []const u8) anyerror!void {
    if (data.len < 12) return StyleLoadError.TooShort;

    var offset: usize = 0;

    // --- Header (12 bytes) ---
    var signature: [4]u8 = undefined;
    try readBytes(&signature, data, &offset);

    if (!std.mem.eql(u8, &signature, RGS_SIGNATURE)) return StyleLoadError.BadSignature;

    const version = try readInt(i16, data, &offset);
    const _reserved = try readInt(i16, data, &offset);
    _ = _reserved;
    const property_count = try readInt(i32, data, &offset);

    // --- Style properties ---
    for (0..@intCast(property_count)) |_| {
        const control_id = try readInt(i16, data, &offset);
        const property_id = try readInt(i16, data, &offset);
        const property_value = try readInt(u32, data, &offset);

        if (control_id == 0) {
            GuiSetStyle(0, property_id, @bitCast(property_value));
            if (property_id < RAYGUI_MAX_PROPS_BASE) {
                for (1..RAYGUI_MAX_CONTROLS) |j| {
                    GuiSetStyle(@intCast(j), property_id, @bitCast(property_value));
                }
            }
        } else {
            GuiSetStyle(control_id, property_id, @bitCast(property_value));
        }
    }

    // --- Custom font (optional) ---
    const font_data_size = try readInt(i32, data, &offset);
    if (font_data_size <= 0) return;

    // Font header
    const base_size = try readInt(i32, data, &offset);
    const glyph_count = try readInt(i32, data, &offset);
    const _font_type = try readInt(i32, data, &offset);
    _ = _font_type; // 0=Normal, 1=SDF

    // Font white rectangle (4x f32 = 16 bytes)
    const white_x = try readInt(u32, data, &offset);
    const white_y = try readInt(u32, data, &offset);
    const white_w = try readInt(u32, data, &offset);
    const white_h = try readInt(u32, data, &offset);
    const font_white_rec = rl.Rectangle{
        .x = @bitCast(white_x),
        .y = @bitCast(white_y),
        .width = @bitCast(white_w),
        .height = @bitCast(white_h),
    };

    // Atlas image sizes
    const font_image_uncomp_size = try readInt(i32, data, &offset);
    const font_image_comp_size = try readInt(i32, data, &offset);

    // Atlas image dims + format
    const img_width = try readInt(i32, data, &offset);
    const img_height = try readInt(i32, data, &offset);
    const img_format = try readInt(i32, data, &offset);

    // --- Atlas image data ---
    var im_font = rl.Image{
        .data = @ptrCast(@constCast(&[_]u8{})),
        .width = img_width,
        .height = img_height,
        .mipmaps = 1,
        .format = @enumFromInt(img_format),
    };

    const img_data: []u8 = blk: {
        if (font_image_comp_size > 0 and font_image_comp_size != font_image_uncomp_size) {
            // Compressed (DEFLATE) — decompress via raylib
            if (offset + @as(usize, @intCast(font_image_comp_size)) > data.len)
                return StyleLoadError.BufferOverrun;

            const decomp = try rl.decompressData(
                data[offset..][0..@intCast(font_image_comp_size)],
                font_image_comp_size,
            );
            offset += @intCast(font_image_comp_size);

            if (decomp.len != @as(usize, @intCast(font_image_uncomp_size)))
                std.log.warn("raygui: font atlas decompressed size mismatch", .{});

            break :blk decomp;
        } else {
            // Uncompressed — copy out
            const sz: usize = @intCast(font_image_uncomp_size);
            if (offset + sz > data.len) return StyleLoadError.BufferOverrun;
            const buf = try allocator.alloc(u8, sz);
            @memcpy(buf, data[offset..][0..sz]);
            offset += sz;
            break :blk buf;
        }
    };
    im_font.data = img_data.ptr;

    // Unload previous font texture if not the default
    var font = std.mem.zeroes(rl.Font);
    font.baseSize = base_size;
    font.glyphCount = glyph_count;

    const default_font = try rl.getFontDefault();

    if (font.texture.id != default_font.texture.id)
        rl.unloadTexture(font.texture);

    font.texture = try rl.loadTextureFromImage(im_font);
    allocator.free(img_data); // done with atlas pixel data

    if (font.texture.id == 0) {
        // Texture upload failed — fall back to default font
        rg.setFont(default_font);
        return;
    }

    // --- Recs data ---
    const recs_data_size: usize = @intCast(glyph_count * @sizeOf(rl.Rectangle));
    var recs_comp_size: i32 = 0;
    if (version >= 400) recs_comp_size = try readInt(i32, data, &offset);

    const recs_slice = try allocator.alloc(rl.Rectangle, @intCast(glyph_count));

    if (recs_comp_size > 0 and recs_comp_size != @as(i32, @intCast(recs_data_size))) {
        if (offset + @as(usize, @intCast(recs_comp_size)) > data.len)
            return StyleLoadError.BufferOverrun;

        const decomp = try rl.decompressData(
            data[offset..][0..@intCast(recs_comp_size)],
            recs_comp_size,
        );
        defer rl.memFree(decomp.ptr);
        offset += @intCast(recs_comp_size);

        if (decomp.len != recs_data_size)
            std.log.warn("raygui: font recs decompressed size mismatch", .{});

        @memcpy(std.mem.sliceAsBytes(recs_slice), decomp[0..recs_data_size]);
    } else {
        // Uncompressed recs
        for (recs_slice) |*rec| {
            rec.x = @bitCast(try readInt(u32, data, &offset));
            rec.y = @bitCast(try readInt(u32, data, &offset));
            rec.width = @bitCast(try readInt(u32, data, &offset));
            rec.height = @bitCast(try readInt(u32, data, &offset));
        }
    }
    font.recs = recs_slice.ptr;

    // --- Glyphs data ---
    const glyphs_data_size: i32 = glyph_count * 16; // 16 bytes per glyph
    var glyphs_comp_size: i32 = 0;
    if (version >= 400) glyphs_comp_size = try readInt(i32, data, &offset);

    const glyphs_slice = try allocator.alloc(rl.GlyphInfo, @intCast(glyph_count));
    @memset(glyphs_slice, std.mem.zeroes(rl.GlyphInfo));

    if (glyphs_comp_size > 0 and glyphs_comp_size != glyphs_data_size) {
        if (offset + @as(usize, @intCast(glyphs_comp_size)) > data.len)
            return StyleLoadError.BufferOverrun;

        const decomp = try rl.decompressData(
            data[offset..][0..@intCast(glyphs_comp_size)],
            glyphs_comp_size,
        );
        defer rl.memFree(decomp.ptr);
        offset += @intCast(glyphs_comp_size);

        if (decomp.len != @as(usize, @intCast(glyphs_data_size)))
            std.log.warn("raygui: font glyphs decompressed size mismatch", .{});

        var gp: usize = 0;
        for (glyphs_slice) |*g| {
            g.value = std.mem.readInt(i32, decomp[gp..][0..4], .little);
            g.offsetX = std.mem.readInt(i32, decomp[gp + 4 ..][0..4], .little);
            g.offsetY = std.mem.readInt(i32, decomp[gp + 8 ..][0..4], .little);
            g.advanceX = std.mem.readInt(i32, decomp[gp + 12 ..][0..4], .little);
            gp += 16;
        }
    } else {
        // Uncompressed glyphs
        for (glyphs_slice) |*g| {
            g.value = try readInt(i32, data, &offset);
            g.offsetX = try readInt(i32, data, &offset);
            g.offsetY = try readInt(i32, data, &offset);
            g.advanceX = try readInt(i32, data, &offset);
        }
    }
    font.glyphs = glyphs_slice.ptr;
    font.glyphCount = glyph_count;

    rg.setFont(font);

    // Bind font atlas as the shape-drawing white texture (single draw call optimisation)
    if (font_white_rec.x > 0 and font_white_rec.y > 0 and
        font_white_rec.width > 0 and font_white_rec.height > 0)
    {
        rl.setShapesTexture(font.texture, font_white_rec);
    }
}
