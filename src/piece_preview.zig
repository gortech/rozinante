const std = @import("std");
const vaxis = @import("vaxis");
const rozinante = @import("rozinante");
const sprites = rozinante.tui.sprites;
const Theme = rozinante.tui.renderer.Theme;
const chess = rozinante.chess;

pub const Panic = std.debug.FullPanic(panicHandler);

var global_tty: ?vaxis.Tty = null;
var global_vx: ?vaxis.Vaxis = null;

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

const cell_w: u16 = 9;
const cell_h: u16 = 5;

const piece_types = [_]chess.PieceType{ .pawn, .knight, .bishop, .rook, .queen, .king };
const piece_labels = [_][]const u8{ "Pawn", "Knight", "Bishop", "Rook", "Queen", "King" };

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
            },
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
            },
            else => {},
        }

        const win = vx.window();
        win.clear();
        win.fill(.{ .style = .{ .bg = Theme.bg } });

        const label_row: u16 = 0;
        const white_row: u16 = 1;
        const black_row: u16 = 1 + cell_h;
        const hint_row: u16 = 1 + cell_h * 2;

        for (piece_labels, 0..) |name, i| {
            const col: u16 = @intCast(i);
            const x = col * cell_w + (cell_w -| @as(u16, @intCast(name.len))) / 2;
            for (0..name.len) |ci| {
                win.writeCell(x + @as(u16, @intCast(ci)), label_row, .{
                    .char = .{ .grapheme = name[ci .. ci + 1], .width = 1 },
                    .style = .{ .fg = Theme.text_primary, .bg = Theme.bg },
                });
            }
        }

        for (piece_types, 0..) |pt, i| {
            const col: u16 = @intCast(i);
            const bg_w = if (i % 2 == 0) Theme.dark_square else Theme.light_square;
            const bg_b = if (i % 2 == 0) Theme.light_square else Theme.dark_square;
            const x = col * cell_w;

            fillRect(win, x, white_row, cell_w, cell_h, bg_w);
            sprites.stamp(win, sprites.forPieceType(pt), x, white_row, cell_w, cell_h, Theme.white_piece, bg_w);

            fillRect(win, x, black_row, cell_w, cell_h, bg_b);
            sprites.stamp(win, sprites.forPieceType(pt), x, black_row, cell_w, cell_h, Theme.black_piece, bg_b);
        }

        const hint = "q: quit";
        for (hint, 0..) |_, ci| {
            win.writeCell(@intCast(ci), hint_row, .{
                .char = .{ .grapheme = hint[ci .. ci + 1], .width = 1 },
                .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
            });
        }

        try vx.render(tty.writer());
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
