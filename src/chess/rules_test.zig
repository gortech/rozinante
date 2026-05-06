const std = @import("std");
const testing = std.testing;
const rules = @import("rules.zig");
const board_mod = @import("board.zig");
const piece_mod = @import("piece.zig");
const square_mod = @import("square.zig");
const movegen = @import("movegen.zig");

const Board = board_mod.Board;
const Piece = piece_mod.Piece;
const Color = piece_mod.Color;
const Square = square_mod.Square;

fn sq(comptime notation: *const [2]u8) Square {
    return Square.fromAlgebraic(notation) orelse unreachable;
}

// =============================================================================
// Checkmate positions
// =============================================================================

test "checkmate: back rank mate" {
    // Black king on g8, white rook delivers mate on a8 (8th rank),
    // black pawns on f7, g7, h7 block escape, white king far away.
    // Black to move.
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("g8"), .black_king);
    b.setPiece(sq("f7"), .black_pawn);
    b.setPiece(sq("g7"), .black_pawn);
    b.setPiece(sq("h7"), .black_pawn);
    b.setPiece(sq("a8"), .white_rook);
    b.setPiece(sq("a1"), .white_king);

    try testing.expect(rules.isCheckmate(&b));
    try testing.expect(!rules.isStalemate(&b));
    try testing.expect(!rules.isDraw(&b));
}

test "checkmate: scholar's mate position" {
    // White queen on f7 delivering check, supported by bishop on c4.
    // Black king on e8, pieces blocking escape.
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("d8"), .black_queen);
    b.setPiece(sq("f8"), .black_bishop);
    b.setPiece(sq("d7"), .black_pawn);
    b.setPiece(sq("e7"), .black_pawn);
    b.setPiece(sq("f7"), .white_queen);
    b.setPiece(sq("c4"), .white_bishop);
    b.setPiece(sq("e1"), .white_king);

    try testing.expect(rules.isCheckmate(&b));
}

test "checkmate: smothered mate" {
    // Classic smothered mate: knight on f7 checking king on h8,
    // king surrounded by own pieces (Rg8, pawn g7).
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("g8"), .black_rook);
    b.setPiece(sq("g7"), .black_pawn);
    b.setPiece(sq("h7"), .black_pawn);
    b.setPiece(sq("f7"), .white_knight);
    b.setPiece(sq("a1"), .white_king);

    try testing.expect(rules.isCheckmate(&b));
}

test "checkmate: not checkmate when king can escape" {
    // King in check but has escape square
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("a8"), .white_rook);
    b.setPiece(sq("a1"), .white_king);

    // King is in check from rook on a8, but can move to d7, e7, f7, etc.
    try testing.expect(!rules.isCheckmate(&b));
}

test "checkmate: not checkmate when piece can block" {
    // King in check but a piece can interpose
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("d7"), .black_pawn);
    b.setPiece(sq("f7"), .black_pawn);
    b.setPiece(sq("d8"), .black_bishop); // Bishop can potentially block
    b.setPiece(sq("e1"), .white_rook); // Rook checks along e-file
    b.setPiece(sq("a1"), .white_king);

    // King is in check from rook on e1, but the king can move to f8
    try testing.expect(!rules.isCheckmate(&b));
}

test "checkmate produces zero legal moves" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("g8"), .black_king);
    b.setPiece(sq("f7"), .black_pawn);
    b.setPiece(sq("g7"), .black_pawn);
    b.setPiece(sq("h7"), .black_pawn);
    b.setPiece(sq("a8"), .white_rook);
    b.setPiece(sq("a1"), .white_king);

    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 0), moves.len);
    try testing.expect(rules.isCheckmate(&b));
}

// =============================================================================
// Stalemate positions
// =============================================================================

test "stalemate: king in corner with queen" {
    // White king on f6, white queen on g6, black king on h8.
    // Black to move — no legal moves, not in check.
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("f6"), .white_king);
    b.setPiece(sq("g6"), .white_queen);

    try testing.expect(rules.isStalemate(&b));
    try testing.expect(!rules.isCheckmate(&b));
    try testing.expect(rules.isDraw(&b));
}

test "stalemate: king trapped by king and rook" {
    // Black king on a8, white king on a6, white rook on b1.
    // Black to move — king cannot move anywhere.
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("a6"), .white_king);
    b.setPiece(sq("b1"), .white_rook);

    // a8: blocked. b8: attacked by rook on b1. a7: attacked by white king on a6.
    // b7: attacked by white king on a6.
    try testing.expect(rules.isStalemate(&b));
}

test "stalemate: not stalemate when in check" {
    // King in check with no legal moves is checkmate, not stalemate
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("g8"), .black_king);
    b.setPiece(sq("f7"), .black_pawn);
    b.setPiece(sq("g7"), .black_pawn);
    b.setPiece(sq("h7"), .black_pawn);
    b.setPiece(sq("a8"), .white_rook);
    b.setPiece(sq("a1"), .white_king);

    try testing.expect(!rules.isStalemate(&b));
    try testing.expect(rules.isCheckmate(&b));
}

test "stalemate: not stalemate when moves available" {
    // Starting position — plenty of legal moves
    const b = Board.initial;
    try testing.expect(!rules.isStalemate(&b));
}

// =============================================================================
// Fifty-move rule
// =============================================================================

test "fifty-move rule: halfmove_clock at 99 is not triggered" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.halfmove_clock = 99;

    try testing.expect(!rules.isFiftyMoveRule(&b));
}

