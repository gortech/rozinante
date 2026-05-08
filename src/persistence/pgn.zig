const std = @import("std");
const chess = @import("../chess.zig");
const game = @import("../tui/game.zig");

pub const MoveRecord = game.MoveRecord;

pub const SanNotation = struct {
    buf: [24]u8,
    len: u8,

    pub fn slice(self: *const SanNotation) []const u8 {
        return self.buf[0..self.len];
    }
};

fn sanPieceLetter(pt: chess.PieceType) ?u8 {
    return switch (pt) {
        .king => 'K',
        .queen => 'Q',
        .rook => 'R',
        .bishop => 'B',
        .knight => 'N',
        .pawn => null,
    };
}

pub fn computeSan(record: MoveRecord, board_before: *const chess.Board, board_after: *const chess.Board) SanNotation {
    var san: SanNotation = .{ .buf = .{0} ** 24, .len = 0 };
    const m = record.move;
    const pt = record.piece.pieceType() orelse return san;
    var pos: u8 = 0;

    if (m.move_type == .castle) {
        if (@intFromEnum(m.to.file) > @intFromEnum(m.from.file)) {
            const s = "O-O";
            @memcpy(san.buf[pos..][0..s.len], s);
            pos += s.len;
        } else {
            const s = "O-O-O";
            @memcpy(san.buf[pos..][0..s.len], s);
            pos += s.len;
        }
    } else {
        if (pt != .pawn) {
            if (sanPieceLetter(pt)) |letter| {
                san.buf[pos] = letter;
                pos += 1;
            }

            const legal = chess.legalMoves(board_before);
            var need_file = false;
            var need_rank = false;
            var ambiguous = false;
            for (legal.moves[0..legal.len]) |lm| {
                if (lm.to.eql(m.to) and !lm.from.eql(m.from)) {
                    const other = board_before.pieceAt(lm.from);
                    if (other.pieceType() == pt and other.color() == record.piece.color()) {
                        ambiguous = true;
                        if (lm.from.file == m.from.file) need_rank = true;
                        if (lm.from.rank == m.from.rank) need_file = true;
                    }
                }
            }
            if (ambiguous) {
                if (!need_file and !need_rank) {
                    san.buf[pos] = m.from.file.toChar();
                    pos += 1;
                } else if (need_file and need_rank) {
                    san.buf[pos] = m.from.file.toChar();
                    pos += 1;
                    san.buf[pos] = m.from.rank.toChar();
                    pos += 1;
                } else if (need_rank) {
                    san.buf[pos] = m.from.rank.toChar();
                    pos += 1;
                } else {
                    san.buf[pos] = m.from.file.toChar();
                    pos += 1;
                }
            }
        } else if (record.captured != null) {
            san.buf[pos] = m.from.file.toChar();
            pos += 1;
        }

        if (record.captured != null) {
            san.buf[pos] = 'x';
            pos += 1;
        }

        san.buf[pos] = m.to.file.toChar();
        pos += 1;
        san.buf[pos] = m.to.rank.toChar();
        pos += 1;

        if (m.move_type == .promotion) {
            san.buf[pos] = '=';
            pos += 1;
            if (m.promotion_piece) |pp| {
                if (sanPieceLetter(pp)) |letter| {
                    san.buf[pos] = letter;
                    pos += 1;
                }
            }
        }
    }

    if (chess.isCheckmate(board_after)) {
        san.buf[pos] = '#';
        pos += 1;
    } else if (chess.isInCheck(board_after, board_after.active_color)) {
        san.buf[pos] = '+';
        pos += 1;
    }

    san.len = pos;
    return san;
}

pub const PgnHeader = struct {
    event: []const u8 = "Rozinante",
    site: []const u8 = "Local",
    date: []const u8 = "????.??.??",
    round: []const u8 = "-",
    white: []const u8 = "?",
    black: []const u8 = "?",
    result: []const u8 = "*",
};

pub const PgnError = error{BufferTooSmall};

fn appendSlice(buf: []u8, pos: usize, data: []const u8) PgnError!usize {
    if (pos + data.len > buf.len) return error.BufferTooSmall;
    @memcpy(buf[pos..][0..data.len], data);
    return pos + data.len;
}

