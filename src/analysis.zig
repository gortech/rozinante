//! Post-game analysis: evaluation representation, move rating, and per-game
//! aggregates. Pure — depends only on `chess`. No engine, no I/O, no allocator
//! (matches the `src/chess/` convention: stack arrays, table-driven, allocator-free).
//!
//! U1 seeds `Eval` + `toCp` (the single comparison currency); U2 adds the rating
//! model (`Tier`, `MoveAnalysis`, `GameAnalysis`, `rateMove`, `aggregate`,
//! `computeKeyMoments`).

const std = @import("std");
const chess = @import("chess.zig");

/// A position evaluation from the side-to-move's perspective, as reported by the
/// engine. `cp` is centipawns; `mate` is signed mate-in-N (positive = the side to
/// move delivers mate in N plies/moves, negative = the side to move gets mated).
///
/// Keeping mate distinct from cp is what lets a missed or allowed forced mate rate
/// as a blunder and top the key-moment ranking instead of parsing as 0.00 (R3/AE4).
pub const Eval = union(enum) {
    cp: i32,
    mate: i32,

    /// Centipawn magnitude a mate saturates to before the mate distance is
    /// subtracted. Chosen to dominate any centipawn value the engine ever reports
    /// (Stockfish emits `mate` rather than cp once a forced mate exists, so real cp
    /// never approaches this), so a mate always outranks material in comparisons.
    pub const mate_base: i32 = 100_000;

    /// Collapse to one signed centipawn currency for comparison and ranking.
    /// A mate maps to ±(mate_base − |N|): a closer mate dominates a farther one, and
    /// either sign dominates any cp value. The only comparison currency the rating
    /// model uses. Overflow-safe: widens to i64 so a garbage `mate` value can't trap.
    pub fn toCp(self: Eval) i32 {
        return switch (self) {
            .cp => |c| c,
            .mate => |n| blk: {
                const n64: i64 = n;
                const dist: i64 = if (n64 < 0) -n64 else n64;
                const clamped: i64 = @min(dist, @as(i64, mate_base) - 1);
                const mag: i32 = @intCast(@as(i64, mate_base) - clamped);
                break :blk if (n < 0) -mag else mag;
            },
        };
    }
};

test "toCp: cp passes through" {
    try std.testing.expectEqual(@as(i32, 35), (Eval{ .cp = 35 }).toCp());
    try std.testing.expectEqual(@as(i32, -150), (Eval{ .cp = -150 }).toCp());
    try std.testing.expectEqual(@as(i32, 0), (Eval{ .cp = 0 }).toCp());
}

test "toCp: mate dominates any realistic cp, sign preserved" {
    try std.testing.expect((Eval{ .mate = 1 }).toCp() > 50_000);
    try std.testing.expect((Eval{ .mate = -1 }).toCp() < -50_000);
    // A mate outranks even a huge material advantage.
    try std.testing.expect((Eval{ .mate = 5 }).toCp() > (Eval{ .cp = 9_000 }).toCp());
}

test "toCp: closer mate dominates farther mate" {
    try std.testing.expect((Eval{ .mate = 1 }).toCp() > (Eval{ .mate = 5 }).toCp());
    try std.testing.expect((Eval{ .mate = -1 }).toCp() < (Eval{ .mate = -5 }).toCp());
}

test "toCp: garbage mate distance does not overflow" {
    // Defensive: a bogus huge mate value clamps instead of trapping.
    _ = (Eval{ .mate = std.math.maxInt(i32) }).toCp();
    _ = (Eval{ .mate = std.math.minInt(i32) }).toCp();
}
