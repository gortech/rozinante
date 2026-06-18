const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Window = vaxis.Window;
const chess = @import("../chess.zig");

pub const MAX_W = 7;
pub const MAX_H = 5;

pub const Sprite = struct {
    data: [MAX_H][MAX_W][]const u8,
    width: u8,
    height: u8,
};

const empty_row = [1][]const u8{" "} ** MAX_W;
const empty_grid = [1][MAX_W][]const u8{empty_row} ** MAX_H;

fn make(comptime w: u8, comptime rows: anytype) Sprite {
    var data = empty_grid;
    inline for (0..rows.len) |r| {
        inline for (0..w) |c| {
            data[r][c] = rows[r][c];
        }
    }
    return .{ .data = data, .width = w, .height = @intCast(rows.len) };
}

pub const pawn = make(6, .{
    .{ " ", " ", "▗", "▖", " ", " " },
    .{ " ", "▜", "█", "█", "▛", " " },
    .{ " ", "▗", "█", "█", "▖", " " },
    .{ "▟", "█", "█", "█", "█", "▙" },
});

pub const knight = make(6, .{
    .{ " ", " ", "▗", "▙", "▟", " " },
    .{ "▗", "▟", "▇", "▟", "█", "▌" },
    .{ " ", "▗", "█", "█", "▛", " " },
    .{ "▟", "█", "█", "█", "█", "▙" },
});

pub const bishop = make(6, .{
    .{ " ", "▟", "▙", "▝", "█", " " },
    .{ " ", "█", "█", "▙", "▟", " " },
    .{ " ", "▟", "█", "█", "▙", " " },
    .{ "▟", "█", "█", "█", "█", "▙" },
});

pub const rook = make(6, .{
    .{ "█", "▙", "▟", "▙", "▟", "█" },
    .{ "▝", "█", "█", "█", "█", "▘" },
    .{ "▗", "█", "█", "█", "█", "▖" },
    .{ "█", "█", "█", "█", "█", "█" },
});

pub const queen = make(6, .{
    .{ "▙", " ", "▟", "▙", " ", "▟" },
    .{ "▜", "▙", "█", "█", "▟", "▛" },
    .{ " ", "▜", "█", "█", "▛", " " },
    .{ "▟", "█", "█", "█", "█", "▙" },
});

pub const king = make(6, .{
    .{ "▄", "▂", "▟", "▙", "▂", "▄" },
    .{ "▜", "█", "▜", "▛", "█", "▛" },
    .{ " ", "▜", "█", "█", "▛", " " },
    .{ "▟", "█", "█", "█", "█", "▙" },
});

pub fn forPieceType(pt: chess.PieceType) Sprite {
    return switch (pt) {
        .pawn => pawn,
        .knight => knight,
        .bishop => bishop,
        .rook => rook,
        .queen => queen,
        .king => king,
    };
}

pub fn stamp(
    win: Window,
    s: Sprite,
    x: u16,
    y: u16,
    cell_w: u16,
    cell_h: u16,
    fg: Color,
    bg: Color,
) void {
    const x_off = x + (cell_w -| @as(u16, s.width)) / 2;
    const y_off = y + (cell_h -| @as(u16, s.height)) / 2;

    for (0..s.height) |r| {
        for (0..s.width) |c| {
            const glyph = s.data[r][c];
            const px = x_off + @as(u16, @intCast(c));
            const py = y_off + @as(u16, @intCast(r));

            if (std.mem.eql(u8, glyph, " ")) continue;

            win.writeCell(px, py, .{
                .char = .{ .grapheme = glyph, .width = 1 },
                .style = .{ .fg = fg, .bg = bg },
            });
        }
    }
}