fn appendTag(buf: []u8, pos: usize, name: []const u8, value: []const u8) PgnError!usize {
    var p = pos;
    p = try appendSlice(buf, p, "[");
    p = try appendSlice(buf, p, name);
    p = try appendSlice(buf, p, " \"");
    p = try appendSlice(buf, p, value);
    p = try appendSlice(buf, p, "\"]\n");
    return p;
}

pub fn writePgn(
    buf: []u8,
    header: PgnHeader,
    move_records: []const MoveRecord,
    board_history: []const chess.Board,
) PgnError![]const u8 {
    var pos: usize = 0;

    pos = try appendTag(buf, pos, "Event", header.event);
    pos = try appendTag(buf, pos, "Site", header.site);
    pos = try appendTag(buf, pos, "Date", header.date);
    pos = try appendTag(buf, pos, "Round", header.round);
    pos = try appendTag(buf, pos, "White", header.white);
    pos = try appendTag(buf, pos, "Black", header.black);
    pos = try appendTag(buf, pos, "Result", header.result);
    pos = try appendSlice(buf, pos, "\n");

    var line_len: usize = 0;
    for (move_records, 0..) |record, i| {
        var token_buf: [32]u8 = undefined;
        var token_len: usize = 0;

        if (i % 2 == 0) {
            const move_num = i / 2 + 1;
            const num_str = std.fmt.bufPrint(&token_buf, "{}. ", .{move_num}) catch unreachable;
            token_len = num_str.len;
        }

        const san = computeSan(record, &board_history[i], &board_history[i + 1]);
        const san_str = san.slice();
        @memcpy(token_buf[token_len..][0..san_str.len], san_str);
        token_len += san_str.len;

        const token = token_buf[0..token_len];

        if (line_len > 0 and line_len + 1 + token.len > 80) {
            pos = try appendSlice(buf, pos, "\n");
            line_len = 0;
        }

        if (line_len > 0) {
            pos = try appendSlice(buf, pos, " ");
            line_len += 1;
        }

        pos = try appendSlice(buf, pos, token);
        line_len += token.len;
    }

    if (line_len > 0) {
        if (line_len + 1 + header.result.len > 80) {
            pos = try appendSlice(buf, pos, "\n");
        } else {
            pos = try appendSlice(buf, pos, " ");
        }
    }
    pos = try appendSlice(buf, pos, header.result);
    pos = try appendSlice(buf, pos, "\n");

    return buf[0..pos];
}

// ---------------------------------------------------------------------------
// PGN Parser
// ---------------------------------------------------------------------------

pub const ParseError = error{
    InvalidSan,
    AmbiguousMove,
    NoLegalMove,
    InvalidTag,
    InvalidPgn,
};

pub const ParsedMove = struct {
    move: chess.Move,
    piece: chess.Piece,
    captured: ?chess.Piece,
};

pub const MAX_GAME_MOVES = 512;

pub const ParsedGame = struct {
    event: ?[]const u8 = null,
    site: ?[]const u8 = null,
    date: ?[]const u8 = null,
    round: ?[]const u8 = null,
    white: ?[]const u8 = null,
    black: ?[]const u8 = null,
    result: ?[]const u8 = null,

    moves: [MAX_GAME_MOVES]ParsedMove = undefined,
    move_count: usize = 0,
    final_board: chess.Board = chess.Board.initial,
};

fn pieceTypeFromSanLetter(c: u8) ?chess.PieceType {
    return switch (c) {
        'K' => .king,
        'Q' => .queen,
        'R' => .rook,
        'B' => .bishop,
        'N' => .knight,
        else => null,
    };
}

