const std = @import("std");
const vaxis = @import("vaxis");
const rozinante = @import("rozinante");
const sprites = rozinante.tui.sprites;
const renderer = rozinante.tui.renderer;
const Theme = &renderer.Theme;
const Marks = renderer.Marks;
const chess = rozinante.chess;

pub const Panic = std.debug.FullPanic(panicHandler);

var global_tty: ?vaxis.Tty = null;
var global_vx: ?vaxis.Vaxis = null;
var preview_theme: renderer.ThemeId = .classic;

fn panicHandler(msg: []const u8, ret_addr: ?usize) noreturn {
    if (global_tty) |*tty| {
        if (global_vx) |*vx| {
            vx.deinit(null, tty.writer());
        }
        tty.deinit();
    }
    std.debug.defaultPanic(msg, ret_addr);
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    cap_da1,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    mouse_leave,
    focus_in,
    focus_out,
    paste_start,
    paste_end,
    paste: []const u8,
    color_report: vaxis.Cell.Color.Report,
    color_scheme: vaxis.Cell.Color.Scheme,
    cap_kitty_keyboard,
    cap_kitty_graphics,
    cap_rgb,
    cap_sgr_pixels,
    cap_unicode,
    cap_color_scheme_updates,
    cap_multi_cursor,
};

const cell_w: u16 = 12;
const cell_h: u16 = 6;

const piece_types = [_]chess.PieceType{ .pawn, .knight, .bishop, .rook, .queen, .king };
const piece_labels = [_][]const u8{ "Pawn", "Knight", "Bishop", "Rook", "Queen", "King" };

const Sample = struct { label: []const u8, marks: Marks };

// One labeled sample per state (R2-R10) plus the key combinations (R14). Each is
// rendered through renderer.drawMarks so the gallery cannot drift from the board.
const samples = [_]Sample{
    .{ .label = "selected", .marks = .{ .border = .selected } },
    .{ .label = "cursor", .marks = .{ .cursor = true } },
    .{ .label = "legal (empty)", .marks = .{ .center = true } },
    .{ .label = "capture", .marks = .{ .border = .capture } },
    .{ .label = "check", .marks = .{ .border = .check } },
    .{ .label = "endangered", .marks = .{ .endangered = true } },
    .{ .label = "best move", .marks = .{ .best_move = true } },
    .{ .label = "engine move", .marks = .{ .border = .engine } },
    .{ .label = "capture flash", .marks = .{ .border = .flash } },
    .{ .label = "cap+endgr+best", .marks = .{ .border = .capture, .endangered = true, .best_move = true } },
    .{ .label = "selected+cursor", .marks = .{ .border = .selected, .cursor = true } },
    .{ .label = "MAX stack", .marks = .{ .border = .capture, .cursor = true, .endangered = true, .best_move = true } },
};

const gallery_cols: u16 = 4;
const col_stride: u16 = cell_w * 2 + 2; // two variant columns + gap
const row_stride: u16 = cell_h * 2 + 2; // label + two variant rows + gap

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();

    var tty_buf: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buf);
    global_tty = tty;
    defer {
        tty.deinit();
        global_tty = null;
    }

    var vx = try vaxis.Vaxis.init(io, alloc, init.environ_map, .{});
    global_vx = vx;
    defer {
        vx.deinit(alloc, tty.writer());
        global_vx = null;
    }

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), std.Io.Duration.fromMilliseconds(3000));

    while (true) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.codepoint == 'q') break;
                if (key.codepoint == 't') {
                    preview_theme = switch (preview_theme) {
                        .classic => .wood,
                        .wood => .green,
                        .green => .blue,
                        .blue => .classic,
                    };
                    renderer.Theme = renderer.palette(preview_theme);
                }
            },
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
            },
            else => {},
        }

        const win = vx.window();
        win.clear();
        win.fill(.{ .style = .{ .bg = Theme.bg } });

        render(win);

        try vx.render(tty.writer());
    }
}

