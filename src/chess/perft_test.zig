const std = @import("std");
const testing = std.testing;
const board_mod = @import("board.zig");
const movegen = @import("movegen.zig");
const move_mod = @import("move.zig");
const perft_mod = @import("perft.zig");
const rules = @import("rules.zig");
const square_mod = @import("square.zig");

const Board = board_mod.Board;
const Move = move_mod.Move;
const Square = square_mod.Square;

fn sq(comptime notation: *const [2]u8) Square {
    return Square.fromAlgebraic(notation) orelse unreachable;
}

// --- Perft from starting position ---

test "perft(0) from starting position is 1" {
    const b = Board.initial;
    try testing.expectEqual(@as(u64, 1), perft_mod.perft(&b, 0));
}

test "perft(1) from starting position is 20" {
    const b = Board.initial;
    try testing.expectEqual(@as(u64, 20), perft_mod.perft(&b, 1));
}

test "perft(2) from starting position is 400" {
    const b = Board.initial;
    try testing.expectEqual(@as(u64, 400), perft_mod.perft(&b, 2));
}

test "perft(3) from starting position is 8902" {
    const b = Board.initial;
    try testing.expectEqual(@as(u64, 8902), perft_mod.perft(&b, 3));
}

// --- Perft from Kiwipete position ---

test "perft(1) from Kiwipete is 48" {
    const b = Board.fromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1") orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u64, 48), perft_mod.perft(&b, 1));
}

test "perft(2) from Kiwipete is 2039" {
    const b = Board.fromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1") orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u64, 2039), perft_mod.perft(&b, 2));
}

// --- Perft from position 3 (en passant / promotion edge cases) ---

test "perft(1) from position 3 is 14" {
    const b = Board.fromFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1") orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u64, 14), perft_mod.perft(&b, 1));
}

test "perft(2) from position 3 is 191" {
    const b = Board.fromFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1") orelse
        return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u64, 191), perft_mod.perft(&b, 2));
}

// --- FEN-based position tests after move sequences ---

test "e2e4 produces correct FEN" {
    const b = Board.initial;
    const after = movegen.makeMove(b, Move.init(sq("e2"), sq("e4")));
    var buf: [128]u8 = undefined;
    const fen = after.toFen(&buf);
    try testing.expectEqualStrings("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", fen);
}

test "e2e4 e7e5 produces correct FEN" {
    var b = Board.initial;
    b = movegen.makeMove(b, Move.init(sq("e2"), sq("e4")));
    b = movegen.makeMove(b, Move.init(sq("e7"), sq("e5")));
    var buf: [128]u8 = undefined;
    const fen = b.toFen(&buf);
    try testing.expectEqualStrings("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2", fen);
}

test "castling produces correct FEN" {
    var b = Board.fromFen("r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1") orelse
        return error.TestUnexpectedResult;
    b = movegen.makeMove(b, Move.initCastle(sq("e1"), sq("g1")));
    var buf: [128]u8 = undefined;
    const fen = b.toFen(&buf);
    try testing.expectEqualStrings("r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R4RK1 b kq - 1 1", fen);
}

// --- Move sequence integration tests ---

test "scholar's mate is checkmate" {
    var b = Board.initial;
    b = movegen.makeMove(b, Move.init(sq("e2"), sq("e4")));
    b = movegen.makeMove(b, Move.init(sq("e7"), sq("e5")));
    b = movegen.makeMove(b, Move.init(sq("f1"), sq("c4")));
    b = movegen.makeMove(b, Move.init(sq("b8"), sq("c6")));
    b = movegen.makeMove(b, Move.init(sq("d1"), sq("h5")));
    b = movegen.makeMove(b, Move.init(sq("g8"), sq("f6")));
    b = movegen.makeMove(b, Move.init(sq("h5"), sq("f7")));
    try testing.expect(rules.isCheckmate(&b));
}

test "move sequence preserves legal move count" {
    var b = Board.initial;
    b = movegen.makeMove(b, Move.init(sq("e2"), sq("e4")));
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 20), moves.len);
}

// --- Edge cases ---

test "en passant only valid immediately after double push" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("e5"), .white_pawn);
    b.setPiece(sq("d7"), .black_pawn);
    b.active_color = .black;

    b = movegen.makeMove(b, Move.init(sq("d7"), sq("d5")));
    const ep = b.en_passant_square orelse return error.TestUnexpectedResult;
    try testing.expect(ep.eql(sq("d6")));

    b = movegen.makeMove(b, Move.init(sq("e1"), sq("e2")));
    try testing.expectEqual(@as(?Square, null), b.en_passant_square);
}

test "promotion with check" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a7"), .white_pawn);
    b.setPiece(sq("b8"), .black_king);
    const after = movegen.makeMove(b, Move.initPromotion(sq("a7"), sq("a8"), .queen));
    try testing.expect(movegen.isInCheck(&after, .black));
}

test "promotion with checkmate" {
    var b = Board.empty();
    b.setPiece(sq("h1"), .white_king);
    b.setPiece(sq("g1"), .white_rook);
    b.setPiece(sq("f7"), .white_pawn);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("g8"), .black_rook);
    const after = movegen.makeMove(b, Move.initPromotion(sq("f7"), sq("g8"), .queen));
    try testing.expect(rules.isCheckmate(&after));
}

test "cannot castle out of check" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("e8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    try testing.expect(movegen.isInCheck(&b, .white));
    const moves = movegen.legalMoves(&b);
    for (moves.slice()) |m| {
        try testing.expect(m.move_type != .castle);
    }
}

test "cannot castle through check" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("f8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    const moves = movegen.legalMoves(&b);
    for (moves.slice()) |m| {
        if (m.move_type == .castle and m.to.eql(sq("g1"))) {
            return error.TestUnexpectedResult;
        }
    }
}

test "UCI round-trip through move sequence" {
    var b = Board.initial;
    const uci_moves = [_][]const u8{ "e2e4", "e7e5", "g1f3", "b8c6" };
    for (uci_moves) |uci| {
        const m = Move.fromUci(uci) orelse return error.TestUnexpectedResult;
        b = movegen.makeMove(b, m);
        var buf: [5]u8 = undefined;
        const rt = m.toUci(&buf);
        try testing.expectEqualStrings(uci, rt);
    }
    const moves = movegen.legalMoves(&b);
    try testing.expect(moves.len > 0);
}
