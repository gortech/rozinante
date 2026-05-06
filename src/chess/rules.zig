const std = @import("std");
const piece_mod = @import("piece.zig");
const board_mod = @import("board.zig");
const movegen = @import("movegen.zig");
const square_mod = @import("square.zig");

const Piece = piece_mod.Piece;
const PieceType = piece_mod.PieceType;
const Color = piece_mod.Color;
const Board = board_mod.Board;
const Square = square_mod.Square;

/// Returns true if the active color is in checkmate: their king is in check
/// and they have no legal moves to escape.
pub fn isCheckmate(b: *const Board) bool {
    const color = b.active_color;
    if (!movegen.isInCheck(b, color)) return false;
    const moves = movegen.legalMoves(b);
    return moves.len == 0;
}

/// Returns true if the active color is in stalemate: their king is NOT in check
/// but they have no legal moves available.
pub fn isStalemate(b: *const Board) bool {
    const color = b.active_color;
    if (movegen.isInCheck(b, color)) return false;
    const moves = movegen.legalMoves(b);
    return moves.len == 0;
}

/// Returns true if the fifty-move rule applies: the halfmove clock has reached
/// 100 (50 full moves without a pawn move or capture).
pub fn isFiftyMoveRule(b: *const Board) bool {
    return b.halfmove_clock >= 100;
}

/// Returns true if neither side has sufficient material to force checkmate.
/// Detected cases:
/// - King vs King
/// - King + Bishop vs King
/// - King + Knight vs King
/// - King + Bishop vs King + Bishop (bishops on same-colored squares)
///
/// Note: Does not detect all theoretically drawn positions (e.g. blocked pawns),
/// only FIDE-standard insufficient material cases.
pub fn isInsufficientMaterial(b: *const Board) bool {
    var white_bishops: u8 = 0;
    var black_bishops: u8 = 0;
    var white_knights: u8 = 0;
    var black_knights: u8 = 0;
    var other_pieces: u8 = 0;
    var white_bishop_sq_color: ?u1 = null;
    var black_bishop_sq_color: ?u1 = null;

    for (0..64) |i| {
        const p = b.squares[i];
        if (p.isEmpty()) continue;
        const pt = p.pieceType() orelse continue;
        const c = p.color() orelse continue;
        switch (pt) {
            .king => {},
            .bishop => {
                const sq = Square.fromIndex(@intCast(i));
                const sq_color: u1 = @truncate(@as(u8, sq.file.index()) + @as(u8, sq.rank.index()));
                if (c == .white) {
                    white_bishops += 1;
                    white_bishop_sq_color = sq_color;
                } else {
                    black_bishops += 1;
                    black_bishop_sq_color = sq_color;
                }
            },
            .knight => {
                if (c == .white) white_knights += 1 else black_knights += 1;
            },
            else => {
                other_pieces += 1;
            },
        }
    }

    if (other_pieces > 0) return false;

    const total_minor = white_bishops + black_bishops + white_knights + black_knights;

    // K vs K
    if (total_minor == 0) return true;

    // K+B vs K or K+N vs K
    if (total_minor == 1) return true;

    // K+B vs K+B with bishops on same-colored squares
    if (white_bishops == 1 and black_bishops == 1 and white_knights == 0 and black_knights == 0) {
        if (white_bishop_sq_color != null and black_bishop_sq_color != null) {
            return white_bishop_sq_color.? == black_bishop_sq_color.?;
        }
    }

    return false;
}

/// Returns true if the position is a draw by any of the following rules:
/// - Fifty-move rule (halfmove clock >= 100)
/// - Insufficient material
/// - Stalemate (no legal moves, not in check)
///
/// Note: Threefold repetition is NOT detected because the Board struct does not
/// track position history. Implementing threefold repetition requires game-level
/// state (a Game struct with position hash history).
pub fn isDraw(b: *const Board) bool {
    if (isFiftyMoveRule(b)) return true;
    if (isInsufficientMaterial(b)) return true;
    if (isStalemate(b)) return true;
    return false;
}

test {
    _ = @import("rules_test.zig");
}
