const std = @import("std");
const vaxis = @import("vaxis");
const chess = @import("../chess.zig");
const renderer = @import("renderer.zig");
const sprites = @import("sprites.zig");
const pgn = @import("../persistence/pgn.zig");

const Theme = renderer.Theme;
const Window = vaxis.Window;

pub const ViewerAction = enum {
    none,
    back,
};

pub const ViewerState = struct {
    boards: [*]const chess.Board,
    san_list: [*]const pgn.SanNotation,
    position: usize,
    total: usize,

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
        renderViewerBoard(board_win, self.currentBoard(), opts);

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

        var y: u16 = 0;

        _ = renderer.writeStr(win, 1, y, "GAME VIEWER", .{ .fg = Theme.text_primary, .bg = Theme.bg });
        y += 2;

        var pos_col = renderer.writeStr(win, 1, y, "Move ", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        pos_col = renderer.writeNum(win, pos_col, y, @intCast(self.position), .{ .fg = Theme.text_primary, .bg = Theme.bg });
        pos_col = renderer.writeStr(win, pos_col, y, "/", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        _ = renderer.writeNum(win, pos_col, y, @intCast(self.total), .{ .fg = Theme.text_primary, .bg = Theme.bg });
        y += 2;

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
                }

                const black_idx = white_idx + 1;
                if (black_idx < self.total) {
                    col = if (col < 14) 14 else col + 1;
                    const is_current = (black_idx + 1 == self.position);
                    const move_style: vaxis.Cell.Style = if (is_current)
                        .{ .fg = Theme.highlight_cursor, .bg = Theme.bg }
                    else
                        .{ .fg = Theme.text_primary, .bg = Theme.bg };
                    _ = renderer.writeStr(win, col, y, san_list[black_idx].slice(), move_style);
                }

                y += 1;
            }
        }

        const hint_y = win.height -| 2;
        if (hint_y > y) {
            _ = renderer.writeStr(win, 1, hint_y, "\xe2\x86\x90\xe2\x86\x92 Step  Home/End  Esc Back", .{ .fg = Theme.text_dim, .bg = Theme.bg });
        }
    }
};

fn renderViewerBoard(win: Window, board: *const chess.Board, opts: renderer.RenderOptions) void {
    const x_origin: u16 = if (opts.show_labels) opts.label_w else 0;
    const use_sprites = opts.cell_w >= 5 and opts.cell_h >= 4;

    const rank_labels = [_][]const u8{ "8", "7", "6", "5", "4", "3", "2", "1" };
    const file_labels = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h" };

    for (0..8) |dr| {
        const display_row: u3 = @intCast(dr);
        const ry: u16 = @as(u16, display_row) * opts.cell_h;

        if (opts.show_labels) {
            win.writeCell(0, ry + opts.cell_h / 2, .{
                .char = .{ .grapheme = rank_labels[dr], .width = 1 },
                .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
            });
        }

        for (0..8) |dc| {
            const display_col: u3 = @intCast(dc);
            const file: u3 = display_col;
            const rank: u3 = 7 - display_row;
            const sq_idx: u6 = @as(u6, rank) * 8 + @as(u6, file);
            const piece = board.squares[sq_idx];
            const bg = if ((@as(u4, file) + rank) % 2 == 0) Theme.dark_square else Theme.light_square;

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

            if (piece != .empty) {
                if (use_sprites) {
                    if (piece.pieceType()) |pt| {
                        const fg = if (piece.isWhite()) Theme.white_piece else Theme.black_piece;
                        sprites.stamp(win, sprites.forPieceType(pt), cx, ry, opts.cell_w, opts.cell_h, fg, bg);
                    }
                } else {
                    const sym: ?[]const u8 = pieceToUnicode(piece);
                    if (sym) |s| {
                        const px = cx + opts.cell_w / 2;
                        const py = ry + opts.cell_h / 2;
                        const fg = if (piece.isWhite()) Theme.white_piece else Theme.black_piece;
                        win.writeCell(px, py, .{
                            .char = .{ .grapheme = s, .width = 1 },
                            .style = .{ .fg = fg, .bg = bg },
                        });
                    }
                }
            }
        }
    }

    if (opts.show_labels) {
        for (0..8) |dc| {
            const cx: u16 = x_origin + @as(u16, @intCast(dc)) * opts.cell_w + opts.cell_w / 2;
            const fy: u16 = 8 * opts.cell_h;
            win.writeCell(cx, fy, .{
                .char = .{ .grapheme = file_labels[dc], .width = 1 },
                .style = .{ .fg = Theme.text_dim, .bg = Theme.bg },
            });
        }
    }
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
