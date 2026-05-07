const std = @import("std");
const vaxis = @import("vaxis");
const rozinante = @import("rozinante");
const chess = rozinante.chess;
const renderer = rozinante.tui.renderer;
const Game = rozinante.tui.game.Game;
const game_mod = rozinante.tui.game;
const input = rozinante.tui.input;
const Menu = rozinante.tui.menu.Menu;
const MenuAction = rozinante.tui.menu.MenuAction;
const engine_mod = rozinante.engine;
const Io = std.Io;

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
    engine_move_ready,
};

const EngineResult = struct {
    move: ?chess.Move = null,
    failed: bool = false,
};

fn engineWork(eng: *engine_mod.Engine, board: *const chess.Board, movetime: u32, result: *EngineResult, event_loop: *vaxis.Loop(Event)) void {
    if (eng.getMove(board, movetime)) |m| {
        result.move = m;
    } else |_| {
        result.failed = true;
    }
    event_loop.postEvent(.engine_move_ready) catch {};
}

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

fn dispatchEngineMove(
    io: Io,
    eng: *engine_mod.Engine,
    game_state: *Game,
    engine_board: *chess.Board,
    engine_result: *EngineResult,
    engine_future: *?Io.Future(void),
    loop_ptr: *vaxis.Loop(Event),
    elo: u16,
) void {
    engine_board.* = game_state.board;
    engine_result.* = .{};
    game_state.engine_state = .thinking;
    game_state.thinking_start_ns = Io.Timestamp.now(io, .awake).nanoseconds;

    engine_future.* = io.concurrent(engineWork, .{
        eng,
        engine_board,
        engine_mod.eloToMovetime(elo),
        engine_result,
        loop_ptr,
    }) catch {
        game_state.engine_state = .@"error";
        return;
    };
}

fn cancelEngineFuture(engine_future: *?Io.Future(void), io: Io) void {
    if (engine_future.*) |*f| {
        _ = f.cancel(io);
        engine_future.* = null;
    }
}

