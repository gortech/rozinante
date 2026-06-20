//! Absolute-pin detection: which pieces are pinned to their own king by an
//! enemy slider, and along which ray. Pure, allocator-free, total.
//!
//! Two consumers (per plan U1): the pin learning aid (reads presence only, for
//! both colors) and SEE (needs the ray axis to permit a pinned defender's legal
//! along-the-ray recapture, and to forbid a king recapturing into check).

const std = @import("std");
const piece_mod = @import("piece.zig");
const square_mod = @import("square.zig");
const board_mod = @import("board.zig");
const movegen = @import("movegen.zig");

const Piece = piece_mod.Piece;
const PieceType = piece_mod.PieceType;
const Color = piece_mod.Color;
const Square = square_mod.Square;
const Board = board_mod.Board;

/// The ray axis an absolutely-pinned piece is constrained to. `df`/`dr` are a
/// unit slider step pointing from the king out through the pinned piece toward
/// the pinning slider. Sign does not matter to the colinearity test in `onRay`.
pub const Pin = struct {
    df: i4,
    dr: i4,

    /// True if `target` lies on the pin's ray line (which passes through the
    /// pinned piece at `from`). A pinned piece may only ever move/capture along
    /// this line, so this is the recapture-admissibility test SEE needs.
    pub fn onRay(self: Pin, from: Square, target: Square) bool {
        const vf: i16 = @as(i16, target.file.index()) - @as(i16, from.file.index());
        const vr: i16 = @as(i16, target.rank.index()) - @as(i16, from.rank.index());
        return vf * @as(i16, self.dr) - vr * @as(i16, self.df) == 0;
    }
};

/// Per-square pin result for a whole position (both colors at once).
pub const Pins = struct {
    axes: [64]?Pin,

    pub fn isPinned(self: *const Pins, sq: Square) bool {
        return self.axes[sq.toIndex()] != null;
    }

    pub fn axisOf(self: *const Pins, sq: Square) ?Pin {
        return self.axes[sq.toIndex()];
    }

    /// Whether a piece at `from` may legally capture on `target` with respect to
    /// its absolute pin: an unpinned piece always may; a pinned one only along
    /// its ray.
    pub fn allowsCapture(self: *const Pins, from: Square, target: Square) bool {
        const pin = self.axes[from.toIndex()] orelse return true;
        return pin.onRay(from, target);
    }
};

/// Detect every absolutely-pinned piece of both colors in `b`.
pub fn detect(b: *const Board) Pins {
    var pins = Pins{ .axes = [_]?Pin{null} ** 64 };
    detectForColor(b, .white, &pins);
    detectForColor(b, .black, &pins);
    return pins;
}

fn detectForColor(b: *const Board, color: Color, pins: *Pins) void {
    const king_sq = movegen.findKing(b, color) orelse return;
    scanRays(b, king_sq, color, &movegen.diagonal_dirs, .bishop, pins);
    scanRays(b, king_sq, color, &movegen.straight_dirs, .rook, pins);
}

/// Walk each ray out from the king: the first piece must be friendly to be a pin
/// candidate; if the next piece on the same ray is an enemy slider of the
/// matching kind (or a queen), the candidate is absolutely pinned along the ray.
fn scanRays(
    b: *const Board,
    king_sq: Square,
    color: Color,
    dirs: []const [2]i4,
    slider_kind: PieceType,
    pins: *Pins,
) void {
    const enemy = color.opponent();
    for (dirs) |dir| {
        var cur = king_sq;
        var candidate: ?Square = null;
        while (true) {
            cur = movegen.offsetSquare(cur, dir[0], dir[1]) orelse break;
            const p = b.pieceAt(cur);
            if (p.isEmpty()) continue;
            const pc = p.color().?;
            if (candidate == null) {
                // First piece on the ray: only a friendly piece can be pinned.
                if (pc != color) break;
                candidate = cur;
            } else {
                // Second piece: a matching enemy slider behind the friendly
                // piece completes an absolute pin; anything else does not.
                if (pc == enemy) {
                    const pt = p.pieceType().?;
                    if (pt == slider_kind or pt == .queen) {
                        pins.axes[candidate.?.toIndex()] = .{ .df = dir[0], .dr = dir[1] };
                    }
                }
                break;
            }
        }
    }
}

