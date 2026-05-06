const std = @import("std");
const testing = std.testing;
const movegen = @import("movegen.zig");
const board_mod = @import("board.zig");
const piece_mod = @import("piece.zig");
const square_mod = @import("square.zig");
const move_mod = @import("move.zig");

const Board = board_mod.Board;
const Piece = piece_mod.Piece;
const PieceType = piece_mod.PieceType;
const Color = piece_mod.Color;
const Square = square_mod.Square;
const Move = move_mod.Move;
const MoveType = move_mod.MoveType;
const MoveList = movegen.MoveList;

fn sq(comptime notation: *const [2]u8) Square {
    return Square.fromAlgebraic(notation) orelse unreachable;
}

fn countMovesFrom(list: *const MoveList, from: Square) usize {
    var n: usize = 0;
    for (list.slice()) |m| {
        if (m.from.eql(from)) n += 1;
    }
    return n;
}

fn containsMove(list: *const MoveList, from: Square, to: Square) bool {
    for (list.slice()) |m| {
        if (m.from.eql(from) and m.to.eql(to)) return true;
    }
    return false;
}

fn containsMoveTyped(list: *const MoveList, from: Square, to: Square, move_type: MoveType) bool {
    for (list.slice()) |m| {
        if (m.from.eql(from) and m.to.eql(to) and m.move_type == move_type) return true;
    }
    return false;
}

// --- Starting position ---

test "starting position has exactly 20 legal moves" {
    const b = Board.initial;
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 20), moves.len);
}

// --- Pawn moves ---

test "pawn single push from non-starting rank" {
    var b = Board.empty();
    b.setPiece(sq("a1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("e4"), .white_pawn);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 1), countMovesFrom(&moves, sq("e4")));
    try testing.expect(containsMove(&moves, sq("e4"), sq("e5")));
}

test "pawn double push from starting rank" {
    var b = Board.empty();
    b.setPiece(sq("a1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("e2"), .white_pawn);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 2), countMovesFrom(&moves, sq("e2")));
    try testing.expect(containsMove(&moves, sq("e2"), sq("e3")));
    try testing.expect(containsMove(&moves, sq("e2"), sq("e4")));
}

test "pawn captures diagonally" {
    var b = Board.empty();
    b.setPiece(sq("a1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("d4"), .white_pawn);
    b.setPiece(sq("c5"), .black_pawn);
    b.setPiece(sq("e5"), .black_pawn);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 3), countMovesFrom(&moves, sq("d4")));
    try testing.expect(containsMove(&moves, sq("d4"), sq("d5")));
    try testing.expect(containsMove(&moves, sq("d4"), sq("c5")));
    try testing.expect(containsMove(&moves, sq("d4"), sq("e5")));
}

test "pawn blocked cannot push" {
    var b = Board.empty();
    b.setPiece(sq("a1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("e2"), .white_pawn);
    b.setPiece(sq("e3"), .black_pawn);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 0), countMovesFrom(&moves, sq("e2")));
}

test "black pawn moves forward correctly" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("a1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("e7"), .black_pawn);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 2), countMovesFrom(&moves, sq("e7")));
    try testing.expect(containsMove(&moves, sq("e7"), sq("e6")));
    try testing.expect(containsMove(&moves, sq("e7"), sq("e5")));
}

// --- Knight moves ---

test "knight center has 8 moves" {
    var b = Board.empty();
    b.setPiece(sq("a1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("d4"), .white_knight);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 8), countMovesFrom(&moves, sq("d4")));
}

test "knight corner has 2 moves" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("a1"), .white_knight);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 2), countMovesFrom(&moves, sq("a1")));
    try testing.expect(containsMove(&moves, sq("a1"), sq("b3")));
    try testing.expect(containsMove(&moves, sq("a1"), sq("c2")));
}

test "knight edge has 4 moves" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h8"), .black_king);
    b.setPiece(sq("a4"), .white_knight);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 4), countMovesFrom(&moves, sq("a4")));
}

// --- Bishop moves ---

test "bishop center has 13 moves" {
    var b = Board.empty();
    b.setPiece(sq("a2"), .white_king);
    b.setPiece(sq("h1"), .black_king);
    b.setPiece(sq("d4"), .white_bishop);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 13), countMovesFrom(&moves, sq("d4")));
}

// --- Rook moves ---

