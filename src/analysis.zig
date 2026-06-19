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

/// Mirrors `persistence/pgn.MAX_GAME_MOVES`; analysis is chess-pure and cannot import
/// persistence, so the value is duplicated here. U3 adds a comptime assert in pgn.zig
/// tying them together. A game is at most this many plies.
pub const max_plies = 512;

/// How many biggest-swing plies the key-moment ranking keeps for navigation (R6).
pub const max_key_moments = 16;

/// Current on-disk analysis format version. Bumping it invalidates older cached
/// analysis so it is recomputed rather than trusted (U3 completeness gate).
pub const current_version: u8 = 1;

/// Centipawn-loss tier boundaries, from lichess move classification: an inaccuracy is
/// ≥ 50 cp; a mistake (≥ 100) and a blunder (≥ 300) collapse into `bad` — the headline
/// "blunder/mistake count". Tunable, not invented.
pub const meh_threshold: i32 = 50;
pub const bad_threshold: i32 = 100;

/// Quality of a player's move by centipawn loss vs the engine's best.
pub const Tier = enum { good, meh, bad };

/// Per-ply analysis. `eval`/`best_eval` are engine output (side-to-move POV at the
/// respective position); `cpl` and `tier` are derived. `tier` is set only on the
/// player's plies — engine plies carry `eval`/`cpl` (feeding swings) but `tier == null`.
pub const MoveAnalysis = struct {
    /// Eval of the position AFTER this move (its side-to-move = the mover's opponent).
    eval: Eval,
    /// Engine's best move at the position BEFORE this move; null if unknown.
    best: ?chess.Move,
    /// Eval of that best line, from the mover's perspective (the mover is to move there).
    best_eval: Eval,
    /// Centipawn loss vs best, from the mover's perspective (≥ 0). Computed for every
    /// ply (drives key-moment ranking), not just player plies.
    cpl: i32,
    /// Quality tier — player plies only; null for engine plies.
    tier: ?Tier,
};

/// A full game's analysis. Fixed stack arrays (no allocator), like `MoveList`.
pub const GameAnalysis = struct {
    moves: [max_plies]MoveAnalysis = undefined,
    count: u16 = 0,

    // Player aggregates (filled by `finalize`).
    blunders: u16 = 0,
    inaccuracies: u16 = 0,
    /// Win-probability accuracy in [0, 100]; null when the player made no rated move
    /// (e.g. resigned before moving) — never NaN.
    accuracy: ?f32 = null,

    /// Biggest-swing plies, descending; valid range `key_moments[0..key_moment_count]`.
    key_moments: [max_key_moments]u16 = undefined,
    key_moment_count: u8 = 0,

    // Completeness marker (R11).
    version: u8 = current_version,
    plies_covered: u16 = 0,

    /// Append one ply's analysis. The caller (U4 pass) computes `cpl`/`tier` via
    /// `rateMove` and nulls `tier` for engine plies.
    pub fn append(self: *GameAnalysis, m: MoveAnalysis) void {
        if (self.count >= max_plies) return;
        self.moves[self.count] = m;
        self.count += 1;
    }

    /// Compute the player aggregates, key-moment ranking, and completeness marker from
    /// the appended plies. Call once after the pass fills `moves[0..count]`.
    pub fn finalize(self: *GameAnalysis) void {
        const agg = aggregate(self.moves[0..self.count]);
        self.blunders = agg.blunders;
        self.inaccuracies = agg.inaccuracies;
        self.accuracy = agg.accuracy;
        self.key_moment_count = computeKeyMoments(self.moves[0..self.count], &self.key_moments);
        self.version = current_version;
        self.plies_covered = self.count;
    }
};

/// Result of rating one played move.
pub const RatedMove = struct { cpl: i32, tier: Tier };