const testing = std.testing;

fn at(name: []const u8) Square {
    return Square.fromAlgebraic(name).?;
}

test "bishop pins knight to king on a diagonal" {
    const b = Board.fromFen("4k3/8/8/8/8/2b5/3N4/4K3 w - - 0 1").?;
    const pins = detect(&b);
    try testing.expect(pins.isPinned(at("d2")));
    const axis = pins.axisOf(at("d2")).?;
    try testing.expectEqual(@as(i4, -1), axis.df);
    try testing.expectEqual(@as(i4, 1), axis.dr);
    // The pinned knight may recapture the pinner along the ray, not off it.
    try testing.expect(pins.allowsCapture(at("d2"), at("c3")));
    try testing.expect(!pins.allowsCapture(at("d2"), at("e4")));
}

test "rook pins rook on an open file" {
    const b = Board.fromFen("k3r3/8/8/8/4R3/8/8/4K3 w - - 0 1").?;
    const pins = detect(&b);
    try testing.expect(pins.isPinned(at("e4")));
    const axis = pins.axisOf(at("e4")).?;
    try testing.expectEqual(@as(i4, 0), axis.df);
    try testing.expectEqual(@as(i4, 1), axis.dr);
    // May capture along the file (toward the pinner), not across it.
    try testing.expect(pins.allowsCapture(at("e4"), at("e8")));
    try testing.expect(!pins.allowsCapture(at("e4"), at("d4")));
}

test "two friendly pieces between king and slider: neither pinned" {
    const b = Board.fromFen("k3r3/8/8/8/4R3/4R3/8/4K3 w - - 0 1").?;
    const pins = detect(&b);
    try testing.expect(!pins.isPinned(at("e3")));
    try testing.expect(!pins.isPinned(at("e4")));
}

test "enemy slider of the wrong kind for the ray: not pinned" {
    // Rook on a diagonal cannot pin.
    const b = Board.fromFen("4k3/8/8/8/8/2r5/3N4/4K3 w - - 0 1").?;
    const pins = detect(&b);
    try testing.expect(!pins.isPinned(at("d2")));
}

test "only the first friendly piece on the ray is the pin candidate" {
    // King e1, friendly rook e2, friendly bishop e5, enemy rook e8.
    const b = Board.fromFen("k3r3/8/8/4B3/8/8/4R3/4K3 w - - 0 1").?;
    const pins = detect(&b);
    try testing.expect(!pins.isPinned(at("e2")));
    try testing.expect(!pins.isPinned(at("e5")));
}

test "pins of both colors are reported in one position" {
    const b = Board.fromFen("4k3/3n4/2B5/8/8/2b5/3N4/4K3 w - - 0 1").?;
    const pins = detect(&b);
    try testing.expect(pins.isPinned(at("d2"))); // white knight pinned by black bishop
    try testing.expect(pins.isPinned(at("d7"))); // black knight pinned by white bishop
}

test "missing king of a color: no pins for it, no crash" {
    // No black king; white king still present, white knight still pinnable.
    const b = Board.fromFen("8/8/8/8/8/2b5/3N4/4K3 w - - 0 1").?;
    const pins = detect(&b);
    try testing.expect(pins.isPinned(at("d2")));
    // Sanity: a board with no kings at all yields no pins and does not crash.
    const b2 = Board.fromFen("8/8/8/8/8/2b5/3N4/8 w - - 0 1").?;
    const pins2 = detect(&b2);
    try testing.expect(!pins2.isPinned(at("d2")));
}
