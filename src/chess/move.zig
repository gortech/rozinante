const std = @import("std");
const piece_mod = @import("piece.zig");
const square_mod = @import("square.zig");

const PieceType = piece_mod.PieceType;
const Square = square_mod.Square;

pub const MoveType = enum(u2) {
    normal = 0,
    castle = 1,
    en_passant = 2,
    promotion = 3,
};

pub const Move = struct {
    from: Square,
    to: Square,
    move_type: MoveType = .normal,
    promotion_piece: ?PieceType = null,

    pub fn init(from: Square, to: Square) Move {
        return .{ .from = from, .to = to };
    }

    pub fn initPromotion(from: Square, to: Square, promotion: PieceType) Move {
        return .{
            .from = from,
            .to = to,
            .move_type = .promotion,
            .promotion_piece = promotion,
        };
    }

    pub fn initCastle(from: Square, to: Square) Move {
        return .{
            .from = from,
            .to = to,
            .move_type = .castle,
        };
    }

    pub fn initEnPassant(from: Square, to: Square) Move {
        return .{
            .from = from,
            .to = to,
            .move_type = .en_passant,
        };
    }

    pub fn toUci(self: Move, buf: *[5]u8) []const u8 {
        var from_buf: [2]u8 = undefined;
        var to_buf: [2]u8 = undefined;
        const from_str = self.from.toAlgebraic(&from_buf);
        const to_str = self.to.toAlgebraic(&to_buf);
        buf[0] = from_str[0];
        buf[1] = from_str[1];
        buf[2] = to_str[0];
        buf[3] = to_str[1];
        if (self.promotion_piece) |promo| {
            buf[4] = switch (promo) {
                .queen => 'q',
                .rook => 'r',
                .bishop => 'b',
                .knight => 'n',
                else => unreachable,
            };
            return buf[0..5];
        }
        return buf[0..4];
    }

    pub fn fromUci(uci: []const u8) ?Move {
        if (uci.len < 4 or uci.len > 5) return null;
        const from = Square.fromAlgebraic(uci[0..2]) orelse return null;
        const to = Square.fromAlgebraic(uci[2..4]) orelse return null;
        if (uci.len == 5) {
            const promo: PieceType = switch (uci[4]) {
                'q' => .queen,
                'r' => .rook,
                'b' => .bishop,
                'n' => .knight,
                else => return null,
            };
            return initPromotion(from, to, promo);
        }
        return init(from, to);
    }

    pub fn eql(self: Move, other: Move) bool {
        return self.from.eql(other.from) and
            self.to.eql(other.to) and
            self.move_type == other.move_type and
            self.promotion_piece == other.promotion_piece;
    }
};

test "Move.init creates normal move" {
    const e2 = Square.fromAlgebraic("e2").?;
    const e4 = Square.fromAlgebraic("e4").?;
    const m = Move.init(e2, e4);
    try std.testing.expectEqual(MoveType.normal, m.move_type);
    try std.testing.expectEqual(@as(?PieceType, null), m.promotion_piece);
    try std.testing.expect(m.from.eql(e2));
    try std.testing.expect(m.to.eql(e4));
}

test "Move.initPromotion" {
    const e7 = Square.fromAlgebraic("e7").?;
    const e8 = Square.fromAlgebraic("e8").?;
    const m = Move.initPromotion(e7, e8, .queen);
    try std.testing.expectEqual(MoveType.promotion, m.move_type);
    try std.testing.expectEqual(PieceType.queen, m.promotion_piece.?);
}

test "Move.initCastle" {
    const e1 = Square.fromAlgebraic("e1").?;
    const g1 = Square.fromAlgebraic("g1").?;
    const m = Move.initCastle(e1, g1);
    try std.testing.expectEqual(MoveType.castle, m.move_type);
}

test "Move.initEnPassant" {
    const e5 = Square.fromAlgebraic("e5").?;
    const d6 = Square.fromAlgebraic("d6").?;
    const m = Move.initEnPassant(e5, d6);
    try std.testing.expectEqual(MoveType.en_passant, m.move_type);
}

test "Move.toUci normal move" {
    const m = Move.init(
        Square.fromAlgebraic("e2").?,
        Square.fromAlgebraic("e4").?,
    );
    var buf: [5]u8 = undefined;
    try std.testing.expectEqualStrings("e2e4", m.toUci(&buf));
}

test "Move.toUci promotion" {
    const m = Move.initPromotion(
        Square.fromAlgebraic("e7").?,
        Square.fromAlgebraic("e8").?,
        .queen,
    );
    var buf: [5]u8 = undefined;
    try std.testing.expectEqualStrings("e7e8q", m.toUci(&buf));
}

test "Move.fromUci round-trips" {
    const cases = [_][]const u8{ "e2e4", "d7d5", "e1g1", "e7e8q", "a7a8n" };
    for (cases) |uci| {
        const m = Move.fromUci(uci).?;
        var buf: [5]u8 = undefined;
        const result = m.toUci(&buf);
        try std.testing.expectEqualStrings(uci, result);
    }
}

test "Move.fromUci rejects invalid" {
    try std.testing.expectEqual(@as(?Move, null), Move.fromUci(""));
    try std.testing.expectEqual(@as(?Move, null), Move.fromUci("e2"));
    try std.testing.expectEqual(@as(?Move, null), Move.fromUci("e2e4x"));
    try std.testing.expectEqual(@as(?Move, null), Move.fromUci("e2e9"));
    try std.testing.expectEqual(@as(?Move, null), Move.fromUci("e2e4p"));
}

test "Move.eql" {
    const a = Move.init(Square.fromAlgebraic("e2").?, Square.fromAlgebraic("e4").?);
    const b = Move.init(Square.fromAlgebraic("e2").?, Square.fromAlgebraic("e4").?);
    const c = Move.init(Square.fromAlgebraic("d2").?, Square.fromAlgebraic("d4").?);
    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));
}
