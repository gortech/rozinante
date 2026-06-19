const std = @import("std");
const chess = @import("../chess.zig");
const game = @import("../tui/game.zig");
const analysis = @import("../analysis.zig");

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
    ga: ?*const analysis.GameAnalysis,
) PgnError![]const u8 {
    var pos: usize = 0;

    pos = try appendTag(buf, pos, "Event", header.event);
    pos = try appendTag(buf, pos, "Site", header.site);
    pos = try appendTag(buf, pos, "Date", header.date);
    pos = try appendTag(buf, pos, "Round", header.round);
    pos = try appendTag(buf, pos, "White", header.white);
    pos = try appendTag(buf, pos, "Black", header.black);
    pos = try appendTag(buf, pos, "Result", header.result);

    if (ga) |a| {
        var hbuf: [96]u8 = undefined;
        var abuf: [16]u8 = undefined;
        const acc_str = if (a.accuracy) |acc|
            (std.fmt.bufPrint(&abuf, "{d:.1}", .{acc}) catch "-")
        else
            "-";
        const val = std.fmt.bufPrint(&hbuf, "v{d} plies={d} bad={d} meh={d} acc={s}", .{
            a.version, a.plies_covered, a.blunders, a.inaccuracies, acc_str,
        }) catch return error.BufferTooSmall;
        pos = try appendTag(buf, pos, "RozAnalysis", val);
    }
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

        if (ga) |a| {
            if (i < a.count) {
                var cbuf: [64]u8 = undefined;
                const comment = formatRozComment(&cbuf, a.moves[i], &board_history[i]);
                if (line_len > 0 and line_len + 1 + comment.len > 80) {
                    pos = try appendSlice(buf, pos, "\n");
                    line_len = 0;
                }
                if (line_len > 0) {
                    pos = try appendSlice(buf, pos, " ");
                    line_len += 1;
                }
                pos = try appendSlice(buf, pos, comment);
                line_len += comment.len;
            }
        }
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

    /// Raw value of the custom `[RozAnalysis "..."]` tag, if present (slice into input).
    roz_analysis: ?[]const u8 = null,
    /// Per-ply `{...}` comment content (slice into input); null where a ply had none.
    comments: [MAX_GAME_MOVES]?[]const u8 = [_]?[]const u8{null} ** MAX_GAME_MOVES,

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
        } else if (std.mem.eql(u8, key, "RozAnalysis")) {
            g.roz_analysis = value;
        }
    }

    return .{ .game = g, .movetext_start = pos };
}