pub fn sanToMove(b: *const chess.Board, san: []const u8) ParseError!chess.Move {
    if (san.len == 0) return error.InvalidSan;

    var s = san;

    // Strip trailing +, #, !, ? annotations
    while (s.len > 0 and (s[s.len - 1] == '+' or s[s.len - 1] == '#' or
        s[s.len - 1] == '!' or s[s.len - 1] == '?'))
    {
        s = s[0 .. s.len - 1];
    }
    if (s.len == 0) return error.InvalidSan;

    // Castling
    if (std.mem.eql(u8, s, "O-O") or std.mem.eql(u8, s, "O-O-O")) {
        const is_kingside = std.mem.eql(u8, s, "O-O");
        const legal = chess.legalMoves(b);
        for (legal.moves[0..legal.len]) |m| {
            if (m.move_type == .castle) {
                const king_side = @intFromEnum(m.to.file) > @intFromEnum(m.from.file);
                if (king_side == is_kingside) return m;
            }
        }
        return error.NoLegalMove;
    }

    // Parse SAN components
    var pt: chess.PieceType = .pawn;
    var idx: usize = 0;

    // Piece letter
    if (s.len > 0 and pieceTypeFromSanLetter(s[0]) != null) {
        pt = pieceTypeFromSanLetter(s[0]).?;
        idx += 1;
    }

    // Collect remaining chars to parse: disambiguation, capture, destination, promotion
    const rest = s[idx..];
    if (rest.len < 2) return error.InvalidSan;

    // Parse from right: promotion, then destination square, then optional capture, then disambiguation
    var rlen = rest.len;
    var promo_piece: ?chess.PieceType = null;

    // Check for promotion: =Q, =R, =B, =N
    if (rlen >= 2 and rest[rlen - 2] == '=') {
        promo_piece = pieceTypeFromSanLetter(rest[rlen - 1]);
        if (promo_piece == null) return error.InvalidSan;
        rlen -= 2;
    }

    // Last two chars must be destination square
    if (rlen < 2) return error.InvalidSan;
    const dest_file = chess.File.fromChar(rest[rlen - 2]) orelse return error.InvalidSan;
    const dest_rank = chess.Rank.fromChar(rest[rlen - 1]) orelse return error.InvalidSan;
    const dest = chess.Square.init(dest_file, dest_rank);
    rlen -= 2;

    // Optional capture marker
    if (rlen > 0 and rest[rlen - 1] == 'x') {
        rlen -= 1;
    }

    // Remaining chars are disambiguation (file, rank, or both)
    var disambig_file: ?chess.File = null;
    var disambig_rank: ?chess.Rank = null;
    const disambig = rest[0..rlen];
    for (disambig) |c| {
        if (chess.File.fromChar(c)) |f| {
            disambig_file = f;
        } else if (chess.Rank.fromChar(c)) |r| {
            disambig_rank = r;
        } else {
            return error.InvalidSan;
        }
    }

    // Generate legal moves and filter
    const legal = chess.legalMoves(b);
    var match: ?chess.Move = null;
    var match_count: u32 = 0;

    for (legal.moves[0..legal.len]) |m| {
        const moved_piece = b.pieceAt(m.from);
        const moved_pt = moved_piece.pieceType() orelse continue;
        if (moved_pt != pt) continue;
        if (!m.to.eql(dest)) continue;

        // Check promotion match
        if (promo_piece != null) {
            if (m.move_type != .promotion or m.promotion_piece != promo_piece) continue;
        } else {
            if (m.move_type == .promotion) continue;
        }

        // Check disambiguation
        if (disambig_file) |f| {
            if (m.from.file != f) continue;
        }
        if (disambig_rank) |r| {
            if (m.from.rank != r) continue;
        }

        match = m;
        match_count += 1;
    }

    if (match_count == 0) return error.NoLegalMove;
    if (match_count > 1) return error.AmbiguousMove;
    return match.?;
}

fn isResultToken(token: []const u8) bool {
    return std.mem.eql(u8, token, "1-0") or
        std.mem.eql(u8, token, "0-1") or
        std.mem.eql(u8, token, "1/2-1/2") or
        std.mem.eql(u8, token, "*");
}

fn isMoveNumber(token: []const u8) bool {
    if (token.len == 0) return false;
    // Move numbers: digits followed by one or more dots (e.g. "1.", "12.", "1...")
    var i: usize = 0;
    while (i < token.len and token[i] >= '0' and token[i] <= '9') : (i += 1) {}
    if (i == 0) return false;
    while (i < token.len and token[i] == '.') : (i += 1) {}
    return i == token.len;
}

