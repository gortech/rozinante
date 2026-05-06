const std = @import("std");

pub const File = enum(u3) {
    a = 0,
    b = 1,
    c = 2,
    d = 3,
    e = 4,
    f = 5,
    g = 6,
    h = 7,

    pub fn fromChar(c: u8) ?File {
        if (c >= 'a' and c <= 'h') {
            return @enumFromInt(@as(u3, @intCast(c - 'a')));
        }
        return null;
    }

    pub fn toChar(self: File) u8 {
        return 'a' + @as(u8, @intFromEnum(self));
    }

    pub fn index(self: File) u3 {
        return @intFromEnum(self);
    }
};

pub const Rank = enum(u3) {
    @"1" = 0,
    @"2" = 1,
    @"3" = 2,
    @"4" = 3,
    @"5" = 4,
    @"6" = 5,
    @"7" = 6,
    @"8" = 7,

    pub fn fromChar(c: u8) ?Rank {
        if (c >= '1' and c <= '8') {
            return @enumFromInt(@as(u3, @intCast(c - '1')));
        }
        return null;
    }

    pub fn toChar(self: Rank) u8 {
        return '1' + @as(u8, @intFromEnum(self));
    }

    pub fn index(self: Rank) u3 {
        return @intFromEnum(self);
    }
};

pub const Square = struct {
    file: File,
    rank: Rank,

    pub fn init(file: File, rank: Rank) Square {
        return .{ .file = file, .rank = rank };
    }

    pub fn fromAlgebraic(notation: []const u8) ?Square {
        if (notation.len != 2) return null;
        const f = File.fromChar(notation[0]) orelse return null;
        const r = Rank.fromChar(notation[1]) orelse return null;
        return init(f, r);
    }

    pub fn toAlgebraic(self: Square, buf: *[2]u8) []const u8 {
        buf[0] = self.file.toChar();
        buf[1] = self.rank.toChar();
        return buf[0..2];
    }

    pub fn toIndex(self: Square) u6 {
        return @as(u6, self.rank.index()) * 8 + @as(u6, self.file.index());
    }

    pub fn fromIndex(idx: u6) Square {
        return .{
            .file = @enumFromInt(@as(u3, @truncate(idx))),
            .rank = @enumFromInt(@as(u3, @truncate(idx >> 3))),
        };
    }

    pub fn eql(self: Square, other: Square) bool {
        return self.file == other.file and self.rank == other.rank;
    }
};

test "File.fromChar and toChar round-trip" {
    const files = "abcdefgh";
    for (files) |c| {
        const f = File.fromChar(c).?;
        try std.testing.expectEqual(c, f.toChar());
    }
}

test "File.fromChar returns null for invalid" {
    try std.testing.expectEqual(@as(?File, null), File.fromChar('i'));
    try std.testing.expectEqual(@as(?File, null), File.fromChar('A'));
    try std.testing.expectEqual(@as(?File, null), File.fromChar('1'));
}

test "Rank.fromChar and toChar round-trip" {
    const ranks = "12345678";
    for (ranks) |c| {
        const r = Rank.fromChar(c).?;
        try std.testing.expectEqual(c, r.toChar());
    }
}

test "Rank.fromChar returns null for invalid" {
    try std.testing.expectEqual(@as(?Rank, null), Rank.fromChar('0'));
    try std.testing.expectEqual(@as(?Rank, null), Rank.fromChar('9'));
    try std.testing.expectEqual(@as(?Rank, null), Rank.fromChar('a'));
}

test "Square.fromAlgebraic round-trips" {
    const cases = [_][]const u8{ "a1", "e4", "h8", "d7", "b2" };
    for (cases) |notation| {
        const sq = Square.fromAlgebraic(notation).?;
        var buf: [2]u8 = undefined;
        const result = sq.toAlgebraic(&buf);
        try std.testing.expectEqualStrings(notation, result);
    }
}

test "Square.fromAlgebraic rejects invalid" {
    try std.testing.expectEqual(@as(?Square, null), Square.fromAlgebraic(""));
    try std.testing.expectEqual(@as(?Square, null), Square.fromAlgebraic("a"));
    try std.testing.expectEqual(@as(?Square, null), Square.fromAlgebraic("a9"));
    try std.testing.expectEqual(@as(?Square, null), Square.fromAlgebraic("i1"));
    try std.testing.expectEqual(@as(?Square, null), Square.fromAlgebraic("a1b"));
}

test "Square.toIndex and fromIndex round-trip all 64 squares" {
    for (0..64) |i| {
        const idx: u6 = @intCast(i);
        const sq = Square.fromIndex(idx);
        try std.testing.expectEqual(idx, sq.toIndex());
    }
}

test "Square.toIndex known values" {
    const a1 = Square.fromAlgebraic("a1").?;
    try std.testing.expectEqual(@as(u6, 0), a1.toIndex());

    const h8 = Square.fromAlgebraic("h8").?;
    try std.testing.expectEqual(@as(u6, 63), h8.toIndex());

    const e1 = Square.fromAlgebraic("e1").?;
    try std.testing.expectEqual(@as(u6, 4), e1.toIndex());
}

test "Square.eql" {
    const e4a = Square.fromAlgebraic("e4").?;
    const e4b = Square.init(.e, .@"4");
    const d4 = Square.fromAlgebraic("d4").?;
    try std.testing.expect(e4a.eql(e4b));
    try std.testing.expect(!e4a.eql(d4));
}
