const std = @import("std");
const piece_mod = @import("piece.zig");
const square_mod = @import("square.zig");
const move_mod = @import("move.zig");
const board_mod = @import("board.zig");

const Piece = piece_mod.Piece;
const PieceType = piece_mod.PieceType;
const Color = piece_mod.Color;
const Square = square_mod.Square;
const File = square_mod.File;
const Rank = square_mod.Rank;
const Move = move_mod.Move;
const Board = board_mod.Board;

pub const MAX_MOVES = 256;

pub const MoveList = struct {
    moves: [MAX_MOVES]Move,
    len: usize,

    pub fn init() MoveList {
        return .{ .moves = undefined, .len = 0 };
    }

    pub fn append(self: *MoveList, m: Move) void {
        std.debug.assert(self.len < MAX_MOVES);
        self.moves[self.len] = m;
        self.len += 1;
    }

    pub fn slice(self: *const MoveList) []const Move {
        return self.moves[0..self.len];
    }
};

const knight_offsets = [_][2]i4{
    .{ -2, -1 }, .{ -2, 1 }, .{ -1, -2 }, .{ -1, 2 },
    .{ 1, -2 },  .{ 1, 2 },  .{ 2, -1 },  .{ 2, 1 },
};

const king_offsets = [_][2]i4{
    .{ -1, -1 }, .{ -1, 0 }, .{ -1, 1 }, .{ 0, -1 },
    .{ 0, 1 },   .{ 1, -1 }, .{ 1, 0 },  .{ 1, 1 },
};

const diagonal_dirs = [_][2]i4{
    .{ -1, -1 }, .{ -1, 1 }, .{ 1, -1 }, .{ 1, 1 },
};

const straight_dirs = [_][2]i4{
    .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 },
};

fn offsetSquare(sq: Square, file_delta: i4, rank_delta: i4) ?Square {
    const f: i8 = @intCast(sq.file.index());
    const r: i8 = @intCast(sq.rank.index());
    const fd: i8 = @intCast(file_delta);
    const rd: i8 = @intCast(rank_delta);
    const new_f = f + fd;
    const new_r = r + rd;
    if (new_f < 0 or new_f > 7 or new_r < 0 or new_r > 7) return null;
    return Square.init(
        @enumFromInt(@as(u3, @intCast(new_f))),
        @enumFromInt(@as(u3, @intCast(new_r))),
    );
}

pub fn makeMove(b: Board, m: Move) Board {
    var new = b;
    const piece = b.pieceAt(m.from);
    const captured = b.pieceAt(m.to);
    const pt = piece.pieceType() orelse return new;
    const color = piece.color() orelse return new;

    new.setPiece(m.from, .empty);

    if (m.move_type == .promotion) {
        new.setPiece(m.to, Piece.init(color, m.promotion_piece.?));
    } else {
        new.setPiece(m.to, piece);
    }

    if (m.move_type == .en_passant) {
        const captured_sq = Square.init(m.to.file, m.from.rank);
        new.setPiece(captured_sq, .empty);
    }

    if (m.move_type == .castle) {
        const rook_from: Square, const rook_to: Square = castleRookSquares(m.to);
        const rook = new.pieceAt(rook_from);
        new.setPiece(rook_from, .empty);
        new.setPiece(rook_to, rook);
    }

    new.en_passant_square = null;
    if (pt == .pawn) {
        const from_ri = m.from.rank.index();
        const to_ri = m.to.rank.index();
        if ((from_ri == 1 and to_ri == 3) or (from_ri == 6 and to_ri == 4)) {
            const ep_ri: u3 = if (from_ri < to_ri) from_ri + 1 else from_ri - 1;
            new.en_passant_square = Square.init(m.from.file, @enumFromInt(ep_ri));
        }
    }

    if (pt == .pawn or !captured.isEmpty()) {
        new.halfmove_clock = 0;
    } else {
        new.halfmove_clock += 1;
    }

    if (b.active_color == .black) {
        new.fullmove_number += 1;
    }

    updateCastlingRights(&new, m, piece, captured);

    new.active_color = b.active_color.opponent();
    return new;
}

fn updateCastlingRights(b: *Board, m: Move, piece: Piece, captured: Piece) void {
    const pt = piece.pieceType() orelse return;

    if (pt == .king) {
        if (piece.color().? == .white) {
            b.castling_rights.white_kingside = false;
            b.castling_rights.white_queenside = false;
        } else {
            b.castling_rights.black_kingside = false;
            b.castling_rights.black_queenside = false;
        }
    }

    if (pt == .rook) {
        revokeCastlingForSquare(b, m.from);
    }

    if (!captured.isEmpty()) {
        revokeCastlingForSquare(b, m.to);
    }
}