pub fn parseTags(text: []const u8) struct { game: ParsedGame, movetext_start: usize } {
    var g = ParsedGame{};
    var pos: usize = 0;

    while (pos < text.len) {
        // Skip whitespace
        while (pos < text.len and (text[pos] == ' ' or text[pos] == '\t' or text[pos] == '\r' or text[pos] == '\n')) : (pos += 1) {}
        if (pos >= text.len or text[pos] != '[') break;

        // Find end of tag line
        const line_start = pos;
        while (pos < text.len and text[pos] != '\n') : (pos += 1) {}
        const line = text[line_start..pos];
        if (pos < text.len) pos += 1; // skip newline

        // Parse [Key "Value"]
        if (line.len < 5 or line[0] != '[' or line[line.len - 1] != ']') continue;
        const inner = line[1 .. line.len - 1];

        // Find space separating key from value
        const space_idx = std.mem.indexOfScalar(u8, inner, ' ') orelse continue;
        const key = inner[0..space_idx];
        const val_part = inner[space_idx + 1 ..];

        // Value is in quotes
        if (val_part.len < 2 or val_part[0] != '"' or val_part[val_part.len - 1] != '"') continue;
        const value = val_part[1 .. val_part.len - 1];

        if (std.mem.eql(u8, key, "Event")) {
            g.event = value;
        } else if (std.mem.eql(u8, key, "Site")) {
            g.site = value;
        } else if (std.mem.eql(u8, key, "Date")) {
            g.date = value;
        } else if (std.mem.eql(u8, key, "Round")) {
            g.round = value;
        } else if (std.mem.eql(u8, key, "White")) {
            g.white = value;
        } else if (std.mem.eql(u8, key, "Black")) {
            g.black = value;
        } else if (std.mem.eql(u8, key, "Result")) {
            g.result = value;
        }
    }

    return .{ .game = g, .movetext_start = pos };
}

pub const MovetextResult = struct {
    moves: [MAX_GAME_MOVES]ParsedMove = undefined,
    count: usize = 0,
    final_board: chess.Board = chess.Board.initial,
};

pub fn parseMovetext(text: []const u8, initial_board: chess.Board) ParseError!MovetextResult {
    var result = MovetextResult{
        .final_board = initial_board,
    };
    var board = initial_board;
    var pos: usize = 0;

    while (pos < text.len) {
        // Skip whitespace
        while (pos < text.len and (text[pos] == ' ' or text[pos] == '\t' or text[pos] == '\r' or text[pos] == '\n')) : (pos += 1) {}
        if (pos >= text.len) break;

        // Skip comments in braces
        if (text[pos] == '{') {
            while (pos < text.len and text[pos] != '}') : (pos += 1) {}
            if (pos < text.len) pos += 1;
            continue;
        }

        // Read token
        const tok_start = pos;
        while (pos < text.len and text[pos] != ' ' and text[pos] != '\t' and text[pos] != '\r' and text[pos] != '\n') : (pos += 1) {}
        const token = text[tok_start..pos];
        if (token.len == 0) continue;

        // Skip move numbers and result tokens
        if (isMoveNumber(token)) continue;
        if (isResultToken(token)) continue;

        // This should be a SAN move
        const m = try sanToMove(&board, token);
        const piece = board.pieceAt(m.from);
        const captured_raw = board.pieceAt(m.to);
        const captured: ?chess.Piece = if (m.move_type == .en_passant)
            chess.Piece.init(board.active_color.opponent(), .pawn)
        else if (captured_raw != .empty)
            captured_raw
        else
            null;

        if (result.count >= MAX_GAME_MOVES) return error.InvalidPgn;
        result.moves[result.count] = .{ .move = m, .piece = piece, .captured = captured };
        result.count += 1;
        board = chess.makeMove(board, m);
    }

    result.final_board = board;
    return result;
}

