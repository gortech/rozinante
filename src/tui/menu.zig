const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Window = vaxis.Window;
const renderer = @import("renderer.zig");
const Theme = renderer.Theme;

pub const PlayerColor = enum {
    white,
    black,
    random,

    pub fn label(self: PlayerColor) []const u8 {
        return switch (self) {
            .white => "White",
            .black => "Black",
            .random => "Random",
        };
    }
};

pub const GameConfig = struct {
    elo: u16,
    player_color: PlayerColor,
};

const ActiveField = enum {
    elo,
    color,
    start,
};

pub const MenuAction = enum {
    none,
    render,
    start,
    quit,
};

pub const Menu = struct {
    selected_elo: u16 = 1500,
    selected_color: PlayerColor = .white,
    active_field: ActiveField = .elo,
    confirmed: bool = false,

    const elo_min: u16 = 800;
    const elo_max: u16 = 2500;
    const elo_step: u16 = 100;

    pub fn handleInput(self: *Menu, key: vaxis.Key) MenuAction {
        if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true }))
            return .quit;

        if (key.matches(vaxis.Key.up, .{})) {
            self.active_field = switch (self.active_field) {
                .elo => .elo,
                .color => .elo,
                .start => .color,
            };
            return .render;
        }

        if (key.matches(vaxis.Key.down, .{})) {
            self.active_field = switch (self.active_field) {
                .elo => .color,
                .color => .start,
                .start => .start,
            };
            return .render;
        }

        if (key.matches(vaxis.Key.left, .{})) {
            switch (self.active_field) {
                .elo => {
                    if (self.selected_elo > elo_min)
                        self.selected_elo -= elo_step;
                },
                .color => {
                    self.selected_color = switch (self.selected_color) {
                        .white => .random,
                        .black => .white,
                        .random => .black,
                    };
                },
                .start => {},
            }
            return .render;
        }

        if (key.matches(vaxis.Key.right, .{})) {
            switch (self.active_field) {
                .elo => {
                    if (self.selected_elo < elo_max)
                        self.selected_elo += elo_step;
                },
                .color => {
                    self.selected_color = switch (self.selected_color) {
                        .white => .black,
                        .black => .random,
                        .random => .white,
                    };
                },
                .start => {},
            }
            return .render;
        }

        if (key.matches(vaxis.Key.enter, .{})) {
            if (self.active_field == .start) {
                self.confirmed = true;
                return .start;
            }
            return .none;
        }

        return .none;
    }

    pub fn getConfig(self: *const Menu) GameConfig {
        return .{
            .elo = self.selected_elo,
            .player_color = self.selected_color,
        };
    }

    pub fn render(self: *const Menu, win: Window) void {
        win.fill(.{ .style = .{ .bg = Theme.bg } });

        if (win.width < 20 or win.height < 12) {
            _ = renderer.writeStr(win, 1, win.height / 2, "Terminal too small", .{ .fg = Theme.text_primary, .bg = Theme.bg });
            return;
        }

        const content_w: u16 = 30;
        const content_h: u16 = 11;
        const x0: u16 = if (win.width > content_w) (win.width - content_w) / 2 else 0;
        const y0: u16 = if (win.height > content_h) (win.height - content_h) / 2 else 0;

        var y = y0;

        // Title
        const title = "ROZINANTE";
        const title_x = x0 + (content_w -| 9) / 2;
        _ = renderer.writeStr(win, title_x, y, title, .{ .fg = Theme.highlight_cursor, .bg = Theme.bg });
        y += 2;

        const subtitle = "New Game";
        const sub_x = x0 + (content_w -| 8) / 2;
        _ = renderer.writeStr(win, sub_x, y, subtitle, .{ .fg = Theme.text_primary, .bg = Theme.bg });
        y += 2;

        // Elo selector
        const elo_active = self.active_field == .elo;
        const elo_style = fieldStyle(elo_active);
        var col = renderer.writeStr(win, x0 + 2, y, "Elo Rating:  ", elo_style);
        col = renderer.writeStr(win, col, y, "\xe2\x97\x80 ", elo_style);
        col = renderer.writeNum(win, col, y, self.selected_elo, elo_style);
        _ = renderer.writeStr(win, col, y, " \xe2\x96\xb6", elo_style);
        if (elo_active) highlightRow(win, x0, y, content_w);
        y += 2;

        // Color selector
        const color_active = self.active_field == .color;
        const color_style = fieldStyle(color_active);
        col = renderer.writeStr(win, x0 + 2, y, "Play as:     ", color_style);
        col = renderer.writeStr(win, col, y, "\xe2\x97\x80 ", color_style);
        col = renderer.writeStr(win, col, y, self.selected_color.label(), color_style);
        _ = renderer.writeStr(win, col, y, " \xe2\x96\xb6", color_style);
        if (color_active) highlightRow(win, x0, y, content_w);
        y += 2;

        // Start button
        const start_active = self.active_field == .start;
        const btn_label = "[ Start Game ]";
        const btn_x = x0 + (content_w -| 14) / 2;
        if (start_active) {
            _ = renderer.writeStr(win, btn_x, y, btn_label, .{ .fg = Theme.bg, .bg = Theme.highlight_cursor });
        } else {
            _ = renderer.writeStr(win, btn_x, y, btn_label, .{ .fg = Theme.text_dim, .bg = Theme.bg });
        }
        y += 2;

        // Hints
        const hint = "\xe2\x86\x91\xe2\x86\x93 Navigate  \xe2\x86\x90\xe2\x86\x92 Adjust  Enter Select  Q Quit";
        const hint_y = if (win.height > 2) win.height - 2 else y;
        const hint_x = if (win.width > 50) (win.width - 50) / 2 else 0;
        _ = renderer.writeStr(win, hint_x, hint_y, hint, .{ .fg = Theme.text_dim, .bg = Theme.bg });
    }

    fn fieldStyle(active: bool) Cell.Style {
        return if (active)
            .{ .fg = Theme.text_primary, .bg = Theme.bg }
        else
            .{ .fg = Theme.text_dim, .bg = Theme.bg };
    }

    fn highlightRow(win: Window, x: u16, y: u16, w: u16) void {
        var i: u16 = x;
        while (i < x + w and i < win.width) : (i += 1) {
            var cell = win.readCell(i, y) orelse continue;
            cell.style.bg = .{ .rgb = .{ 40, 30, 70 } };
            win.writeCell(i, y, cell);
        }
    }
};