fn revokeCastlingForSquare(b: *Board, sq: Square) void {
    const idx = sq.toIndex();
    if (idx == 0) {
        b.castling_rights.white_queenside = false;
    } else if (idx == 7) {
        b.castling_rights.white_kingside = false;
    } else if (idx == 56) {
        b.castling_rights.black_queenside = false;
    } else if (idx == 63) {
        b.castling_rights.black_kingside = false;
    }
}

pub fn isSquareAttacked(b: *const Board, sq: Square, by_color: Color) bool {
    const pawn_rank_dir: i4 = if (by_color == .white) -1 else 1;
    const enemy_pawn = Piece.init(by_color, .pawn);
    for ([_]i4{ -1, 1 }) |fd| {
        if (offsetSquare(sq, fd, pawn_rank_dir)) |s| {
            if (b.pieceAt(s) == enemy_pawn) return true;
        }
    }

    const enemy_knight = Piece.init(by_color, .knight);
    for (knight_offsets) |off| {
        if (offsetSquare(sq, off[0], off[1])) |s| {
            if (b.pieceAt(s) == enemy_knight) return true;
        }
    }

    const enemy_king = Piece.init(by_color, .king);
    for (king_offsets) |off| {
        if (offsetSquare(sq, off[0], off[1])) |s| {
            if (b.pieceAt(s) == enemy_king) return true;
        }
    }

    const enemy_bishop = Piece.init(by_color, .bishop);
    const enemy_queen = Piece.init(by_color, .queen);
    for (diagonal_dirs) |dir| {
        var cur = sq;
        while (true) {
            cur = offsetSquare(cur, dir[0], dir[1]) orelse break;
            const p = b.pieceAt(cur);
            if (!p.isEmpty()) {
                if (p == enemy_bishop or p == enemy_queen) return true;
                break;
            }
        }
    }

    const enemy_rook = Piece.init(by_color, .rook);
    for (straight_dirs) |dir| {
        var cur = sq;
        while (true) {
            cur = offsetSquare(cur, dir[0], dir[1]) orelse break;
            const p = b.pieceAt(cur);
            if (!p.isEmpty()) {
                if (p == enemy_rook or p == enemy_queen) return true;
                break;
            }
        }
    }

    return false;
}

pub fn findKing(b: *const Board, color: Color) ?Square {
    const king = Piece.init(color, .king);
    for (0..64) |i| {
        if (b.squares[i] == king) return Square.fromIndex(@intCast(i));
    }
    return null;
}

pub fn isInCheck(b: *const Board, color: Color) bool {
    const king_sq = findKing(b, color) orelse return false;
    return isSquareAttacked(b, king_sq, color.opponent());
}

pub fn legalMoves(b: *const Board) MoveList {
    var pseudo = MoveList.init();
    const color = b.active_color;

    for (0..64) |i| {
        const p = b.squares[i];
        if (p.isEmpty()) continue;
        if ((p.color() orelse continue) != color) continue;
        generatePieceMoves(b, Square.fromIndex(@intCast(i)), color, &pseudo);
    }

    var legal = MoveList.init();
    for (pseudo.slice()) |m| {
        const after = makeMove(b.*, m);
        if (!isInCheck(&after, color)) {
            legal.append(m);
        }
    }

    return legal;
}

fn generatePieceMoves(b: *const Board, sq: Square, color: Color, list: *MoveList) void {
    const pt = b.pieceAt(sq).pieceType() orelse return;

    switch (pt) {
        .pawn => generatePawnMoves(b, sq, color, list),
        .knight => generateLeaperMoves(b, sq, color, &knight_offsets, list),
        .bishop => generateSlidingMoves(b, sq, color, &diagonal_dirs, list),
        .rook => generateSlidingMoves(b, sq, color, &straight_dirs, list),
        .queen => {
            generateSlidingMoves(b, sq, color, &diagonal_dirs, list);
            generateSlidingMoves(b, sq, color, &straight_dirs, list);
        },
        .king => {
            generateLeaperMoves(b, sq, color, &king_offsets, list);
            generateCastlingMoves(b, color, list);
        },
    }
}

