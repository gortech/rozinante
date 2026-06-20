pub const piece = @import("chess/piece.zig");
pub const square = @import("chess/square.zig");
pub const move = @import("chess/move.zig");
pub const board = @import("chess/board.zig");
pub const movegen = @import("chess/movegen.zig");
pub const pin = @import("chess/pin.zig");
pub const see = @import("chess/see.zig");
pub const rules = @import("chess/rules.zig");
pub const perft = @import("chess/perft.zig");

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
pub const MoveList = movegen.MoveList;
pub const makeMove = movegen.makeMove;
pub const legalMoves = movegen.legalMoves;
pub const isSquareAttacked = movegen.isSquareAttacked;
pub const isInCheck = movegen.isInCheck;
pub const isCheck = movegen.isInCheck;
pub const findKing = movegen.findKing;
pub const Pins = pin.Pins;
pub const detectPins = pin.detect;
pub const seeValue = see.see;
pub const isCheckmate = rules.isCheckmate;
pub const isStalemate = rules.isStalemate;
pub const isDraw = rules.isDraw;
pub const isFiftyMoveRule = rules.isFiftyMoveRule;
pub const isInsufficientMaterial = rules.isInsufficientMaterial;
pub const moveToUci = Move.toUci;
pub const uciToMove = Move.fromUci;

test {
    @import("std").testing.refAllDecls(@This());
}