fn renderGame(vx: *vaxis.Vaxis, game_state: *const Game) void {
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
        renderer.renderBoard(board_win, game_state, opts);

        const info_x: u16 = board_w + 1;
        const info_w = if (win.width > info_x) win.width - info_x else 0;
        const info_win = win.child(.{
            .x_off = @intCast(info_x),
            .y_off = 0,
            .width = info_w,
            .height = board_h,
        });
        renderer.renderInfoPanel(info_win, game_state);
    } else {
        renderer.renderResizeMessage(win);
    }
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

    // Check for Stockfish before entering alt screen so errors are visible
    const stockfish_path = engine_mod.findStockfish(io) catch {
        const w = tty.writer();
        w.writeAll("Error: Stockfish not found. Please install Stockfish:\r\n") catch {};
        w.writeAll("  Ubuntu/Debian: sudo apt install stockfish\r\n") catch {};
        w.writeAll("  macOS:         brew install stockfish\r\n") catch {};
        w.writeAll("  Arch:          sudo pacman -S stockfish\r\n") catch {};
        return;
    };

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), Io.Duration.fromMilliseconds(3000));

    var current_engine: ?engine_mod.Engine = null;
    defer {
        if (current_engine) |*eng| eng.deinit();
    }

    var engine_future: ?Io.Future(void) = null;
    var engine_result: EngineResult = .{};
    var engine_board: chess.Board = undefined;

    main_loop: while (true) {
        // --- Menu phase ---
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

        // Cleanup previous engine if any
        cancelEngineFuture(&engine_future, io);
        if (current_engine) |*eng| {
            eng.deinit();
            current_engine = null;
        }

        // Init engine with selected Elo
        current_engine = engine_mod.Engine.init(io, stockfish_path, config.elo) catch {
            continue :main_loop;
        };

        // Resolve player color (Random → coin flip)
        const player_color: chess.Color = switch (config.player_color) {
            .white => .white,
            .black => .black,
            .random => if (@mod(Io.Timestamp.now(io, .awake).nanoseconds, 2) == 0) .white else .black,
        };

        // Init game with player color
        var game_state = Game.initWithColor(player_color);

        // If engine goes first (player is black), dispatch immediately
        if (game_state.isEngineTurn()) {
            dispatchEngineMove(io, &current_engine.?, &game_state, &engine_board, &engine_result, &engine_future, &loop, config.elo);
        }

        // --- Game phase ---
        game_loop: while (true) {
            // When engine is thinking, poll with timeout for spinner animation
            const event = if (game_state.engine_state == .thinking or game_state.engine_state == .reconnecting)
                loop.tryEvent() catch null
            else
                loop.nextEvent() catch null;

            if (event) |ev| {
                switch (ev) {
                    .key_press => |key| {
                        const action = input.handleKeyPress(&game_state, key);
                        switch (action) {
                            .quit => {
                                cancelEngineFuture(&engine_future, io);
                                return;
                            },
                            .new_game => {
                                cancelEngineFuture(&engine_future, io);
                                game_state.engine_state = .idle;
                                continue :main_loop;
                            },
                            .resign => {
                                if (game_state.game_phase == .playing) {
                                    cancelEngineFuture(&engine_future, io);
                                    game_state.engine_state = .idle;
                                    game_state.game_phase = .ended;
                                    game_state.result = if (game_state.player_color == .white)
                                        "White resigns \u{2014} Black wins"
                                    else
                                        "Black resigns \u{2014} White wins";
                                }
                            },
                            .render => {
                                game_state.tickFlash();
                                game_state.tickEngineHighlight();

                                // After human move, check if engine should go
                                if (game_state.isEngineTurn() and game_state.engine_state == .idle) {
                                    dispatchEngineMove(io, &current_engine.?, &game_state, &engine_board, &engine_result, &engine_future, &loop, config.elo);
                                }
                            },
                            .none => {},
                        }
                    },
                    .engine_move_ready => {
                        // Await the future to clean it up
                        if (engine_future) |*f| {
                            f.await(io);
                            engine_future = null;
                        }

                        if (engine_result.failed) {
                            game_state.engine_state = .reconnecting;
                            // Try restart
                            if (current_engine) |*eng| {
                                eng.restart(&game_state.board) catch {
                                    game_state.engine_state = .@"error";
                                    continue :game_loop;
                                };
                                // Re-dispatch after restart
                                dispatchEngineMove(io, eng, &game_state, &engine_board, &engine_result, &engine_future, &loop, config.elo);
                            }
                        } else if (engine_result.move) |move| {
                            game_state.executeMove(move.from, move.to, if (move.move_type == .promotion) move.promotion_piece else null);
                            game_state.engine_last_move = .{ .from = move.from, .to = move.to };
                            game_state.engine_last_move_timer = 8;
                            game_state.engine_state = .idle;
                        }
                        engine_result = .{};
                    },
                    .winsize => |ws| {
                        try vx.resize(alloc, tty.writer(), ws);
                    },
                    else => {},
                }
            }

            // Update thinking timer for display
            if (game_state.engine_state == .thinking) {
                const now_ns = Io.Timestamp.now(io, .awake).nanoseconds;
                const elapsed_ns = now_ns - game_state.thinking_start_ns;
                const elapsed_s = @divTrunc(elapsed_ns, std.time.ns_per_s);
                game_state.thinking_elapsed_s = if (elapsed_s >= 0) @intCast(@min(elapsed_s, 9999)) else 0;
                const spinner_raw = @divTrunc(elapsed_ns, 250 * std.time.ns_per_ms);
                game_state.spinner_idx = @intCast(@as(u2, @truncate(@as(u64, @intCast(@max(spinner_raw, 0))))));
            }

            renderGame(&vx, &game_state);
            try vx.render(tty.writer());

            // When polling (engine thinking), sleep briefly to avoid busy-wait
            if (event == null) {
                io.sleep(Io.Duration.fromMilliseconds(100), .awake) catch {};
            }
        }
    }
}