fn generatePawnMoves(b: *const Board, sq: Square, color: Color, list: *MoveList) void {
    const dir: i4 = if (color == .white) 1 else -1;
    const start_rank: Rank = if (color == .white) .@"2" else .@"7";
    const promo_rank: Rank = if (color == .white) .@"8" else .@"1";

    if (offsetSquare(sq, 0, dir)) |target| {
        if (b.pieceAt(target).isEmpty()) {
            if (target.rank == promo_rank) {
                appendPromotions(sq, target, list);
            } else {
                list.append(Move.init(sq, target));
                if (sq.rank == start_rank) {
                    if (offsetSquare(sq, 0, dir * 2)) |dbl| {
                        if (b.pieceAt(dbl).isEmpty()) {
                            list.append(Move.init(sq, dbl));
                        }
                    }
                }
            }
        }
    }

    for ([_]i4{ -1, 1 }) |fd| {
        if (offsetSquare(sq, fd, dir)) |target| {
            const tp = b.pieceAt(target);
            if (!tp.isEmpty()) {
                if ((tp.color() orelse continue) != color) {
                    if (target.rank == promo_rank) {
                        appendPromotions(sq, target, list);
                    } else {
                        list.append(Move.init(sq, target));
                    }
                }
            }
        }
    }

    if (b.en_passant_square) |ep_sq| {
        for ([_]i4{ -1, 1 }) |fd| {
            if (offsetSquare(sq, fd, dir)) |target| {
                if (target.eql(ep_sq)) {
                    list.append(Move.initEnPassant(sq, target));
                }
            }
        }
    }
}

fn appendPromotions(from: Square, to: Square, list: *MoveList) void {
    for ([_]PieceType{ .queen, .rook, .bishop, .knight }) |pt| {
        list.append(Move.initPromotion(from, to, pt));
    }
}

fn generateLeaperMoves(b: *const Board, sq: Square, color: Color, offsets: []const [2]i4, list: *MoveList) void {
    for (offsets) |off| {
        if (offsetSquare(sq, off[0], off[1])) |target| {
            const tp = b.pieceAt(target);
            if (tp.isEmpty() or tp.color().? != color) {
                list.append(Move.init(sq, target));
            }
        }
    }
}

fn generateSlidingMoves(b: *const Board, sq: Square, color: Color, dirs: []const [2]i4, list: *MoveList) void {
    for (dirs) |dir| {
        var cur = sq;
        while (true) {
            cur = offsetSquare(cur, dir[0], dir[1]) orelse break;
            const tp = b.pieceAt(cur);
            if (tp.isEmpty()) {
                list.append(Move.init(sq, cur));
            } else {
                if (tp.color().? != color) {
                    list.append(Move.init(sq, cur));
                }
                break;
            }
        }
    }
}

fn generateCastlingMoves(b: *const Board, color: Color, list: *MoveList) void {
    const enemy = color.opponent();
    const rank: Rank = if (color == .white) .@"1" else .@"8";
    const king_sq = Square.init(.e, rank);

    if (isSquareAttacked(b, king_sq, enemy)) return;

    const kingside = if (color == .white) b.castling_rights.white_kingside else b.castling_rights.black_kingside;
    if (kingside) {
        const f_sq = Square.init(.f, rank);
        const g_sq = Square.init(.g, rank);
        if (b.pieceAt(f_sq).isEmpty() and b.pieceAt(g_sq).isEmpty()) {
            if (!isSquareAttacked(b, f_sq, enemy) and !isSquareAttacked(b, g_sq, enemy)) {
                list.append(Move.initCastle(king_sq, g_sq));
            }
        }
    }

    const queenside = if (color == .white) b.castling_rights.white_queenside else b.castling_rights.black_queenside;
    if (queenside) {
        const d_sq = Square.init(.d, rank);
        const c_sq = Square.init(.c, rank);
        const b_sq = Square.init(.b, rank);
        if (b.pieceAt(d_sq).isEmpty() and b.pieceAt(c_sq).isEmpty() and b.pieceAt(b_sq).isEmpty()) {
            if (!isSquareAttacked(b, d_sq, enemy) and !isSquareAttacked(b, c_sq, enemy)) {
                list.append(Move.initCastle(king_sq, c_sq));
            }
        }
    }
}

fn castleRookSquares(king_to: Square) struct { Square, Square } {
    const rank = king_to.rank;
    if (king_to.file == .g) {
        return .{ Square.init(.h, rank), Square.init(.f, rank) };
    }
    return .{ Square.init(.a, rank), Square.init(.d, rank) };
}

test {
    _ = @import("movegen_test.zig");
}