pub fn parsePgn(text: []const u8) ParseError!ParsedGame {
    const tag_result = parseTags(text);
    var g = tag_result.game;

    const movetext = text[tag_result.movetext_start..];
    const move_result = try parseMovetext(movetext, chess.Board.initial);

    g.moves = move_result.moves;
    g.move_count = move_result.count;
    g.final_board = move_result.final_board;

    return g;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn makeRecord(piece: chess.Piece, m: chess.Move, captured: ?chess.Piece) MoveRecord {
    return .{ .move = m, .piece = piece, .captured = captured };
}

fn sq(file: chess.File, rank: chess.Rank) chess.Square {
    return chess.Square.init(file, rank);
}

test "SAN: pawn push e4" {
    const b = chess.Board.initial;
    const m = chess.Move.init(sq(.e, .@"2"), sq(.e, .@"4"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_pawn, m, null);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("e4", san.slice());
}

test "SAN: knight Nf3" {
    const b = chess.Board.initial;
    const m = chess.Move.init(sq(.g, .@"1"), sq(.f, .@"3"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_knight, m, null);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("Nf3", san.slice());
}

test "SAN: kingside castle O-O" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.castling_rights = .{ .white_kingside = true, .white_queenside = false, .black_kingside = false, .black_queenside = false };
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.h, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = chess.Move.initCastle(sq(.e, .@"1"), sq(.g, .@"1"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_king, m, null);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("O-O", san.slice());
}

test "SAN: queenside castle O-O-O" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.castling_rights = .{ .white_kingside = false, .white_queenside = true, .black_kingside = false, .black_queenside = false };
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.a, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = chess.Move.initCastle(sq(.e, .@"1"), sq(.c, .@"1"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_king, m, null);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("O-O-O", san.slice());
}

test "SAN: pawn capture exd5" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.e, .@"4"), .white_pawn);
    b.setPiece(sq(.d, .@"5"), .black_pawn);
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = chess.Move.init(sq(.e, .@"4"), sq(.d, .@"5"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_pawn, m, chess.Piece.black_pawn);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("exd5", san.slice());
}

test "SAN: bishop capture Bxc6" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.b, .@"5"), .white_bishop);
    b.setPiece(sq(.c, .@"6"), .black_knight);
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.h, .@"8"), .black_king);

    const m = chess.Move.init(sq(.b, .@"5"), sq(.c, .@"6"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_bishop, m, chess.Piece.black_knight);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("Bxc6", san.slice());
}

test "SAN: promotion e8=Q" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.e, .@"7"), .white_pawn);
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.h, .@"6"), .black_king);

    const m = chess.Move.initPromotion(sq(.e, .@"7"), sq(.e, .@"8"), .queen);
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_pawn, m, null);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("e8=Q", san.slice());
}

test "SAN: en passant exd6 (no e.p. suffix)" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.e, .@"5"), .white_pawn);
    b.setPiece(sq(.d, .@"5"), .black_pawn);
    b.en_passant_square = sq(.d, .@"6");
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = chess.Move.initEnPassant(sq(.e, .@"5"), sq(.d, .@"6"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_pawn, m, chess.Piece.black_pawn);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("exd6", san.slice());
}

test "SAN: rook disambiguation Rae1" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.a, .@"1"), .white_rook);
    b.setPiece(sq(.f, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"2"), .white_king);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = chess.Move.init(sq(.a, .@"1"), sq(.e, .@"1"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_rook, m, null);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("Rae1", san.slice());
}

test "SAN: check notation" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.a, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = chess.Move.init(sq(.a, .@"1"), sq(.a, .@"8"));
    const b_after = chess.makeMove(b, m);
    const record = makeRecord(chess.Piece.white_rook, m, null);
    const san = computeSan(record, &b, &b_after);
    try std.testing.expectEqualStrings("Ra8+", san.slice());
}

test "writePgn: short game" {
    var boards: [5]chess.Board = undefined;
    boards[0] = chess.Board.initial;

    const moves = [_]struct { from: chess.Square, to: chess.Square }{
        .{ .from = sq(.e, .@"2"), .to = sq(.e, .@"4") },
        .{ .from = sq(.e, .@"7"), .to = sq(.e, .@"5") },
        .{ .from = sq(.g, .@"1"), .to = sq(.f, .@"3") },
        .{ .from = sq(.b, .@"8"), .to = sq(.c, .@"6") },
    };

    var records: [4]MoveRecord = undefined;
    for (moves, 0..) |mv, i| {
        const m = chess.Move.init(mv.from, mv.to);
        const piece = boards[i].pieceAt(mv.from);
        const captured_piece = boards[i].pieceAt(mv.to);
        const captured = if (captured_piece != .empty) captured_piece else null;
        records[i] = makeRecord(piece, m, captured);
        boards[i + 1] = chess.makeMove(boards[i], m);
    }

    const header = PgnHeader{
        .event = "Test",
        .date = "2026.05.07",
        .white = "Alice",
        .black = "Bob",
        .result = "*",
    };

    var buf: [2048]u8 = undefined;
    const output = try writePgn(&buf, header, &records, &boards);

    try std.testing.expect(std.mem.indexOf(u8, output, "[Event \"Test\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[White \"Alice\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[Black \"Bob\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[Date \"2026.05.07\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1. e4 e5 2. Nf3 Nc6") != null);
    try std.testing.expect(std.mem.endsWith(u8, output, "*\n"));
}