pub const MovetextResult = struct {
    moves: [MAX_GAME_MOVES]ParsedMove = undefined,
    count: usize = 0,
    final_board: chess.Board = chess.Board.initial,
    comments: [MAX_GAME_MOVES]?[]const u8 = [_]?[]const u8{null} ** MAX_GAME_MOVES,
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

        // Capture brace comments and attach to the preceding ply (instead of discarding).
        if (text[pos] == '{') {
            const content_start = pos + 1;
            while (pos < text.len and text[pos] != '}') : (pos += 1) {}
            const content_end = pos;
            if (pos < text.len) pos += 1; // skip '}'
            if (result.count > 0) {
                result.comments[result.count - 1] = text[content_start..content_end];
            }
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
    g.comments = move_result.comments;

    return g;
}

// ---------------------------------------------------------------------------
// Analysis annotation round-trip (U3): per-move `{roz: ...}` comments + a single
// `[RozAnalysis "..."]` header tag. Keeps the file valid for standard PGN tools.
// ---------------------------------------------------------------------------

comptime {
    // GameAnalysis.moves must hold every ply a game can reach.
    if (analysis.max_plies < MAX_GAME_MOVES) @compileError("analysis.max_plies < MAX_GAME_MOVES");
}

/// Encode an eval for a `{roz: ...}` comment: integer centipawns, or `#N` for mate.
fn encodeEval(buf: []u8, e: analysis.Eval) []const u8 {
    return switch (e) {
        .cp => |c| std.fmt.bufPrint(buf, "{d}", .{c}) catch "0",
        .mate => |n| std.fmt.bufPrint(buf, "#{d}", .{n}) catch "#0",
    };
}

/// Decode an eval token (`120`, `-50`, `#3`, `#-2`). Null on malformation.
fn decodeEval(s: []const u8) ?analysis.Eval {
    if (s.len == 0) return null;
    if (s[0] == '#') return .{ .mate = std.fmt.parseInt(i32, s[1..], 10) catch return null };
    return .{ .cp = std.fmt.parseInt(i32, s, 10) catch return null };
}

fn tierStr(t: ?analysis.Tier) []const u8 {
    return switch (t orelse return "-") {
        .good => "good",
        .meh => "meh",
        .bad => "bad",
    };
}

/// Parse a tier token. `-` and any unknown token → null (engine ply / no tier).
fn parseTier(s: []const u8) ?analysis.Tier {
    if (std.mem.eql(u8, s, "good")) return .good;
    if (std.mem.eql(u8, s, "meh")) return .meh;
    if (std.mem.eql(u8, s, "bad")) return .bad;
    return null;
}

/// SAN of a hypothetical move from `board_before` (used for the engine's best move).
fn sanForMove(board_before: *const chess.Board, m: chess.Move) SanNotation {
    const piece = board_before.pieceAt(m.from);
    const captured_raw = board_before.pieceAt(m.to);
    const captured: ?chess.Piece = if (m.move_type == .en_passant)
        chess.Piece.init(board_before.active_color.opponent(), .pawn)
    else if (captured_raw != .empty)
        captured_raw
    else
        null;
    const after = chess.makeMove(board_before.*, m);
    return computeSan(.{ .move = m, .piece = piece, .captured = captured }, board_before, &after);
}

/// Format one ply's analysis as a `{roz: TIER best=SAN eval=ENC cpl=N}` comment.
/// `eval` is the best-line eval (the value the viewer displays); `cpl` is the loss.
fn formatRozComment(buf: []u8, m: analysis.MoveAnalysis, board_before: *const chess.Board) []const u8 {
    var eval_buf: [16]u8 = undefined;
    const eval_enc = encodeEval(&eval_buf, m.best_eval);
    if (m.best) |bm| {
        const san = sanForMove(board_before, bm);
        return std.fmt.bufPrint(buf, "{{roz: {s} best={s} eval={s} cpl={d}}}", .{
            tierStr(m.tier), san.slice(), eval_enc, m.cpl,
        }) catch "{roz:}";
    }
    return std.fmt.bufPrint(buf, "{{roz: {s} best=- eval={s} cpl={d}}}", .{
        tierStr(m.tier), eval_enc, m.cpl,
    }) catch "{roz:}";
}

/// Fields recovered from one `{roz: ...}` comment.
pub const ParsedRoz = struct {
    tier: ?analysis.Tier,
    best: ?chess.Move,
    best_eval: analysis.Eval,
    cpl: i32,
};

/// Best-effort, fault-isolated parse of one brace comment. Returns null when the
/// comment is not a `roz:` comment OR is malformed in any way (bad best-SAN, garbage
/// eval/cpl) — the caller then treats the ply as unanalyzed, which fails the
/// completeness gate so the game is re-analyzed. NEVER throws (one bad annotation must
/// not abort `parsePgn`).
pub fn parseRozComment(comment: []const u8, board_before: *const chess.Board) ?ParsedRoz {
    const trimmed = std.mem.trim(u8, comment, " \t");
    if (!std.mem.startsWith(u8, trimmed, "roz:")) return null;
    var it = std.mem.tokenizeScalar(u8, trimmed["roz:".len..], ' ');
    const tier = parseTier(it.next() orelse return null);
    var best: ?chess.Move = null;
    var best_eval: ?analysis.Eval = null;
    var cpl: ?i32 = null;
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "best=")) {
            const v = tok["best=".len..];
            best = if (std.mem.eql(u8, v, "-")) null else (sanToMove(board_before, v) catch return null);
        } else if (std.mem.startsWith(u8, tok, "eval=")) {
            best_eval = decodeEval(tok["eval=".len..]) orelse return null;
        } else if (std.mem.startsWith(u8, tok, "cpl=")) {
            cpl = std.fmt.parseInt(i32, tok["cpl=".len..], 10) catch return null;
        }
    }
    if (best_eval == null or cpl == null) return null;
    return .{ .tier = tier, .best = best, .best_eval = best_eval.?, .cpl = cpl.? };
}

/// Parsed `[RozAnalysis "..."]` header value: the cheap per-game summary + marker.
pub const RozHeader = struct {
    version: u8,
    plies: u16,
    blunders: u16,
    inaccuracies: u16,
    accuracy: ?f32,
};

