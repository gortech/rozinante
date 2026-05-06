const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Window = vaxis.Window;
const chess = @import("../chess.zig");
const Game = @import("game.zig").Game;

pub const Theme = struct {
    pub const bg: Color = .{ .rgb = .{ 15, 15, 35 } };
    pub const dark_square: Color = .{ .rgb = .{ 45, 30, 80 } };
    pub const light_square: Color = .{ .rgb = .{ 75, 50, 120 } };
    pub const white_piece: Color = .{ .rgb = .{ 220, 220, 240 } };
    pub const black_piece: Color = .{ .rgb = .{ 40, 40, 60 } };
    pub const text_primary: Color = .{ .rgb = .{ 192, 202, 245 } };
    pub const text_dim: Color = .{ .rgb = .{ 100, 110, 150 } };
    pub const highlight_cursor: Color = .{ .rgb = .{ 255, 0, 255 } };
    pub const highlight_selected: Color = .{ .rgb = .{ 180, 0, 255 } };
    pub const highlight_legal: Color = .{ .rgb = .{ 0, 200, 255 } };
    pub const highlight_check: Color = .{ .rgb = .{ 255, 50, 50 } };
    pub const highlight_flash: Color = .{ .rgb = .{ 255, 0, 0 } };
};

pub const RenderMode = enum {
    spacious,
    compact,
};

pub fn detectRenderMode(win_width: u16, win_height: u16) RenderMode {
    if (win_height < 26 or win_width < 52) return .compact;
    return .spacious;
}

pub fn toUnicode(p: chess.Piece) []const u8 {
    return switch (p) {
        .white_king => "♔",
        .white_queen => "♕",
        .white_rook => "♖",
        .white_bishop => "♗",
        .white_knight => "♘",
        .white_pawn => "♙",
        .black_king => "♚",
        .black_queen => "♛",
        .black_rook => "♜",
        .black_bishop => "♝",
        .black_knight => "♞",
        .black_pawn => "♟",
        .empty => " ",
    };
}

fn pieceColor(p: chess.Piece) Color {
    if (p.isWhite()) return Theme.white_piece;
    if (p.isBlack()) return Theme.black_piece;
    return Theme.bg;
}

fn baseSquareColor(file: u3, rank: u3) Color {
    if ((file + rank) % 2 == 0) return Theme.dark_square;
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

pub fn renderBoard(win: Window, game: *const Game, mode: RenderMode) void {
    switch (mode) {
        .spacious => renderSpacious(win, game),
        .compact => renderCompact(win, game),
    }
}

fn renderSpacious(win: Window, game: *const Game) void {
    const cell_w: u16 = 6;
    const cell_h: u16 = 3;
    const label_w: u16 = 2;
    const label_h: u16 = 1;

    for (0..8) |dr| {
        const display_row: u3 = @intCast(dr);
        const rank_label: u8 = if (game.flipped) '1' + @as(u8, display_row) else '8' - @as(u8, display_row);

        const ry: u16 = @as(u16, display_row) * cell_h;
        win.writeCell(0, ry + 1, .{
            .char = .{ .grapheme = &.{rank_label}, .width = 1 },
            .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
        });

        for (0..8) |dc| {
            const display_col: u3 = @intCast(dc);
            const sq_idx = boardSquare(display_row, display_col, game.flipped);
            const piece = game.board.squares[sq_idx];
            const bg = resolveSquareColor(game, sq_idx, display_col, display_row);

            const cx: u16 = label_w + @as(u16, display_col) * cell_w;

            for (0..cell_h) |row_off| {
                const ry_off: u16 = ry + @as(u16, @intCast(row_off));
                for (0..cell_w) |col_off| {
                    const cx_off: u16 = cx + @as(u16, @intCast(col_off));
                    win.writeCell(cx_off, ry_off, .{
                        .style = .{ .bg = bg },
                    });
                }
            }

            if (piece != .empty) {
                win.writeCell(cx + cell_w / 2, ry + cell_h / 2, .{
                    .char = .{ .grapheme = toUnicode(piece), .width = 1 },
                    .style = .{ .fg = pieceColor(piece), .bg = bg },
                });
            }
        }
    }

    for (0..8) |dc| {
        const display_col: u3 = @intCast(dc);
        const file_label: u8 = if (game.flipped) 'h' - @as(u8, display_col) else 'a' + @as(u8, display_col);
        const cx: u16 = label_w + @as(u16, display_col) * cell_w + cell_w / 2;
        const fy: u16 = 8 * cell_h + label_h - 1;
        win.writeCell(cx, fy, .{
            .char = .{ .grapheme = &.{file_label}, .width = 1 },
            .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
        });
    }
}

fn renderCompact(win: Window, game: *const Game) void {
    const cell_w: u16 = 2;
    const label_w: u16 = 2;

    for (0..8) |dr| {
        const display_row: u3 = @intCast(dr);
        const rank_label: u8 = if (game.flipped) '1' + @as(u8, display_row) else '8' - @as(u8, display_row);
        const ry: u16 = @intCast(dr);

        win.writeCell(0, ry, .{
            .char = .{ .grapheme = &.{rank_label}, .width = 1 },
            .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
        });

        for (0..8) |dc| {
            const display_col: u3 = @intCast(dc);
            const sq_idx = boardSquare(display_row, display_col, game.flipped);
            const piece = game.board.squares[sq_idx];
            const bg = resolveSquareColor(game, sq_idx, display_col, display_row);

            const cx: u16 = label_w + @as(u16, display_col) * cell_w;

            win.writeCell(cx, ry, .{
                .style = .{ .bg = bg },
            });
            win.writeCell(cx + 1, ry, .{
                .style = .{ .bg = bg },
            });

            if (piece != .empty) {
                win.writeCell(cx, ry, .{
                    .char = .{ .grapheme = toUnicode(piece), .width = 1 },
                    .style = .{ .fg = pieceColor(piece), .bg = bg },
                });
            }
        }
    }

    const fy: u16 = 8;
    for (0..8) |dc| {
        const display_col: u3 = @intCast(dc);
        const file_label: u8 = if (game.flipped) 'h' - @as(u8, display_col) else 'a' + @as(u8, display_col);
        const cx: u16 = label_w + @as(u16, display_col) * cell_w;
        win.writeCell(cx, fy, .{
            .char = .{ .grapheme = &.{file_label}, .width = 1 },
            .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
        });
    }
}

pub fn renderInfoPanel(win: Window) void {
    win.fill(.{ .style = .{ .bg = Theme.bg } });
}