test "rook center has 14 moves" {
    var b = Board.empty();
    b.setPiece(sq("a2"), .white_king);
    b.setPiece(sq("h1"), .black_king);
    b.setPiece(sq("d4"), .white_rook);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 14), countMovesFrom(&moves, sq("d4")));
}

// --- Queen moves ---

test "queen center has 27 moves" {
    var b = Board.empty();
    b.setPiece(sq("a2"), .white_king);
    b.setPiece(sq("h1"), .black_king);
    b.setPiece(sq("d4"), .white_queen);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 27), countMovesFrom(&moves, sq("d4")));
}

// --- King moves ---

test "king center has 8 moves" {
    var b = Board.empty();
    b.setPiece(sq("d4"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 8), countMovesFrom(&moves, sq("d4")));
}

test "king cannot move into check" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("f8"), .black_rook);
    const moves = movegen.legalMoves(&b);
    // f1 and f2 are attacked by the rook on f8, king can't go there
    try testing.expect(!containsMove(&moves, sq("e1"), sq("f1")));
    try testing.expect(!containsMove(&moves, sq("e1"), sq("f2")));
    // d1 and d2 are safe
    try testing.expect(containsMove(&moves, sq("e1"), sq("d1")));
    try testing.expect(containsMove(&moves, sq("e1"), sq("d2")));
}

// --- Pin detection ---

test "pinned piece restricted to pin line" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e4"), .white_rook);
    b.setPiece(sq("e8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);
    const moves = movegen.legalMoves(&b);
    // Rook on e4 pinned along e-file: can only move to e2, e3, e5, e6, e7, e8
    try testing.expectEqual(@as(usize, 6), countMovesFrom(&moves, sq("e4")));
}

// --- isSquareAttacked ---

test "isSquareAttacked by pawn" {
    var b = Board.empty();
    b.setPiece(sq("d4"), .white_pawn);
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    try testing.expect(movegen.isSquareAttacked(&b, sq("c5"), .white));
    try testing.expect(movegen.isSquareAttacked(&b, sq("e5"), .white));
    try testing.expect(!movegen.isSquareAttacked(&b, sq("d5"), .white));
}

test "isSquareAttacked by knight" {
    var b = Board.empty();
    b.setPiece(sq("d4"), .black_knight);
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    try testing.expect(movegen.isSquareAttacked(&b, sq("c2"), .black));
    try testing.expect(movegen.isSquareAttacked(&b, sq("f5"), .black));
    try testing.expect(!movegen.isSquareAttacked(&b, sq("d5"), .black));
}

test "isSquareAttacked by sliding pieces" {
    var b = Board.empty();
    b.setPiece(sq("d4"), .white_queen);
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    try testing.expect(movegen.isSquareAttacked(&b, sq("g7"), .white));
    try testing.expect(movegen.isSquareAttacked(&b, sq("d8"), .white));
    // Blocked by friendly piece
    b.setPiece(sq("d6"), .white_pawn);
    try testing.expect(!movegen.isSquareAttacked(&b, sq("d8"), .white));
}

// --- isInCheck ---

test "isInCheck detects check" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);
    try testing.expect(movegen.isInCheck(&b, .white));
    try testing.expect(!movegen.isInCheck(&b, .black));
}

// --- makeMove ---

test "makeMove applies basic move" {
    const b = Board.initial;
    const m = Move.init(sq("e2"), sq("e4"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("e2")));
    try testing.expectEqual(Piece.white_pawn, after.pieceAt(sq("e4")));
    try testing.expectEqual(Color.black, after.active_color);
}

test "makeMove sets en passant on double pawn push" {
    const b = Board.initial;
    const m = Move.init(sq("e2"), sq("e4"));
    const after = movegen.makeMove(b, m);
    const ep = after.en_passant_square orelse return error.TestUnexpectedResult;
    try testing.expect(ep.eql(sq("e3")));
}