// ---------------------------------------------------------------------------
// Parser Tests
// ---------------------------------------------------------------------------

test "parseTags: extracts seven tag roster" {
    const pgn =
        \\[Event "Rozinante"]
        \\[Site "Local"]
        \\[Date "2026.05.07"]
        \\[Round "-"]
        \\[White "Player"]
        \\[Black "Stockfish"]
        \\[Result "1-0"]
        \\
        \\1. e4 e5 1-0
    ;
    const result = parseTags(pgn);
    try std.testing.expectEqualStrings("Rozinante", result.game.event.?);
    try std.testing.expectEqualStrings("Local", result.game.site.?);
    try std.testing.expectEqualStrings("2026.05.07", result.game.date.?);
    try std.testing.expectEqualStrings("-", result.game.round.?);
    try std.testing.expectEqualStrings("Player", result.game.white.?);
    try std.testing.expectEqualStrings("Stockfish", result.game.black.?);
    try std.testing.expectEqualStrings("1-0", result.game.result.?);
}

test "sanToMove: pawn push e4" {
    const b = chess.Board.initial;
    const m = try sanToMove(&b, "e4");
    try std.testing.expect(m.from.eql(sq(.e, .@"2")));
    try std.testing.expect(m.to.eql(sq(.e, .@"4")));
}

test "sanToMove: knight Nf3" {
    const b = chess.Board.initial;
    const m = try sanToMove(&b, "Nf3");
    try std.testing.expect(m.from.eql(sq(.g, .@"1")));
    try std.testing.expect(m.to.eql(sq(.f, .@"3")));
}

test "sanToMove: capture Bxc6" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.b, .@"5"), .white_bishop);
    b.setPiece(sq(.c, .@"6"), .black_knight);
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.h, .@"8"), .black_king);

    const m = try sanToMove(&b, "Bxc6");
    try std.testing.expect(m.from.eql(sq(.b, .@"5")));
    try std.testing.expect(m.to.eql(sq(.c, .@"6")));
}

test "sanToMove: kingside castle O-O" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.castling_rights = .{ .white_kingside = true, .white_queenside = false, .black_kingside = false, .black_queenside = false };
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.h, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = try sanToMove(&b, "O-O");
    try std.testing.expectEqual(chess.MoveType.castle, m.move_type);
    try std.testing.expect(m.to.eql(sq(.g, .@"1")));
}

test "sanToMove: queenside castle O-O-O" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.castling_rights = .{ .white_kingside = false, .white_queenside = true, .black_kingside = false, .black_queenside = false };
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.a, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = try sanToMove(&b, "O-O-O");
    try std.testing.expectEqual(chess.MoveType.castle, m.move_type);
    try std.testing.expect(m.to.eql(sq(.c, .@"1")));
}

test "sanToMove: promotion e8=Q" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.e, .@"7"), .white_pawn);
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.h, .@"6"), .black_king);

    const m = try sanToMove(&b, "e8=Q");
    try std.testing.expectEqual(chess.MoveType.promotion, m.move_type);
    try std.testing.expectEqual(chess.PieceType.queen, m.promotion_piece.?);
    try std.testing.expect(m.to.eql(sq(.e, .@"8")));
}

test "sanToMove: disambiguation Rae1" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.a, .@"1"), .white_rook);
    b.setPiece(sq(.f, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"2"), .white_king);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = try sanToMove(&b, "Rae1");
    try std.testing.expect(m.from.eql(sq(.a, .@"1")));
    try std.testing.expect(m.to.eql(sq(.e, .@"1")));
}

test "sanToMove: strips check/checkmate suffixes" {
    var b = chess.Board.empty();
    b.active_color = .white;
    b.setPiece(sq(.a, .@"1"), .white_rook);
    b.setPiece(sq(.e, .@"1"), .white_king);
    b.setPiece(sq(.e, .@"8"), .black_king);

    const m = try sanToMove(&b, "Ra8+");
    try std.testing.expect(m.to.eql(sq(.a, .@"8")));
}

test "parsePgn: full game parse" {
    const pgn =
        \\[Event "Test"]
        \\[Site "Local"]
        \\[Date "2026.05.07"]
        \\[Round "-"]
        \\[White "Alice"]
        \\[Black "Bob"]
        \\[Result "*"]
        \\
        \\1. e4 e5 2. Nf3 Nc6 *
    ;
    const g = try parsePgn(pgn);
    try std.testing.expectEqualStrings("Test", g.event.?);
    try std.testing.expectEqualStrings("Alice", g.white.?);
    try std.testing.expectEqualStrings("Bob", g.black.?);
    try std.testing.expectEqual(@as(usize, 4), g.move_count);
}