/// Parse a `v1 plies=80 bad=3 meh=5 acc=78.4` header value (`acc=-` → null). Null on
/// malformation or a missing ply-count (the marker is meaningless without it).
pub fn parseRozHeaderValue(value: []const u8) ?RozHeader {
    var it = std.mem.tokenizeScalar(u8, value, ' ');
    const vtok = it.next() orelse return null;
    if (vtok.len < 2 or vtok[0] != 'v') return null;
    const version = std.fmt.parseInt(u8, vtok[1..], 10) catch return null;
    var plies: ?u16 = null;
    var bad: u16 = 0;
    var meh: u16 = 0;
    var acc: ?f32 = null;
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "plies=")) {
            plies = std.fmt.parseInt(u16, tok["plies=".len..], 10) catch return null;
        } else if (std.mem.startsWith(u8, tok, "bad=")) {
            bad = std.fmt.parseInt(u16, tok["bad=".len..], 10) catch 0;
        } else if (std.mem.startsWith(u8, tok, "meh=")) {
            meh = std.fmt.parseInt(u16, tok["meh=".len..], 10) catch 0;
        } else if (std.mem.startsWith(u8, tok, "acc=")) {
            const v = tok["acc=".len..];
            if (!std.mem.eql(u8, v, "-")) acc = std.fmt.parseFloat(f32, v) catch null;
        }
    }
    if (plies == null) return null;
    return .{ .version = version, .plies = plies.?, .blunders = bad, .inaccuracies = meh, .accuracy = acc };
}

/// Cheaply scan PGN text for the `[RozAnalysis "..."]` tag (no movetext parse), like
/// `readResultTag`. Null when absent or malformed.
pub fn readAnalysisHeader(text: []const u8) ?RozHeader {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        const prefix = "[RozAnalysis \"";
        if (std.mem.startsWith(u8, trimmed, prefix)) {
            const start = prefix.len;
            const end = std.mem.indexOf(u8, trimmed[start..], "\"]") orelse continue;
            return parseRozHeaderValue(trimmed[start .. start + end]);
        }
    }
    return null;
}

/// Reconstruct a `GameAnalysis` from a parsed game + the boards before each ply.
/// Completeness-gated (R11): returns null — meaning "unanalyzed, re-run the pass" —
/// unless the `RozAnalysis` marker is present, the version matches, the ply-count
/// matches the game length, and every ply carries a parseable `roz:` comment.
/// `boards[i]` must be the position before ply `i` (length ≥ move_count).
pub fn assembleAnalysis(parsed: *const ParsedGame, boards: []const chess.Board) ?analysis.GameAnalysis {
    const header = parseRozHeaderValue(parsed.roz_analysis orelse return null) orelse return null;
    if (header.version != analysis.current_version) return null;
    if (header.plies != parsed.move_count) return null;
    if (boards.len < parsed.move_count) return null;

    var ga = analysis.GameAnalysis{};
    for (0..parsed.move_count) |i| {
        const comment = parsed.comments[i] orelse return null;
        const roz = parseRozComment(comment, &boards[i]) orelse return null;
        ga.append(.{
            // The true after-eval is not persisted; mirror best_eval (no loaded surface
            // reads .eval — the pass is the only producer of a real after-eval).
            .eval = roz.best_eval,
            .best = roz.best,
            .best_eval = roz.best_eval,
            .cpl = roz.cpl,
            .tier = roz.tier,
        });
    }
    // Aggregates come from the cheap header; key moments recompute from stored cpl.
    ga.blunders = header.blunders;
    ga.inaccuracies = header.inaccuracies;
    ga.accuracy = header.accuracy;
    ga.key_moment_count = analysis.computeKeyMoments(ga.moves[0..ga.count], &ga.key_moments);
    ga.version = header.version;
    ga.plies_covered = header.plies;
    return ga;
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
    const output = try writePgn(&buf, header, &records, &boards, null);

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
    const pgn_text = try writePgn(&buf, header, &records, &boards, null);

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

test "writePgn after a take-back omits the taken-back plies (AE2)" {
    var g = game.Game.init();
    g.executeMove(chess.Square.init(.e, .@"2"), chess.Square.init(.e, .@"4"), null);
    g.executeMove(chess.Square.init(.e, .@"7"), chess.Square.init(.e, .@"5"), null);
    g.executeMove(chess.Square.init(.g, .@"1"), chess.Square.init(.f, .@"3"), null);
    g.executeMove(chess.Square.init(.b, .@"8"), chess.Square.init(.c, .@"6"), null);
    g.undoMovePair();
    try std.testing.expectEqual(@as(usize, 2), g.move_count);

    // Mirror autoSave: board_history[board_count] holds the current board.
    g.board_history[g.board_count] = g.board;
    var buf: [4096]u8 = undefined;
    const text = try writePgn(&buf, .{}, g.move_history[0..g.move_count], g.board_history[0 .. g.board_count + 1], null);

    try std.testing.expect(std.mem.indexOf(u8, text, "e4") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "e5") != null);
    // The taken-back knight moves must be gone.
    try std.testing.expect(std.mem.indexOf(u8, text, "Nf3") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "2.") == null);
}

