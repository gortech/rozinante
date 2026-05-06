pub const piece = @import("chess/piece.zig");
pub const square = @import("chess/square.zig");
pub const move = @import("chess/move.zig");
pub const board = @import("chess/board.zig");

pub const Piece = piece.Piece;
pub const PieceType = piece.PieceType;
pub const Color = piece.Color;
pub const Square = square.Square;
pub const File = square.File;
pub const Rank = square.Rank;
pub const Move = move.Move;
pub const MoveType = move.MoveType;
pub const Board = board.Board;
pub const CastlingRights = board.CastlingRights;

test {
    @import("std").testing.refAllDecls(@This());
}
