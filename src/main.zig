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
const PlayerColor = rozinante.tui.menu.PlayerColor;
const HistoryScreen = rozinante.tui.history.HistoryScreen;
const ViewerState = rozinante.tui.viewer.ViewerState;
const engine_mod = rozinante.engine;
const openings = rozinante.openings;
const persistence = rozinante.persistence;
const pgn = persistence.pgn;
const storage = persistence.storage;
const config = persistence.config;
const Io = std.Io;

const log = std.log.scoped(.persistence);
const hints_log = std.log.scoped(.hints);
const linux = std.os.linux;

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = fileLogFn,
};

const log_path: [*:0]const u8 = "/tmp/rozinante.log";

fn fileLogFn(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_str = comptime message_level.asText();
    const scope_str = comptime @tagName(scope);
    const prefix = level_str ++ " (" ++ scope_str ++ "): ";

    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, prefix ++ format ++ "\n", args) catch return;

    const rc = linux.open(log_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, 0o644);
    const fd: i32 = @bitCast(@as(u32, @truncate(rc)));
    if (fd < 0) return;
    _ = linux.write(fd, msg.ptr, msg.len);
    _ = linux.close(fd);
}

pub const Panic = std.debug.FullPanic(panicHandler);

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
    engine_analysis_ready,
};

const EngineResult = struct {
    move: ?chess.Move = null,
    failed: bool = false,
};

fn engineWork(eng: *engine_mod.Engine, board: *const chess.Board, result: *EngineResult, event_loop: *vaxis.Loop(Event)) void {
    if (eng.getMove(board)) |m| {
        result.move = m;
    } else |_| {
        result.failed = true;
    }
    event_loop.postEvent(.engine_move_ready) catch {};
}

fn analysisWork(eng: *engine_mod.Engine, board: *const chess.Board, result: *EngineResult, event_loop: *vaxis.Loop(Event)) void {
    hints_log.debug("background analysis started", .{});
    const analysis = eng.analyze(board, 500) catch {
        hints_log.warn("background analysis failed", .{});
        result.failed = true;
        event_loop.postEvent(.engine_analysis_ready) catch {};
        return;
    };
    result.move = analysis.best_move;
    if (analysis.best_move) |m| {
        var buf: [5]u8 = undefined;
        const uci = m.toUci(&buf);
        hints_log.debug("analysis result: best_move={s}", .{uci});
    } else {
        hints_log.debug("analysis result: no best move", .{});
    }
    event_loop.postEvent(.engine_analysis_ready) catch {};
}

const MIN_W: u16 = 118;
const MIN_H: u16 = 49;

fn fits(width: u16, height: u16) bool {
    return width >= MIN_W and height >= MIN_H;
}