test "makeMove clears en passant on non-double push" {
    var b = Board.initial;
    b.en_passant_square = sq("e3");
    const m = Move.init(sq("d2"), sq("d3"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(@as(?Square, null), after.en_passant_square);
}

test "makeMove revokes castling on king move" {
    var b = Board.initial;
    b.setPiece(sq("e2"), .empty);
    const m = Move.init(sq("e1"), sq("e2"));
    const after = movegen.makeMove(b, m);
    try testing.expect(!after.castling_rights.white_kingside);
    try testing.expect(!after.castling_rights.white_queenside);
    try testing.expect(after.castling_rights.black_kingside);
    try testing.expect(after.castling_rights.black_queenside);
}

test "makeMove revokes castling on rook move" {
    var b = Board.initial;
    b.setPiece(sq("b1"), .empty);
    b.setPiece(sq("c1"), .empty);
    b.setPiece(sq("d1"), .empty);
    const m = Move.init(sq("a1"), sq("d1"));
    const after = movegen.makeMove(b, m);
    try testing.expect(after.castling_rights.white_kingside);
    try testing.expect(!after.castling_rights.white_queenside);
}

test "makeMove resets halfmove clock on pawn move" {
    var b = Board.initial;
    b.halfmove_clock = 10;
    const m = Move.init(sq("e2"), sq("e4"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(@as(u16, 0), after.halfmove_clock);
}

test "makeMove increments halfmove clock on quiet move" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("b1"), .white_knight);
    b.halfmove_clock = 5;
    const m = Move.init(sq("b1"), sq("c3"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(@as(u16, 6), after.halfmove_clock);
}

test "makeMove increments fullmove number after black" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.fullmove_number = 1;
    const m = Move.init(sq("e8"), sq("d8"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(@as(u16, 2), after.fullmove_number);
}

// --- En passant ---

test "en passant capture generated for white" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("e5"), .white_pawn);
    b.setPiece(sq("d5"), .black_pawn);
    b.en_passant_square = sq("d6");
    const moves = movegen.legalMoves(&b);
    try testing.expect(containsMoveTyped(&moves, sq("e5"), sq("d6"), .en_passant));
}

test "en passant capture generated for black" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("d4"), .black_pawn);
    b.setPiece(sq("e4"), .white_pawn);
    b.en_passant_square = sq("e3");
    const moves = movegen.legalMoves(&b);
    try testing.expect(containsMoveTyped(&moves, sq("d4"), sq("e3"), .en_passant));
}

test "en passant capture removes captured pawn" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("e5"), .white_pawn);
    b.setPiece(sq("d5"), .black_pawn);
    b.en_passant_square = sq("d6");
    const m = Move.initEnPassant(sq("e5"), sq("d6"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(Piece.white_pawn, after.pieceAt(sq("d6")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("e5")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("d5")));
}

test "en passant not generated when no ep square set" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("e5"), .white_pawn);
    b.setPiece(sq("d5"), .black_pawn);
    const moves = movegen.legalMoves(&b);
    try testing.expect(!containsMoveTyped(&moves, sq("e5"), sq("d6"), .en_passant));
}

// --- Castling move generation ---

test "white kingside castling generated" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(containsMoveTyped(&moves, sq("e1"), sq("g1"), .castle));
}

test "white queenside castling generated" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a1"), .white_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_queenside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(containsMoveTyped(&moves, sq("e1"), sq("c1"), .castle));
}

test "black kingside castling generated" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("h8"), .black_rook);
    b.castling_rights.black_kingside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(containsMoveTyped(&moves, sq("e8"), sq("g8"), .castle));
}

test "black queenside castling generated" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("a8"), .black_rook);
    b.castling_rights.black_queenside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(containsMoveTyped(&moves, sq("e8"), sq("c8"), .castle));
}

// --- Castling execution ---

test "white kingside castling moves king and rook" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    const m = Move.initCastle(sq("e1"), sq("g1"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(Piece.white_king, after.pieceAt(sq("g1")));
    try testing.expectEqual(Piece.white_rook, after.pieceAt(sq("f1")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("e1")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("h1")));
}

test "white queenside castling moves king and rook" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a1"), .white_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_queenside = true;
    const m = Move.initCastle(sq("e1"), sq("c1"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(Piece.white_king, after.pieceAt(sq("c1")));
    try testing.expectEqual(Piece.white_rook, after.pieceAt(sq("d1")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("e1")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("a1")));
}

test "black kingside castling moves king and rook" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("h8"), .black_rook);
    b.castling_rights.black_kingside = true;
    const m = Move.initCastle(sq("e8"), sq("g8"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(Piece.black_king, after.pieceAt(sq("g8")));
    try testing.expectEqual(Piece.black_rook, after.pieceAt(sq("f8")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("e8")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("h8")));
}

test "black queenside castling moves king and rook" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("e8"), .black_king);
    b.setPiece(sq("a8"), .black_rook);
    b.castling_rights.black_queenside = true;
    const m = Move.initCastle(sq("e8"), sq("c8"));
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(Piece.black_king, after.pieceAt(sq("c8")));
    try testing.expectEqual(Piece.black_rook, after.pieceAt(sq("d8")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("e8")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("a8")));
}

