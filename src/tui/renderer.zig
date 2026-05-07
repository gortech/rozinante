const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Window = vaxis.Window;
const chess = @import("../chess.zig");
const game_mod = @import("game.zig");
const Game = game_mod.Game;
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
    pub const highlight_promotion: Color = .{ .rgb = .{ 255, 200, 0 } };
};

pub const RenderOptions = struct {
    cell_w: u16 = 9,
    cell_h: u16 = 4,
    label_w: u16 = 2,
    label_h: u16 = 1,
    show_labels: bool = true,
    show_pieces: bool = true,
};

pub const compact_options = RenderOptions{
    .cell_w = 3,
    .cell_h = 2,
    .label_w = 2,
    .label_h = 1,
    .show_labels = true,
    .show_pieces = true,
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

fn pieceToUnicode(p: chess.Piece) ?[]const u8 {
    return switch (p) {
        .white_king => "\u{2654}",
        .white_queen => "\u{2655}",
        .white_rook => "\u{2656}",
        .white_bishop => "\u{2657}",
        .white_knight => "\u{2658}",
        .white_pawn => "\u{2659}",
        .black_king => "\u{265A}",
        .black_queen => "\u{265B}",
        .black_rook => "\u{265C}",
        .black_bishop => "\u{265D}",
        .black_knight => "\u{265E}",
        .black_pawn => "\u{265F}",
        .empty => null,
    };
}

const rank_labels = [_][]const u8{ "8", "7", "6", "5", "4", "3", "2", "1" };
const rank_labels_flipped = [_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8" };
const file_labels = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h" };
const file_labels_flipped = [_][]const u8{ "h", "g", "f", "e", "d", "c", "b", "a" };

pub fn renderBoard(win: Window, game: *const Game, opts: RenderOptions) void {
    const x_origin: u16 = if (opts.show_labels) opts.label_w else 0;
    const use_sprites = opts.cell_w >= 5 and opts.cell_h >= 4;

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
                if (use_sprites) {
                    if (piece.pieceType()) |pt| {
                        const fg = pieceColor(piece);
                        sprites.stamp(win, sprites.forPieceType(pt), cx, ry, opts.cell_w, opts.cell_h, fg, bg);
                    }
                } else {
                    if (pieceToUnicode(piece)) |sym| {
                        const px = cx + opts.cell_w / 2;
                        const py = ry + opts.cell_h / 2;
                        win.writeCell(px, py, .{
                            .char = .{ .grapheme = sym, .width = 1 },
                            .style = .{ .fg = pieceColor(piece), .bg = bg },
                        });
                    }
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

// --- Text rendering helpers ---

const digit_strs = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" };

pub fn writeStr(win: Window, x: u16, y: u16, text: []const u8, style: Cell.Style) u16 {
    var col = x;
    var i: usize = 0;
    while (i < text.len) {
        const b = text[i];
        const byte_len: usize = if (b < 0x80) 1 else if (b < 0xE0) 2 else if (b < 0xF0) 3 else 4;
        if (i + byte_len > text.len) break;
        if (col >= win.width) break;
        win.writeCell(col, y, .{
            .char = .{ .grapheme = text[i..][0..byte_len], .width = 1 },
            .style = style,
        });
        col += 1;
        i += byte_len;
    }
    return col;
}

pub fn writeNum(win: Window, x: u16, y: u16, n: u16, style: Cell.Style) u16 {
    if (n == 0) {
        win.writeCell(x, y, .{ .char = .{ .grapheme = "0", .width = 1 }, .style = style });
        return x + 1;
    }
    var col = x;
    var digits: [5]u8 = undefined;
    var len: u8 = 0;
    var num = n;
    while (num > 0) {
        digits[len] = @intCast(num % 10);
        num /= 10;
        len += 1;
    }
    while (len > 0) {
        len -= 1;
        win.writeCell(col, y, .{ .char = .{ .grapheme = digit_strs[digits[len]], .width = 1 }, .style = style });
        col += 1;
    }
    return col;
}

fn writePad(win: Window, x: u16, y: u16, target: u16) u16 {
    var col = x;
    while (col < target and col < win.width) {
        win.writeCell(col, y, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{ .bg = Theme.bg } });
        col += 1;
    }
    return col;
}

// --- Info panel sections ---

fn renderCapturedRow(win: Window, game: *const Game, color: chess.Color, x: u16, y: u16) void {
    const piece_order = [5]chess.PieceType{ .queen, .rook, .bishop, .knight, .pawn };
    var col = x;
    for (piece_order) |pt| {
        for (game.move_history[0..game.move_count]) |record| {
            if (record.captured) |cap| {
                if (cap.color()) |c| {
                    if (c == color) {
                        if (cap.pieceType()) |cpt| {
                            if (cpt == pt) {
                                if (col < win.width) {
                                    const sym = game_mod.pieceSymbol(pt, color);
                                    col = writeStr(win, col, y, sym, .{ .fg = Theme.text_primary, .bg = Theme.bg });
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn renderPromotionStatus(win: Window, x: u16, y: u16, pp: game_mod.PromotionPending, game: *const Game) void {
    const color = game.board.active_color;
    var col = x;
    col = writeStr(win, col, y, "Promote: ", .{ .fg = Theme.text_primary, .bg = Theme.bg });

    for (0..4) |i| {
        const sym = game_mod.pieceSymbol(game_mod.promotion_pieces[i], color);
        const is_selected = (i == pp.selected_idx);
        if (is_selected) {
            col = writeStr(win, col, y, "[", .{ .fg = Theme.highlight_promotion, .bg = Theme.bg });
            col = writeStr(win, col, y, sym, .{ .fg = Theme.highlight_promotion, .bg = Theme.bg });
            col = writeStr(win, col, y, "]", .{ .fg = Theme.highlight_promotion, .bg = Theme.bg });
        } else {
            col = writeStr(win, col, y, " ", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            col = writeStr(win, col, y, sym, .{ .fg = Theme.text_dim, .bg = Theme.bg });
            col = writeStr(win, col, y, " ", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        }
    }
}

pub fn renderInfoPanel(win: Window, game: *const Game) void {
    win.fill(.{ .style = .{ .bg = Theme.bg } });

    if (win.width < 8 or win.height < 8) return;

    var y: u16 = 0;

    _ = writeStr(win, 1, y, "ROZINANTE", .{ .fg = Theme.text_primary, .bg = Theme.bg });
    y += 2;

    // Status / promotion UI
    if (game.promotion_pending) |pp| {
        renderPromotionStatus(win, 1, y, pp, game);
        y += 1;
        _ = writeStr(win, 1, y, "\u{2190}\u{2192} cycle  Enter confirm  Esc cancel", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        y += 1;
    } else if (game.game_phase == .ended) {
        if (game.result) |result| {
            _ = writeStr(win, 1, y, result, .{ .fg = Theme.highlight_check, .bg = Theme.bg });
        }
        y += 1;
    } else {
        const status_str = if (game.board.active_color == .white) "White to move" else "Black to move";
        const col = writeStr(win, 1, y, status_str, .{ .fg = Theme.text_primary, .bg = Theme.bg });
        if (game.isKingInCheck()) {
            _ = writeStr(win, col + 1, y, "Check!", .{ .fg = Theme.highlight_check, .bg = Theme.bg });
        }
        y += 1;
    }
    y += 1;

    // Captured pieces
    const cap_label_style: Cell.Style = .{ .fg = Theme.text_dim, .bg = Theme.bg };
    _ = writeStr(win, 1, y, "Captured:", .{ .fg = Theme.text_dim, .bg = Theme.bg });
    y += 1;
    _ = writeStr(win, 1, y, "\u{2659}", cap_label_style);
    _ = writeStr(win, 2, y, " ", cap_label_style);
    renderCapturedRow(win, game, .white, 3, y);
    y += 1;
    _ = writeStr(win, 1, y, "\u{265F}", cap_label_style);
    _ = writeStr(win, 2, y, " ", cap_label_style);
    renderCapturedRow(win, game, .black, 3, y);
    y += 1;
    y += 1;

    // Move history
    const keybind_lines: u16 = 3;
    const avail_h = if (win.height > y + keybind_lines) win.height - y - keybind_lines else 0;

    if (avail_h > 0 and game.move_count > 0) {
        const total_pairs: u16 = @intCast((game.move_count + 1) / 2);
        const display_pairs = @min(avail_h, total_pairs);
        const start_pair = total_pairs - display_pairs;

        for (0..display_pairs) |i| {
            const pair_idx: u16 = start_pair + @as(u16, @intCast(i));
            const white_idx: usize = @as(usize, pair_idx) * 2;
            const move_num: u16 = pair_idx + 1;

            var col: u16 = 1;
            col = writeNum(win, col, y, move_num, .{ .fg = Theme.text_dim, .bg = Theme.bg });
            col = writeStr(win, col, y, ".", .{ .fg = Theme.text_dim, .bg = Theme.bg });

            if (white_idx < game.move_count) {
                col += 1;
                col = writeStr(win, col, y, game.fan_history[white_idx].slice(), .{ .fg = Theme.text_primary, .bg = Theme.bg });
            }

            const black_idx = white_idx + 1;
            if (black_idx < game.move_count) {
                const padded = writePad(win, col, y, @min(14, win.width -| 1));
                _ = writeStr(win, padded, y, game.fan_history[black_idx].slice(), .{ .fg = Theme.text_primary, .bg = Theme.bg });
            }

            y += 1;
        }
    }

    // Keybind hints at bottom
    const hint_y = win.height -| 2;
    if (hint_y > y) {
        _ = writeStr(win, 1, hint_y, "\u{2191}\u{2193}\u{2190}\u{2192} Move  Enter Select", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        _ = writeStr(win, 1, hint_y + 1, "U Undo N New F Flip Q Quit", .{ .fg = Theme.text_dim, .bg = Theme.bg });
    }
}

pub fn renderResizeMessage(win: Window) void {
    win.fill(.{ .style = .{ .bg = Theme.bg } });
    const msg = "Terminal too small";
    const hint = "Please resize your terminal";
    const cy = win.height / 2;
    const msg_x = if (win.width > 18) (win.width - 18) / 2 else 0;
    const hint_x = if (win.width > 27) (win.width - 27) / 2 else 0;
    _ = writeStr(win, msg_x, cy -| 1, msg, .{ .fg = Theme.text_primary, .bg = Theme.bg });
    _ = writeStr(win, hint_x, cy, hint, .{ .fg = Theme.text_dim, .bg = Theme.bg });
}
