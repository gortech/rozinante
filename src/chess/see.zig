//! Static exchange evaluation (SEE): the net material the initiating side wins
//! by starting a capture sequence on a square, with cheapest-attacker-first
//! ordering, x-ray reveals, and absolute-pin restrictions. Pure, allocator-free.
//!
//! Endangered verdict (plan U3): for a friendly piece on `sq`, it is losing
//! material (red) iff `see(b, sq, opponent) > 0`, attacked-but-safe (orange)
//! when attacked and `<= 0`.

const std = @import("std");
const piece_mod = @import("piece.zig");
const square_mod = @import("square.zig");
const board_mod = @import("board.zig");
const movegen = @import("movegen.zig");
const pin = @import("pin.zig");

const Piece = piece_mod.Piece;
const PieceType = piece_mod.PieceType;
const Color = piece_mod.Color;
const Square = square_mod.Square;
const Board = board_mod.Board;
const Pins = pin.Pins;

/// King value: larger than any reachable material sum, so the king is never
/// profitably "traded". The king only ever appears as the terminal recapturer
/// (admitted only onto an undefended square), and that terminal gain is dropped
/// by the negamax fold, so this magnitude never leaks into a result.
pub const KING_VALUE: i32 = 10_000;

/// Standard piece values (pawns = 1). Empty squares value 0.
pub fn value(p: Piece) i32 {
    return switch (p.pieceType() orelse return 0) {
        .pawn => 1,
        .knight => 3,
        .bishop => 3,
        .rook => 5,
        .queen => 9,
        .king => KING_VALUE,
    };
}

/// Net material `by_color` wins by initiating the capture sequence on `target`,
/// assuming optimal stand-pat by both sides. Positive => `by_color` wins
/// material. Returns 0 when `by_color` has no admissible attacker of `target`.
pub fn see(b: *const Board, target: Square, by_color: Color) i32 {
    const pins = pin.detect(b);
    var occ = b.*;

    var gain: [32]i32 = undefined;
    gain[0] = value(occ.pieceAt(target)); // the initial victim on `target`

    var side = by_color;
    var attacker = cheapestAttacker(&occ, target, side, &pins) orelse return 0;
    var d: usize = 0;
    while (true) {
        d += 1;
        gain[d] = value(occ.pieceAt(attacker)) - gain[d - 1];
        occ.setPiece(attacker, .empty); // the attacker moves off; x-ray rescan reveals any piece behind
        side = side.opponent();
        attacker = cheapestAttacker(&occ, target, side, &pins) orelse break;
    }

    // Negamax fold-back with stand-pat (classic SEE `while(--d)` fold).
    while (d > 1) {
        d -= 1;
        gain[d - 1] = -@max(-gain[d - 1], gain[d]);
    }
    return gain[0];
}

/// Square of the cheapest admissible `side` attacker of `target` in the current
/// occupancy, in ascending piece value. Returns null when none can capture.
fn cheapestAttacker(occ: *const Board, target: Square, side: Color, pins: *const Pins) ?Square {
    if (pawnAttacker(occ, target, side, pins)) |s| return s;
    if (knightAttacker(occ, target, side, pins)) |s| return s;
    if (sliderAttacker(occ, target, side, &movegen.diagonal_dirs, .bishop, pins)) |s| return s;
    if (sliderAttacker(occ, target, side, &movegen.straight_dirs, .rook, pins)) |s| return s;
    if (sliderAttacker(occ, target, side, &movegen.diagonal_dirs, .queen, pins)) |s| return s;
    if (sliderAttacker(occ, target, side, &movegen.straight_dirs, .queen, pins)) |s| return s;
    if (kingAttacker(occ, target, side)) |s| return s;
    return null;
}

fn pawnAttacker(occ: *const Board, target: Square, side: Color, pins: *const Pins) ?Square {
    const want = Piece.init(side, .pawn);
    const rank_off: i4 = if (side == .white) -1 else 1; // where a `side` pawn capturing `target` sits
    for ([_]i4{ -1, 1 }) |fd| {
        if (movegen.offsetSquare(target, fd, rank_off)) |s| {
            if (occ.pieceAt(s) == want and pins.allowsCapture(s, target)) return s;
        }
    }
    return null;
}

fn knightAttacker(occ: *const Board, target: Square, side: Color, pins: *const Pins) ?Square {
    const want = Piece.init(side, .knight);
    for (movegen.knight_offsets) |off| {
        if (movegen.offsetSquare(target, off[0], off[1])) |s| {
            if (occ.pieceAt(s) == want and pins.allowsCapture(s, target)) return s;
        }
    }
    return null;
}

