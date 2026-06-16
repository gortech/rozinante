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
    pub const highlight_engine_move: Color = .{ .rgb = .{ 0, 220, 180 } };
    pub const highlight_endangered: Color = .{ .rgb = .{ 255, 100, 50 } };
    pub const highlight_hint_best: Color = .{ .rgb = .{ 50, 200, 100 } };
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

    if (game.engine_last_move) |em| {
        if (em.from.toIndex() == sq_idx or em.to.toIndex() == sq_idx)
            return Theme.highlight_engine_move;
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

    if (game.hints_enabled) {
        if (game.hint_best_move) |bm| {
            if (bm.from.toIndex() == sq_idx or bm.to.toIndex() == sq_idx)
                return Theme.highlight_hint_best;
        }
        if (game.hint_endangered[sq_idx])
            return Theme.highlight_endangered;
    }

    return null;
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

pub fn renderBoardCore(win: Window, board: *const chess.Board, opts: RenderOptions, flipped: bool, highlight: ?*const Game) void {
    const x_origin: u16 = if (opts.show_labels) opts.label_w else 0;
    const use_sprites = opts.cell_w >= 5 and opts.cell_h >= 4;

    for (0..8) |dr| {
        const display_row: u3 = @intCast(dr);
        const ry: u16 = @as(u16, display_row) * opts.cell_h;

        if (opts.show_labels) {
            const labels = if (flipped) rank_labels_flipped else rank_labels;
            win.writeCell(0, ry + opts.cell_h / 2, .{
                .char = .{ .grapheme = labels[dr], .width = 1 },
                .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
            });
        }

        for (0..8) |dc| {
            const display_col: u3 = @intCast(dc);
            const sq_idx = boardSquare(display_row, display_col, flipped);
            const piece = board.squares[sq_idx];
            const file: u3 = @intCast(sq_idx % 8);
            const rank: u3 = @intCast(sq_idx / 8);
            const base = baseSquareColor(file, rank);
            const bg = if (highlight) |g| (squareHighlight(g, sq_idx) orelse base) else base;

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
                    if (piece.pieceType()) |pt| {
                        const sym = game_mod.pieceSymbol(pt, piece.color() orelse continue);
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
        const f_labels = if (flipped) file_labels_flipped else file_labels;
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

pub fn renderBoard(win: Window, game: *const Game, opts: RenderOptions) void {
    renderBoardCore(win, &game.board, opts, game.flipped, game);
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
    } else if (game.resign_pending) {
        _ = writeStr(win, 1, y, "Resign? Y/Enter = Yes, N/Esc = No", .{ .fg = Theme.highlight_check, .bg = Theme.bg });
        y += 1;
    } else if (game.game_phase == .ended) {
        if (game.result) |result| {
            _ = writeStr(win, 1, y, result, .{ .fg = Theme.highlight_check, .bg = Theme.bg });
        }
        y += 1;
    } else if (game.engine_state == .thinking) {
        const spinners = [_][]const u8{ "|", "/", "-", "\\" };
        var col = writeStr(win, 1, y, spinners[game.spinner_idx], .{ .fg = Theme.highlight_cursor, .bg = Theme.bg });
        col = writeStr(win, col, y, " Engine thinking... (", .{ .fg = Theme.text_primary, .bg = Theme.bg });
        col = writeNum(win, col, y, game.thinking_elapsed_s, .{ .fg = Theme.text_primary, .bg = Theme.bg });
        _ = writeStr(win, col, y, "s)", .{ .fg = Theme.text_primary, .bg = Theme.bg });
        y += 1;
    } else if (game.engine_state == .@"error" or game.engine_state == .reconnecting) {
        _ = writeStr(win, 1, y, "Engine reconnecting...", .{ .fg = Theme.highlight_check, .bg = Theme.bg });
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

    // Opening line
    if (game.current_opening) |opening| {
        var col: u16 = 1;
        const style: Cell.Style = if (game.opening_is_current)
            .{ .fg = Theme.text_primary, .bg = Theme.bg }
        else
            .{ .fg = Theme.text_dim, .bg = Theme.bg };
        col = writeStr(win, col, y, opening.eco, style);
        col = writeStr(win, col, y, " ", style);
        _ = writeStr(win, col, y, opening.name, style);
        y += 1;
        y += 1;
    }

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
        var hint_col = writeStr(win, 1, hint_y + 1, "R Resign N Menu F Flip Q Quit", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        hint_col = writeStr(win, hint_col + 1, hint_y + 1, "H Hints", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        const hint_status: []const u8 = if (game.hints_enabled) " On" else " Off";
        _ = writeStr(win, hint_col, hint_y + 1, hint_status, .{ .fg = Theme.text_dim, .bg = Theme.bg });
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

const testing = @import("std").testing;

test "squareHighlight: cursor takes priority over endangered hint" {
    var game = Game.init();
    game.hints_enabled = true;
    const sq = game.cursor.toIndex();
    game.hint_endangered[sq] = true;

    const color = squareHighlight(&game, sq);
    try testing.expect(color != null);
    try testing.expectEqual(Theme.highlight_cursor, color.?);
}

test "squareHighlight: check takes priority over endangered hint" {
    var game = Game.init();
    // Set up a check position: white king on e1, black rook on e8
    game.board = chess.Board.empty();
    const wk_sq = chess.Square.init(.e, .@"1");
    const bk_sq = chess.Square.init(.h, .@"8");
    const br_sq = chess.Square.init(.e, .@"8");
    game.board.squares[wk_sq.toIndex()] = chess.Piece.init(.white, .king);
    game.board.squares[bk_sq.toIndex()] = chess.Piece.init(.black, .king);
    game.board.squares[br_sq.toIndex()] = chess.Piece.init(.black, .rook);
    game.board.active_color = .white;

    game.hints_enabled = true;
    game.hint_endangered[wk_sq.toIndex()] = true;
    // Move cursor away so it doesn't interfere
    game.cursor = chess.Square.init(.a, .@"1");

    const color = squareHighlight(&game, wk_sq.toIndex());
    try testing.expect(color != null);
    try testing.expectEqual(Theme.highlight_check, color.?);
}

test "squareHighlight: endangered hint shown when no higher priority" {
    var game = Game.init();
    game.hints_enabled = true;
    // Pick a square that's not the cursor
    const sq = chess.Square.init(.a, .@"8");
    game.hint_endangered[sq.toIndex()] = true;
    // Cursor is at e2 by default, not a8

    const color = squareHighlight(&game, sq.toIndex());
    try testing.expect(color != null);
    try testing.expectEqual(Theme.highlight_endangered, color.?);
}

test "squareHighlight: best move hint shown when enabled" {
    var game = Game.init();
    game.hints_enabled = true;
    const from_sq = chess.Square.init(.a, .@"8");
    const to_sq = chess.Square.init(.a, .@"7");
    game.hint_best_move = .{ .from = from_sq, .to = to_sq };

    const color_from = squareHighlight(&game, from_sq.toIndex());
    try testing.expect(color_from != null);
    try testing.expectEqual(Theme.highlight_hint_best, color_from.?);

    const color_to = squareHighlight(&game, to_sq.toIndex());
    try testing.expect(color_to != null);
    try testing.expectEqual(Theme.highlight_hint_best, color_to.?);
}

test "squareHighlight: hints not shown when disabled" {
    var game = Game.init();
    game.hints_enabled = false;
    const sq = chess.Square.init(.a, .@"8");
    game.hint_endangered[sq.toIndex()] = true;

    const color = squareHighlight(&game, sq.toIndex());
    try testing.expect(color == null);
}
