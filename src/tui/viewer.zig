const std = @import("std");
const vaxis = @import("vaxis");
const chess = @import("../chess.zig");
const renderer = @import("renderer.zig");
const pgn = @import("../persistence/pgn.zig");
const analysis_mod = @import("../analysis.zig");

const Theme = &renderer.Theme;
const Window = vaxis.Window;

pub const ViewerAction = enum {
    none,
    back,
};

/// What the viewer panel conveys about analysis availability (U5/U6).
pub const AnalysisDisplay = enum {
    analyzing, // a backfill pass is in flight
    ready, // analysis available — overlays shown
    unavailable, // no engine / pass failed — plain step-through stays usable (R7)
};

pub const ViewerState = struct {
    boards: [*]const chess.Board,
    san_list: [*]const pgn.SanNotation,
    position: usize,
    total: usize,
    /// Loaded or freshly computed analysis for overlays (U6); null until ready.
    analysis: ?*const analysis_mod.GameAnalysis = null,
    /// What the panel shows about analysis availability (U5/U6).
    analysis_state: AnalysisDisplay = .unavailable,
    /// Which color the human played, for player-perspective eval display (R4).
    player_color: chess.Color = .white,
    /// Cursor into the swing-ranked key moments, null until the key is first pressed.
    key_moment_idx: ?usize = null,

    pub fn init(boards: [*]const chess.Board, san_list: [*]const pgn.SanNotation, move_count: usize) ViewerState {
        return .{
            .boards = boards,
            .san_list = san_list,
            .position = move_count,
            .total = move_count,
        };
    }

    pub fn handleInput(self: *ViewerState, key: vaxis.Key) ViewerAction {
        if (key.matches(vaxis.Key.escape, .{}) or key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
            return .back;
        }
        if (key.matches(vaxis.Key.left, .{}) or key.matches(vaxis.Key.up, .{})) {
            self.stepBackward();
        }
        if (key.matches(vaxis.Key.right, .{}) or key.matches(vaxis.Key.down, .{})) {
            self.stepForward();
        }
        if (key.matches(vaxis.Key.home, .{})) {
            self.jumpStart();
        }
        if (key.matches(vaxis.Key.end, .{})) {
            self.jumpEnd();
        }
        if (key.matches('n', .{})) self.nextKeyMoment();
        if (key.matches('p', .{})) self.prevKeyMoment();
        return .none;
    }

    pub fn stepForward(self: *ViewerState) void {
        if (self.position < self.total) self.position += 1;
    }

    pub fn stepBackward(self: *ViewerState) void {
        if (self.position > 0) self.position -= 1;
    }

    pub fn jumpStart(self: *ViewerState) void {
        self.position = 0;
    }

    pub fn jumpEnd(self: *ViewerState) void {
        self.position = self.total;
    }

    /// Advance to the next biggest-swing key moment (R6/AE5); inert without analysis (R7).
    pub fn nextKeyMoment(self: *ViewerState) void {
        const ga = self.analysis orelse return;
        if (ga.key_moment_count == 0) return;
        const next: usize = if (self.key_moment_idx) |k|
            @min(k + 1, @as(usize, ga.key_moment_count) - 1)
        else
            0;
        self.key_moment_idx = next;
        self.jumpToKeyMoment(ga, next);
    }

    /// Step back to the previous key moment; clamps at the first.
    pub fn prevKeyMoment(self: *ViewerState) void {
        const ga = self.analysis orelse return;
        if (ga.key_moment_count == 0) return;
        const cur = self.key_moment_idx orelse {
            self.key_moment_idx = 0;
            self.jumpToKeyMoment(ga, 0);
            return;
        };
        const prev: usize = if (cur == 0) 0 else cur - 1;
        self.key_moment_idx = prev;
        self.jumpToKeyMoment(ga, prev);
    }

    fn jumpToKeyMoment(self: *ViewerState, ga: *const analysis_mod.GameAnalysis, idx: usize) void {
        const ply = ga.key_moments[idx];
        const target: usize = @as(usize, ply) + 1; // board after the swing move
        self.position = if (target <= self.total) target else self.total;
    }

    /// Jump to the worst player move — the first swing-ranked key moment that is a
    /// player mistake/blunder — for the summary card's jump-into-review (R8). No-op
    /// without analysis or player mistakes.
    pub fn jumpToWorstMove(self: *ViewerState) void {
        const ga = self.analysis orelse return;
        var i: usize = 0;
        while (i < ga.key_moment_count) : (i += 1) {
            const ply = ga.key_moments[i];
            if (ply >= ga.count) continue;
            const t = ga.moves[ply].tier orelse continue;
            if (t == .bad) {
                self.key_moment_idx = i;
                self.jumpToKeyMoment(ga, i);
                return;
            }
        }
    }

    pub fn currentBoard(self: *const ViewerState) *const chess.Board {
        return &self.boards[self.position];
    }

    pub fn render(self: *const ViewerState, win: Window) void {
        win.clear();
        win.fill(.{ .style = .{ .bg = Theme.bg } });

        const opts = renderer.RenderOptions{};
        const board_w = renderer.boardWidth(opts);
        const board_h = renderer.boardHeight(opts);

        if (win.width < board_w or win.height < board_h) {
            renderer.renderResizeMessage(win);
            return;
        }

        const board_win = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = board_w,
            .height = board_h,
        });
        renderer.renderBoardCore(board_win, self.currentBoard(), opts, false, null);

        const info_x: u16 = board_w + 1;
        const info_w = if (win.width > info_x) win.width - info_x else 0;
        const info_win = win.child(.{
            .x_off = @intCast(info_x),
            .y_off = 0,
            .width = info_w,
            .height = board_h,
        });
        self.renderInfoPanel(info_win);
    }

    fn renderInfoPanel(self: *const ViewerState, win: Window) void {
        win.fill(.{ .style = .{ .bg = Theme.bg } });
        if (win.width < 8 or win.height < 8) return;

        const ana: ?*const analysis_mod.GameAnalysis =
            if (self.analysis_state == .ready) self.analysis else null;

        var y: u16 = 0;

        _ = renderer.writeStr(win, 1, y, "GAME VIEWER", .{ .fg = Theme.text_primary, .bg = Theme.bg });
        y += 2;

        var pos_col = renderer.writeStr(win, 1, y, "Move ", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        pos_col = renderer.writeNum(win, pos_col, y, @intCast(self.position), .{ .fg = Theme.text_primary, .bg = Theme.bg });
        pos_col = renderer.writeStr(win, pos_col, y, "/", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        _ = renderer.writeNum(win, pos_col, y, @intCast(self.total), .{ .fg = Theme.text_primary, .bg = Theme.bg });
        y += 2;

        // Analysis overlays / status (U6). All three no-overlay states keep stepping usable (R7).
        switch (self.analysis_state) {
            .ready => if (ana) |ga| {
                y = self.renderAnalysisLines(win, y, ga);
            },
            .analyzing => {
                _ = renderer.writeStr(win, 1, y, "analyzing\xe2\x80\xa6", .{ .fg = Theme.text_dim, .bg = Theme.bg });
                y += 2;
            },
            .unavailable => {
                _ = renderer.writeStr(win, 1, y, "(no analysis)", .{ .fg = Theme.text_dim, .bg = Theme.bg });
                y += 2;
            },
        }

        const keybind_lines: u16 = 3;
        const avail_h = if (win.height > y + keybind_lines) win.height - y - keybind_lines else 0;

        if (avail_h > 0 and self.total > 0) {
            const san_list = self.san_list[0..self.total];
            const total_pairs: usize = (self.total + 1) / 2;
            const display_pairs: u16 = @intCast(@min(avail_h, total_pairs));

            const current_pair: usize = if (self.position > 0) (self.position - 1) / 2 else 0;
            var start_pair: usize = 0;
            if (current_pair >= display_pairs) {
                start_pair = current_pair + 1 - display_pairs;
            }
            if (start_pair + display_pairs > total_pairs) {
                start_pair = total_pairs -| display_pairs;
            }

            for (0..display_pairs) |i| {
                const pair_idx = start_pair + i;
                const white_idx = pair_idx * 2;
                const move_num: u16 = @intCast(pair_idx + 1);

                var col: u16 = 1;
                col = renderer.writeNum(win, col, y, move_num, .{ .fg = Theme.text_dim, .bg = Theme.bg });
                col = renderer.writeStr(win, col, y, ".", .{ .fg = Theme.text_dim, .bg = Theme.bg });

                if (white_idx < self.total) {
                    col += 1;
                    const is_current = (white_idx + 1 == self.position);
                    const move_style: vaxis.Cell.Style = if (is_current)
                        .{ .fg = Theme.highlight_cursor, .bg = Theme.bg }
                    else
                        .{ .fg = Theme.text_primary, .bg = Theme.bg };
                    col = renderer.writeStr(win, col, y, san_list[white_idx].slice(), move_style);
                    col = drawTierGlyph(win, col, y, ana, white_idx);
                }

                const black_idx = white_idx + 1;
                if (black_idx < self.total) {
                    col = if (col < 14) 14 else col + 1;
                    const is_current = (black_idx + 1 == self.position);
                    const move_style: vaxis.Cell.Style = if (is_current)
                        .{ .fg = Theme.highlight_cursor, .bg = Theme.bg }
                    else
                        .{ .fg = Theme.text_primary, .bg = Theme.bg };
                    col = renderer.writeStr(win, col, y, san_list[black_idx].slice(), move_style);
                    _ = drawTierGlyph(win, col, y, ana, black_idx);
                }

                y += 1;
            }
        }

        const hint_y = win.height -| 2;
        if (hint_y > y) {
            const hint = if (ana != null)
                "\xe2\x86\x90\xe2\x86\x92 Step  n/p Key  Esc Back"
            else
                "\xe2\x86\x90\xe2\x86\x92 Step  Home/End  Esc Back";
            _ = renderer.writeStr(win, 1, hint_y, hint, .{ .fg = Theme.text_dim, .bg = Theme.bg });
        }
    }

    /// Analysis panel lines for the current position: best move + eval (R4), the tier
    /// of the move that led here (R5), and the key-moment cursor (R6). Returns new y.
    fn renderAnalysisLines(self: *const ViewerState, win: Window, y0: u16, ga: *const analysis_mod.GameAnalysis) u16 {
        var y = y0;
        const pos = self.position;

        if (pos < ga.count) {
            const ma = ga.moves[pos];
            if (ma.best) |bm| {
                const flip = self.currentBoard().active_color != self.player_color;
                var ebuf: [16]u8 = undefined;
                const ev = formatPovEval(&ebuf, ma.best_eval, flip);
                const san = pgn.sanForMove(self.currentBoard(), bm);
                var col = renderer.writeStr(win, 1, y, "Best ", .{ .fg = Theme.text_dim, .bg = Theme.bg });
                col = renderer.writeStr(win, col, y, san.slice(), .{ .fg = Theme.text_primary, .bg = Theme.bg });
                col += 1;
                _ = renderer.writeStr(win, col, y, ev, .{ .fg = Theme.text_primary, .bg = Theme.bg });
                y += 1;
            }
        }

        if (pos > 0 and pos - 1 < ga.count) {
            const ma = ga.moves[pos - 1];
            if (ma.tier) |t| {
                var col = renderer.writeStr(win, 1, y, "Move ", .{ .fg = Theme.text_dim, .bg = Theme.bg });
                col = renderer.writeStr(win, col, y, renderer.tierGlyph(t), .{ .fg = renderer.tierColor(t), .bg = Theme.bg });
                col += 1;
                _ = renderer.writeStr(win, col, y, moveLabel(ma.cpl), .{ .fg = renderer.tierColor(t), .bg = Theme.bg });
                y += 1;
            }
        }

        if (self.key_moment_idx) |ki| {
            var col = renderer.writeStr(win, 1, y, "Key ", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            col = renderer.writeNum(win, col, y, @intCast(ki + 1), .{ .fg = Theme.text_primary, .bg = Theme.bg });
            col = renderer.writeStr(win, col, y, "/", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            _ = renderer.writeNum(win, col, y, @intCast(ga.key_moment_count), .{ .fg = Theme.text_primary, .bg = Theme.bg });
            y += 1;
        }

        return y + 1;
    }
};

/// Draw a 1-char tier glyph after a move's SAN (player plies only), if the panel has
/// room. Returns the column after the glyph (or `col` unchanged when skipped).
fn drawTierGlyph(win: Window, col: u16, y: u16, ana: ?*const analysis_mod.GameAnalysis, ply: usize) u16 {
    const ga = ana orelse return col;
    if (ply >= ga.count) return col;
    const t = ga.moves[ply].tier orelse return col;
    const gx = col + 1;
    if (gx >= win.width) return col; // no room in a narrow panel
    return renderer.writeStr(win, gx, y, renderer.tierGlyph(t), .{ .fg = renderer.tierColor(t), .bg = Theme.bg });
}

/// Format an eval in pawns for display, flipped to the player's perspective when the
/// position's side-to-move is the opponent (+ = player better). Mate shows as `#N`.
fn formatPovEval(buf: []u8, e: analysis_mod.Eval, flip: bool) []const u8 {
    switch (e) {
        .mate => |n| return std.fmt.bufPrint(buf, "#{d}", .{if (flip) -n else n}) catch "#",
        .cp => |c| {
            const v: i32 = if (flip) -c else c;
            const pawns = @as(f32, @floatFromInt(v)) / 100.0;
            const sign: []const u8 = if (pawns >= 0) "+" else ""; // negatives already carry '-'
            return std.fmt.bufPrint(buf, "{s}{d:.1}", .{ sign, pawns }) catch "";
        },
    }
}

/// lichess-vocabulary label for a player move by its centipawn loss.
fn moveLabel(cpl: i32) []const u8 {
    if (cpl >= 300) return "blunder";
    if (cpl >= 100) return "mistake";
    if (cpl >= 50) return "inaccuracy";
    return "good";
}

test "nextKeyMoment cycles the ranked moments and clamps at the end" {
    var boards: [5]chess.Board = undefined;
    boards[0] = chess.Board.initial;
    var sans: [4]pgn.SanNotation = undefined;
    var ga = analysis_mod.GameAnalysis{};
    ga.count = 4;
    ga.key_moment_count = 3;
    ga.key_moments[0] = 2;
    ga.key_moments[1] = 0;
    ga.key_moments[2] = 3;

    var v = ViewerState.init(&boards, &sans, 4);
    v.analysis = &ga;
    v.analysis_state = .ready;

    try std.testing.expectEqual(@as(?usize, null), v.key_moment_idx);
    v.nextKeyMoment(); // -> idx 0, ply 2 → position 3
    try std.testing.expectEqual(@as(?usize, 0), v.key_moment_idx);
    try std.testing.expectEqual(@as(usize, 3), v.position);
    v.nextKeyMoment(); // -> idx 1, ply 0 → position 1
    try std.testing.expectEqual(@as(usize, 1), v.position);
    v.nextKeyMoment(); // -> idx 2, ply 3 → position 4 (== total)
    try std.testing.expectEqual(@as(usize, 4), v.position);
    v.nextKeyMoment(); // clamp at idx 2
    try std.testing.expectEqual(@as(?usize, 2), v.key_moment_idx);
    v.prevKeyMoment();
    v.prevKeyMoment();
    try std.testing.expectEqual(@as(?usize, 0), v.key_moment_idx);
}

test "key-moment nav is inert without analysis (R7)" {
    var boards: [3]chess.Board = undefined;
    boards[0] = chess.Board.initial;
    var sans: [2]pgn.SanNotation = undefined;
    var v = ViewerState.init(&boards, &sans, 2);
    v.position = 1;
    v.nextKeyMoment();
    try std.testing.expectEqual(@as(usize, 1), v.position);
    try std.testing.expectEqual(@as(?usize, null), v.key_moment_idx);
}

test "moveLabel maps centipawn loss to lichess vocabulary" {
    try std.testing.expectEqualStrings("good", moveLabel(0));
    try std.testing.expectEqualStrings("good", moveLabel(49));
    try std.testing.expectEqualStrings("inaccuracy", moveLabel(50));
    try std.testing.expectEqualStrings("mistake", moveLabel(100));
    try std.testing.expectEqualStrings("blunder", moveLabel(300));
}

test "jumpToWorstMove lands on the first player mistake by swing rank" {
    var boards: [5]chess.Board = undefined;
    boards[0] = chess.Board.initial;
    var sans: [4]pgn.SanNotation = undefined;
    var ga = analysis_mod.GameAnalysis{};
    ga.count = 4;
    ga.key_moment_count = 3;
    ga.key_moments[0] = 2;
    ga.moves[2].tier = null; // engine ply (biggest swing) — skipped
    ga.key_moments[1] = 0;
    ga.moves[0].tier = .good; // not a mistake — skipped
    ga.key_moments[2] = 3;
    ga.moves[3].tier = .bad; // the worst player move
    var v = ViewerState.init(&boards, &sans, 4);
    v.analysis = &ga;
    v.analysis_state = .ready;
    v.jumpToWorstMove();
    try std.testing.expectEqual(@as(?usize, 2), v.key_moment_idx);
    try std.testing.expectEqual(@as(usize, 4), v.position); // ply 3 + 1
}

test "formatPovEval: player-perspective sign and mate notation" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("+1.2", formatPovEval(&buf, .{ .cp = 120 }, false));
    try std.testing.expectEqualStrings("-0.5", formatPovEval(&buf, .{ .cp = 50 }, true)); // flip: 50 -> -50
    try std.testing.expectEqualStrings("+0.0", formatPovEval(&buf, .{ .cp = 0 }, false));
    try std.testing.expectEqualStrings("#3", formatPovEval(&buf, .{ .mate = 3 }, false));
    try std.testing.expectEqualStrings("#-2", formatPovEval(&buf, .{ .mate = 2 }, true)); // flip mate
}
