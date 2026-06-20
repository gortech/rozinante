const std = @import("std");
const chess = @import("chess.zig");
const analysis = @import("analysis.zig");
const Io = std.Io;
const File = Io.File;
const process = std.process;
const Move = chess.Move;
const Board = chess.Board;

const log = std.log.scoped(.engine);

pub const EngineError = error{
    StockfishNotFound,
    EngineTimeout,
    InvalidUciResponse,
    EngineDead,
};

pub const Eval = analysis.Eval;

pub const Analysis = struct {
    eval: Eval,
    best_move: ?Move,
    principal_variation: []const u8,
    depth: u16,
};

pub const Engine = struct {
    child: process.Child,
    io: Io,
    skill: u8,
    is_ready: bool,
    stockfish_path: []const u8,

    stdin_buf: [4096]u8,
    stdout_buf: [4096]u8,
    stdin_writer: File.Writer,
    stdout_reader: File.Reader,

    pub fn init(io: Io, stockfish_path: []const u8, skill: u8) !Engine {
        const child = try process.spawn(io, .{
            .argv = &.{stockfish_path},
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .ignore,
        });

        var engine = Engine{
            .child = child,
            .io = io,
            .skill = skill,
            .is_ready = false,
            .stockfish_path = stockfish_path,
            .stdin_buf = undefined,
            .stdout_buf = undefined,
            .stdin_writer = undefined,
            .stdout_reader = undefined,
        };

        engine.relocate();

        try engine.uciHandshake();

        log.info("engine initialized: path={s} skill={d}", .{ stockfish_path, skill });

        return engine;
    }

    /// Re-point internal reader/writer buffer pointers after the struct has been
    /// moved in memory (e.g. returned by value from init).
    pub fn relocate(self: *Engine) void {
        self.stdin_writer = File.Writer.initStreaming(self.child.stdin.?, self.io, &self.stdin_buf);
        self.stdout_reader = File.Reader.initStreaming(self.child.stdout.?, self.io, &self.stdout_buf);
    }

    pub fn deinit(self: *Engine) void {
        self.sendCommand("quit") catch {};
        self.stdin_writer.interface.flush() catch {};
        self.child.kill(self.io);
        self.is_ready = false;
    }

    fn uciHandshake(self: *Engine) !void {
        try self.sendCommand("uci");
        try self.readUntilToken("uciok");

        try self.setSkillLevel(self.skill);

        try self.waitReady();
    }

    fn waitReady(self: *Engine) !void {
        try self.sendCommand("isready");
        try self.readUntilToken("readyok");
        self.is_ready = true;
    }

    fn sendCommand(self: *Engine, cmd: []const u8) !void {
        const writer = &self.stdin_writer.interface;
        try writer.writeAll(cmd);
        try writer.writeAll("\n");
        try writer.flush();
    }

    fn readLine(self: *Engine, buf: *[4096]u8) ![]const u8 {
        const reader = &self.stdout_reader.interface;
        const line = reader.takeSentinel('\n') catch |err| switch (err) {
            error.EndOfStream => return EngineError.EngineDead,
            error.StreamTooLong => return EngineError.InvalidUciResponse,
            else => return err,
        };
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        @memcpy(buf[0..trimmed.len], trimmed);
        return buf[0..trimmed.len];
    }

    fn readUntilToken(self: *Engine, token: []const u8) !void {
        var buf: [4096]u8 = undefined;
        var attempts: u32 = 0;
        while (attempts < 1000) : (attempts += 1) {
            const line = try self.readLine(&buf);
            if (std.mem.startsWith(u8, line, token)) return;
        }
        return EngineError.EngineTimeout;
    }

    pub fn getMove(self: *Engine, board: *const Board) !Move {
        try self.waitReady();

        var fen_buf: [128]u8 = undefined;
        const fen = board.toFen(&fen_buf);

        var pos_buf: [256]u8 = undefined;
        const pos_cmd = std.fmt.bufPrint(&pos_buf, "position fen {s}", .{fen}) catch
            return EngineError.InvalidUciResponse;
        try self.sendCommand(pos_cmd);

        const elo = skillToElo(self.skill);
        var go_buf: [64]u8 = undefined;
        const go_cmd = std.fmt.bufPrint(&go_buf, "go depth {d} movetime {d}", .{ eloToDepth(elo), eloToMovetime(elo) }) catch
            return EngineError.InvalidUciResponse;
        try self.sendCommand(go_cmd);

        var line_buf: [4096]u8 = undefined;
        var attempts: u32 = 0;
        while (attempts < 5000) : (attempts += 1) {
            const line = try self.readLine(&line_buf);
            if (std.mem.startsWith(u8, line, "bestmove ")) {
                const uci_move = parseBestMove(line) orelse {
                    log.warn("engine returned unparseable bestmove: {s}", .{line});
                    return EngineError.InvalidUciResponse;
                };
                return Move.fromUci(uci_move) orelse {
                    log.warn("invalid bestmove UCI string: {s}", .{uci_move});
                    return EngineError.InvalidUciResponse;
                };
            }
        }
        return EngineError.EngineTimeout;
    }

    pub fn analyze(self: *Engine, board: *const Board, movetime_ms: u32) !Analysis {
        var fen_buf: [128]u8 = undefined;
        const fen = board.toFen(&fen_buf);

        var pos_buf: [256]u8 = undefined;
        const pos_cmd = std.fmt.bufPrint(&pos_buf, "position fen {s}", .{fen}) catch
            return EngineError.InvalidUciResponse;
        try self.sendCommand(pos_cmd);

        var go_buf: [64]u8 = undefined;
        const go_cmd = std.fmt.bufPrint(&go_buf, "go movetime {d}", .{movetime_ms}) catch
            return EngineError.InvalidUciResponse;
        try self.sendCommand(go_cmd);

        var result = Analysis{
            .eval = .{ .cp = 0 },
            .best_move = null,
            .principal_variation = "",
            .depth = 0,
        };

        var line_buf: [4096]u8 = undefined;
        var attempts: u32 = 0;
        while (attempts < 5000) : (attempts += 1) {
            const line = try self.readLine(&line_buf);

            if (std.mem.startsWith(u8, line, "info ")) {
                parseInfoLine(line, &result);
            }

            if (parseBestMove(line)) |uci_move| {
                result.best_move = Move.fromUci(uci_move);
                return result;
            }
        }
        return EngineError.EngineTimeout;
    }

    fn setSkillLevel(self: *Engine, level: u8) !void {
        var buf: [64]u8 = undefined;
        const cmd = std.fmt.bufPrint(&buf, "setoption name Skill Level value {d}", .{level}) catch unreachable;
        try self.sendCommand(cmd);
    }

    /// Analyze at full strength regardless of the configured skill: raise Skill Level
    /// to 20 for the search and restore the configured skill on every exit path. Safe
    /// because hints fire only on the human's turn and cancelAnalysis precedes every
    /// opponent getMove, so the raise never overlaps the opponent search on this engine.
    pub fn analyzeFullStrength(self: *Engine, board: *const Board, movetime_ms: u32) !Analysis {
        try self.setSkillLevel(20);
        defer self.setSkillLevel(self.skill) catch {};
        return self.analyze(board, movetime_ms);
    }

    pub fn stop(self: *Engine) void {
        self.sendCommand("stop") catch |err| {
            log.warn("failed to send stop command: {}", .{err});
        };
    }

    pub fn restart(self: *Engine, board: *const Board) !void {
        log.info("restarting engine", .{});

        self.child.kill(self.io);

        const child = try process.spawn(self.io, .{
            .argv = &.{self.stockfish_path},
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .ignore,
        });
        self.child = child;
        self.relocate();
        self.is_ready = false;

        try self.uciHandshake();

        var fen_buf: [128]u8 = undefined;
        const fen = board.toFen(&fen_buf);
        var pos_buf: [256]u8 = undefined;
        const pos_cmd = std.fmt.bufPrint(&pos_buf, "position fen {s}", .{fen}) catch
            return EngineError.InvalidUciResponse;
        try self.sendCommand(pos_cmd);

        log.info("engine restarted successfully", .{});
    }
};

