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
