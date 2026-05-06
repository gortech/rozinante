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

    pub fn toFen(self: *const Board, buf: *[128]u8) []const u8 {
        var pos: usize = 0;
        var rank_i: u4 = 8;
        while (rank_i > 0) {
            rank_i -= 1;
            var empty_count: u8 = 0;
            for (0..8) |file_i| {
                const idx: u6 = @intCast(@as(usize, rank_i) * 8 + file_i);
                const p = self.squares[idx];
                if (p == .empty) {
                    empty_count += 1;
                } else {
                    if (empty_count > 0) {
                        buf[pos] = '0' + empty_count;
                        pos += 1;
                        empty_count = 0;
                    }
                    buf[pos] = p.toChar();
                    pos += 1;
                }
            }
            if (empty_count > 0) {
                buf[pos] = '0' + empty_count;
                pos += 1;
            }
            if (rank_i > 0) {
                buf[pos] = '/';
                pos += 1;
            }
        }

        buf[pos] = ' ';
        pos += 1;
        buf[pos] = if (self.active_color == .white) 'w' else 'b';
        pos += 1;

        buf[pos] = ' ';
        pos += 1;
        const cr = self.castling_rights;
        if (!cr.white_kingside and !cr.white_queenside and !cr.black_kingside and !cr.black_queenside) {
            buf[pos] = '-';
            pos += 1;
        } else {
            if (cr.white_kingside) {
                buf[pos] = 'K';
                pos += 1;
            }
            if (cr.white_queenside) {
                buf[pos] = 'Q';
                pos += 1;
            }
            if (cr.black_kingside) {
                buf[pos] = 'k';
                pos += 1;
            }
            if (cr.black_queenside) {
                buf[pos] = 'q';
                pos += 1;
            }
        }

        buf[pos] = ' ';
        pos += 1;
        if (self.en_passant_square) |ep| {
            buf[pos] = ep.file.toChar();
            pos += 1;
            buf[pos] = ep.rank.toChar();
            pos += 1;
        } else {
            buf[pos] = '-';
            pos += 1;
        }

        buf[pos] = ' ';
        pos += 1;
        pos += formatU16(buf[pos..], self.halfmove_clock);

        buf[pos] = ' ';
        pos += 1;
        pos += formatU16(buf[pos..], self.fullmove_number);

        return buf[0..pos];
    }

    pub fn fromFen(fen: []const u8) ?Board {
        var b = Board.empty();
        var i: usize = 0;

        var rank_i: u4 = 8;
        while (rank_i > 0) {
            rank_i -= 1;
            var file_i: u4 = 0;
            while (file_i < 8) {
                if (i >= fen.len) return null;
                const c = fen[i];
                i += 1;
                if (c >= '1' and c <= '8') {
                    file_i += @intCast(c - '0');
                } else {
                    const p = Piece.fromChar(c) orelse return null;
                    const idx: u6 = @intCast(@as(usize, rank_i) * 8 + @as(usize, file_i));
                    b.squares[idx] = p;
                    file_i += 1;
                }
            }
            if (rank_i > 0) {
                if (i >= fen.len or fen[i] != '/') return null;
                i += 1;
            }
        }

        if (i >= fen.len or fen[i] != ' ') return null;
        i += 1;

        if (i >= fen.len) return null;
        b.active_color = switch (fen[i]) {
            'w' => .white,
            'b' => .black,
            else => return null,
        };
        i += 1;

        if (i >= fen.len or fen[i] != ' ') return null;
        i += 1;

        if (i >= fen.len) return null;
        if (fen[i] == '-') {
            i += 1;
        } else {
            while (i < fen.len and fen[i] != ' ') {
                switch (fen[i]) {
                    'K' => b.castling_rights.white_kingside = true,
                    'Q' => b.castling_rights.white_queenside = true,
                    'k' => b.castling_rights.black_kingside = true,
                    'q' => b.castling_rights.black_queenside = true,
                    else => return null,
                }
                i += 1;
            }
        }

        if (i >= fen.len or fen[i] != ' ') return null;
        i += 1;

        if (i >= fen.len) return null;
        if (fen[i] == '-') {
            b.en_passant_square = null;
            i += 1;
        } else {
            if (i + 1 >= fen.len) return null;
            b.en_passant_square = Square.fromAlgebraic(fen[i .. i + 2]);
            if (b.en_passant_square == null) return null;
            i += 2;
        }

        if (i >= fen.len or fen[i] != ' ') return null;
        i += 1;

        var halfmove: u16 = 0;
        while (i < fen.len and fen[i] >= '0' and fen[i] <= '9') {
            halfmove = halfmove * 10 + @as(u16, fen[i] - '0');
            i += 1;
        }
        b.halfmove_clock = halfmove;

        if (i >= fen.len or fen[i] != ' ') return null;
        i += 1;

        var fullmove: u16 = 0;
        while (i < fen.len and fen[i] >= '0' and fen[i] <= '9') {
            fullmove = fullmove * 10 + @as(u16, fen[i] - '0');
            i += 1;
        }
        b.fullmove_number = fullmove;

        return b;
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

fn formatU16(buf: []u8, val: u16) usize {
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    var v = val;
    var tmp: [5]u8 = undefined;
    var len: usize = 0;
    while (v > 0) {
        tmp[len] = @intCast(v % 10 + '0');
        v /= 10;
        len += 1;
    }
    for (0..len) |j| {
        buf[j] = tmp[len - 1 - j];
    }
    return len;
}

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

test "Board.toFen starting position" {
    const b = Board.initial;
    var buf: [128]u8 = undefined;
    const fen = b.toFen(&buf);
    try std.testing.expectEqualStrings("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", fen);
}

test "Board.fromFen round-trips starting position" {
    const b = Board.fromFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") orelse
        return error.TestUnexpectedResult;
    var buf: [128]u8 = undefined;
    const fen = b.toFen(&buf);
    try std.testing.expectEqualStrings("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", fen);
}

test "Board.fromFen with en passant and partial castling" {
    const b = Board.fromFen("rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2") orelse
        return error.TestUnexpectedResult;
    try std.testing.expectEqual(Color.white, b.active_color);
    try std.testing.expect(b.castling_rights.white_kingside);
    const ep = b.en_passant_square orelse return error.TestUnexpectedResult;
    try std.testing.expect(ep.eql(Square.fromAlgebraic("e6").?));
    try std.testing.expectEqual(@as(u16, 0), b.halfmove_clock);
    try std.testing.expectEqual(@as(u16, 2), b.fullmove_number);
}

test "Board.fromFen rejects invalid" {
    try std.testing.expectEqual(@as(?Board, null), Board.fromFen(""));
    try std.testing.expectEqual(@as(?Board, null), Board.fromFen("invalid"));
}

test "Board.toFen empty board" {
    const b = Board.empty();
    var buf: [128]u8 = undefined;
    const fen = b.toFen(&buf);
    try std.testing.expectEqualStrings("8/8/8/8/8/8/8/8 w - - 0 1", fen);
}
