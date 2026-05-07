const std = @import("std");
const vaxis = @import("vaxis");
const rozinante = @import("rozinante");
const renderer = rozinante.tui.renderer;
const Game = rozinante.tui.game.Game;
const input = rozinante.tui.input;
const Menu = rozinante.tui.menu.Menu;
const MenuAction = rozinante.tui.menu.MenuAction;

pub const Panic = struct {
    pub const call = panicHandler;
    pub const sentinelMismatch = std.debug.FormattedPanic.sentinelMismatch;
    pub const unwrapError = std.debug.FormattedPanic.unwrapError;
    pub const outOfBounds = std.debug.FormattedPanic.outOfBounds;
    pub const startGreaterThanEnd = std.debug.FormattedPanic.startGreaterThanEnd;
    pub const inactiveUnionField = std.debug.FormattedPanic.inactiveUnionField;
    pub const messages = std.debug.FormattedPanic.messages;
};

fn panicHandler(msg: []const u8, ret_addr: ?usize) noreturn {
    if (global_tty) |*tty| {
        if (global_vx) |*vx| {
            vx.deinit(null, tty.writer());
        }
        tty.deinit();
    }
    std.debug.defaultPanic(msg, ret_addr);
}

var global_tty: ?vaxis.Tty = null;
var global_vx: ?vaxis.Vaxis = null;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    cap_da1,
    key_release: vaxis.Key,
    mouse: vaxis.Mouse,
    mouse_leave,
    focus_in,
    focus_out,
    paste_start,
    paste_end,
    paste: []const u8,
    color_report: vaxis.Cell.Color.Report,
    color_scheme: vaxis.Cell.Color.Scheme,
    cap_kitty_keyboard,
    cap_kitty_graphics,
    cap_rgb,
    cap_sgr_pixels,
    cap_unicode,
    cap_color_scheme_updates,
    cap_multi_cursor,
};

const SPACIOUS_MIN_W: u16 = 94;
const SPACIOUS_MIN_H: u16 = 33;
const COMPACT_MIN_W: u16 = 50;
const COMPACT_MIN_H: u16 = 18;

fn selectRenderOpts(width: u16, height: u16) ?renderer.RenderOptions {
    if (width >= SPACIOUS_MIN_W and height >= SPACIOUS_MIN_H) {
        return renderer.RenderOptions{};
    }
    if (width >= COMPACT_MIN_W and height >= COMPACT_MIN_H) {
        return renderer.compact_options;
    }
    return null;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();

    var tty_buf: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &tty_buf);
    global_tty = tty;
    defer {
        tty.deinit();
        global_tty = null;
    }

    var vx = try vaxis.Vaxis.init(io, alloc, init.environ_map, .{});
    global_vx = vx;
    defer {
        vx.deinit(alloc, tty.writer());
        global_vx = null;
    }

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), std.Io.Duration.fromMilliseconds(3000));

    // Menu phase
    var menu_state = Menu{};
    var menu_done = false;

    while (!menu_done) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                const action = menu_state.handleInput(key);
                switch (action) {
                    .quit => return,
                    .start => menu_done = true,
                    .render, .none => {},
                }
            },
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
            },
            else => {},
        }

        const win = vx.window();
        win.clear();
        menu_state.render(win);
        try vx.render(tty.writer());
    }

    const config = menu_state.getConfig();
    _ = config;

    // Game phase
    var game_state = Game.init();

    while (true) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                const action = input.handleKeyPress(&game_state, key);
                switch (action) {
                    .quit => break,
                    .render => game_state.tickFlash(),
                    .none => {},
                }
            },
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
            },
            else => {},
        }

        const win = vx.window();
        win.clear();
        win.fill(.{ .style = .{ .bg = renderer.Theme.bg } });

        const maybe_opts = selectRenderOpts(win.width, win.height);

        if (maybe_opts) |opts| {
            const board_w = renderer.boardWidth(opts);
            const board_h = renderer.boardHeight(opts);

            const board_win = win.child(.{
                .x_off = 0,
                .y_off = 0,
                .width = board_w,
                .height = board_h,
            });
            renderer.renderBoard(board_win, &game_state, opts);

            const info_x: u16 = board_w + 1;
            const info_w = if (win.width > info_x) win.width - info_x else 0;
            const info_win = win.child(.{
                .x_off = @intCast(info_x),
                .y_off = 0,
                .width = info_w,
                .height = board_h,
            });
            renderer.renderInfoPanel(info_win, &game_state);
        } else {
            renderer.renderResizeMessage(win);
        }

        try vx.render(tty.writer());
    }
}
