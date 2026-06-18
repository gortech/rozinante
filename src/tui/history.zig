const std = @import("std");
const vaxis = @import("vaxis");
const renderer = @import("renderer.zig");
const storage = @import("../persistence/storage.zig");

const Theme = renderer.Theme;
const Window = vaxis.Window;

pub const HistoryAction = enum {
    none,
    back,
    select_finished,
    select_unfinished,
    delete,
};

pub const HistoryScreen = struct {
    games: std.ArrayList(storage.GameInfo),
    cursor: usize,
    scroll: usize,
    delete_pending: bool,

    pub fn init(games: std.ArrayList(storage.GameInfo)) HistoryScreen {
        return .{
            .games = games,
            .cursor = 0,
            .scroll = 0,
            .delete_pending = false,
        };
    }

    pub fn handleInput(self: *HistoryScreen, key: vaxis.Key) HistoryAction {
        const total = self.games.items.len;

        if (self.delete_pending) {
            if (key.matches('y', .{}) or key.matches(vaxis.Key.enter, .{})) {
                self.delete_pending = false;
                return .delete;
            }
            if (key.matches('n', .{}) or key.matches(vaxis.Key.escape, .{})) {
                self.delete_pending = false;
                return .none;
            }
            return .none;
        }

        if (key.matches(vaxis.Key.escape, .{}) or key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
            return .back;
        }
        if (key.matches(vaxis.Key.up, .{})) {
            if (self.cursor > 0) self.cursor -= 1;
        }
        if (key.matches(vaxis.Key.down, .{})) {
            if (total > 0 and self.cursor + 1 < total) self.cursor += 1;
        }
        if (key.matches(vaxis.Key.enter, .{}) and total > 0) {
            const g = self.games.items[self.cursor];
            return if (g.is_finished) .select_finished else .select_unfinished;
        }
        if (key.matches(vaxis.Key.delete, .{}) and total > 0) {
            self.delete_pending = true;
            return .none;
        }
        return .none;
    }

    pub fn selectedGame(self: *const HistoryScreen) ?storage.GameInfo {
        if (self.games.items.len == 0) return null;
        if (self.cursor >= self.games.items.len) return null;
        return self.games.items[self.cursor];
    }

    pub fn removeAtCursor(self: *HistoryScreen) void {
        if (self.games.items.len == 0) return;
        _ = self.games.orderedRemove(self.cursor);
        if (self.cursor > 0 and self.cursor >= self.games.items.len) self.cursor -= 1;
    }

    pub fn render(self: *const HistoryScreen, win: Window) void {
        win.clear();
        win.fill(.{ .style = .{ .bg = Theme.bg } });

        const total = self.games.items.len;
        const content_w: u16 = 60;
        const x0: u16 = if (win.width > content_w) (win.width - content_w) / 2 else 0;
        var y: u16 = 1;

        const title = "Game History";
        const title_x = x0 + (content_w -| 12) / 2;
        _ = renderer.writeStr(win, title_x, y, title, .{ .fg = Theme.highlight_cursor, .bg = Theme.bg });
        y += 2;

        if (total == 0) {
            _ = renderer.writeStr(win, x0 + 2, y, "No saved games", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            y += 2;
        } else {
            var cursor = self.cursor;
            if (cursor >= total) cursor = total -| 1;
            var scroll = self.scroll;

            _ = renderer.writeStr(win, x0 + 1, y, "Date", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            _ = renderer.writeStr(win, x0 + 13, y, "Elo", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            _ = renderer.writeStr(win, x0 + 19, y, "Color", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            _ = renderer.writeStr(win, x0 + 27, y, "Result", .{ .fg = Theme.text_dim, .bg = Theme.bg });
            y += 1;

            const sep = "\xe2\x94\x80" ** 12;
            _ = renderer.writeStr(win, x0 + 1, y, sep, .{ .fg = Theme.text_dim, .bg = Theme.bg });
            y += 1;

            const avail_rows: usize = if (win.height > y + 3) win.height - y - 3 else 1;
            const visible = @min(total, avail_rows);

            if (cursor < scroll) scroll = cursor;
            if (cursor >= scroll + visible) scroll = cursor + 1 - visible;
            if (scroll + visible > total) scroll = total -| visible;

            for (0..visible) |i| {
                const idx = scroll + i;
                const g = self.games.items[idx];
                const is_selected = idx == cursor;
                const row_bg: vaxis.Cell.Color = if (is_selected) .{ .rgb = .{ 40, 30, 70 } } else Theme.bg;
                const fg: vaxis.Cell.Color = if (is_selected) Theme.text_primary else Theme.text_dim;
                const style: vaxis.Cell.Style = .{ .fg = fg, .bg = row_bg };

                if (is_selected) {
                    var cx: u16 = x0;
                    while (cx < x0 + content_w and cx < win.width) : (cx += 1) {
                        win.writeCell(cx, y, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{ .bg = row_bg } });
                    }
                }

                const date_display = if (g.date.len >= 10) g.date[0..10] else g.date;
                _ = renderer.writeStr(win, x0 + 1, y, date_display, style);
                _ = renderer.writeNum(win, x0 + 13, y, g.elo, style);
                _ = renderer.writeStr(win, x0 + 19, y, g.player_color, style);
                _ = renderer.writeStr(win, x0 + 27, y, displayResult(g.result, g.player_color), style);
                y += 1;
            }
        }

        const hint_y = win.height -| 2;
        if (hint_y > y) {
            const hints = if (self.delete_pending)
                "Delete permanently? Y/Enter = Yes  N/Esc = No"
            else if (total > 0)
                "\xe2\x86\x91\xe2\x86\x93 Navigate  Enter View  Del Remove  Esc Back"
            else
                "Esc Back";
            _ = renderer.writeStr(win, x0 + 1, hint_y, hints, .{ .fg = Theme.text_dim, .bg = Theme.bg });
        }
    }
};

fn displayResult(result: []const u8, player_color: []const u8) []const u8 {
    if (std.mem.eql(u8, result, "*")) return "In Progress";
    if (std.mem.eql(u8, result, "1/2-1/2")) return "Draw";
    const is_white = std.mem.eql(u8, player_color, "white");
    if (std.mem.eql(u8, result, "1-0")) {
        return if (is_white) "Won" else "Lost";
    }
    if (std.mem.eql(u8, result, "0-1")) {
        return if (!is_white) "Won" else "Lost";
    }
    return result;
}

test "displayResult maps PGN results to human-readable" {
    try std.testing.expectEqualStrings("Won", displayResult("1-0", "white"));
    try std.testing.expectEqualStrings("Lost", displayResult("1-0", "black"));
    try std.testing.expectEqualStrings("Won", displayResult("0-1", "black"));
    try std.testing.expectEqualStrings("Lost", displayResult("0-1", "white"));
    try std.testing.expectEqualStrings("Draw", displayResult("1/2-1/2", "white"));
    try std.testing.expectEqualStrings("In Progress", displayResult("*", "white"));
}

fn fakeKey(codepoint: u21, mods: vaxis.Key.Modifiers) vaxis.Key {
    return .{ .codepoint = codepoint, .mods = mods };
}

test "history: delete asks first, confirms on Y, cancels on Esc (AE7/R8)" {
    var list = std.ArrayList(storage.GameInfo).empty;
    defer list.deinit(std.testing.allocator);
    try list.append(std.testing.allocator, .{
        .filename = "g.pgn",
        .date = "2026-06-18",
        .elo = 1500,
        .player_color = "white",
        .result = "*",
        .is_finished = false,
    });
    var screen = HistoryScreen.init(list);

    // Del opens the confirm; nothing is removed yet.
    try std.testing.expectEqual(HistoryAction.none, screen.handleInput(fakeKey(vaxis.Key.delete, .{})));
    try std.testing.expect(screen.delete_pending);

    // Esc cancels: stays on the screen (not .back), no delete.
    try std.testing.expectEqual(HistoryAction.none, screen.handleInput(fakeKey(vaxis.Key.escape, .{})));
    try std.testing.expect(!screen.delete_pending);

    // Del then Y confirms.
    _ = screen.handleInput(fakeKey(vaxis.Key.delete, .{}));
    try std.testing.expectEqual(HistoryAction.delete, screen.handleInput(fakeKey(vaxis.Key.enter, .{})));
}