// --- Castling blocked ---

test "castling blocked by piece between king and rook" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("f1"), .white_bishop);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(!containsMoveTyped(&moves, sq("e1"), sq("g1"), .castle));
}

test "queenside castling blocked by piece on b-file" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a1"), .white_rook);
    b.setPiece(sq("b1"), .white_knight);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_queenside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(!containsMoveTyped(&moves, sq("e1"), sq("c1"), .castle));
}

test "castling blocked when king passes through attacked square" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("f8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(!containsMoveTyped(&moves, sq("e1"), sq("g1"), .castle));
}

test "castling blocked when king lands on attacked square" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("g8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(!containsMoveTyped(&moves, sq("e1"), sq("g1"), .castle));
}

test "castling blocked when king is in check" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("e8"), .black_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    const moves = movegen.legalMoves(&b);
    try testing.expect(!containsMoveTyped(&moves, sq("e1"), sq("g1"), .castle));
}

// --- Castling rights revocation ---

test "castling rights revoked after castling" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("a1"), .white_rook);
    b.setPiece(sq("a8"), .black_king);
    b.castling_rights.white_kingside = true;
    b.castling_rights.white_queenside = true;
    const m = Move.initCastle(sq("e1"), sq("g1"));
    const after = movegen.makeMove(b, m);
    try testing.expect(!after.castling_rights.white_kingside);
    try testing.expect(!after.castling_rights.white_queenside);
}

test "castling rights revoked when rook captured" {
    var b = Board.empty();
    b.active_color = .black;
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("h1"), .white_rook);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("h8"), .black_rook);
    b.castling_rights.white_kingside = true;
    const m = Move.init(sq("h8"), sq("h1"));
    const after = movegen.makeMove(b, m);
    try testing.expect(!after.castling_rights.white_kingside);
}

// --- Promotion ---

test "promotion generates all four piece types" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("e7"), .white_pawn);
    const moves = movegen.legalMoves(&b);
    var promo_count: usize = 0;
    var has_queen = false;
    var has_rook = false;
    var has_bishop = false;
    var has_knight = false;
    for (moves.slice()) |m| {
        if (m.from.eql(sq("e7")) and m.to.eql(sq("e8")) and m.move_type == .promotion) {
            promo_count += 1;
            if (m.promotion_piece) |pp| {
                switch (pp) {
                    .queen => has_queen = true,
                    .rook => has_rook = true,
                    .bishop => has_bishop = true,
                    .knight => has_knight = true,
                    else => {},
                }
            }
        }
    }
    try testing.expectEqual(@as(usize, 4), promo_count);
    try testing.expect(has_queen);
    try testing.expect(has_rook);
    try testing.expect(has_bishop);
    try testing.expect(has_knight);
}

test "promotion capture generates all four piece types" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("e7"), .white_pawn);
    b.setPiece(sq("d8"), .black_rook);
    const moves = movegen.legalMoves(&b);
    var promo_capture_count: usize = 0;
    for (moves.slice()) |m| {
        if (m.from.eql(sq("e7")) and m.to.eql(sq("d8")) and m.move_type == .promotion) {
            promo_capture_count += 1;
        }
    }
    try testing.expectEqual(@as(usize, 4), promo_capture_count);
}

test "makeMove promotion places correct piece" {
    var b = Board.empty();
    b.setPiece(sq("e1"), .white_king);
    b.setPiece(sq("a8"), .black_king);
    b.setPiece(sq("e7"), .white_pawn);
    const m = Move.initPromotion(sq("e7"), sq("e8"), .knight);
    const after = movegen.makeMove(b, m);
    try testing.expectEqual(Piece.white_knight, after.pieceAt(sq("e8")));
    try testing.expectEqual(Piece.empty, after.pieceAt(sq("e7")));
}

// --- Starting position still correct ---

test "starting position still has exactly 20 legal moves with special moves" {
    const b = Board.initial;
    const moves = movegen.legalMoves(&b);
    try testing.expectEqual(@as(usize, 20), moves.len);
}