test "fifty-move rule: halfmove_clock at 100 is triggered" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.halfmove_clock = 100;

    try testing.expect(rules.isFiftyMoveRule(&b));
    try testing.expect(rules.isDraw(&b));
}

test "fifty-move rule: halfmove_clock at 150 is triggered" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.halfmove_clock = 150;

    try testing.expect(rules.isFiftyMoveRule(&b));
}

test "fifty-move rule: halfmove_clock at 0 is not triggered" {
    const b = Board.initial;
    try testing.expect(!rules.isFiftyMoveRule(&b));
}

// =============================================================================
// Insufficient material
// =============================================================================

test "insufficient material: K vs K" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);

    try testing.expect(rules.isInsufficientMaterial(&b));
    try testing.expect(rules.isDraw(&b));
}

test "insufficient material: K+B vs K (white bishop)" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("c4"), .white_bishop);
    b.setPiece(sq("e8"), .black_king);

    try testing.expect(rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+B vs K (black bishop)" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("f6"), .black_bishop);

    try testing.expect(rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+N vs K (white knight)" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("b3"), .white_knight);
    b.setPiece(sq("e8"), .black_king);

    try testing.expect(rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+N vs K (black knight)" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("g6"), .black_knight);

    try testing.expect(rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+B vs K+B same-color squares (both on light)" {
    // Light squares: file_index + rank_index is odd (since @truncate gives LSB)
    // c1: file=2, rank=0 -> 2+0=2 -> LSB=0 (dark)
    // f4: file=5, rank=3 -> 5+3=8 -> LSB=0 (dark)
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("c1"), .white_bishop); // dark square
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("f4"), .black_bishop); // dark square

    try testing.expect(rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+B vs K+B different-color squares" {
    // c1: file=2, rank=0 -> 2+0=2 -> LSB=0 (dark)
    // c4: file=2, rank=3 -> 2+3=5 -> LSB=1 (light)
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("c1"), .white_bishop); // dark square
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("c4"), .black_bishop); // light square

    try testing.expect(!rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+N vs K+N is NOT insufficient" {
    // Two knights can theoretically cooperate to mate (helpmate)
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("b3"), .white_knight);
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("g6"), .black_knight);

    try testing.expect(!rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+R vs K is NOT insufficient" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a1"), .white_rook);
    b.setPiece(sq("e8"), .black_king);

    try testing.expect(!rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+Q vs K is NOT insufficient" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("d1"), .white_queen);
    b.setPiece(sq("e8"), .black_king);

    try testing.expect(!rules.isInsufficientMaterial(&b));
}

test "insufficient material: K+P vs K is NOT insufficient" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e2"), .white_pawn);
    b.setPiece(sq("e8"), .black_king);

    try testing.expect(!rules.isInsufficientMaterial(&b));
}

test "insufficient material: starting position is NOT insufficient" {
    const b = Board.initial;
    try testing.expect(!rules.isInsufficientMaterial(&b));
}

// =============================================================================
// isDraw
// =============================================================================

test "isDraw: stalemate is a draw" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("f6"), .white_king);
    b.setPiece(sq("g6"), .white_queen);

    try testing.expect(rules.isDraw(&b));
}

test "isDraw: fifty-move rule is a draw" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.halfmove_clock = 100;

    try testing.expect(rules.isDraw(&b));
}

test "isDraw: insufficient material is a draw" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);

    try testing.expect(rules.isDraw(&b));
}

test "isDraw: checkmate is not a draw" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("g8"), .black_king);
    b.setPiece(sq("f7"), .black_pawn);
    b.setPiece(sq("g7"), .black_pawn);
    b.setPiece(sq("h7"), .black_pawn);
    b.setPiece(sq("a8"), .white_rook);
    b.setPiece(sq("a1"), .white_king);

    try testing.expect(!rules.isDraw(&b));
    try testing.expect(rules.isCheckmate(&b));
}

test "isDraw: starting position is not a draw" {
    const b = Board.initial;
    try testing.expect(!rules.isDraw(&b));
}

// =============================================================================
// Check detection (via movegen.isInCheck, verify from rules perspective)
// =============================================================================

test "check: king attacked by rook" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);

    try testing.expect(movegen.isInCheck(&b, .white));
    try testing.expect(!rules.isCheckmate(&b));
}

test "check: king attacked by bishop" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h4"), .black_bishop);
    b.setPiece(sq("a8"), .black_king);

    try testing.expect(movegen.isInCheck(&b, .white));
}

test "check: king attacked by knight" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("f3"), .black_knight);
    b.setPiece(sq("a8"), .black_king);

    try testing.expect(movegen.isInCheck(&b, .white));
}

test "check: king attacked by pawn" {
    var b = Board.empty();
    b.setPiece(sq("e4"), .white_king);
    b.setPiece(sq("d5"), .black_pawn);
    b.setPiece(sq("a8"), .black_king);

    try testing.expect(movegen.isInCheck(&b, .white));
}

test "check: king attacked by queen" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_queen);
    b.setPiece(sq("a8"), .black_king);

    try testing.expect(movegen.isInCheck(&b, .white));
}

test "check: king NOT in check (no false positives)" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("h8"), .black_rook);
    b.setPiece(sq("a3"), .black_bishop);
    b.setPiece(sq("c5"), .black_knight);

    try testing.expect(!movegen.isInCheck(&b, .white));
}
