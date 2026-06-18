const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Color = Cell.Color;
const Window = vaxis.Window;
const chess = @import("../chess.zig");
const game_mod = @import("game.zig");
const Game = game_mod.Game;
const sprites = @import("sprites.zig");

pub const Palette = struct {
    bg: Color,
    dark_square: Color,
    light_square: Color,
    white_piece: Color,
    black_piece: Color,
    text_primary: Color,
    text_dim: Color,
    highlight_cursor: Color,
    highlight_selected: Color,
    highlight_legal: Color,
    highlight_check: Color,
    highlight_flash: Color,
    highlight_promotion: Color,
    highlight_engine_move: Color,
    highlight_endangered: Color,
    highlight_hint_best: Color,
    selection_bg: Color,
};

pub const ThemeId = enum {
    classic,
    wood,
    green,
    blue,

    pub fn label(self: ThemeId) []const u8 {
        return switch (self) {
            .classic => "Classic",
            .wood => "Wood",
            .green => "Green",
            .blue => "Blue",
        };
    }

    pub fn fromString(s: []const u8) ThemeId {
        if (std.mem.eql(u8, s, "wood")) return .wood;
        if (std.mem.eql(u8, s, "green")) return .green;
        if (std.mem.eql(u8, s, "blue")) return .blue;
        return .classic;
    }

    pub fn toString(self: ThemeId) []const u8 {
        return switch (self) {
            .classic => "classic",
            .wood => "wood",
            .green => "green",
            .blue => "blue",
        };
    }
};

fn rgb(v: [3]u8) Color {
    return .{ .rgb = v };
}

// The five mark colors (cursor, legal, check, endangered, hint-best) are shared
// across themes: saturated and distinct from every (muted) square palette, so R10
// holds for every preset. Only the board/chrome colors vary per theme.
fn paletteOf(bg: [3]u8, dark: [3]u8, light: [3]u8, wp: [3]u8, bp: [3]u8, tp: [3]u8, td: [3]u8, sel: [3]u8) Palette {
    return .{
        .bg = rgb(bg),
        .dark_square = rgb(dark),
        .light_square = rgb(light),
        .white_piece = rgb(wp),
        .black_piece = rgb(bp),
        .text_primary = rgb(tp),
        .text_dim = rgb(td),
        .highlight_cursor = rgb(.{ 255, 0, 255 }),
        .highlight_selected = rgb(.{ 180, 0, 255 }),
        .highlight_legal = rgb(.{ 0, 200, 255 }),
        .highlight_check = rgb(.{ 255, 50, 50 }),
        .highlight_flash = rgb(.{ 255, 0, 0 }),
        .highlight_promotion = rgb(.{ 255, 200, 0 }),
        .highlight_engine_move = rgb(.{ 0, 220, 180 }),
        .highlight_endangered = rgb(.{ 255, 100, 50 }),
        .highlight_hint_best = rgb(.{ 50, 200, 100 }),
        .selection_bg = rgb(sel),
    };
}

pub fn palette(id: ThemeId) Palette {
    return switch (id) {
        // Classic reproduces the original look exactly (R12).
        .classic => paletteOf(.{ 15, 15, 35 }, .{ 55, 40, 100 }, .{ 105, 70, 150 }, .{ 200, 200, 220 }, .{ 20, 20, 40 }, .{ 192, 202, 245 }, .{ 100, 110, 150 }, .{ 40, 30, 70 }),
        .wood => paletteOf(.{ 30, 22, 15 }, .{ 120, 80, 45 }, .{ 200, 165, 120 }, .{ 245, 235, 215 }, .{ 40, 25, 15 }, .{ 235, 220, 195 }, .{ 150, 125, 100 }, .{ 70, 50, 30 }),
        .green => paletteOf(.{ 12, 25, 15 }, .{ 40, 80, 50 }, .{ 120, 170, 120 }, .{ 230, 240, 225 }, .{ 18, 30, 20 }, .{ 200, 230, 200 }, .{ 110, 140, 110 }, .{ 30, 55, 35 }),
        .blue => paletteOf(.{ 10, 18, 35 }, .{ 35, 60, 110 }, .{ 95, 130, 190 }, .{ 220, 230, 245 }, .{ 15, 22, 40 }, .{ 200, 215, 245 }, .{ 100, 120, 160 }, .{ 30, 45, 80 }),
    };
}

