const chess = @import("../chess.zig");

pub const Opponent = union(enum) {
    human,

    pub fn getMove(self: Opponent, board: *const chess.Board) ?chess.Move {
        _ = board;
        return switch (self) {
            .human => null,
        };
    }
};

pub const MoveRecord = struct {
    move: chess.Move,
    piece: chess.Piece,
    captured: ?chess.Piece,
};

pub const GamePhase = enum {
    playing,
    ended,
};

pub const PromotionPending = struct {
    from: chess.Square,
    to: chess.Square,
    selected_idx: u2,
};

pub const Game = struct {
    board: chess.Board,
    cursor: chess.Square,
    selected: ?chess.Square,
    legal_targets: [64]bool,
    move_history: [512]MoveRecord,
    move_count: usize,
    board_history: [512]chess.Board,
    board_count: usize,
    game_phase: GamePhase,
    result: ?[]const u8,
    white_opponent: Opponent,
    black_opponent: Opponent,
    flipped: bool,
    flash_square: ?chess.Square,
    flash_timer: u8,
    promotion_pending: ?PromotionPending,

    pub fn init() Game {
        return .{
            .board = chess.Board.initial,
            .cursor = chess.Square.init(.e, .@"2"),
            .selected = null,
            .legal_targets = [_]bool{false} ** 64,
            .move_history = undefined,
            .move_count = 0,
            .board_history = undefined,
            .board_count = 0,
            .game_phase = .playing,
            .result = null,
            .white_opponent = .human,
            .black_opponent = .human,
            .flipped = false,
            .flash_square = null,
            .flash_timer = 0,
            .promotion_pending = null,
        };
    }

    pub fn selectSquare(self: *Game) void {
        if (self.promotion_pending != null) return;
        if (self.game_phase == .ended) return;

        const cursor_piece = self.board.pieceAt(self.cursor);

        if (self.selected) |sel| {
            if (self.legal_targets[self.cursor.toIndex()]) {
                self.executeMove(sel, self.cursor);
                return;
            }

            if (cursor_piece.color()) |c| {
                if (c == self.board.active_color) {
                    self.selected = self.cursor;
                    self.computeLegalTargets(self.cursor);
                    return;
                }
            }

            self.flash_square = self.cursor;
            self.flash_timer = 3;
        } else {
            if (cursor_piece.color()) |c| {
                if (c == self.board.active_color) {
                    self.selected = self.cursor;
                    self.computeLegalTargets(self.cursor);
                    return;
                }
            }
            self.flash_square = self.cursor;
            self.flash_timer = 3;
        }
    }

    pub fn cancelSelection(self: *Game) void {
        self.selected = null;
        self.legal_targets = [_]bool{false} ** 64;
    }

    pub fn executeMove(self: *Game, from: chess.Square, to: chess.Square) void {
        const legal = chess.legalMoves(&self.board);
        var matching_move: ?chess.Move = null;

        for (legal.moves[0..legal.len]) |m| {
            if (m.from.eql(from) and m.to.eql(to)) {
                if (m.move_type == .promotion) {
                    if (m.promotion_piece) |pp| {
                        if (pp == .queen) {
                            matching_move = m;
                            break;
                        }
                    }
                    continue;
                }
                matching_move = m;
                break;
            }
        }

        if (matching_move == null) {
            for (legal.moves[0..legal.len]) |m| {
                if (m.from.eql(from) and m.to.eql(to) and m.move_type == .promotion) {
                    matching_move = m;
                    break;
                }
            }
        }

        const m = matching_move orelse return;

        const piece = self.board.pieceAt(from);
        const captured_piece = self.board.pieceAt(to);
        const captured: ?chess.Piece = if (!captured_piece.isEmpty())
            captured_piece
        else if (m.move_type == .en_passant)
            chess.Piece.init(self.board.active_color.opponent(), .pawn)
        else
            null;

        if (self.move_count < 512) {
            self.move_history[self.move_count] = .{
                .move = m,
                .piece = piece,
                .captured = captured,
            };
            self.move_count += 1;
        }

        if (self.board_count < 512) {
            self.board_history[self.board_count] = self.board;
            self.board_count += 1;
        }

        self.board = chess.makeMove(self.board, m);

        self.selected = null;
        self.legal_targets = [_]bool{false} ** 64;

        if (chess.isCheckmate(&self.board)) {
            self.game_phase = .ended;
            self.result = if (self.board.active_color == .white)
                "Checkmate \u{2014} Black wins"
            else
                "Checkmate \u{2014} White wins";
        } else if (chess.isDraw(&self.board)) {
            self.game_phase = .ended;
            if (chess.isStalemate(&self.board)) {
                self.result = "Draw \u{2014} Stalemate";
            } else if (chess.isFiftyMoveRule(&self.board)) {
                self.result = "Draw \u{2014} Fifty-move rule";
            } else {
                self.result = "Draw \u{2014} Insufficient material";
            }
        }
    }

    pub fn undoMove(self: *Game) void {
        if (self.board_count == 0) return;

        self.board_count -= 1;
        self.board = self.board_history[self.board_count];

        if (self.move_count > 0) {
            self.move_count -= 1;
        }

        self.selected = null;
        self.legal_targets = [_]bool{false} ** 64;
        self.game_phase = .playing;
        self.result = null;
    }

    pub fn newGame(self: *Game) void {
        self.* = init();
    }

    pub fn flipBoard(self: *Game) void {
        self.flipped = !self.flipped;
    }

    pub fn computeLegalTargets(self: *Game, from: chess.Square) void {
        self.legal_targets = [_]bool{false} ** 64;
        const moves = chess.legalMoves(&self.board);
        for (moves.moves[0..moves.len]) |m| {
            if (m.from.eql(from)) {
                self.legal_targets[m.to.toIndex()] = true;
            }
        }
    }

    pub fn moveCursor(self: *Game, d_file: i8, d_rank: i8) void {
        const file_delta: i8 = if (self.flipped) -d_file else d_file;
        const rank_delta: i8 = if (self.flipped) -d_rank else d_rank;

        const cur_file: i8 = @intCast(@intFromEnum(self.cursor.file));
        const cur_rank: i8 = @intCast(@intFromEnum(self.cursor.rank));

        const new_file = cur_file + file_delta;
        const new_rank = cur_rank + rank_delta;

        if (new_file >= 0 and new_file <= 7 and new_rank >= 0 and new_rank <= 7) {
            self.cursor = chess.Square.init(
                @enumFromInt(@as(u3, @intCast(new_file))),
                @enumFromInt(@as(u3, @intCast(new_rank))),
            );
        }
    }

    pub fn tickFlash(self: *Game) void {
        if (self.flash_timer > 0) {
            self.flash_timer -= 1;
            if (self.flash_timer == 0) {
                self.flash_square = null;
            }
        }
    }

    pub fn isKingInCheck(self: *const Game) bool {
        return chess.isInCheck(&self.board, self.board.active_color);
    }

    pub fn activeKingSquare(self: *const Game) ?chess.Square {
        const king_piece = chess.Piece.init(self.board.active_color, .king);
        for (0..64) |i| {
            if (self.board.squares[i] == king_piece) {
                return chess.Square.fromIndex(@intCast(i));
            }
        }
        return null;
    }
};