fn dispatchEngineMove(
    io: Io,
    eng: *engine_mod.Engine,
    game_state: *Game,
    engine_board: *chess.Board,
    engine_result: *EngineResult,
    engine_future: *?Io.Future(void),
    loop_ptr: *vaxis.Loop(Event),
) void {
    engine_board.* = game_state.board;
    engine_result.* = .{};
    game_state.engine_state = .thinking;
    game_state.thinking_start_ns = Io.Timestamp.now(io, .awake).nanoseconds;

    engine_future.* = io.concurrent(engineWork, .{
        eng,
        engine_board,
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

fn dispatchAnalysis(
    io: Io,
    eng: *engine_mod.Engine,
    game_state: *const Game,
    analysis_board: *chess.Board,
    analysis_result: *EngineResult,
    analysis_future: *?Io.Future(void),
    analysis_pending: *bool,
    loop_ptr: *vaxis.Loop(Event),
) void {
    if (analysis_pending.*) return;
    if (!game_state.hints_enabled) return;
    if (!game_state.isHumanTurn()) return;

    analysis_board.* = game_state.board;
    analysis_result.* = .{};
    analysis_pending.* = true;
    hints_log.debug("dispatching background analysis", .{});

    analysis_future.* = io.concurrent(analysisWork, .{
        eng,
        analysis_board,
        analysis_result,
        loop_ptr,
    }) catch {
        hints_log.warn("failed to dispatch analysis concurrent task", .{});
        analysis_pending.* = false;
        return;
    };
}

fn cancelAnalysis(
    io: Io,
    eng: *engine_mod.Engine,
    analysis_future: *?Io.Future(void),
    analysis_pending: *bool,
) void {
    if (!analysis_pending.*) return;
    hints_log.debug("cancelling background analysis", .{});
    eng.stop();
    if (analysis_future.*) |*f| {
        f.await(io);
        analysis_future.* = null;
    }
    analysis_pending.* = false;
}

fn renderGame(vx: *vaxis.Vaxis, game_state: *const Game) void {
    const win = vx.window();
    win.clear();
    win.fill(.{ .style = .{ .bg = renderer.Theme.bg } });

    if (fits(win.width, win.height)) {
        const opts = renderer.RenderOptions{};
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

fn formatPgnDate(buf: []u8, secs: i64) []const u8 {
    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@max(0, secs)) };
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.bufPrint(buf, "{d:0>4}.{d:0>2}.{d:0>2}", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
    }) catch "????.??.??";
}

fn pgnResult(game_state: *const Game) []const u8 {
    if (game_state.game_phase != .ended) return "*";
    if (chess.isCheckmate(&game_state.board)) {
        return if (game_state.board.active_color == .white) "0-1" else "1-0";
    }
    if (chess.isDraw(&game_state.board)) return "1/2-1/2";
    // Resignation: the result string contains who resigned
    if (game_state.result) |r| {
        if (std.mem.indexOf(u8, r, "White resigns") != null) return "0-1";
        if (std.mem.indexOf(u8, r, "Black resigns") != null) return "1-0";
    }
    return "*";
}

fn autoSave(
    io: Io,
    alloc: std.mem.Allocator,
    game_state: *Game,
    data_dir: []const u8,
    current_save_path: *?[]const u8,
    game_elo: u16,
    player_color: chess.Color,
    game_start_secs: i64,
) void {
    if (game_state.move_count == 0) return;
    log.debug("autoSave: move_count={d} board_count={d} has_save_path={}", .{ game_state.move_count, game_state.board_count, current_save_path.* != null });

    // Build board_history slice including current board for writePgn
    // writePgn needs board_history[0..move_count] (boards before each move)
    // plus board_history[move_count] (board after last move)
    // Game stores board_history[0..board_count] where board_count == move_count
    // (each executeMove pushes pre-move board). We need to temporarily append current board.
    if (game_state.board_count < 512) {
        game_state.board_history[game_state.board_count] = game_state.board;
    }

    const result_str = pgnResult(game_state);

    var date_buf: [16]u8 = undefined;
    const pgn_date = formatPgnDate(&date_buf, game_start_secs);

    const color_str: []const u8 = if (player_color == .white) "white" else "black";
    const header = pgn.PgnHeader{
        .event = "Rozinante",
        .site = "Local",
        .date = pgn_date,
        .white = if (player_color == .white) "Player" else "Stockfish",
        .black = if (player_color == .black) "Player" else "Stockfish",
        .result = result_str,
    };

    log.debug("autoSave: calling writePgn with {d} moves, {d} boards", .{ game_state.move_count, game_state.board_count + 1 });

    var pgn_buf: [32768]u8 = undefined;
    const pgn_content = pgn.writePgn(
        &pgn_buf,
        header,
        game_state.move_history[0..game_state.move_count],
        game_state.board_history[0 .. game_state.board_count + 1],
    ) catch {
        log.warn("failed to serialize PGN for auto-save", .{});
        return;
    };
    log.debug("autoSave: writePgn produced {d} bytes", .{pgn_content.len});

    if (current_save_path.*) |existing_path| {
        // Overwrite existing file
        const dir = std.Io.Dir.cwd();
        dir.writeFile(io, .{
            .sub_path = existing_path,
            .data = pgn_content,
        }) catch |err| {
            log.warn("failed to overwrite save file: {}", .{err});
        };
    } else {
        // First save — generate filename
        const path = storage.saveGame(alloc, io, data_dir, .{
            .pgn_content = pgn_content,
            .date_secs = game_start_secs,
            .elo = game_elo,
            .color = color_str,
        }) catch |err| {
            log.warn("failed to save game: {}", .{err});
            return;
        };
        current_save_path.* = path;
    }
}

const HistoryResult = enum {
    back,
    view_game,
    resume_game,
};

fn runGameHistory(
    io: Io,
    alloc: std.mem.Allocator,
    loop_ptr: *vaxis.Loop(Event),
    vx: *vaxis.Vaxis,
    tty: *vaxis.Tty,
    history_games: *std.ArrayList(storage.GameInfo),
    data_dir: []const u8,
    selected_filepath: *?[]const u8,
) HistoryResult {
    var screen = HistoryScreen.init(history_games.*);

    while (true) {
        const win = vx.window();
        screen.render(win);
        vx.render(tty.writer()) catch return .back;

        const event = loop_ptr.nextEvent() catch return .back;
        switch (event) {
            .key_press => |key| {
                const action = screen.handleInput(key);
                switch (action) {
                    .back => return .back,
                    .select_finished => {
                        if (screen.selectedGame()) |g| {
                            selected_filepath.* = std.fmt.allocPrint(alloc, "{s}/{s}", .{ data_dir, g.filename }) catch null;
                            const viewer_result = runGameViewer(io, alloc, loop_ptr, vx, tty, selected_filepath.*);
                            if (viewer_result == .back_to_menu) return .back;
                        }
                    },
                    .select_unfinished => {
                        if (screen.selectedGame()) |g| {
                            selected_filepath.* = std.fmt.allocPrint(alloc, "{s}/{s}", .{ data_dir, g.filename }) catch null;
                            return .resume_game;
                        }
                    },
                    .delete => {
                        if (screen.selectedGame()) |g| {
                            const filepath = std.fmt.allocPrint(alloc, "{s}/{s}", .{ data_dir, g.filename }) catch continue;
                            storage.deleteGame(io, filepath) catch {};
                            screen.removeAtCursor();
                            history_games.* = screen.games;
                        }
                    },
                    .none => {},
                }
            },
            .winsize => |ws| {
                vx.resize(alloc, tty.writer(), ws) catch {};
            },
            else => {},
        }
    }
}

const ViewerResult = enum {
    back_to_history,
    back_to_menu,
};

fn runGameViewer(
    io: Io,
    alloc: std.mem.Allocator,
    loop_ptr: *vaxis.Loop(Event),
    vx: *vaxis.Vaxis,
    tty: *vaxis.Tty,
    filepath: ?[]const u8,
) ViewerResult {
    const fp = filepath orelse return .back_to_history;
    const pgn_content = storage.loadGame(alloc, io, fp) catch return .back_to_history;
    const parsed = pgn.parsePgn(pgn_content) catch return .back_to_history;
    const move_count = parsed.move_count;
    if (move_count == 0) return .back_to_history;

    var boards: [513]chess.Board = undefined;
    boards[0] = chess.Board.initial;
    var san_list: [512]pgn.SanNotation = undefined;
    for (0..move_count) |i| {
        const pm = parsed.moves[i];
        const record = game_mod.MoveRecord{ .move = pm.move, .piece = pm.piece, .captured = pm.captured };
        boards[i + 1] = chess.makeMove(boards[i], pm.move);
        san_list[i] = pgn.computeSan(record, &boards[i], &boards[i + 1]);
    }

    var viewer = ViewerState.init(&boards, &san_list, move_count);

    while (true) {
        const win = vx.window();
        viewer.render(win);
        vx.render(tty.writer()) catch return .back_to_history;

        const event = loop_ptr.nextEvent() catch return .back_to_history;
        switch (event) {
            .key_press => |key| {
                const action = viewer.handleInput(key);
                switch (action) {
                    .back => return .back_to_history,
                    .none => {},
                }
            },
            .winsize => |ws| {
                vx.resize(alloc, tty.writer(), ws) catch {};
            },
            else => {},
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();

    log.debug("=== rozinante starting ===", .{});

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

    // --- Persistence setup (optional; both dirs or neither) ---
    log.debug("resolving data and config directories", .{});
    var prefs: config.Preferences = .{};
    var data_dir: ?[]const u8 = null;
    var config_dir: ?[]const u8 = null;
    if (storage.getDataDir(alloc, io, init.environ_map)) |dd| {
        if (storage.getConfigDir(alloc, io, init.environ_map)) |cd| {
            data_dir = dd;
            config_dir = cd;
            log.debug("data_dir={s} config_dir={s}", .{ dd, cd });
            storage.ensureDirExists(io, dd) catch {};
            storage.ensureDirExists(io, cd) catch {};
            prefs = config.loadPreferences(alloc, io, cd);
            config.savePreferences(alloc, io, prefs, cd) catch {};
        } else |err| {
            log.warn("failed to resolve config directory: {}, persistence disabled", .{err});
        }
    } else |err| {
        log.warn("failed to resolve data directory: {}, persistence disabled", .{err});
    }

    // Find Stockfish (with preference override)
    const stockfish_path = engine_mod.findStockfish(io, prefs.stockfish_path) catch {
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

    var analysis_future: ?Io.Future(void) = null;
    var analysis_result: EngineResult = .{};
    var analysis_board: chess.Board = undefined;
    var analysis_pending: bool = false;

    const opening_book = try alloc.create(openings.OpeningBook);
    opening_book.* = openings.OpeningBook.init();

    main_loop: while (true) {
        // --- Crash recovery: scan for unfinished games ---
        var resume_filepath: ?[]const u8 = null;
        var resume_elo: u16 = prefs.default_elo;
        var resume_color: chess.Color = .white;

        if (data_dir) |dd| {
            const games = storage.listGames(alloc, io, dd) catch &.{};
            for (games) |g| {
                if (!g.is_finished) {
                    // Build full filepath
                    resume_filepath = std.fmt.allocPrint(alloc, "{s}/{s}", .{ dd, g.filename }) catch null;
                    resume_elo = g.elo;
                    if (std.mem.eql(u8, g.player_color, "black")) {
                        resume_color = .black;
                    } else {
                        resume_color = .white;
                    }
                    break;
                }
            }
        }

        // --- Menu phase ---
        var menu_state = Menu{};
        menu_state.selected_elo = prefs.default_elo;
        menu_state.selected_color = PlayerColor.fromString(prefs.default_color);
        menu_state.has_resume_game = resume_filepath != null;
        menu_state.initActiveField();

        var menu_done = false;
        var menu_action: MenuAction = .none;

        while (!menu_done) {
            const event = try loop.nextEvent();
            switch (event) {
                .key_press => |key| {
                    const action = menu_state.handleInput(key);
                    switch (action) {
                        .quit => return,
                        .start => {
                            menu_action = .start;
                            menu_done = true;
                        },
                        .resume_game => {
                            menu_action = .resume_game;
                            menu_done = true;
                        },
                        .game_history => if (data_dir) |dd| {
                            var history_list: std.ArrayList(storage.GameInfo) = if (storage.listGames(alloc, io, dd)) |sl|
                                std.ArrayList(storage.GameInfo).fromOwnedSlice(sl)
                            else |_|
                                std.ArrayList(storage.GameInfo).empty;
                            var selected_fp: ?[]const u8 = null;
                            const hist_result = runGameHistory(io, alloc, &loop, &vx, &tty, &history_list, dd, &selected_fp);
                            if (hist_result == .resume_game) {
                                if (selected_fp) |fp| {
                                    // Parse the selected game to extract elo and color for resume
                                    const basename = if (std.mem.lastIndexOfScalar(u8, fp, '/')) |idx| fp[idx + 1 ..] else fp;
                                    resume_filepath = fp;
                                    resume_elo = prefs.default_elo;
                                    resume_color = .white;
                                    // Extract elo and color from filename
                                    if (std.mem.indexOf(u8, basename, "_elo")) |elo_start| {
                                        const after_elo = basename[elo_start + 4 ..];
                                        if (std.mem.indexOf(u8, after_elo, "_s")) |color_sep| {
                                            resume_elo = std.fmt.parseInt(u16, after_elo[0..color_sep], 10) catch prefs.default_elo;
                                            const color_part = after_elo[color_sep + 2 ..];
                                            const color_end = std.mem.indexOf(u8, color_part, ".") orelse color_part.len;
                                            if (std.mem.eql(u8, color_part[0..color_end], "black")) {
                                                resume_color = .black;
                                            }
                                        }
                                    }
                                    menu_action = .resume_game;
                                    menu_done = true;
                                }
                            }
                        },
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

        // --- Save preferences if changed ---
        if (menu_action == .start) {
            const menu_config = menu_state.getConfig();
            const menu_color_str = menu_config.player_color.toString();
            if (menu_config.elo != prefs.default_elo or !std.mem.eql(u8, menu_color_str, prefs.default_color)) {
                prefs.default_elo = menu_config.elo;
                prefs.default_color = menu_color_str;
                if (config_dir) |cd| config.savePreferences(alloc, io, prefs, cd) catch {};
            }
        }

        // Cleanup previous engine if any
        if (current_engine) |*eng| {
            cancelAnalysis(io, eng, &analysis_future, &analysis_pending);
        }
        cancelEngineFuture(&engine_future, io);
        if (current_engine) |*eng| {
            eng.deinit();
            current_engine = null;
        }

        var game_state: Game = undefined;
        var game_elo: u16 = undefined;
        var player_color: chess.Color = undefined;
        var current_save_path: ?[]const u8 = null;
        var game_start_secs: i64 = undefined;

        if (menu_action == .resume_game) {
            // --- Resume game flow ---
            const filepath = resume_filepath orelse continue :main_loop;
            const pgn_content = storage.loadGame(alloc, io, filepath) catch {
                log.warn("failed to load resume game", .{});
                continue :main_loop;
            };

            const parsed = pgn.parsePgn(pgn_content) catch {
                log.warn("failed to parse resume game PGN", .{});
                continue :main_loop;
            };

            game_elo = resume_elo;
            player_color = resume_color;
            current_save_path = filepath;

            // Reconstruct game by replaying moves
            game_state = Game.initWithColorAndBook(player_color, opening_book);
            for (parsed.moves[0..parsed.move_count]) |pm| {
                game_state.executeMove(pm.move.from, pm.move.to, if (pm.move.move_type == .promotion) pm.move.promotion_piece else null);
            }

            // Extract date from filename for continued saves
            game_start_secs = @intCast(@divTrunc(Io.Timestamp.now(io, .real).nanoseconds, std.time.ns_per_s));

            current_engine = engine_mod.Engine.init(io, stockfish_path, game_elo) catch {
                continue :main_loop;
            };
            if (current_engine) |*eng| eng.relocate();

            log.info("resumed game from {s} with {d} moves", .{ filepath, parsed.move_count });
        } else {
            // --- New game flow ---
            const game_config = menu_state.getConfig();
            game_elo = game_config.elo;

            current_engine = engine_mod.Engine.init(io, stockfish_path, game_elo) catch {
                continue :main_loop;
            };
            if (current_engine) |*eng| eng.relocate();

            player_color = switch (game_config.player_color) {
                .white => .white,
                .black => .black,
                .random => if (@mod(Io.Timestamp.now(io, .awake).nanoseconds, 2) == 0) .white else .black,
            };

            game_state = Game.initWithColorAndBook(player_color, opening_book);
            game_start_secs = @intCast(@divTrunc(Io.Timestamp.now(io, .real).nanoseconds, std.time.ns_per_s));
        }

        // If engine goes first (player is black), dispatch immediately
        if (game_state.isEngineTurn()) {
            log.debug("engine goes first, dispatching initial move", .{});
            dispatchEngineMove(io, &current_engine.?, &game_state, &engine_board, &engine_result, &engine_future, &loop);
        }

        log.debug("entering game loop, player_color={s} elo={d}", .{ if (player_color == .white) "white" else "black", game_elo });

        // --- Game phase ---
        var prev_move_count: usize = game_state.move_count;
        renderGame(&vx, &game_state);
        try vx.render(tty.writer());

        game_loop: while (true) {
            const event = if (game_state.engine_state == .thinking or game_state.engine_state == .reconnecting or analysis_pending)
                loop.tryEvent() catch null
            else
                loop.nextEvent() catch null;

            if (event) |ev| {
                switch (ev) {
                    .key_press => |key| {
                        const prev_mc = game_state.move_count;
                        const action = input.handleKeyPress(&game_state, key);
                        if (game_state.move_count > prev_mc) {
                            log.debug("player move detected via input, move_count {d}->{d}", .{ prev_mc, game_state.move_count });
                        }
                        switch (action) {
                            .quit => {
                                if (current_engine) |*eng| {
                                    cancelAnalysis(io, eng, &analysis_future, &analysis_pending);
                                }
                                cancelEngineFuture(&engine_future, io);
                                return;
                            },
                            .new_game => {
                                if (current_engine) |*eng| {
                                    cancelAnalysis(io, eng, &analysis_future, &analysis_pending);
                                }
                                cancelEngineFuture(&engine_future, io);
                                game_state.engine_state = .idle;
                                continue :main_loop;
                            },
                            .resign => {
                                if (game_state.game_phase == .playing) {
                                    if (current_engine) |*eng| {
                                        cancelAnalysis(io, eng, &analysis_future, &analysis_pending);
                                    }
                                    cancelEngineFuture(&engine_future, io);
                                    game_state.engine_state = .idle;
                                    game_state.game_phase = .ended;
                                    game_state.result = if (game_state.player_color == .white)
                                        "White resigns \u{2014} Black wins"
                                    else
                                        "Black resigns \u{2014} White wins";

                                    if (data_dir) |dd| autoSave(io, alloc, &game_state, dd, &current_save_path, game_elo, player_color, game_start_secs);
                                    continue :main_loop;
                                }
                            },
                            .toggle_hints => {
                                game_state.hints_enabled = !game_state.hints_enabled;
                                if (game_state.hints_enabled) {
                                    game_state.computeEndangered();
                                    if (current_engine) |*eng| {
                                        dispatchAnalysis(io, eng, &game_state, &analysis_board, &analysis_result, &analysis_future, &analysis_pending, &loop);
                                    }
                                } else {
                                    if (current_engine) |*eng| {
                                        cancelAnalysis(io, eng, &analysis_future, &analysis_pending);
                                    }
                                    game_state.clearHints();
                                }
                            },
                            .render => {
                                game_state.tickFlash();
                                game_state.tickEngineHighlight();

                                if (game_state.isEngineTurn() and game_state.engine_state == .idle) {
                                    if (current_engine) |*eng| {
                                        cancelAnalysis(io, eng, &analysis_future, &analysis_pending);
                                    }
                                    log.debug("dispatching engine move (engine turn, idle)", .{});
                                    dispatchEngineMove(io, &current_engine.?, &game_state, &engine_board, &engine_result, &engine_future, &loop);
                                }
                            },
                            .none => {},
                        }
                    },
                    .engine_move_ready => {
                        log.debug("engine_move_ready event received", .{});
                        if (engine_future) |*f| {
                            f.await(io);
                            engine_future = null;
                        }

                        if (engine_result.failed) {
                            log.debug("engine move failed, attempting reconnect", .{});
                            game_state.engine_state = .reconnecting;
                            if (current_engine) |*eng| {
                                eng.restart(&game_state.board) catch {
                                    game_state.engine_state = .@"error";
                                    continue :game_loop;
                                };
                                dispatchEngineMove(io, eng, &game_state, &engine_board, &engine_result, &engine_future, &loop);
                            }
                        } else if (engine_result.move) |move| {
                            var move_buf: [5]u8 = undefined;
                            const uci = move.toUci(&move_buf);
                            log.debug("engine move received: {s}", .{uci});
                            game_state.executeMove(move.from, move.to, if (move.move_type == .promotion) move.promotion_piece else null);
                            game_state.engine_last_move = .{ .from = move.from, .to = move.to };
                            game_state.engine_last_move_timer = 8;
                            game_state.engine_state = .idle;
                            log.debug("engine move applied, move_count now {d}", .{game_state.move_count});

                            if (game_state.hints_enabled and game_state.isHumanTurn()) {
                                game_state.computeEndangered();
                                if (current_engine) |*eng| {
                                    dispatchAnalysis(io, eng, &game_state, &analysis_board, &analysis_result, &analysis_future, &analysis_pending, &loop);
                                }
                            }
                        }
                        engine_result = .{};
                    },
                    .engine_analysis_ready => {
                        if (analysis_future) |*f| {
                            f.await(io);
                            analysis_future = null;
                        }
                        if (analysis_pending) {
                            analysis_pending = false;
                            if (!analysis_result.failed) {
                                if (analysis_result.move) |move| {
                                    game_state.hint_best_move = .{ .from = move.from, .to = move.to };
                                    var uci_buf: [5]u8 = undefined;
                                    const uci = move.toUci(&uci_buf);
                                    hints_log.debug("best move hint set: {s}", .{uci});
                                }
                            } else {
                                hints_log.warn("analysis result: failed", .{});
                            }
                        }
                        analysis_result = .{};
                    },
                    .winsize => |ws| {
                        try vx.resize(alloc, tty.writer(), ws);
                    },
                    else => {},
                }
            }

            // Auto-save after new moves
            if (game_state.move_count > prev_move_count) {
                log.debug("move #{d} detected, triggering auto-save", .{game_state.move_count});
                prev_move_count = game_state.move_count;
                if (data_dir) |dd| autoSave(io, alloc, &game_state, dd, &current_save_path, game_elo, player_color, game_start_secs);
                log.debug("auto-save completed for move #{d}", .{game_state.move_count});
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

            if (event == null) {
                io.sleep(Io.Duration.fromMilliseconds(100), .awake) catch {};
            }
        }
    }
}