/// First `side` slider of kind `want` (or a queen, which shares both ray sets)
/// on any of `dirs`, blocked by the first piece encountered on each ray.
fn sliderAttacker(
    occ: *const Board,
    target: Square,
    side: Color,
    dirs: []const [2]i4,
    want: PieceType,
    pins: *const Pins,
) ?Square {
    for (dirs) |dir| {
        var cur = target;
        while (true) {
            cur = movegen.offsetSquare(cur, dir[0], dir[1]) orelse break;
            const p = occ.pieceAt(cur);
            if (p.isEmpty()) continue;
            // First piece on the ray: an admissible matching attacker, else the ray is blocked.
            if (p.color().? == side and p.pieceType().? == want and pins.allowsCapture(cur, target)) {
                return cur;
            }
            break;
        }
    }
    return null;
}

fn kingAttacker(occ: *const Board, target: Square, side: Color) ?Square {
    const want = Piece.init(side, .king);
    for (movegen.king_offsets) |off| {
        if (movegen.offsetSquare(target, off[0], off[1])) |s| {
            if (occ.pieceAt(s) == want) {
                // A king may recapture only onto a square the enemy no longer defends.
                if (movegen.isSquareAttacked(occ, target, side.opponent())) return null;
                return s;
            }
        }
    }
    return null;
}

const testing = std.testing;

fn at(name: []const u8) Square {
    return Square.fromAlgebraic(name).?;
}

test "AE1: hung queen defended only by a rook, attacked by a pawn -> red (see > 0)" {
    const b = Board.fromFen("4k3/8/8/2p5/3Q4/8/8/3RK3 w - - 0 1").?;
    try testing.expectEqual(@as(i32, 8), see(&b, at("d4"), .black));
}

test "AE2: pawn defended by a pawn, attacked by doubled rooks -> orange (see <= 0)" {
    const b = Board.fromFen("k3r3/4r3/8/8/4P3/5P2/8/K7 w - - 0 1").?;
    try testing.expectEqual(@as(i32, -3), see(&b, at("e4"), .black));
}

test "AE3: lone defender pinned off the ray is not counted -> red" {
    const b = Board.fromFen("3rk3/8/8/8/3N4/8/K2R3r/8 w - - 0 1").?;
    // White rook d2 is pinned along the 2nd rank, so it cannot recapture on d4.
    try testing.expectEqual(@as(i32, 3), see(&b, at("d4"), .black));
}

test "AE8: even knight trade -> orange (see == 0)" {
    const b = Board.fromFen("4k3/8/6n1/4N3/3P4/8/8/4K3 w - - 0 1").?;
    try testing.expectEqual(@as(i32, 0), see(&b, at("e5"), .black));
}

test "AE9: a pinned rook may recapture along its own ray (counted)" {
    // White rook e2 pinned by black rook e8; it may still capture up the e-file.
    const b = Board.fromFen("k3r3/8/8/8/8/8/4R3/4K3 w - - 0 1").?;
    // If the pinned rook were wrongly excluded, see would be 0 (no attacker).
    try testing.expectEqual(@as(i32, 5), see(&b, at("e8"), .white));
}

test "AE13: x-ray reveals the queen behind the bishop -> red" {
    const b = Board.fromFen("4k2q/6b1/8/8/3B4/4P3/8/4K3 w - - 0 1").?;
    try testing.expectEqual(@as(i32, 1), see(&b, at("d4"), .black));
}

test "undefended attacked piece: see == value of the piece" {
    const b = Board.fromFen("3rk3/8/8/8/3P4/8/8/4K3 w - - 0 1").?;
    try testing.expectEqual(@as(i32, 1), see(&b, at("d4"), .black));
}

test "defended piece, pricier attacker, no profitable continuation -> see <= 0" {
    const b = Board.fromFen("3qk3/8/8/8/3N4/4P3/8/4K3 w - - 0 1").?;
    try testing.expectEqual(@as(i32, -6), see(&b, at("d4"), .black));
}

test "king recapturer rejected while the square stays defended" {
    // Black pawn e5 defended only by the black king e6, but white rook e1 still
    // covers e5, so the king may not recapture: white simply wins the pawn.
    const b = Board.fromFen("8/8/4k3/4p3/3P4/8/8/4R1K1 w - - 0 1").?;
    try testing.expectEqual(@as(i32, 1), see(&b, at("e5"), .white));
}

test "no attacker of the target: see == 0" {
    const b = Board.fromFen("4k3/8/8/8/3P4/8/8/4K3 w - - 0 1").?;
    try testing.expectEqual(@as(i32, 0), see(&b, at("d4"), .black));
}