pub fn parseBestMove(line: []const u8) ?[]const u8 {
    const prefix = "bestmove ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    if (rest.len == 0) return null;
    const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
    const uci_move = rest[0..end];
    if (uci_move.len < 4 or uci_move.len > 5) return null;
    return uci_move;
}

pub fn parseInfoLine(line: []const u8, result: *Analysis) void {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');
    while (iter.next()) |token| {
        if (std.mem.eql(u8, token, "depth")) {
            if (iter.next()) |val| {
                result.depth = std.fmt.parseInt(u16, val, 10) catch continue;
            }
        } else if (std.mem.eql(u8, token, "cp")) {
            if (iter.next()) |val| {
                result.eval = .{ .cp = std.fmt.parseInt(i32, val, 10) catch continue };
            }
        } else if (std.mem.eql(u8, token, "mate")) {
            if (iter.next()) |val| {
                result.eval = .{ .mate = std.fmt.parseInt(i32, val, 10) catch continue };
            }
        } else if (std.mem.eql(u8, token, "pv")) {
            if (iter.rest().len > 0) {
                result.principal_variation = iter.rest();
            }
            return;
        }
    }
}

pub fn findStockfish(io: Io, override: ?[]const u8) EngineError![]const u8 {
    if (override) |path| {
        if (canSpawn(io, path)) return path;
    }

    const common_paths = [_][]const u8{
        "/usr/bin/stockfish",
        "/usr/local/bin/stockfish",
        "/opt/homebrew/bin/stockfish",
        "/usr/games/stockfish",
        "/snap/bin/stockfish",
    };

    for (common_paths) |path| {
        if (canSpawn(io, path)) return path;
    }

    // Fall back to PATH resolution
    if (canSpawn(io, "stockfish")) return "stockfish";

    return EngineError.StockfishNotFound;
}