// --- U3: analysis annotation round-trip tests ---

fn buildFourMoveGame(boards: *[5]chess.Board, records: *[4]MoveRecord) void {
    boards[0] = chess.Board.initial;
    const move_defs = [_]struct { from: chess.Square, to: chess.Square }{
        .{ .from = sq(.e, .@"2"), .to = sq(.e, .@"4") },
        .{ .from = sq(.e, .@"7"), .to = sq(.e, .@"5") },
        .{ .from = sq(.g, .@"1"), .to = sq(.f, .@"3") },
        .{ .from = sq(.b, .@"8"), .to = sq(.c, .@"6") },
    };
    for (move_defs, 0..) |mv, i| {
        const m = chess.Move.init(mv.from, mv.to);
        const piece = boards[i].pieceAt(mv.from);
        const captured_piece = boards[i].pieceAt(mv.to);
        records[i] = makeRecord(piece, m, if (captured_piece != .empty) captured_piece else null);
        boards[i + 1] = chess.makeMove(boards[i], m);
    }
}

fn fourMoveAnalysis(records: *const [4]MoveRecord) analysis.GameAnalysis {
    var ga = analysis.GameAnalysis{};
    ga.append(.{ .eval = .{ .cp = 30 }, .best = records[0].move, .best_eval = .{ .cp = 30 }, .cpl = 0, .tier = .good });
    ga.append(.{ .eval = .{ .cp = -20 }, .best = records[1].move, .best_eval = .{ .cp = -20 }, .cpl = 10, .tier = null }); // engine ply
    ga.append(.{ .eval = .{ .mate = 3 }, .best = records[2].move, .best_eval = .{ .mate = 3 }, .cpl = 350, .tier = .bad });
    ga.append(.{ .eval = .{ .cp = -50 }, .best = records[3].move, .best_eval = .{ .cp = -50 }, .cpl = 60, .tier = .meh });
    ga.blunders = 1;
    ga.inaccuracies = 1;
    ga.accuracy = 75.0;
    ga.version = analysis.current_version;
    ga.plies_covered = 4;
    return ga;
}

test "writePgn+assembleAnalysis: round-trips tiers, best moves, mate eval (R12)" {
    var boards: [5]chess.Board = undefined;
    var records: [4]MoveRecord = undefined;
    buildFourMoveGame(&boards, &records);
    const ga = fourMoveAnalysis(&records);

    const header = PgnHeader{ .event = "RoundTrip", .white = "W", .black = "B", .result = "1-0" };
    var buf: [4096]u8 = undefined;
    const text = try writePgn(&buf, header, &records, &boards, &ga);

    const parsed = try parsePgn(text);
    // R12: the 7 standard tags and the movetext SAN are unchanged.
    try std.testing.expectEqual(@as(usize, 4), parsed.move_count);
    try std.testing.expectEqualStrings("RoundTrip", parsed.event.?);
    for (0..4) |i| try std.testing.expect(parsed.moves[i].move.eql(records[i].move));

    const ga2 = assembleAnalysis(&parsed, &boards) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u16, 4), ga2.count);
    try std.testing.expectEqual(analysis.Eval{ .mate = 3 }, ga2.moves[2].best_eval);
    try std.testing.expectEqual(@as(?analysis.Tier, .bad), ga2.moves[2].tier);
    try std.testing.expectEqual(@as(?analysis.Tier, null), ga2.moves[1].tier); // engine ply "-"
    try std.testing.expect(ga2.moves[2].best.?.eql(records[2].move));
    try std.testing.expectEqual(@as(i32, 350), ga2.moves[2].cpl);
    try std.testing.expectEqual(@as(u16, 1), ga2.blunders);
    try std.testing.expectEqual(@as(u16, 1), ga2.inaccuracies);
}

test "readAnalysisHeader: cheap scan returns marker + counts" {
    var boards: [5]chess.Board = undefined;
    var records: [4]MoveRecord = undefined;
    buildFourMoveGame(&boards, &records);
    const ga = fourMoveAnalysis(&records);
    var buf: [4096]u8 = undefined;
    const text = try writePgn(&buf, .{}, &records, &boards, &ga);

    const h = readAnalysisHeader(text).?;
    try std.testing.expectEqual(analysis.current_version, h.version);
    try std.testing.expectEqual(@as(u16, 4), h.plies);
    try std.testing.expectEqual(@as(u16, 1), h.blunders);
    try std.testing.expectEqual(@as(u16, 1), h.inaccuracies);
    try std.testing.expect(h.accuracy != null);
}

