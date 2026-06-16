const std = @import("std");
const vaxis = @import("vaxis");
const chess = @import("../chess.zig");
const renderer = @import("renderer.zig");
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