fn canSpawn(io: Io, path: []const u8) bool {
    var child = process.spawn(io, .{
        .argv = &.{path},
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
    }) catch return false;
    child.kill(io);
    return true;
}

pub fn eloToDepth(elo: u16) u8 {
    const clamped: u16 = std.math.clamp(elo, 200, 2800);
    if (clamped <= 600) return 1;
    if (clamped <= 1000) return 2;
    if (clamped <= 1400) return 4;
    if (clamped <= 1800) return 8;
    if (clamped <= 2200) return 12;
    if (clamped <= 2500) return 16;
    return 20;
}

pub fn eloToMovetime(elo: u16) u16 {
    const clamped: u16 = std.math.clamp(elo, 200, 2800);
    if (clamped <= 400) return 25;
    if (clamped <= 800) return 50;
    if (clamped <= 1200) return 120;
    if (clamped <= 1600) return 500;
    if (clamped <= 2000) return 2000;
    if (clamped <= 2400) return 5000;
    return 12000;
}

// Skill Level (0..20) <-> approximate CCRL Elo. Skill Level (not UCI_Elo) is the
// strength lever Stockfish exposes; UCI_Elo floors at ~1320, so the genuine-beginner
// floor is added app-side (see the move handicap). The Elo here is shown beside the
// dial and written to the save filename, and feeds eloToDepth/eloToMovetime.
const skill_elo_table = [_]u16{
    1320, 1418, 1517, 1615, 1714, 1812, 1911, 2009, 2108, 2206,
    2305, 2403, 2502, 2600, 2698, 2797, 2895, 2994, 3092, 3191,
    3500,
};

pub fn skillToElo(skill: u8) u16 {
    return skill_elo_table[@min(skill, 20)];
}

pub fn eloToSkill(elo: u16) u8 {
    var best: u8 = 0;
    var best_diff: u32 = std.math.maxInt(u32);
    for (skill_elo_table, 0..) |e, s| {
        const diff: u32 = if (e > elo) e - elo else elo - e;
        if (diff < best_diff) {
            best_diff = diff;
            best = @intCast(s);
        }
    }
    return best;
}

// --- Beginner move handicap ---
// Stockfish at Skill Level 0 still plays ~club strength, below which no UCI option
// reaches. The lowest skill levels therefore occasionally substitute a uniformly
// random legal move for the engine's pick. ponytail: uniform random is the floor
// lever; swap for a blunder-weighted pick only if calibration shows it feels erratic.
const handicap_table = [_]u8{ 80, 55, 35, 18 }; // percent, by skill 0..3; 0 above.

pub fn handicapRate(skill: u8) u8 {
    return if (skill < handicap_table.len) handicap_table[skill] else 0;
}