/// Rate a played move from the *mover's* perspective (works for either color — the
/// negation flips the opponent-POV after-eval back to the mover).
///   best_eval:  eval of the best line at the position BEFORE the move (mover POV).
///   eval_after: eval of the position AFTER the move (opponent POV).
pub fn rateMove(best_eval: Eval, eval_after: Eval) RatedMove {
    const after_mover: i64 = -@as(i64, eval_after.toCp()); // flip opponent POV → mover POV
    const loss: i64 = @as(i64, best_eval.toCp()) - after_mover;
    const cpl: i32 = if (loss > 0) @intCast(@min(loss, std.math.maxInt(i32))) else 0;
    const tier: Tier = if (cpl >= bad_threshold) .bad else if (cpl >= meh_threshold) .meh else .good;
    return .{ .cpl = cpl, .tier = tier };
}

/// Synthesize the eval of a terminal position reached by the game-ending move. A
/// terminal position has no legal reply, so the engine is never asked — the chess core
/// reports how it ended. Returned from the terminal position's side-to-move POV (the
/// side just checkmated or stalemated), matching `MoveAnalysis.eval`'s "opponent to
/// move" convention. Checkmate → the side to move is mated now (maximal negative mate),
/// so the delivering move rates `good` (cpl ≈ 0); any draw → dead equal (cp 0), so
/// throwing a winning position into stalemate rates `bad`.
pub fn synthesizeTerminalEval(terminal: *const chess.Board) Eval {
    if (chess.isCheckmate(terminal)) return .{ .mate = -1 };
    return .{ .cp = 0 };
}

pub const Aggregate = struct { blunders: u16, inaccuracies: u16, accuracy: ?f32 };

/// lichess win-probability model: centipawns (mover POV) → win% in [0, 100].
/// Saturates cleanly at mate magnitudes (exp under/overflow → 0/100, never NaN).
fn winPercent(cp: i32) f64 {
    const c: f64 = @floatFromInt(cp);
    return 50.0 + 50.0 * (2.0 / (1.0 + @exp(-0.00368208 * c)) - 1.0);
}

/// lichess per-move accuracy% from the win% the move surrendered (both mover POV).
fn moveAccuracy(win_before: f64, win_after: f64) f64 {
    const drop = win_before - win_after; // ≥ 0 when the move loses win%
    const a = 103.1668 * @exp(-0.04354 * drop) - 3.1669;
    return std.math.clamp(a, 0.0, 100.0);
}

/// Player aggregates over the analyzed plies. Counts use `tier` (player plies only);
/// accuracy is the harmonic mean of per-move accuracies, or null when no rated player
/// move exists (guards the empty-set harmonic mean against NaN / divide-by-zero).
pub fn aggregate(moves: []const MoveAnalysis) Aggregate {
    var blunders: u16 = 0;
    var inaccuracies: u16 = 0;
    var inv_sum: f64 = 0; // Σ 1/accuracy_i
    var rated: u32 = 0;
    for (moves) |m| {
        const tier = m.tier orelse continue; // player plies only
        switch (tier) {
            .bad => blunders += 1,
            .meh => inaccuracies += 1,
            .good => {},
        }
        const win_before = winPercent(m.best_eval.toCp());
        const win_after = winPercent(-m.eval.toCp());
        inv_sum += 1.0 / @max(moveAccuracy(win_before, win_after), 0.01);
        rated += 1;
    }
    const accuracy: ?f32 = if (rated == 0)
        null
    else
        @floatCast(@as(f64, @floatFromInt(rated)) / inv_sum);
    return .{ .blunders = blunders, .inaccuracies = inaccuracies, .accuracy = accuracy };
}

/// Rank plies by absolute eval swing (`cpl`) descending and keep the top
/// `max_key_moments` indices in `out`. A mate-related swing dominates (R3 → R6).
/// Returns the number of entries written.
pub fn computeKeyMoments(moves: []const MoveAnalysis, out: *[max_key_moments]u16) u8 {
    const n = moves.len;
    var idx: [max_plies]u16 = undefined;
    for (0..n) |i| idx[i] = @intCast(i);
    std.sort.insertion(u16, idx[0..n], moves, struct {
        fn lessThan(ctx: []const MoveAnalysis, a: u16, b: u16) bool {
            return ctx[a].cpl > ctx[b].cpl; // descending by swing
        }
    }.lessThan);
    const k: u8 = @intCast(@min(n, max_key_moments));
    for (0..k) |i| out[i] = idx[i];
    return k;
}

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

