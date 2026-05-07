const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Window = vaxis.Window;
const chess = @import("../chess.zig");
const Game = @import("game.zig").Game;
const sprites = @import("sprites.zig");

pub const Theme = struct {
    pub const bg: Color = .{ .rgb = .{ 15, 15, 35 } };
    pub const dark_square: Color = .{ .rgb = .{ 55, 40, 100 } };
    pub const light_square: Color = .{ .rgb = .{ 105, 70, 150 } };
    pub const white_piece: Color = .{ .rgb = .{ 200, 200, 220 } };
    pub const black_piece: Color = .{ .rgb = .{ 20, 20, 40 } };
    pub const text_primary: Color = .{ .rgb = .{ 192, 202, 245 } };
    pub const text_dim: Color = .{ .rgb = .{ 100, 110, 150 } };
    pub const highlight_cursor: Color = .{ .rgb = .{ 255, 0, 255 } };
    pub const highlight_selected: Color = .{ .rgb = .{ 180, 0, 255 } };
    pub const highlight_legal: Color = .{ .rgb = .{ 0, 200, 255 } };
    pub const highlight_check: Color = .{ .rgb = .{ 255, 50, 50 } };
    pub const highlight_flash: Color = .{ .rgb = .{ 255, 0, 0 } };
};

pub const RenderOptions = struct {
    cell_w: u16 = 9,
    cell_h: u16 = 4,
    label_w: u16 = 2,
    label_h: u16 = 1,
    show_labels: bool = true,
    show_pieces: bool = true,
};

fn pieceColor(p: chess.Piece) Color {
    if (p.isWhite()) return Theme.white_piece;
    if (p.isBlack()) return Theme.black_piece;
    return Theme.bg;
}

fn baseSquareColor(file: u3, rank: u3) Color {
    if ((@as(u4, file) + rank) % 2 == 0) return Theme.dark_square;
    return Theme.light_square;
}

fn boardSquare(display_row: u3, display_col: u3, flipped: bool) u6 {
    const file: u3 = if (flipped) 7 - display_col else display_col;
    const rank: u3 = if (flipped) display_row else 7 - display_row;
    return @as(u6, rank) * 8 + @as(u6, file);
}

fn squareHighlight(game: *const Game, sq_idx: u6) ?Color {
    if (game.flash_square) |fs| {
        if (fs.toIndex() == sq_idx and game.flash_timer > 0)
            return Theme.highlight_flash;
    }

    if (game.cursor.toIndex() == sq_idx)
        return Theme.highlight_cursor;

    if (game.selected) |sel| {
        if (sel.toIndex() == sq_idx)
            return Theme.highlight_selected;
    }

    if (game.legal_targets[sq_idx])
        return Theme.highlight_legal;

    if (game.isKingInCheck()) {
        if (game.activeKingSquare()) |king_sq| {
            if (king_sq.toIndex() == sq_idx)
                return Theme.highlight_check;
        }
    }

    return null;
}

fn resolveSquareColor(game: *const Game, sq_idx: u6, display_col: u3, display_row: u3) Color {
    return squareHighlight(game, sq_idx) orelse baseSquareColor(display_col, display_row);
}

pub fn boardWidth(opts: RenderOptions) u16 {
    const label = if (opts.show_labels) opts.label_w else 0;
    return label + 8 * opts.cell_w;
}

pub fn boardHeight(opts: RenderOptions) u16 {
    const label = if (opts.show_labels) opts.label_h else 0;
    return label + 8 * opts.cell_h;
}

const rank_labels = [_][]const u8{ "8", "7", "6", "5", "4", "3", "2", "1" };
const rank_labels_flipped = [_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8" };
const file_labels = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h" };
const file_labels_flipped = [_][]const u8{ "h", "g", "f", "e", "d", "c", "b", "a" };

pub fn renderBoard(win: Window, game: *const Game, opts: RenderOptions) void {
    const x_origin: u16 = if (opts.show_labels) opts.label_w else 0;

    for (0..8) |dr| {
        const display_row: u3 = @intCast(dr);
        const ry: u16 = @as(u16, display_row) * opts.cell_h;

        if (opts.show_labels) {
            const labels = if (game.flipped) rank_labels_flipped else rank_labels;
            win.writeCell(0, ry + opts.cell_h / 2, .{
                .char = .{ .grapheme = labels[dr], .width = 1 },
                .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
            });
        }

        for (0..8) |dc| {
            const display_col: u3 = @intCast(dc);
            const sq_idx = boardSquare(display_row, display_col, game.flipped);
            const piece = game.board.squares[sq_idx];
            const bg = resolveSquareColor(game, sq_idx, display_col, display_row);

            const cx: u16 = x_origin + @as(u16, display_col) * opts.cell_w;

            for (0..opts.cell_h) |row_off| {
                const ry_off: u16 = ry + @as(u16, @intCast(row_off));
                for (0..opts.cell_w) |col_off| {
                    const cx_off: u16 = cx + @as(u16, @intCast(col_off));
                    win.writeCell(cx_off, ry_off, .{
                        .char = .{ .grapheme = " ", .width = 1 },
                        .style = .{ .bg = bg },
                    });
                }
            }

            if (opts.show_pieces and piece != .empty) {
                if (piece.pieceType()) |pt| {
                    const fg = pieceColor(piece);
                    sprites.stamp(win, sprites.forPieceType(pt), cx, ry, opts.cell_w, opts.cell_h, fg, bg);
                }
            }
        }
    }

    if (opts.show_labels) {
        const f_labels = if (game.flipped) file_labels_flipped else file_labels;
        for (0..8) |dc| {
            const cx: u16 = x_origin + @as(u16, @intCast(dc)) * opts.cell_w + opts.cell_w / 2;
            const fy: u16 = 8 * opts.cell_h;
            win.writeCell(cx, fy, .{
                .char = .{ .grapheme = f_labels[dc], .width = 1 },
                .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
            });
        }
    }
}

pub fn renderInfoPanel(win: Window) void {
    win.fill(.{ .style = .{ .bg = Theme.bg } });
}
