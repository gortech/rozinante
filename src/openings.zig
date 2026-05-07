const std = @import("std");

pub const Opening = struct {
    eco: []const u8,
    name: []const u8,
    uci_moves: []const u8,
    epd: []const u8,
};

const max_entries = 4096;

pub const OpeningBook = struct {
    entries: [max_entries]Opening,
    count: usize,

    pub fn init() OpeningBook {
        const data = @embedFile("data/openings.tsv");
        var book: OpeningBook = undefined;
        book.count = 0;

        var lines = std.mem.splitScalar(u8, data, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var cols = std.mem.splitScalar(u8, line, '\t');
            const eco = cols.next() orelse continue;
            const name = cols.next() orelse continue;
            const uci_moves = cols.next() orelse continue;
            const epd = cols.next() orelse continue;

            if (book.count >= max_entries) break;
            book.entries[book.count] = .{
                .eco = eco,
                .name = name,
                .uci_moves = uci_moves,
                .epd = epd,
            };
            book.count += 1;
        }

        return book;
    }

    pub fn findByMoves(self: *const OpeningBook, uci_sequence: []const u8) ?Opening {
        var best: ?Opening = null;
        var best_len: usize = 0;

        for (self.entries[0..self.count]) |entry| {
            if (isUciPrefix(entry.uci_moves, uci_sequence) and entry.uci_moves.len > best_len) {
                best = entry;
                best_len = entry.uci_moves.len;
            }
        }

        return best;
    }

    pub fn findByPosition(self: *const OpeningBook, epd: []const u8) ?Opening {
        for (self.entries[0..self.count]) |entry| {
            if (std.mem.eql(u8, entry.epd, epd)) return entry;
        }
        return null;
    }

    pub fn find(self: *const OpeningBook, uci_sequence: []const u8, epd: []const u8) ?Opening {
        return self.findByMoves(uci_sequence) orelse self.findByPosition(epd);
    }
};

fn isUciPrefix(prefix: []const u8, sequence: []const u8) bool {
    if (prefix.len > sequence.len) return false;
    if (!std.mem.startsWith(u8, sequence, prefix)) return false;
    // Must match at a word boundary (exact match or followed by a space)
    if (prefix.len == sequence.len) return true;
    return sequence[prefix.len] == ' ';
}

test "parse openings count" {
    const book = OpeningBook.init();
    try std.testing.expect(book.count > 3000);
}

test "known opening lookup - Ruy Lopez" {
    const book = OpeningBook.init();
    const result = book.findByMoves("e2e4 e7e5 g1f3 b8c6 f1b5");
    try std.testing.expect(result != null);
    const opening = result.?;
    try std.testing.expectEqualStrings("C60", opening.eco);
    try std.testing.expect(std.mem.indexOf(u8, opening.name, "Ruy Lopez") != null);
}

test "longest prefix match" {
    const book = OpeningBook.init();
    // "e2e4 e7e5 g1f3 b8c6" should match a more general opening
    const general = book.findByMoves("e2e4 e7e5 g1f3 b8c6");
    try std.testing.expect(general != null);

    // Adding more moves should get a more specific match
    const specific = book.findByMoves("e2e4 e7e5 g1f3 b8c6 f1b5");
    try std.testing.expect(specific != null);
    try std.testing.expect(specific.?.uci_moves.len >= general.?.uci_moves.len);
}

test "no match returns null" {
    const book = OpeningBook.init();
    const result = book.findByMoves("a1a2");
    try std.testing.expect(result == null);
}

test "empty sequence returns null" {
    const book = OpeningBook.init();
    const result = book.findByMoves("");
    try std.testing.expect(result == null);
}

test "EPD fallback finds position" {
    const book = OpeningBook.init();
    // Use a known EPD from the database — the starting position after 1.e4
    const by_moves = book.findByMoves("e2e4");
    try std.testing.expect(by_moves != null);
    const epd = by_moves.?.epd;

    const by_pos = book.findByPosition(epd);
    try std.testing.expect(by_pos != null);
    try std.testing.expectEqualStrings(by_moves.?.eco, by_pos.?.eco);
}

test "find uses moves first then falls back to EPD" {
    const book = OpeningBook.init();
    const by_moves = book.findByMoves("e2e4");
    try std.testing.expect(by_moves != null);

    // find with valid moves should return the same as findByMoves
    const combined = book.find("e2e4", "");
    try std.testing.expect(combined != null);
    try std.testing.expectEqualStrings(by_moves.?.eco, combined.?.eco);

    // find with no moves should fall back to EPD
    const fallback = book.find("a1a2", by_moves.?.epd);
    try std.testing.expect(fallback != null);
    try std.testing.expectEqualStrings(by_moves.?.eco, fallback.?.eco);
}