fn render(win: vaxis.Window) void {
    const dim: vaxis.Cell.Style = .{ .fg = Theme.text_dim, .bg = Theme.bg };
    const primary: vaxis.Cell.Style = .{ .fg = Theme.text_primary, .bg = Theme.bg };

    _ = renderer.writeStr(win, 0, 0, "Rozinante preview", primary);
    const thx = renderer.writeStr(win, 60, 0, "q: quit  t: ", dim);
    _ = renderer.writeStr(win, thx, 0, preview_theme.label(), primary);

    // --- piece sprite preview ---
    const sp_label: u16 = 2;
    const sp_white: u16 = sp_label + 1;
    const sp_black: u16 = sp_white + cell_h;

    for (piece_labels, 0..) |name, i| {
        const x: u16 = @as(u16, @intCast(i)) * cell_w + (cell_w -| @as(u16, @intCast(name.len))) / 2;
        _ = renderer.writeStr(win, x, sp_label, name, primary);
    }
    for (piece_types, 0..) |pt, i| {
        const bg_w = if (i % 2 == 0) Theme.dark_square else Theme.light_square;
        const bg_b = if (i % 2 == 0) Theme.light_square else Theme.dark_square;
        const x: u16 = @as(u16, @intCast(i)) * cell_w;
        fillRect(win, x, sp_white, cell_w, cell_h, bg_w);
        sprites.stamp(win, sprites.forPieceType(pt), x, sp_white, cell_w, cell_h, Theme.white_piece, bg_w);
        fillRect(win, x, sp_black, cell_w, cell_h, bg_b);
        sprites.stamp(win, sprites.forPieceType(pt), x, sp_black, cell_w, cell_h, Theme.black_piece, bg_b);
    }

    // --- highlight gallery ---
    const g_header: u16 = sp_black + cell_h + 1;
    _ = renderer.writeStr(win, 0, g_header, "Highlight gallery (per block: TL light+piece  TR dark+piece  BL/BR empty)", dim);

    const grid_top: u16 = g_header + 2;
    for (samples, 0..) |s, i| {
        const idx: u16 = @intCast(i);
        const bx: u16 = (idx % gallery_cols) * col_stride;
        const by: u16 = grid_top + (idx / gallery_cols) * row_stride;
        _ = renderer.writeStr(win, bx, by, s.label, primary);
        const blk: u16 = by + 1;
        drawSample(win, bx, blk, Theme.light_square, s.marks, true, Theme.black_piece);
        drawSample(win, bx + cell_w, blk, Theme.dark_square, s.marks, true, Theme.white_piece);
        drawSample(win, bx, blk + cell_h, Theme.light_square, s.marks, false, Theme.black_piece);
        drawSample(win, bx + cell_w, blk + cell_h, Theme.dark_square, s.marks, false, Theme.white_piece);
    }

    // --- legend ---
    const sample_rows = (samples.len + gallery_cols - 1) / gallery_cols;
    const leg: u16 = grid_top + @as(u16, @intCast(sample_rows)) * row_stride;
    _ = renderer.writeStr(win, 0, leg, "Legend:", primary);
    _ = renderer.writeStr(win, 2, leg + 1, "outline = border (one wins): check/flash solid, selected thick, capture/engine thin; hue per state", dim);
    _ = renderer.writeStr(win, 2, leg + 2, "cursor = bright edge-mid blocks   best move = top-right   endangered = bottom-left   center = legal-empty square", dim);
}

fn drawSample(
    win: vaxis.Window,
    x: u16,
    y: u16,
    base: vaxis.Cell.Color,
    marks: Marks,
    with_piece: bool,
    piece_fg: vaxis.Cell.Color,
) void {
    fillRect(win, x, y, cell_w, cell_h, base);
    if (with_piece) {
        sprites.stamp(win, sprites.queen, x, y, cell_w, cell_h, piece_fg, base);
        // A piece is present, so the legal-target mark (empty squares only) would
        // never co-occur on the board; drop it here to stay faithful.
        var m = marks;
        m.center = false;
        renderer.drawMarks(win, x, y, .{}, m, base);
    } else {
        renderer.drawMarks(win, x, y, .{}, marks, base);
    }
}

fn fillRect(win: vaxis.Window, x: u16, y: u16, w: u16, h: u16, bg: vaxis.Cell.Color) void {
    for (0..h) |row| {
        for (0..w) |col| {
            win.writeCell(x + @as(u16, @intCast(col)), y + @as(u16, @intCast(row)), .{
                .style = .{ .bg = bg },
            });
        }
    }
}