test "rateMove: tier thresholds good/meh/bad" {
    // best_eval = cp N, eval_after = cp 0 (opponent POV) → cpl = N.
    try std.testing.expectEqual(Tier.good, rateMove(.{ .cp = 0 }, .{ .cp = 0 }).tier); // cpl 0
    try std.testing.expectEqual(Tier.good, rateMove(.{ .cp = 49 }, .{ .cp = 0 }).tier); // cpl 49
    try std.testing.expectEqual(Tier.meh, rateMove(.{ .cp = 50 }, .{ .cp = 0 }).tier); // cpl 50
    try std.testing.expectEqual(Tier.meh, rateMove(.{ .cp = 99 }, .{ .cp = 0 }).tier); // cpl 99
    try std.testing.expectEqual(Tier.bad, rateMove(.{ .cp = 100 }, .{ .cp = 0 }).tier); // cpl 100
    try std.testing.expectEqual(Tier.bad, rateMove(.{ .cp = 900 }, .{ .cp = 0 }).tier); // cpl 900
    try std.testing.expectEqual(@as(i32, 900), rateMove(.{ .cp = 900 }, .{ .cp = 0 }).cpl);
}

test "rateMove: AE1 hung queen is bad" {
    // Best held ~level; the move drops a queen → opponent now ~+900 → cpl ≈ 900 → bad.
    const r = rateMove(.{ .cp = 0 }, .{ .cp = 900 });
    try std.testing.expectEqual(Tier.bad, r.tier);
    try std.testing.expectEqual(@as(i32, 900), r.cpl);
}

test "rateMove: AE6 perspective-correct for Black" {
    // Black to move, best line +20 (Black POV). A sound move leaves White at -15
    // (White POV) = Black still ~+15. cpl = 20 - 15 = 5 → good.
    const r = rateMove(.{ .cp = 20 }, .{ .cp = -15 });
    try std.testing.expectEqual(Tier.good, r.tier);
    try std.testing.expectEqual(@as(i32, 5), r.cpl);
}

test "rateMove: AE4 missed forced mate is bad, not roughly even" {
    // Best line mates in 2; player plays a quiet move leaving ~+50cp. Huge cpl → bad.
    const r = rateMove(.{ .mate = 2 }, .{ .cp = -50 });
    try std.testing.expectEqual(Tier.bad, r.tier);
    try std.testing.expect(r.cpl > 10_000);
}

test "synthesizeTerminalEval: checkmate-delivering move rates good (R1)" {
    // Fool's mate: Black has played Qh4#, White (side to move) is checkmated.
    const mated = chess.Board.fromFen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3").?;
    try std.testing.expect(chess.isCheckmate(&mated));
    const after = synthesizeTerminalEval(&mated);
    // The best line before the mating move was itself a mate → cpl ≈ 0 → good.
    try std.testing.expectEqual(Tier.good, rateMove(.{ .mate = 1 }, after).tier);
}

test "synthesizeTerminalEval: stalemating a won position rates bad (R1)" {
    // Black to move, no legal move, not in check → stalemate.
    const stalemate = chess.Board.fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").?;
    try std.testing.expect(chess.isStalemate(&stalemate));
    const after = synthesizeTerminalEval(&stalemate); // cp 0 (draw)
    // The player was completely winning; throwing it into stalemate is a big cpl → bad.
    try std.testing.expectEqual(Tier.bad, rateMove(.{ .cp = 900 }, after).tier);
}

test "aggregate: counts player tiers, ignores engine plies" {
    var ga = GameAnalysis{};
    ga.append(.{ .eval = .{ .cp = -10 }, .best = null, .best_eval = .{ .cp = 10 }, .cpl = 0, .tier = .good });
    ga.append(.{ .eval = .{ .cp = -10 }, .best = null, .best_eval = .{ .cp = 70 }, .cpl = 60, .tier = .meh });
    ga.append(.{ .eval = .{ .cp = 200 }, .best = null, .best_eval = .{ .cp = 50 }, .cpl = 250, .tier = .bad });
    ga.append(.{ .eval = .{ .cp = 0 }, .best = null, .best_eval = .{ .cp = 0 }, .cpl = 0, .tier = null }); // engine
    const agg = aggregate(ga.moves[0..ga.count]);
    try std.testing.expectEqual(@as(u16, 1), agg.blunders);
    try std.testing.expectEqual(@as(u16, 1), agg.inaccuracies);
    try std.testing.expect(agg.accuracy != null);
    try std.testing.expect(agg.accuracy.? >= 0 and agg.accuracy.? <= 100);
}