test "menu elo clamping" {
    var m = Menu{};
    m.selected_elo = Menu.elo_min;
    _ = m.handleInput(fakeKey(vaxis.Key.left, .{}));
    try @import("std").testing.expectEqual(Menu.elo_min, m.selected_elo);

    m.selected_elo = Menu.elo_max;
    _ = m.handleInput(fakeKey(vaxis.Key.right, .{}));
    try @import("std").testing.expectEqual(Menu.elo_max, m.selected_elo);
}

test "menu navigation cycles fields" {
    var m = Menu{};
    try @import("std").testing.expectEqual(ActiveField.elo, m.active_field);

    _ = m.handleInput(fakeKey(vaxis.Key.down, .{}));
    try @import("std").testing.expectEqual(ActiveField.color, m.active_field);

    _ = m.handleInput(fakeKey(vaxis.Key.down, .{}));
    try @import("std").testing.expectEqual(ActiveField.start, m.active_field);

    _ = m.handleInput(fakeKey(vaxis.Key.down, .{}));
    try @import("std").testing.expectEqual(ActiveField.start, m.active_field);

    _ = m.handleInput(fakeKey(vaxis.Key.up, .{}));
    try @import("std").testing.expectEqual(ActiveField.color, m.active_field);
}

test "menu enter on start returns start action" {
    var m = Menu{};
    m.active_field = .start;
    const action = m.handleInput(fakeKey(vaxis.Key.enter, .{}));
    try @import("std").testing.expectEqual(MenuAction.start, action);
    try @import("std").testing.expect(m.confirmed);
}

test "menu q returns quit" {
    var m = Menu{};
    const action = m.handleInput(fakeKey('q', .{}));
    try @import("std").testing.expectEqual(MenuAction.quit, action);
}

test "menu color cycling" {
    var m = Menu{};
    m.active_field = .color;
    try @import("std").testing.expectEqual(PlayerColor.white, m.selected_color);

    _ = m.handleInput(fakeKey(vaxis.Key.right, .{}));
    try @import("std").testing.expectEqual(PlayerColor.black, m.selected_color);

    _ = m.handleInput(fakeKey(vaxis.Key.right, .{}));
    try @import("std").testing.expectEqual(PlayerColor.random, m.selected_color);

    _ = m.handleInput(fakeKey(vaxis.Key.right, .{}));
    try @import("std").testing.expectEqual(PlayerColor.white, m.selected_color);
}

test "menu getConfig returns selected values" {
    var m = Menu{};
    m.selected_elo = 2000;
    m.selected_color = .black;
    const config = m.getConfig();
    try @import("std").testing.expectEqual(@as(u16, 2000), config.elo);
    try @import("std").testing.expectEqual(PlayerColor.black, config.player_color);
}

fn fakeKey(codepoint: u21, mods: vaxis.Key.Modifiers) vaxis.Key {
    return .{
        .codepoint = codepoint,
        .mods = mods,
    };
}