pub fn shouldHandicap(skill: u8, rng: std.Random) bool {
    const rate = handicapRate(skill);
    if (rate == 0) return false;
    return rng.uintLessThan(u8, 100) < rate;
}

pub fn pickHandicapMove(board: *const Board, rng: std.Random) ?Move {
    const legal = chess.legalMoves(board);
    if (legal.len == 0) return null;
    return legal.moves[rng.uintLessThan(usize, legal.len)];
}

// --- Tests ---

test "parseBestMove: standard move" {
    try std.testing.expectEqualStrings("e2e4", parseBestMove("bestmove e2e4 ponder d7d5").?);
}

test "parseBestMove: promotion move" {
    try std.testing.expectEqualStrings("e7e8q", parseBestMove("bestmove e7e8q").?);
}

test "parseBestMove: no move after bestmove" {
    try std.testing.expectEqual(@as(?[]const u8, null), parseBestMove("bestmove "));
}

test "parseBestMove: not a bestmove line" {
    try std.testing.expectEqual(@as(?[]const u8, null), parseBestMove("info depth 10"));
}

test "parseBestMove: empty line" {
    try std.testing.expectEqual(@as(?[]const u8, null), parseBestMove(""));
}

test "parseBestMove: bestmove with no trailing content" {
    try std.testing.expectEqualStrings("d2d4", parseBestMove("bestmove d2d4").?);
}

test "parseBestMove: castling notation" {
    try std.testing.expectEqualStrings("e1g1", parseBestMove("bestmove e1g1").?);
}