test "aggregate: zero rated player moves → accuracy null (no NaN)" {
    var ga = GameAnalysis{};
    ga.append(.{ .eval = .{ .cp = 0 }, .best = null, .best_eval = .{ .cp = 0 }, .cpl = 0, .tier = null });
    const agg = aggregate(ga.moves[0..ga.count]);
    try std.testing.expectEqual(@as(u16, 0), agg.blunders);
    try std.testing.expectEqual(@as(u16, 0), agg.inaccuracies);
    try std.testing.expectEqual(@as(?f32, null), agg.accuracy);
}

test "aggregate: accuracy decreases as cpl rises" {
    var clean = GameAnalysis{};
    clean.append(.{ .eval = .{ .cp = -20 }, .best = null, .best_eval = .{ .cp = 20 }, .cpl = 0, .tier = .good });
    var sloppy = GameAnalysis{};
    sloppy.append(.{ .eval = .{ .cp = 300 }, .best = null, .best_eval = .{ .cp = 50 }, .cpl = 350, .tier = .bad });
    const a_clean = aggregate(clean.moves[0..clean.count]).accuracy.?;
    const a_sloppy = aggregate(sloppy.moves[0..sloppy.count]).accuracy.?;
    try std.testing.expect(a_clean > a_sloppy);
}

test "computeKeyMoments: ranks by swing, mate magnitude first" {
    var ga = GameAnalysis{};
    ga.append(.{ .eval = .{ .cp = 0 }, .best = null, .best_eval = .{ .cp = 0 }, .cpl = 10, .tier = .good });
    ga.append(.{ .eval = .{ .cp = 0 }, .best = null, .best_eval = .{ .cp = 0 }, .cpl = 500, .tier = .bad });
    ga.append(.{ .eval = .{ .cp = 0 }, .best = null, .best_eval = .{ .cp = 0 }, .cpl = 99_000, .tier = .bad });
    ga.append(.{ .eval = .{ .cp = 0 }, .best = null, .best_eval = .{ .cp = 0 }, .cpl = 80, .tier = .meh });
    var out: [max_key_moments]u16 = undefined;
    const k = computeKeyMoments(ga.moves[0..ga.count], &out);
    try std.testing.expectEqual(@as(u8, 4), k);
    try std.testing.expectEqual(@as(u16, 2), out[0]); // 99_000 (mate magnitude)
    try std.testing.expectEqual(@as(u16, 1), out[1]); // 500
    try std.testing.expectEqual(@as(u16, 3), out[2]); // 80
    try std.testing.expectEqual(@as(u16, 0), out[3]); // 10
}

test "computeKeyMoments: empty game returns zero" {
    var ga = GameAnalysis{};
    var out: [max_key_moments]u16 = undefined;
    try std.testing.expectEqual(@as(u8, 0), computeKeyMoments(ga.moves[0..ga.count], &out));
}

test "GameAnalysis.finalize: fills aggregates, key moments, marker" {
    var ga = GameAnalysis{};
    ga.append(.{ .eval = .{ .cp = -10 }, .best = null, .best_eval = .{ .cp = 10 }, .cpl = 0, .tier = .good });
    ga.append(.{ .eval = .{ .cp = 200 }, .best = null, .best_eval = .{ .cp = 50 }, .cpl = 250, .tier = .bad });
    ga.finalize();
    try std.testing.expectEqual(@as(u16, 1), ga.blunders);
    try std.testing.expectEqual(@as(u16, 2), ga.plies_covered);
    try std.testing.expectEqual(current_version, ga.version);
    try std.testing.expectEqual(@as(u8, 2), ga.key_moment_count);
    try std.testing.expectEqual(@as(u16, 1), ga.key_moments[0]); // the blunder swings most
}
