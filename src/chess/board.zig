const std = @import("std");
const piece_mod = @import("piece.zig");
const square_mod = @import("square.zig");

const Piece = piece_mod.Piece;
const Color = piece_mod.Color;
const PieceType = piece_mod.PieceType;
const Square = square_mod.Square;
const File = square_mod.File;
const Rank = square_mod.Rank;

pub const CastlingRights = packed struct(u4) {
    white_kingside: bool = false,
    white_queenside: bool = false,
    black_kingside: bool = false,
    black_queenside: bool = false,

    pub const none: CastlingRights = .{};
    pub const all: CastlingRights = .{
        .white_kingside = true,
        .white_queenside = true,
        .black_kingside = true,
        .black_queenside = true,
    };
};

pub const Board = struct {
    squares: [64]Piece,
    active_color: Color,
    castling_rights: CastlingRights,
    en_passant_square: ?Square,
    halfmove_clock: u16,
    fullmove_number: u16,

    pub const initial = initStartingPosition();

    pub fn empty() Board {
        return .{
            .squares = [_]Piece{.empty} ** 64,
            .active_color = .white,
            .castling_rights = .none,
            .en_passant_square = null,
            .halfmove_clock = 0,
            .fullmove_number = 1,
        };
    }

    pub fn pieceAt(self: *const Board, sq: Square) Piece {
        return self.squares[sq.toIndex()];
    }

    pub fn setPiece(self: *Board, sq: Square, p: Piece) void {
        self.squares[sq.toIndex()] = p;
    }

    fn initStartingPosition() Board {
        var b = Board.empty();
        b.castling_rights = .all;

        const back_rank = [_]PieceType{ .rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook };
        for (back_rank, 0..) |pt, file_idx| {
            const f: u3 = @intCast(file_idx);
            b.squares[@as(u6, 0) * 8 + @as(u6, f)] = Piece.init(.white, pt);
            b.squares[@as(u6, 1) * 8 + @as(u6, f)] = Piece.init(.white, .pawn);
            b.squares[@as(u6, 6) * 8 + @as(u6, f)] = Piece.init(.black, .pawn);
            b.squares[@as(u6, 7) * 8 + @as(u6, f)] = Piece.init(.black, pt);
        }

        return b;
    }
};

test "Board.initial has correct starting position" {
    const b = Board.initial;

    try std.testing.expectEqual(Color.white, b.active_color);
    try std.testing.expectEqual(@as(u16, 0), b.halfmove_clock);
    try std.testing.expectEqual(@as(u16, 1), b.fullmove_number);
    try std.testing.expectEqual(@as(?Square, null), b.en_passant_square);
    try std.testing.expect(b.castling_rights.white_kingside);
    try std.testing.expect(b.castling_rights.white_queenside);
    try std.testing.expect(b.castling_rights.black_kingside);
    try std.testing.expect(b.castling_rights.black_queenside);

    try std.testing.expectEqual(Piece.white_rook, b.pieceAt(Square.fromAlgebraic("a1").?));
    try std.testing.expectEqual(Piece.white_knight, b.pieceAt(Square.fromAlgebraic("b1").?));
    try std.testing.expectEqual(Piece.white_bishop, b.pieceAt(Square.fromAlgebraic("c1").?));
    try std.testing.expectEqual(Piece.white_queen, b.pieceAt(Square.fromAlgebraic("d1").?));
    try std.testing.expectEqual(Piece.white_king, b.pieceAt(Square.fromAlgebraic("e1").?));
    try std.testing.expectEqual(Piece.white_bishop, b.pieceAt(Square.fromAlgebraic("f1").?));
    try std.testing.expectEqual(Piece.white_knight, b.pieceAt(Square.fromAlgebraic("g1").?));
    try std.testing.expectEqual(Piece.white_rook, b.pieceAt(Square.fromAlgebraic("h1").?));

    const files = "abcdefgh";
    for (files) |fc| {
        var name_buf: [2]u8 = .{ fc, '2' };
        const sq = Square.fromAlgebraic(&name_buf).?;
        try std.testing.expectEqual(Piece.white_pawn, b.pieceAt(sq));
    }

    for (files) |fc| {
        var name_buf: [2]u8 = .{ fc, '7' };
        const sq = Square.fromAlgebraic(&name_buf).?;
        try std.testing.expectEqual(Piece.black_pawn, b.pieceAt(sq));
    }

    try std.testing.expectEqual(Piece.black_rook, b.pieceAt(Square.fromAlgebraic("a8").?));
    try std.testing.expectEqual(Piece.black_king, b.pieceAt(Square.fromAlgebraic("e8").?));
    try std.testing.expectEqual(Piece.black_queen, b.pieceAt(Square.fromAlgebraic("d8").?));

    for (files) |fc| {
        for ("3456") |rc| {
            var name_buf: [2]u8 = .{ fc, rc };
            const sq = Square.fromAlgebraic(&name_buf).?;
            try std.testing.expectEqual(Piece.empty, b.pieceAt(sq));
        }
    }
}

test "Board.empty has no pieces" {
    const b = Board.empty();
    for (0..64) |i| {
        try std.testing.expectEqual(Piece.empty, b.squares[i]);
    }
    try std.testing.expectEqual(Color.white, b.active_color);
    try std.testing.expect(!b.castling_rights.white_kingside);
}

test "Board.setPiece and pieceAt" {
    var b = Board.empty();
    const sq = Square.fromAlgebraic("e4").?;
    b.setPiece(sq, .white_queen);
    try std.testing.expectEqual(Piece.white_queen, b.pieceAt(sq));
}