test "parsePgn: round-trip writePgn then parsePgn" {
    var boards: [5]chess.Board = undefined;
    boards[0] = chess.Board.initial;

    const move_defs = [_]struct { from: chess.Square, to: chess.Square }{
        .{ .from = sq(.e, .@"2"), .to = sq(.e, .@"4") },
        .{ .from = sq(.e, .@"7"), .to = sq(.e, .@"5") },
        .{ .from = sq(.g, .@"1"), .to = sq(.f, .@"3") },
        .{ .from = sq(.b, .@"8"), .to = sq(.c, .@"6") },
    };

    var records: [4]MoveRecord = undefined;
    for (move_defs, 0..) |mv, i| {
        const m = chess.Move.init(mv.from, mv.to);
        const piece = boards[i].pieceAt(mv.from);
        const captured_piece = boards[i].pieceAt(mv.to);
        const captured = if (captured_piece != .empty) captured_piece else null;
        records[i] = makeRecord(piece, m, captured);
        boards[i + 1] = chess.makeMove(boards[i], m);
    }

    const header = PgnHeader{
        .event = "RoundTrip",
        .white = "W",
        .black = "B",
        .result = "1-0",
    };

    var buf: [4096]u8 = undefined;
    const pgn_text = try writePgn(&buf, header, &records, &boards);

    const parsed = try parsePgn(pgn_text);
    try std.testing.expectEqual(@as(usize, 4), parsed.move_count);

    // Verify each parsed move matches the original
    for (0..4) |i| {
        try std.testing.expect(parsed.moves[i].move.eql(records[i].move));
    }
}

test "parsePgn: handles all result tokens" {
    const results = [_][]const u8{ "1-0", "0-1", "1/2-1/2", "*" };
    for (results) |result_token| {
        var pgn_buf: [512]u8 = undefined;
        const prefix = "[Event \"T\"]\n[Site \"L\"]\n[Date \"?\"]\n[Round \"-\"]\n[White \"W\"]\n[Black \"B\"]\n[Result \"";
        @memcpy(pgn_buf[0..prefix.len], prefix);
        var p: usize = prefix.len;
        @memcpy(pgn_buf[p..][0..result_token.len], result_token);
        p += result_token.len;
        const suffix = "\"]\n\n";
        @memcpy(pgn_buf[p..][0..suffix.len], suffix);
        p += suffix.len;
        @memcpy(pgn_buf[p..][0..result_token.len], result_token);
        p += result_token.len;
        const pgn_text = pgn_buf[0..p];

        const g = try parsePgn(pgn_text);
        try std.testing.expectEqualStrings(result_token, g.result.?);
        try std.testing.expectEqual(@as(usize, 0), g.move_count);
    }
}

test "parsePgn: empty PGN string" {
    const g = try parsePgn("");
    try std.testing.expectEqual(@as(usize, 0), g.move_count);
    try std.testing.expectEqual(@as(?[]const u8, null), g.event);
}

test "parsePgn: headers only, no movetext" {
    const pgn =
        \\[Event "NoMoves"]
        \\[Site "Local"]
        \\[Date "2026.05.07"]
        \\[Round "-"]
        \\[White "W"]
        \\[Black "B"]
        \\[Result "*"]
    ;
    const g = try parsePgn(pgn);
    try std.testing.expectEqual(@as(usize, 0), g.move_count);
    try std.testing.expectEqualStrings("NoMoves", g.event.?);
}

test "sanToMove: invalid SAN returns error" {
    const b = chess.Board.initial;
    try std.testing.expectError(error.InvalidSan, sanToMove(&b, "Zx9"));
    try std.testing.expectError(error.InvalidSan, sanToMove(&b, ""));
    try std.testing.expectError(error.InvalidSan, sanToMove(&b, "e9"));
}

test "parsePgn: invalid SAN in movetext returns error" {
    const pgn =
        \\[Event "Bad"]
        \\[Result "*"]
        \\
        \\1. Zx9 *
    ;
    try std.testing.expectError(error.InvalidSan, parsePgn(pgn));
}