test "parseInfoLine: depth and score" {
    var result = Analysis{ .eval = .{ .cp = 0 }, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 12 seldepth 15 score cp 35 nodes 12345 pv e2e4 e7e5", &result);
    try std.testing.expectEqual(@as(u16, 12), result.depth);
    try std.testing.expectEqual(Eval{ .cp = 35 }, result.eval);
    try std.testing.expectEqualStrings("e2e4 e7e5", result.principal_variation);
}

test "parseInfoLine: negative score" {
    var result = Analysis{ .eval = .{ .cp = 0 }, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 8 score cp -150 pv d7d5", &result);
    try std.testing.expectEqual(Eval{ .cp = -150 }, result.eval);
}

test "parseInfoLine: forced mate parses as mate, not 0.00" {
    var result = Analysis{ .eval = .{ .cp = 0 }, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 20 score mate 3 pv h5f7", &result);
    try std.testing.expectEqual(Eval{ .mate = 3 }, result.eval);
    try std.testing.expect(result.eval.toCp() > 1000);
}

test "parseInfoLine: getting mated parses as negative mate" {
    var result = Analysis{ .eval = .{ .cp = 0 }, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 18 score mate -2 pv g1h1", &result);
    try std.testing.expectEqual(Eval{ .mate = -2 }, result.eval);
    try std.testing.expect(result.eval.toCp() < -1000);
}

test "parseInfoLine: info without score" {
    var result = Analysis{ .eval = .{ .cp = 0 }, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 5 seldepth 5 nodes 100", &result);
    try std.testing.expectEqual(@as(u16, 5), result.depth);
    try std.testing.expectEqual(Eval{ .cp = 0 }, result.eval);
}

test "parseInfoLine: empty info" {
    var result = Analysis{ .eval = .{ .cp = 0 }, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info string ", &result);
    try std.testing.expectEqual(@as(u16, 0), result.depth);
}

test "eloToDepth: at 200 returns depth 1" {
    try std.testing.expectEqual(@as(u8, 1), eloToDepth(200));
}

test "eloToDepth: at 2800 returns depth 20" {
    try std.testing.expectEqual(@as(u8, 20), eloToDepth(2800));
}

test "eloToDepth: at 1500 returns depth 8" {
    try std.testing.expectEqual(@as(u8, 8), eloToDepth(1500));
}

test "eloToDepth: below minimum clamps" {
    try std.testing.expectEqual(@as(u8, 1), eloToDepth(100));
}

test "eloToDepth: above maximum clamps" {
    try std.testing.expectEqual(@as(u8, 20), eloToDepth(3000));
}

test "eloToMovetime: at 200 returns 25ms" {
    try std.testing.expectEqual(@as(u16, 25), eloToMovetime(200));
}

test "eloToMovetime: at 2800 returns 12000ms" {
    try std.testing.expectEqual(@as(u16, 12000), eloToMovetime(2800));
}

test "eloToMovetime: at 1000 returns 120ms" {
    try std.testing.expectEqual(@as(u16, 120), eloToMovetime(1000));
}

test "skillToElo: floor, ceiling, and clamp" {
    try std.testing.expectEqual(@as(u16, 1320), skillToElo(0));
    try std.testing.expectEqual(@as(u16, 3500), skillToElo(20));
    try std.testing.expectEqual(@as(u16, 3500), skillToElo(99));
}

test "skillToElo: monotonically non-decreasing" {
    var prev: u16 = 0;
    var s: u8 = 0;
    while (s <= 20) : (s += 1) {
        const e = skillToElo(s);
        try std.testing.expect(e >= prev);
        prev = e;
    }
}

test "eloToSkill: anchors and legacy clamp" {
    try std.testing.expectEqual(@as(u8, 0), eloToSkill(1320));
    try std.testing.expectEqual(@as(u8, 0), eloToSkill(1200));
    try std.testing.expectEqual(@as(u8, 20), eloToSkill(3500));
}

test "eloToSkill: round-trips skillToElo" {
    var s: u8 = 0;
    while (s <= 20) : (s += 1) {
        try std.testing.expectEqual(s, eloToSkill(skillToElo(s)));
    }
}

test "Move.fromUci: promotion round-trip" {
    const m = Move.fromUci("e7e8q").?;
    try std.testing.expectEqual(chess.MoveType.promotion, m.move_type);
    try std.testing.expectEqual(chess.PieceType.queen, m.promotion_piece.?);
    var buf: [5]u8 = undefined;
    try std.testing.expectEqualStrings("e7e8q", m.toUci(&buf));
}

test "Move.fromUci: knight promotion" {
    const m = Move.fromUci("a7a8n").?;
    try std.testing.expectEqual(chess.PieceType.knight, m.promotion_piece.?);
}

test "findStockfish: function signature compiles" {
    // findStockfish requires a real Io from main(); we can only verify it compiles.
    // Integration testing with Stockfish is done via the game loop.
    try std.testing.expect(@TypeOf(findStockfish) == fn (Io, ?[]const u8) EngineError![]const u8);
}

test "handicapRate: high at floor, zero above threshold, non-increasing" {
    try std.testing.expect(handicapRate(0) > 0);
    try std.testing.expectEqual(@as(u8, 0), handicapRate(20));
    var prev: u8 = 255;
    var s: u8 = 0;
    while (s <= 20) : (s += 1) {
        try std.testing.expect(handicapRate(s) <= prev);
        prev = handicapRate(s);
    }
}

test "shouldHandicap: never fires above threshold" {
    var prng = std.Random.DefaultPrng.init(0xABCDEF);
    const rng = prng.random();
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        try std.testing.expect(!shouldHandicap(20, rng));
    }
}

test "shouldHandicap: fires often at skill 0" {
    var prng = std.Random.DefaultPrng.init(0xABCDEF);
    const rng = prng.random();
    var fires: usize = 0;
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        if (shouldHandicap(0, rng)) fires += 1;
    }
    try std.testing.expect(fires > 500);
}

test "pickHandicapMove: returns a legal move (initial position)" {
    var prng = std.Random.DefaultPrng.init(0x1234);
    const rng = prng.random();
    const board = Board.initial;
    const m = pickHandicapMove(&board, rng).?;
    const legal = chess.legalMoves(&board);
    var found = false;
    for (legal.moves[0..legal.len]) |lm| {
        if (lm.eql(m)) found = true;
    }
    try std.testing.expect(found);
}

test "pickHandicapMove: single legal move returns it" {
    var prng = std.Random.DefaultPrng.init(0x9999);
    const rng = prng.random();
    // White Ka1, Black Kc1 + Rb8: the only legal move is Ka1-a2.
    const board = Board.fromFen("1r6/8/8/8/8/8/8/K1k5 w - - 0 1").?;
    const legal = chess.legalMoves(&board);
    try std.testing.expectEqual(@as(usize, 1), legal.len);
    const m = pickHandicapMove(&board, rng).?;
    try std.testing.expect(m.eql(legal.moves[0]));
}