test "writePgn with null analysis is byte-identical to the un-annotated path" {
    var boards: [5]chess.Board = undefined;
    var records: [4]MoveRecord = undefined;
    buildFourMoveGame(&boards, &records);
    var buf_plain: [4096]u8 = undefined;
    const plain = try writePgn(&buf_plain, .{}, &records, &boards, null);
    // No marker, and the game still parses + has no recoverable analysis.
    try std.testing.expect(readAnalysisHeader(plain) == null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "RozAnalysis") == null);
    const parsed = try parsePgn(plain);
    try std.testing.expect(assembleAnalysis(&parsed, &boards) == null);
}

test "assembleAnalysis: ply-count mismatch fails the completeness gate" {
    var boards: [5]chess.Board = undefined;
    var records: [4]MoveRecord = undefined;
    buildFourMoveGame(&boards, &records);
    var ga = fourMoveAnalysis(&records);
    ga.plies_covered = 2; // marker claims 2 plies for a 4-ply game → incomplete
    var buf: [4096]u8 = undefined;
    const text = try writePgn(&buf, .{}, &records, &boards, &ga);
    const parsed = try parsePgn(text);
    try std.testing.expect(assembleAnalysis(&parsed, &boards) == null);
}

test "parseMovetext: brace comment attaches to its ply, never errors" {
    const text =
        \\[Event "C"]
        \\[Result "*"]
        \\
        \\1. e4 {roz: good best=e4 eval=30 cpl=0} e5 *
    ;
    const parsed = try parsePgn(text);
    try std.testing.expectEqual(@as(usize, 2), parsed.move_count);
    try std.testing.expect(parsed.comments[0] != null);
    try std.testing.expect(parsed.comments[1] == null);
}

test "assembleAnalysis: corrupted roz comment fails the gate but still parses" {
    const text =
        \\[Event "B"]
        \\[Result "*"]
        \\[RozAnalysis "v1 plies=1 bad=0 meh=0 acc=-"]
        \\
        \\1. e4 {roz: good best=Zz9 eval=30 cpl=0} *
    ;
    const parsed = try parsePgn(text); // a bad annotation must NOT abort the parse
    try std.testing.expectEqual(@as(usize, 1), parsed.move_count);
    var boards = [_]chess.Board{chess.Board.initial};
    try std.testing.expect(assembleAnalysis(&parsed, &boards) == null);
}

test "writePgn: a fully-annotated 512-ply game fits the 64 KB write buffer" {
    var boards: [513]chess.Board = undefined;
    var records: [512]MoveRecord = undefined;
    boards[0] = chess.Board.initial;
    // Legal knight shuffle (g1<->f3 / g8<->f6): cycles indefinitely, no captures/mate.
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        const m = if (i % 2 == 0)
            (if (i % 4 == 0) chess.Move.init(sq(.g, .@"1"), sq(.f, .@"3")) else chess.Move.init(sq(.f, .@"3"), sq(.g, .@"1")))
        else
            (if (i % 4 == 1) chess.Move.init(sq(.g, .@"8"), sq(.f, .@"6")) else chess.Move.init(sq(.f, .@"6"), sq(.g, .@"8")));
        records[i] = makeRecord(boards[i].pieceAt(m.from), m, null);
        boards[i + 1] = chess.makeMove(boards[i], m);
    }
    var ga = analysis.GameAnalysis{};
    for (0..512) |k| ga.append(.{ .eval = .{ .cp = 10 }, .best = records[k].move, .best_eval = .{ .cp = 10 }, .cpl = 5, .tier = .good });
    ga.blunders = 0;
    ga.inaccuracies = 0;
    ga.accuracy = 99.0;
    ga.version = analysis.current_version;
    ga.plies_covered = 512;

    var buf: [64 * 1024]u8 = undefined;
    const text = try writePgn(&buf, .{}, &records, &boards, &ga);
    try std.testing.expect(text.len < buf.len);
}

test "writePgn: too-small buffer returns BufferTooSmall, never overflows" {
    var boards: [5]chess.Board = undefined;
    var records: [4]MoveRecord = undefined;
    buildFourMoveGame(&boards, &records);
    const ga = fourMoveAnalysis(&records);
    var tiny: [16]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, writePgn(&tiny, .{}, &records, &boards, &ga));
}
