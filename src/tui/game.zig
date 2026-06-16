const chess = @import("../chess.zig");
const openings = @import("../openings.zig");

pub const Opponent = enum {
    human,
    engine,
};

pub const EngineState = enum {
    idle,
    thinking,
    @"error",
    reconnecting,
};

pub const LastMove = struct {
    from: chess.Square,
    to: chess.Square,
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

pub const FanNotation = struct {
    buf: [24]u8,
    len: u8,

    pub fn slice(self: *const FanNotation) []const u8 {
        return self.buf[0..self.len];
    }
};

pub const promotion_pieces = [4]chess.PieceType{ .queen, .rook, .bishop, .knight };

pub fn pieceSymbol(pt: chess.PieceType, color: chess.Color) []const u8 {
    return switch (color) {
        .white => switch (pt) {
            .king => "\u{2654}",
            .queen => "\u{2655}",
            .rook => "\u{2656}",
            .bishop => "\u{2657}",
            .knight => "\u{2658}",
            .pawn => "\u{2659}",
        },
        .black => switch (pt) {
            .king => "\u{265A}",
            .queen => "\u{265B}",
            .rook => "\u{265C}",
            .bishop => "\u{265D}",
            .knight => "\u{265E}",
            .pawn => "\u{265F}",
        },
    };
}

fn computeFan(record: MoveRecord, board_before: *const chess.Board, board_after: *const chess.Board) FanNotation {
    var fan: FanNotation = .{ .buf = .{0} ** 24, .len = 0 };
    const m = record.move;
    const pt = record.piece.pieceType() orelse return fan;
    const color = record.piece.color() orelse return fan;
    var pos: u8 = 0;

    if (m.move_type == .castle) {
        if (@intFromEnum(m.to.file) > @intFromEnum(m.from.file)) {
            const s = "O-O";
            @memcpy(fan.buf[pos..][0..s.len], s);
            pos += s.len;
        } else {
            const s = "O-O-O";
            @memcpy(fan.buf[pos..][0..s.len], s);
            pos += s.len;
        }
    } else {
        if (pt != .pawn) {
            const sym = pieceSymbol(pt, color);
            @memcpy(fan.buf[pos..][0..sym.len], sym);
            pos += @intCast(sym.len);

            const legal = chess.legalMoves(board_before);
            var need_file = false;
            var need_rank = false;
            var ambiguous = false;
            for (legal.moves[0..legal.len]) |lm| {
                if (lm.to.eql(m.to) and !lm.from.eql(m.from)) {
                    const other = board_before.pieceAt(lm.from);
                    if (other.pieceType() == pt and other.color() == color) {
                        ambiguous = true;
                        if (lm.from.file == m.from.file) need_rank = true;
                        if (lm.from.rank == m.from.rank) need_file = true;
                    }
                }
            }
            if (ambiguous) {
                if (!need_file and !need_rank) {
                    fan.buf[pos] = m.from.file.toChar();
                    pos += 1;
                } else if (need_file and need_rank) {
                    fan.buf[pos] = m.from.file.toChar();
                    pos += 1;
                    fan.buf[pos] = m.from.rank.toChar();
                    pos += 1;
                } else if (need_rank) {
                    fan.buf[pos] = m.from.rank.toChar();
                    pos += 1;
                } else {
                    fan.buf[pos] = m.from.file.toChar();
                    pos += 1;
                }
            }
        } else if (record.captured != null) {
            fan.buf[pos] = m.from.file.toChar();
            pos += 1;
        }

        if (record.captured != null) {
            fan.buf[pos] = 'x';
            pos += 1;
        }

        fan.buf[pos] = m.to.file.toChar();
        pos += 1;
        fan.buf[pos] = m.to.rank.toChar();
        pos += 1;

        if (m.move_type == .en_passant) {
            const ep = " e.p.";
            @memcpy(fan.buf[pos..][0..ep.len], ep);
            pos += ep.len;
        }

        if (m.move_type == .promotion) {
            fan.buf[pos] = '=';
            pos += 1;
            if (m.promotion_piece) |pp| {
                const sym = pieceSymbol(pp, color);
                @memcpy(fan.buf[pos..][0..sym.len], sym);
                pos += @intCast(sym.len);
            }
        }
    }

    if (chess.isCheckmate(board_after)) {
        fan.buf[pos] = '#';
        pos += 1;
    } else if (chess.isInCheck(board_after, board_after.active_color)) {
        fan.buf[pos] = '+';
        pos += 1;
    }

    fan.len = pos;
    return fan;
}

pub const Game = struct {
    board: chess.Board,
    cursor: chess.Square,
    selected: ?chess.Square,
    legal_targets: [64]bool,
    move_history: [512]MoveRecord,
    move_count: usize,
    board_history: [512]chess.Board,
    board_count: usize,
    fan_history: [512]FanNotation,
    game_phase: GamePhase,
    result: ?[]const u8,
    white_opponent: Opponent,
    black_opponent: Opponent,
    flipped: bool,
    flash_square: ?chess.Square,
    flash_timer: u8,
    promotion_pending: ?PromotionPending,
    engine_state: EngineState,
    engine_last_move: ?LastMove,
    engine_last_move_timer: u8,
    thinking_start_ns: i96,
    thinking_elapsed_s: u16,
    spinner_idx: u2,
    player_color: chess.Color,
    opening_book: ?*const openings.OpeningBook,
    current_opening: ?openings.Opening,
    opening_is_current: bool,
    resign_pending: bool,
    hints_enabled: bool,
    hint_endangered: [64]bool,
    hint_best_move: ?LastMove,

    pub fn init() Game {
        return initWithColorAndBook(.white, null);
    }

    pub fn initWithColorAndBook(player_color: chess.Color, book: ?*const openings.OpeningBook) Game {
        return .{
            .board = chess.Board.initial,
            .cursor = chess.Square.init(.e, .@"2"),
            .selected = null,
            .legal_targets = [_]bool{false} ** 64,
            .move_history = undefined,
            .move_count = 0,
            .board_history = undefined,
            .board_count = 0,
            .fan_history = undefined,
            .game_phase = .playing,
            .result = null,
            .white_opponent = if (player_color == .white) .human else .engine,
            .black_opponent = if (player_color == .black) .human else .engine,
            .flipped = player_color == .black,
            .flash_square = null,
            .flash_timer = 0,
            .promotion_pending = null,
            .engine_state = .idle,
            .engine_last_move = null,
            .engine_last_move_timer = 0,
            .thinking_start_ns = 0,
            .thinking_elapsed_s = 0,
            .spinner_idx = 0,
            .player_color = player_color,
            .opening_book = book,
            .current_opening = null,
            .opening_is_current = true,
            .resign_pending = false,
            .hints_enabled = false,
            .hint_endangered = [_]bool{false} ** 64,
            .hint_best_move = null,
        };
    }

    pub fn clearHints(self: *Game) void {
        self.hint_endangered = [_]bool{false} ** 64;
        self.hint_best_move = null;
    }

    pub fn computeEndangered(self: *Game) void {
        self.hint_endangered = [_]bool{false} ** 64;
        const friendly_color = self.board.active_color;
        const opponent_color = friendly_color.opponent();
        for (0..64) |i| {
            const piece = self.board.squares[i];
            if (piece.color()) |c| {
                if (c == friendly_color) {
                    const sq = chess.Square.fromIndex(@intCast(i));
                    if (chess.isSquareAttacked(&self.board, sq, opponent_color)) {
                        self.hint_endangered[i] = true;
                    }
                }
            }
        }
    }

    pub fn selectSquare(self: *Game) void {
        if (self.promotion_pending != null) return;
        if (self.game_phase == .ended) return;

        const cursor_piece = self.board.pieceAt(self.cursor);

        if (self.selected) |sel| {
            if (self.legal_targets[self.cursor.toIndex()]) {
                const piece = self.board.pieceAt(sel);
                if (piece.pieceType()) |pt| {
                    if (pt == .pawn) {
                        if (piece.color()) |c| {
                            if ((c == .white and self.cursor.rank == .@"8") or
                                (c == .black and self.cursor.rank == .@"1"))
                            {
                                self.promotion_pending = .{
                                    .from = sel,
                                    .to = self.cursor,
                                    .selected_idx = 0,
                                };
                                return;
                            }
                        }
                    }
                }
                self.executeMove(sel, self.cursor, null);
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

    pub fn executeMove(self: *Game, from: chess.Square, to: chess.Square, promotion: ?chess.PieceType) void {
        self.clearHints();
        const legal = chess.legalMoves(&self.board);
        var matching_move: ?chess.Move = null;

        for (legal.moves[0..legal.len]) |m| {
            if (m.from.eql(from) and m.to.eql(to)) {
                if (m.move_type == .promotion) {
                    if (promotion) |pp| {
                        if (m.promotion_piece) |mp| {
                            if (mp == pp) {
                                matching_move = m;
                                break;
                            }
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

        const record = MoveRecord{
            .move = m,
            .piece = piece,
            .captured = captured,
        };

        const board_before = self.board;

        if (self.board_count < 512) {
            self.board_history[self.board_count] = self.board;
            self.board_count += 1;
        }

        self.board = chess.makeMove(self.board, m);

        if (self.move_count < 512) {
            self.fan_history[self.move_count] = computeFan(record, &board_before, &self.board);
            self.move_history[self.move_count] = record;
            self.move_count += 1;
        }

        self.selected = null;
        self.legal_targets = [_]bool{false} ** 64;

        self.updateOpening();

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

    pub fn confirmPromotion(self: *Game) void {
        const promo = self.promotion_pending orelse return;
        const piece_type = promotion_pieces[promo.selected_idx];
        self.promotion_pending = null;
        self.executeMove(promo.from, promo.to, piece_type);
    }

    pub fn cancelPromotion(self: *Game) void {
        self.promotion_pending = null;
    }

    pub fn cyclePromotionNext(self: *Game) void {
        var pp = self.promotion_pending orelse return;
        pp.selected_idx +%= 1;
        self.promotion_pending = pp;
    }

    pub fn cyclePromotionPrev(self: *Game) void {
        var pp = self.promotion_pending orelse return;
        pp.selected_idx -%= 1;
        self.promotion_pending = pp;
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
        self.promotion_pending = null;
    }

    fn updateOpening(self: *Game) void {
        const book = self.opening_book orelse return;

        // Build UCI sequence from move history
        var uci_buf: [512 * 6]u8 = undefined;
        var uci_len: usize = 0;
        for (self.move_history[0..self.move_count]) |record| {
            if (uci_len > 0) {
                uci_buf[uci_len] = ' ';
                uci_len += 1;
            }
            var move_buf: [5]u8 = undefined;
            const uci_str = record.move.toUci(&move_buf);
            @memcpy(uci_buf[uci_len..][0..uci_str.len], uci_str);
            uci_len += uci_str.len;
        }

        // Build EPD from current board (first 4 FEN fields)
        var fen_buf: [128]u8 = undefined;
        const fen = self.board.toFen(&fen_buf);
        const epd = extractEpd(fen);

        const result = book.find(uci_buf[0..uci_len], epd);
        if (result) |opening| {
            self.current_opening = opening;
            self.opening_is_current = true;
        } else {
            self.opening_is_current = false;
        }
    }

    fn extractEpd(fen: []const u8) []const u8 {
        // EPD = first 4 space-separated fields of FEN
        var spaces: usize = 0;
        for (fen, 0..) |c, i| {
            if (c == ' ') {
                spaces += 1;
                if (spaces == 4) return fen[0..i];
            }
        }
        return fen;
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

    pub fn isEngineTurn(self: *const Game) bool {
        if (self.game_phase != .playing) return false;
        return switch (self.board.active_color) {
            .white => self.white_opponent == .engine,
            .black => self.black_opponent == .engine,
        };
    }

    pub fn tickEngineHighlight(self: *Game) void {
        if (self.engine_last_move_timer > 0) {
            self.engine_last_move_timer -= 1;
            if (self.engine_last_move_timer == 0) {
                self.engine_last_move = null;
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

    pub fn isHumanTurn(self: *const Game) bool {
        if (self.game_phase != .playing) return false;
        return switch (self.board.active_color) {
            .white => self.white_opponent == .human,
            .black => self.black_opponent == .human,
        };
    }
};

const testing = @import("std").testing;

test "clearHints zeroes all hint state" {
    var game = Game.init();
    game.hints_enabled = true;
    game.hint_endangered[0] = true;
    game.hint_endangered[63] = true;
    game.hint_best_move = .{ .from = chess.Square.init(.e, .@"2"), .to = chess.Square.init(.e, .@"4") };

    game.clearHints();

    for (0..64) |i| {
        try testing.expect(!game.hint_endangered[i]);
    }
    try testing.expect(game.hint_best_move == null);
}

test "computeEndangered marks attacked pieces on initial board" {
    var game = Game.init();
    game.hints_enabled = true;
    game.computeEndangered();

    // On the initial board with white to move, none of white's pieces are attacked
    // by black (black pawns on rank 7 don't attack rank 1 or 2)
    for (0..16) |i| {
        try testing.expect(!game.hint_endangered[i]);
    }
}

test "computeEndangered detects piece attacked by opponent" {
    var game = Game.init();
    // Set up a board: white king on e1, white pawn on d4, black pawn on e5
    game.board = chess.Board.empty();
    const wk_sq = chess.Square.init(.e, .@"1");
    const wp_sq = chess.Square.init(.d, .@"4");
    const bp_sq = chess.Square.init(.e, .@"5");
    game.board.squares[wk_sq.toIndex()] = chess.Piece.init(.white, .king);
    game.board.squares[wp_sq.toIndex()] = chess.Piece.init(.white, .pawn);
    game.board.squares[bp_sq.toIndex()] = chess.Piece.init(.black, .pawn);
    // Add black king so the position is valid
    const bk_sq = chess.Square.init(.h, .@"8");
    game.board.squares[bk_sq.toIndex()] = chess.Piece.init(.black, .king);
    game.board.active_color = .white;

    game.hints_enabled = true;
    game.computeEndangered();

    // d4 pawn is attacked diagonally by e5 pawn
    try testing.expect(game.hint_endangered[wp_sq.toIndex()]);
    // King on e1 is not attacked
    try testing.expect(!game.hint_endangered[wk_sq.toIndex()]);
}

test "computeEndangered empty board has no endangered pieces" {
    var game = Game.init();
    game.board = chess.Board.empty();
    // Just two kings
    const wk_sq = chess.Square.init(.a, .@"1");
    const bk_sq = chess.Square.init(.h, .@"8");
    game.board.squares[wk_sq.toIndex()] = chess.Piece.init(.white, .king);
    game.board.squares[bk_sq.toIndex()] = chess.Piece.init(.black, .king);
    game.board.active_color = .white;

    game.hints_enabled = true;
    game.computeEndangered();

    for (0..64) |i| {
        try testing.expect(!game.hint_endangered[i]);
    }
}

test "executeMove clears hints" {
    var game = Game.init();
    game.hints_enabled = true;
    game.hint_endangered[0] = true;
    game.hint_best_move = .{ .from = chess.Square.init(.e, .@"2"), .to = chess.Square.init(.e, .@"4") };

    // Execute e2-e4
    game.executeMove(chess.Square.init(.e, .@"2"), chess.Square.init(.e, .@"4"), null);

    for (0..64) |i| {
        try testing.expect(!game.hint_endangered[i]);
    }
    try testing.expect(game.hint_best_move == null);
}
