const std = @import("std");

pub const Color = enum(u1) {
    white = 0,
    black = 1,

    pub fn opponent(self: Color) Color {
        return switch (self) {
            .white => .black,
            .black => .white,
        };
    }
};

pub const PieceType = enum(u3) {
    pawn = 0,
    knight = 1,
    bishop = 2,
    rook = 3,
    queen = 4,
    king = 5,
};

pub const Piece = enum(u4) {
    white_pawn = 0,
    white_knight = 1,
    white_bishop = 2,
    white_rook = 3,
    white_queen = 4,
    white_king = 5,
    black_pawn = 8,
    black_knight = 9,
    black_bishop = 10,
    black_rook = 11,
    black_queen = 12,
    black_king = 13,
    empty = 15,

    pub fn init(c: Color, pt: PieceType) Piece {
        const color_bits: u4 = @as(u4, @intFromEnum(c)) << 3;
        const type_bits: u4 = @intFromEnum(pt);
        return @enumFromInt(color_bits | type_bits);
    }

    pub fn color(self: Piece) ?Color {
        if (self == .empty) return null;
        return @enumFromInt(@as(u1, @truncate(@intFromEnum(self) >> 3)));
    }

    pub fn pieceType(self: Piece) ?PieceType {
        if (self == .empty) return null;
        return @enumFromInt(@as(u3, @truncate(@intFromEnum(self))));
    }

    pub fn isWhite(self: Piece) bool {
        const c = self.color() orelse return false;
        return c == .white;
    }

    pub fn isBlack(self: Piece) bool {
        const c = self.color() orelse return false;
        return c == .black;
    }

    pub fn isEmpty(self: Piece) bool {
        return self == .empty;
    }

    pub fn toChar(self: Piece) u8 {
        return switch (self) {
            .white_pawn => 'P',
            .white_knight => 'N',
            .white_bishop => 'B',
            .white_rook => 'R',
            .white_queen => 'Q',
            .white_king => 'K',
            .black_pawn => 'p',
            .black_knight => 'n',
            .black_bishop => 'b',
            .black_rook => 'r',
            .black_queen => 'q',
            .black_king => 'k',
            .empty => '.',
        };
    }

    pub fn fromChar(c: u8) ?Piece {
        return switch (c) {
            'P' => .white_pawn,
            'N' => .white_knight,
            'B' => .white_bishop,
            'R' => .white_rook,
            'Q' => .white_queen,
            'K' => .white_king,
            'p' => .black_pawn,
            'n' => .black_knight,
            'b' => .black_bishop,
            'r' => .black_rook,
            'q' => .black_queen,
            'k' => .black_king,
            else => null,
        };
    }
};

test "Piece.init creates correct pieces" {
    try std.testing.expectEqual(Piece.white_pawn, Piece.init(.white, .pawn));
    try std.testing.expectEqual(Piece.black_king, Piece.init(.black, .king));
    try std.testing.expectEqual(Piece.white_queen, Piece.init(.white, .queen));
    try std.testing.expectEqual(Piece.black_rook, Piece.init(.black, .rook));
}

test "Piece.color returns correct color" {
    try std.testing.expectEqual(Color.white, Piece.white_pawn.color().?);
    try std.testing.expectEqual(Color.black, Piece.black_king.color().?);
    try std.testing.expectEqual(Color.white, Piece.white_queen.color().?);
    try std.testing.expectEqual(Color.black, Piece.black_bishop.color().?);
    try std.testing.expectEqual(@as(?Color, null), Piece.empty.color());
}

test "Piece.pieceType returns correct type" {
    try std.testing.expectEqual(PieceType.pawn, Piece.white_pawn.pieceType().?);
    try std.testing.expectEqual(PieceType.king, Piece.black_king.pieceType().?);
    try std.testing.expectEqual(PieceType.queen, Piece.white_queen.pieceType().?);
    try std.testing.expectEqual(@as(?PieceType, null), Piece.empty.pieceType());
}

test "Piece.isWhite and isBlack" {
    try std.testing.expect(Piece.white_pawn.isWhite());
    try std.testing.expect(!Piece.white_pawn.isBlack());
    try std.testing.expect(Piece.black_king.isBlack());
    try std.testing.expect(!Piece.black_king.isWhite());
    try std.testing.expect(!Piece.empty.isWhite());
    try std.testing.expect(!Piece.empty.isBlack());
}

test "Piece.toChar and fromChar round-trip" {
    const pieces = [_]Piece{
        .white_pawn, .white_knight, .white_bishop,
        .white_rook, .white_queen,  .white_king,
        .black_pawn, .black_knight, .black_bishop,
        .black_rook, .black_queen,  .black_king,
    };
    for (pieces) |p| {
        try std.testing.expectEqual(p, Piece.fromChar(p.toChar()).?);
    }
}

test "Piece.fromChar returns null for invalid" {
    try std.testing.expectEqual(@as(?Piece, null), Piece.fromChar('x'));
    try std.testing.expectEqual(@as(?Piece, null), Piece.fromChar('1'));
}

test "Color.opponent" {
    try std.testing.expectEqual(Color.black, Color.white.opponent());
    try std.testing.expectEqual(Color.white, Color.black.opponent());
}
