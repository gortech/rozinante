const std = @import("std");
const chess = @import("chess.zig");
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

pub const Analysis = struct {
    eval_cp: i32,
    best_move: ?Move,
    principal_variation: []const u8,
    depth: u16,
};

pub const Engine = struct {
    child: process.Child,
    io: Io,
    elo: u16,
    is_ready: bool,
    stockfish_path: []const u8,

    stdin_buf: [4096]u8,
    stdout_buf: [4096]u8,
    stdin_writer: File.Writer,
    stdout_reader: File.Reader,

    pub fn init(io: Io, stockfish_path: []const u8, elo: u16) !Engine {
        const child = try process.spawn(io, .{
            .argv = &.{stockfish_path},
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .ignore,
        });

        var engine = Engine{
            .child = child,
            .io = io,
            .elo = elo,
            .is_ready = false,
            .stockfish_path = stockfish_path,
            .stdin_buf = undefined,
            .stdout_buf = undefined,
            .stdin_writer = undefined,
            .stdout_reader = undefined,
        };

        engine.stdin_writer = File.Writer.initStreaming(child.stdin.?, io, &engine.stdin_buf);
        engine.stdout_reader = File.Reader.initStreaming(child.stdout.?, io, &engine.stdout_buf);

        try engine.uciHandshake();

        log.info("engine initialized: path={s} elo={d}", .{ stockfish_path, elo });

        return engine;
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

        var elo_buf: [64]u8 = undefined;
        const elo_cmd = std.fmt.bufPrint(&elo_buf, "setoption name UCI_LimitStrength value true", .{}) catch unreachable;
        try self.sendCommand(elo_cmd);

        var elo_val_buf: [64]u8 = undefined;
        const elo_val_cmd = std.fmt.bufPrint(&elo_val_buf, "setoption name UCI_Elo value {d}", .{self.elo}) catch unreachable;
        try self.sendCommand(elo_val_cmd);

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

    pub fn getMove(self: *Engine, board: *const Board, movetime_ms: u32) !Move {
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

        var line_buf: [4096]u8 = undefined;
        var attempts: u32 = 0;
        while (attempts < 5000) : (attempts += 1) {
            const line = try self.readLine(&line_buf);
            if (parseBestMove(line)) |uci_move| {
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
            .eval_cp = 0,
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

    pub fn newGame(self: *Engine) !void {
        try self.sendCommand("ucinewgame");
        try self.waitReady();
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
        self.stdin_writer = File.Writer.initStreaming(child.stdin.?, self.io, &self.stdin_buf);
        self.stdout_reader = File.Reader.initStreaming(child.stdout.?, self.io, &self.stdout_buf);
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
                result.eval_cp = std.fmt.parseInt(i32, val, 10) catch continue;
            }
        } else if (std.mem.eql(u8, token, "pv")) {
            if (iter.rest().len > 0) {
                result.principal_variation = iter.rest();
            }
            return;
        }
    }
}

pub fn findStockfish(io: Io) EngineError![]const u8 {
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

pub fn eloToMovetime(elo: u16) u32 {
    const clamped_elo: i32 = @intCast(std.math.clamp(elo, 800, 2500));
    const result: i32 = 1000 + @divTrunc((clamped_elo - 800) * 2000, 1700);
    return std.math.clamp(@as(u32, @intCast(result)), 500, 5000);
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
    var result = Analysis{ .eval_cp = 0, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 12 seldepth 15 score cp 35 nodes 12345 pv e2e4 e7e5", &result);
    try std.testing.expectEqual(@as(u16, 12), result.depth);
    try std.testing.expectEqual(@as(i32, 35), result.eval_cp);
    try std.testing.expectEqualStrings("e2e4 e7e5", result.principal_variation);
}

test "parseInfoLine: negative score" {
    var result = Analysis{ .eval_cp = 0, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 8 score cp -150 pv d7d5", &result);
    try std.testing.expectEqual(@as(i32, -150), result.eval_cp);
}

test "parseInfoLine: info without score" {
    var result = Analysis{ .eval_cp = 0, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info depth 5 seldepth 5 nodes 100", &result);
    try std.testing.expectEqual(@as(u16, 5), result.depth);
    try std.testing.expectEqual(@as(i32, 0), result.eval_cp);
}

test "parseInfoLine: empty info" {
    var result = Analysis{ .eval_cp = 0, .best_move = null, .principal_variation = "", .depth = 0 };
    parseInfoLine("info string ", &result);
    try std.testing.expectEqual(@as(u16, 0), result.depth);
}

test "eloToMovetime: at 800 (minimum)" {
    try std.testing.expectEqual(@as(u32, 1000), eloToMovetime(800));
}

test "eloToMovetime: at 2500 (maximum)" {
    try std.testing.expectEqual(@as(u32, 3000), eloToMovetime(2500));
}

test "eloToMovetime: at 1650 (midpoint)" {
    const result = eloToMovetime(1650);
    try std.testing.expect(result >= 1900 and result <= 2100);
}

test "eloToMovetime: below minimum clamps to 800" {
    try std.testing.expectEqual(@as(u32, 1000), eloToMovetime(400));
}

test "eloToMovetime: above maximum clamps to 2500" {
    try std.testing.expectEqual(@as(u32, 3000), eloToMovetime(3000));
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
    try std.testing.expect(@TypeOf(findStockfish) == fn (Io) EngineError![]const u8);
}