pub var Theme: Palette = palette(.classic);

// drawMarks is hand-fitted to exactly this cell geometry; the RenderOptions
// defaults and the drawMarks guard both reference it so they cannot drift apart.
const min_cell_w: u16 = 12;
const min_cell_h: u16 = 6;

pub const RenderOptions = struct {
    cell_w: u16 = min_cell_w,
    cell_h: u16 = min_cell_h,
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

pub const BorderStyle = enum { selected, capture, check, flash, engine };

pub const Marks = struct {
    border: ?BorderStyle = null,
    cursor: bool = false,
    endangered: bool = false,
    best_move: bool = false,
    center: bool = false,
};

/// Border family is single-winner: the inner-column bars can only show one
/// style, resolved by precedence check > flash > selected > capture > engine.
fn resolveBorder(check: bool, flash: bool, selected: bool, capture: bool, engine: bool) ?BorderStyle {
    if (check) return .check;
    if (flash) return .flash;
    if (selected) return .selected;
    if (capture) return .capture;
    if (engine) return .engine;
    return null;
}

/// Pure mapping from game state to the marks for one square. Corner and center
/// marks compose freely; only the border family is single-winner.
pub fn squareMarks(game: *const Game, sq_idx: u6) Marks {
    const flash = if (game.flash_square) |fs|
        fs.toIndex() == sq_idx and game.flash_timer > 0
    else
        false;

    const engine = if (game.engine_last_move) |em|
        em.from.toIndex() == sq_idx or em.to.toIndex() == sq_idx
    else
        false;

    const selected = if (game.selected) |sel| sel.toIndex() == sq_idx else false;

    const check = game.isKingInCheck() and
        (if (game.activeKingSquare()) |ks| ks.toIndex() == sq_idx else false);

    const is_target = game.legal_targets[sq_idx];
    const occupied = game.board.squares[sq_idx] != .empty;

    var marks: Marks = .{};
    marks.border = resolveBorder(check, flash, selected, is_target and occupied, engine);
    marks.center = is_target and !occupied;
    marks.cursor = game.cursor.toIndex() == sq_idx;

    if (game.hints_enabled) {
        marks.endangered = game.hint_endangered[sq_idx];
        if (game.hint_best_move) |bm|
            marks.best_move = bm.from.toIndex() == sq_idx or bm.to.toIndex() == sq_idx;
    }

    return marks;
}

fn borderColor(style: BorderStyle) Color {
    return switch (style) {
        .selected => Theme.highlight_selected,
        .capture => Theme.highlight_legal,
        .check => Theme.highlight_check,
        .flash => Theme.highlight_flash,
        .engine => Theme.highlight_engine_move,
    };
}

fn putCell(win: Window, x: u16, y: u16, glyph: []const u8, fg: Color, bg: Color) void {
    win.writeCell(x, y, .{ .char = .{ .grapheme = glyph, .width = 1 }, .style = .{ .fg = fg, .bg = bg } });
}

/// Fill the inclusive horizontal run x0..x1 on row y with one glyph.
fn hRun(win: Window, x0: u16, x1: u16, y: u16, glyph: []const u8, fg: Color, bg: Color) void {
    var x = x0;
    while (x <= x1) : (x += 1) putCell(win, x, y, glyph, fg, bg);
}

/// Fill the inclusive vertical run y0..y1 on column x with one glyph.
fn vRun(win: Window, x: u16, y0: u16, y1: u16, glyph: []const u8, fg: Color, bg: Color) void {
    var y = y0;
    while (y <= y1) : (y += 1) putCell(win, x, y, glyph, fg, bg);
}

// Thick block glyphs: top edges use the upper half (top-aligned), bottom edges
// the lower half (bottom-aligned), sides and fills the full block.
const UPPER = "▀";
const LOWER = "▄";
const FULL = "█";

const OutlineLevel = struct {
    tl: []const u8,
    tr: []const u8,
    bl: []const u8,
    br: []const u8,
    top: []const u8,
    bottom: []const u8,
    left: []const u8,
    right: []const u8,
    inner_left: ?[]const u8 = null,
    inner_right: ?[]const u8 = null,
};

// Outline weight encodes border importance (see borderLevel). Thin = quarter
// edges (🮂/▂) + 3-quadrant corners (▛▜▙▟) that cleanly join the half-block
// sides; thick = half edges + full sides; solid = a 2-cell-thick full frame.
const level_thin = OutlineLevel{ .tl = "▛", .tr = "▜", .bl = "▙", .br = "▟", .top = "🮂", .bottom = "▂", .left = "▌", .right = "▐" };
const level_thick = OutlineLevel{ .tl = "█", .tr = "█", .bl = "█", .br = "█", .top = "▀", .bottom = "▄", .left = "█", .right = "█" };
const level_solid = OutlineLevel{ .tl = "█", .tr = "█", .bl = "█", .br = "█", .top = "█", .bottom = "█", .left = "█", .right = "█", .inner_left = "█", .inner_right = "█" };

fn borderLevel(style: BorderStyle) OutlineLevel {
    return switch (style) {
        .check, .flash => level_solid,
        .selected => level_thick,
        .capture, .engine => level_thin,
    };
}

fn drawOutline(win: Window, cx: u16, ry: u16, opts: RenderOptions, lv: OutlineLevel, c: Color, base: Color) void {
    const left = cx;
    const right = cx + opts.cell_w - 1;
    const top = ry;
    const bottom = ry + opts.cell_h - 1;
    putCell(win, left, top, lv.tl, c, base);
    putCell(win, right, top, lv.tr, c, base);
    putCell(win, left, bottom, lv.bl, c, base);
    putCell(win, right, bottom, lv.br, c, base);
    hRun(win, left + 1, right - 1, top, lv.top, c, base);
    hRun(win, left + 1, right - 1, bottom, lv.bottom, c, base);
    var y = top + 1;
    while (y < bottom) : (y += 1) {
        putCell(win, left, y, lv.left, c, base);
        putCell(win, right, y, lv.right, c, base);
        if (lv.inner_left) |g| putCell(win, left + 1, y, g, c, base);
        if (lv.inner_right) |g| putCell(win, right - 1, y, g, c, base);
    }
}

/// Overlay marks onto an already-drawn base + sprite. Pure: the same routine
/// drives the live board and the gallery, so what a developer judges is what
/// ships. Layers compose top-to-bottom; only the border outline is single-winner.
/// Geometry assumes the 12x6 cell — even dims have no single middle cell, so
/// centered marks span the two straddling rows/cols.
pub fn drawMarks(win: Window, cx: u16, ry: u16, opts: RenderOptions, marks: Marks, base: Color) void {
    // Hand-fitted to the min_cell_w x min_cell_h (12x6) cell — a 6x4
    // sprite centered with a 3-col horizontal / 1-row vertical margin. The only
    // live caller renders at exactly that size; smaller windows show the resize
    // message, so below it we draw nothing.
    if (opts.cell_w < min_cell_w or opts.cell_h < min_cell_h) return;

    const left = cx;
    const right = cx + opts.cell_w - 1;
    const top = ry;
    const bottom = ry + opts.cell_h - 1;
    const col_a = cx + opts.cell_w / 2 - 1; // left of the two center columns
    const col_b = cx + opts.cell_w / 2; // right of the two center columns
    const row_a = ry + opts.cell_h / 2 - 1; // upper of the two center rows
    const row_b = ry + opts.cell_h / 2; // lower of the two center rows

    // Layer 1: border outline (single winner). Weight encodes importance
    // (borderLevel), hue encodes state (borderColor).
    if (marks.border) |style|
        drawOutline(win, cx, ry, opts, borderLevel(style), borderColor(style), base);

    // Layer 2: legal empty-target dot — four quadrant blocks meeting at the
    // exact cell center form a centered square (empty squares only).
    if (marks.center) {
        const c = Theme.highlight_legal;
        putCell(win, col_a, row_a, LOWER, c, base);
        putCell(win, col_b, row_a, LOWER, c, base);
        putCell(win, col_a, row_b, UPPER, c, base);
        putCell(win, col_b, row_b, UPPER, c, base);
    }

    // Layer 3: hint corners — thick, edge-aligned (compose).
    if (marks.best_move)
        hRun(win, right - 1, right, top, FULL, Theme.highlight_hint_best, base); // ▀ top-right
    if (marks.endangered)
        hRun(win, left, left + 1, bottom, FULL, Theme.highlight_endangered, base); // ▄ bottom-left

    // Layer 4: cursor — thick bright segments at the middle of each edge (top
    // layer, most visible).
    if (marks.cursor) {
        const c = Theme.highlight_cursor;
        hRun(win, left + 3, right - 3, top, UPPER, c, base); // ▀ top-mid
        hRun(win, left + 3, right - 3, bottom, LOWER, c, base); // ▄ bottom-mid
        vRun(win, left, row_a, row_b, FULL, c, base); // █ left-mid
        vRun(win, right, row_a, row_b, FULL, c, base); // █ right-mid
    }
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

            const cx: u16 = x_origin + @as(u16, display_col) * opts.cell_w;

            for (0..opts.cell_h) |row_off| {
                const ry_off: u16 = ry + @as(u16, @intCast(row_off));
                for (0..opts.cell_w) |col_off| {
                    const cx_off: u16 = cx + @as(u16, @intCast(col_off));
                    win.writeCell(cx_off, ry_off, .{
                        .char = .{ .grapheme = " ", .width = 1 },
                        .style = .{ .bg = base },
                    });
                }
            }

            if (opts.show_pieces and piece != .empty) {
                if (use_sprites) {
                    if (piece.pieceType()) |pt| {
                        const fg = pieceColor(piece);
                        sprites.stamp(win, sprites.forPieceType(pt), cx, ry, opts.cell_w, opts.cell_h, fg, base);
                    }
                } else {
                    if (piece.pieceType()) |pt| {
                        const sym = game_mod.pieceSymbol(pt, piece.color() orelse continue);
                        const px = cx + opts.cell_w / 2;
                        const py = ry + opts.cell_h / 2;
                        win.writeCell(px, py, .{
                            .char = .{ .grapheme = sym, .width = 1 },
                            .style = .{ .fg = pieceColor(piece), .bg = base },
                        });
                    }
                }
            }

            if (highlight) |g| {
                drawMarks(win, cx, ry, opts, squareMarks(g, sq_idx), base);
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
    } else if (game.quit_pending) {
        _ = writeStr(win, 1, y, "Quit game? Y/Enter = Yes, N/Esc = No", .{ .fg = Theme.highlight_check, .bg = Theme.bg });
        y += 1;
    } else if (game.leave_pending) {
        _ = writeStr(win, 1, y, "Leave to menu? Y/Enter = Yes, N/Esc = No", .{ .fg = Theme.highlight_check, .bg = Theme.bg });
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
        _ = writeStr(win, 1, hint_y, "\u{2191}\u{2193}\u{2190}\u{2192} Move  Enter Select  U Undo", .{ .fg = Theme.text_dim, .bg = Theme.bg });
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

test "squareMarks: empty legal target -> center, no border (AE1)" {
    var game = Game.init();
    game.board = chess.Board.empty();
    const sq = chess.Square.init(.d, .@"4");
    game.legal_targets[sq.toIndex()] = true;

    const m = squareMarks(&game, sq.toIndex());
    try testing.expect(m.center);
    try testing.expect(m.border == null);
}

test "squareMarks: occupied legal target -> capture border (AE1)" {
    var game = Game.init();
    game.board = chess.Board.empty();
    const sq = chess.Square.init(.d, .@"4");
    game.board.squares[sq.toIndex()] = chess.Piece.init(.black, .knight);
    game.legal_targets[sq.toIndex()] = true;

    const m = squareMarks(&game, sq.toIndex());
    try testing.expectEqual(BorderStyle.capture, m.border.?);
    try testing.expect(!m.center);
}

test "squareMarks: capture composes with endangered and best-move corners (AE2)" {
    var game = Game.init();
    game.board = chess.Board.empty();
    const sq = chess.Square.init(.d, .@"4");
    game.board.squares[sq.toIndex()] = chess.Piece.init(.black, .knight);
    game.legal_targets[sq.toIndex()] = true;
    game.hints_enabled = true;
    game.hint_endangered[sq.toIndex()] = true;
    game.hint_best_move = .{ .from = chess.Square.init(.a, .@"1"), .to = sq };

    const m = squareMarks(&game, sq.toIndex());
    try testing.expectEqual(BorderStyle.capture, m.border.?);
    try testing.expect(m.endangered);
    try testing.expect(m.best_move);
    // from-arm of the best_move disjunction (bm.from == sq)
    try testing.expect(squareMarks(&game, chess.Square.init(.a, .@"1").toIndex()).best_move);
}

test "squareMarks: check outranks selected on the king square (AE3)" {
    var game = Game.init();
    game.board = chess.Board.empty();
    const wk = chess.Square.init(.e, .@"1");
    const bk = chess.Square.init(.h, .@"8");
    const br = chess.Square.init(.e, .@"8");
    game.board.squares[wk.toIndex()] = chess.Piece.init(.white, .king);
    game.board.squares[bk.toIndex()] = chess.Piece.init(.black, .king);
    game.board.squares[br.toIndex()] = chess.Piece.init(.black, .rook);
    game.board.active_color = .white;
    game.selected = wk;

    const m = squareMarks(&game, wk.toIndex());
    try testing.expectEqual(BorderStyle.check, m.border.?);
}

test "squareMarks: selected vs cursor are distinct families (AE4)" {
    var game = Game.init();
    const sel_sq = chess.Square.init(.a, .@"8");
    game.selected = sel_sq;
    game.cursor = chess.Square.init(.h, .@"1");

    const m_sel = squareMarks(&game, sel_sq.toIndex());
    try testing.expectEqual(BorderStyle.selected, m_sel.border.?);
    try testing.expect(!m_sel.cursor);

    const m_cur = squareMarks(&game, game.cursor.toIndex());
    try testing.expect(m_cur.cursor);
    try testing.expect(m_cur.border == null);
}

test "resolveBorder: full precedence chain check > flash > selected > capture > engine" {
    try testing.expectEqual(BorderStyle.check, resolveBorder(true, true, true, true, true).?);
    try testing.expectEqual(BorderStyle.flash, resolveBorder(false, true, true, true, true).?);
    try testing.expectEqual(BorderStyle.selected, resolveBorder(false, false, true, true, true).?);
    try testing.expectEqual(BorderStyle.capture, resolveBorder(false, false, false, true, true).?);
    try testing.expectEqual(BorderStyle.engine, resolveBorder(false, false, false, false, true).?);
    try testing.expect(resolveBorder(false, false, false, false, false) == null);
    // selected outranks capture even when both flags are set (data model allows it)
    try testing.expectEqual(BorderStyle.selected, resolveBorder(false, false, true, true, false).?);
}

test "squareMarks: selected wins over engine-last-move" {
    var game = Game.init();
    const sq = chess.Square.init(.c, .@"3");
    game.selected = sq;
    game.engine_last_move = .{ .from = chess.Square.init(.a, .@"1"), .to = sq };

    const m = squareMarks(&game, sq.toIndex());
    try testing.expectEqual(BorderStyle.selected, m.border.?);
}

test "squareMarks: engine-last-move alone yields engine border" {
    var game = Game.init();
    const sq = chess.Square.init(.c, .@"3");
    game.engine_last_move = .{ .from = chess.Square.init(.a, .@"3"), .to = sq };

    const m = squareMarks(&game, sq.toIndex());
    try testing.expectEqual(BorderStyle.engine, m.border.?);
    // from-arm of the engine disjunction (em.from == sq)
    try testing.expectEqual(BorderStyle.engine, squareMarks(&game, chess.Square.init(.a, .@"3").toIndex()).border.?);
}

test "squareMarks: flash wins over selected when timer active" {
    var game = Game.init();
    const sq = chess.Square.init(.c, .@"3");
    game.selected = sq;
    game.flash_square = sq;
    game.flash_timer = 1;

    const m = squareMarks(&game, sq.toIndex());
    try testing.expectEqual(BorderStyle.flash, m.border.?);
}

test "squareMarks: flash ignored when timer is zero" {
    var game = Game.init();
    const sq = chess.Square.init(.c, .@"3");
    game.flash_square = sq;
    game.flash_timer = 0;
    game.selected = sq;

    const m = squareMarks(&game, sq.toIndex());
    try testing.expectEqual(BorderStyle.selected, m.border.?);
}

test "squareMarks: hints disabled suppresses endangered and best-move" {
    var game = Game.init();
    game.hints_enabled = false;
    const sq = chess.Square.init(.a, .@"8");
    game.hint_endangered[sq.toIndex()] = true;
    game.hint_best_move = .{ .from = sq, .to = chess.Square.init(.a, .@"7") };

    const m = squareMarks(&game, sq.toIndex());
    try testing.expect(!m.endangered);
    try testing.expect(!m.best_move);
}

test "squareMarks: quiet empty square has no marks" {
    var game = Game.init();
    game.board = chess.Board.empty();
    const sq = chess.Square.init(.d, .@"5");
    game.cursor = chess.Square.init(.h, .@"1");

    const m = squareMarks(&game, sq.toIndex());
    try testing.expect(m.border == null);
    try testing.expect(!m.cursor and !m.endangered and !m.best_move and !m.center);
}

test "drawMarks: writes nothing below the minimum cell size (guard)" {
    var screen = try vaxis.Screen.init(testing.allocator, .{ .rows = 20, .cols = 20, .x_pixel = 0, .y_pixel = 0 });
    defer screen.deinit(testing.allocator);
    const win = Window{ .x_off = 0, .y_off = 0, .parent_x_off = 0, .parent_y_off = 0, .width = 20, .height = 20, .screen = &screen };

    for (0..20) |y| {
        for (0..20) |x| {
            win.writeCell(@intCast(x), @intCast(y), .{ .char = .{ .grapheme = "X", .width = 1 } });
        }
    }

    const marks: Marks = .{ .border = .capture, .cursor = true, .endangered = true, .best_move = true, .center = true };
    drawMarks(win, 2, 2, .{ .cell_w = 11, .cell_h = 6 }, marks, Theme.dark_square);

    for (0..20) |y| {
        for (0..20) |x| {
            try testing.expectEqualStrings("X", screen.readCell(@intCast(x), @intCast(y)).?.char.grapheme);
        }
    }
}

test "drawMarks: marks stay inside the cell rect (containment)" {
    var screen = try vaxis.Screen.init(testing.allocator, .{ .rows = 20, .cols = 20, .x_pixel = 0, .y_pixel = 0 });
    defer screen.deinit(testing.allocator);
    const win = Window{ .x_off = 0, .y_off = 0, .parent_x_off = 0, .parent_y_off = 0, .width = 20, .height = 20, .screen = &screen };

    for (0..20) |y| {
        for (0..20) |x| {
            win.writeCell(@intCast(x), @intCast(y), .{ .char = .{ .grapheme = "X", .width = 1 } });
        }
    }

    const cx: u16 = 2;
    const ry: u16 = 2;
    const marks: Marks = .{ .border = .capture, .cursor = true, .endangered = true, .best_move = true, .center = true };
    drawMarks(win, cx, ry, .{}, marks, Theme.dark_square);

    // It actually drew: the cell's top-left corner is now a (multi-byte) mark glyph, not the sentinel.
    try testing.expect(!std.mem.eql(u8, "X", screen.readCell(cx, ry).?.char.grapheme));

    // No mark bled outside [cx, cx+12) x [ry, ry+6); vaxis clips to the window, not the cell.
    for (0..20) |yy| {
        for (0..20) |xx| {
            const x: u16 = @intCast(xx);
            const y: u16 = @intCast(yy);
            const inside = x >= cx and x < cx + 12 and y >= ry and y < ry + 6;
            if (!inside) {
                try testing.expectEqualStrings("X", screen.readCell(x, y).?.char.grapheme);
            }
        }
    }
}

test "palette: classic reproduces the original RGBs (R12)" {
    const p = palette(.classic);
    try testing.expectEqual(Color{ .rgb = .{ 15, 15, 35 } }, p.bg);
    try testing.expectEqual(Color{ .rgb = .{ 55, 40, 100 } }, p.dark_square);
    try testing.expectEqual(Color{ .rgb = .{ 105, 70, 150 } }, p.light_square);
}

test "palette: marks pairwise-distinct and distinct from squares for every theme (R10)" {
    for ([_]ThemeId{ .classic, .wood, .green, .blue }) |id| {
        const p = palette(id);
        const marks = [_]Color{ p.highlight_cursor, p.highlight_legal, p.highlight_check, p.highlight_endangered, p.highlight_hint_best };
        for (marks, 0..) |a, i| {
            for (marks[i + 1 ..]) |b| {
                try testing.expect(!std.meta.eql(a, b));
            }
            try testing.expect(!std.meta.eql(a, p.dark_square));
            try testing.expect(!std.meta.eql(a, p.light_square));
        }
    }
}

test "ThemeId fromString/toString round-trip; unknown -> classic (AE10)" {
    for ([_]ThemeId{ .classic, .wood, .green, .blue }) |id| {
        try testing.expectEqual(id, ThemeId.fromString(id.toString()));
    }
    try testing.expectEqual(ThemeId.classic, ThemeId.fromString("nonsense"));
}
