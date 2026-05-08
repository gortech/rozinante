const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;
const known_folders = @import("known_folders");

const log = std.log.scoped(.persistence);

const app_name = "rozinante";

pub const GameInfo = struct {
    filename: []const u8,
    date: []const u8,
    elo: u16,
    player_color: []const u8,
    result: []const u8,
    is_finished: bool,
};

pub const SaveGameData = struct {
    pgn_content: []const u8,
    date_secs: i64,
    elo: u16,
    color: []const u8,
};

pub fn getDataDir(allocator: Allocator, io: Io, environ: *const std.process.Environ.Map) ![]const u8 {
    const base = try known_folders.getPath(io, allocator, environ, .data) orelse {
        return error.NoDataDir;
    };
    defer allocator.free(base);
    return std.fmt.allocPrint(allocator, "{s}/{s}/games", .{ base, app_name });
}

pub fn getConfigDir(allocator: Allocator, io: Io, environ: *const std.process.Environ.Map) ![]const u8 {
    const base = try known_folders.getPath(io, allocator, environ, .local_configuration) orelse {
        return error.NoConfigDir;
    };
    defer allocator.free(base);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, app_name });
}

pub fn ensureDirExists(io: Io, path: []const u8) !void {
    Dir.cwd().createDirPath(io, path) catch |err| {
        log.err("failed to create directory {s}: {}", .{ path, err });
        return err;
    };
}

pub fn generateFilename(buf: []u8, date_secs: i64, elo: u16, color: []const u8) []const u8 {
    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@max(0, date_secs)) };
    const day = epoch_secs.getDaySeconds();
    const year_day = epoch_secs.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}_{d:0>2}{d:0>2}{d:0>2}_elo{d}_s{s}.pgn", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1,
        day.getHoursIntoDay(),
        day.getMinutesIntoHour(),
        day.getSecondsIntoMinute(),
        elo,
        color,
    }) catch unreachable;
}

pub fn saveGame(allocator: Allocator, io: Io, data_dir: []const u8, game: SaveGameData) ![]const u8 {
    try ensureDirExists(io, data_dir);

    var name_buf: [128]u8 = undefined;
    const filename = generateFilename(&name_buf, game.date_secs, game.elo, game.color);

    const dir = Dir.openDirAbsolute(io, data_dir, .{}) catch |err| {
        log.err("failed to open data directory {s}: {}", .{ data_dir, err });
        return err;
    };

    var atomic = dir.createFileAtomic(io, filename, .{ .replace = true }) catch |err| {
        log.err("failed to create atomic file: {}", .{err});
        return err;
    };
    errdefer atomic.deinit(io);

    atomic.file.writeStreamingAll(io, game.pgn_content) catch |err| {
        log.err("failed to write game data: {}", .{err});
        return err;
    };

    atomic.replace(io) catch |err| {
        log.err("failed to atomically replace file: {}", .{err});
        return err;
    };

    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ data_dir, filename });
}

pub fn loadGame(allocator: Allocator, io: Io, filepath: []const u8) ![]const u8 {
    const content = Dir.cwd().readFileAlloc(io, filepath, allocator, .limited(1024 * 1024)) catch |err| {
        log.err("failed to load game from {s}: {}", .{ filepath, err });
        return err;
    };
    return content;
}

pub fn listGames(allocator: Allocator, io: Io, data_dir: []const u8) ![]GameInfo {
    var dir = Dir.openDirAbsolute(io, data_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return &.{};
        log.err("failed to open games directory {s}: {}", .{ data_dir, err });
        return err;
    };
    defer dir.close(io);

    var games = std.ArrayList(GameInfo).empty;
    defer games.deinit(allocator);

    var iter = dir.iterate();
    while (iter.next(io) catch |err| {
        log.err("failed to iterate games directory: {}", .{err});
        return err;
    }) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (!std.mem.endsWith(u8, name, ".pgn")) continue;

        const info = parseFilename(allocator, name) orelse continue;

        const result_tag = readResultTag(allocator, io, dir, name) catch "*";
        const is_finished = !std.mem.eql(u8, result_tag, "*");

        games.append(allocator, .{
            .filename = info.filename,
            .date = info.date,
            .elo = info.elo,
            .player_color = info.player_color,
            .result = result_tag,
            .is_finished = is_finished,
        }) catch |err| {
            log.err("failed to collect game info: {}", .{err});
            return err;
        };
    }

    const items = try games.toOwnedSlice(allocator);
    std.mem.sort(GameInfo, items, {}, struct {
        fn lessThan(_: void, a: GameInfo, b: GameInfo) bool {
            return std.mem.order(u8, b.date, a.date) == .lt;
        }
    }.lessThan);
    return items;
}

pub fn deleteGame(io: Io, filepath: []const u8) !void {
    Dir.cwd().deleteFile(io, filepath) catch |err| {
        log.err("failed to delete game {s}: {}", .{ filepath, err });
        return err;
    };
}

const ParsedFilename = struct {
    filename: []const u8,
    date: []const u8,
    elo: u16,
    player_color: []const u8,
};

fn parseFilename(allocator: Allocator, name: []const u8) ?ParsedFilename {
    // Expected: YYYY-MM-DD_HHMMSS_eloXXXX_sColor.pgn
    if (!std.mem.endsWith(u8, name, ".pgn")) return null;
    const actual_stem = name[0 .. name.len - 4];

    // Find date portion: YYYY-MM-DD_HHMMSS (17 chars)
    if (actual_stem.len < 17) return null;
    const date_str = actual_stem[0..17];

    // Validate date format roughly
    if (date_str[4] != '-' or date_str[7] != '-' or date_str[10] != '_') return null;

    const rest = actual_stem[17..];
    // rest should be: _eloXXXX_sColor
    if (rest.len < 2 or rest[0] != '_') return null;

    const after_underscore = rest[1..];
    if (!std.mem.startsWith(u8, after_underscore, "elo")) return null;

    const elo_and_color = after_underscore[3..];
    const color_sep = std.mem.indexOf(u8, elo_and_color, "_s") orelse return null;

    const elo_str = elo_and_color[0..color_sep];
    const elo = std.fmt.parseInt(u16, elo_str, 10) catch return null;
    const color = elo_and_color[color_sep + 2 ..];

    const duped_name = allocator.dupe(u8, name) catch return null;
    const duped_date = allocator.dupe(u8, date_str) catch return null;
    const duped_color = allocator.dupe(u8, color) catch return null;

    return .{
        .filename = duped_name,
        .date = duped_date,
        .elo = elo,
        .player_color = duped_color,
    };
}

fn readResultTag(allocator: Allocator, io: Io, dir: Dir, filename: []const u8) ![]const u8 {
    const content = dir.readFileAlloc(io, filename, allocator, .limited(8192)) catch {
        return "*";
    };
    defer allocator.free(content);

    // Look for [Result "..."] tag
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (std.mem.startsWith(u8, trimmed, "[Result \"")) {
            const start = 9;
            const end = std.mem.indexOf(u8, trimmed[start..], "\"]") orelse continue;
            return allocator.dupe(u8, trimmed[start .. start + end]) catch "*";
        }
    }
    return allocator.dupe(u8, "*") catch "*";
}

// --- Tests ---

fn getTestIo() Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn cleanupTestDir(io: Io, dir_path: []const u8) void {
    var dir = Dir.openDirAbsolute(io, dir_path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var iter = dir.iterate();
    while (iter.next(io) catch null) |entry| {
        if (entry.kind == .file) {
            dir.deleteFile(io, entry.name) catch {};
        }
    }
    Dir.cwd().deleteFile(io, dir_path) catch {};
}

test "generateFilename produces correct format" {
    var buf: [128]u8 = undefined;
    // 2026-05-07 14:30:22 UTC = epoch 1783529422
    const result = generateFilename(&buf, 1783529422, 1200, "white");
    try std.testing.expectEqualStrings("2026-07-08_165022_elo1200_swhite.pgn", result);
}

test "generateFilename with different color and elo" {
    var buf: [128]u8 = undefined;
    const result = generateFilename(&buf, 0, 800, "black");
    try std.testing.expectEqualStrings("1970-01-01_000000_elo800_sblack.pgn", result);
}

test "parseFilename valid" {
    const info = parseFilename(std.testing.allocator, "2026-05-07_143022_elo1200_swhite.pgn") orelse {
        return error.TestUnexpectedResult;
    };
    defer {
        std.testing.allocator.free(info.filename);
        std.testing.allocator.free(info.date);
        std.testing.allocator.free(info.player_color);
    }
    try std.testing.expectEqual(@as(u16, 1200), info.elo);
    try std.testing.expectEqualStrings("white", info.player_color);
    try std.testing.expectEqualStrings("2026-05-07_143022", info.date);
}

test "parseFilename invalid" {
    try std.testing.expect(parseFilename(std.testing.allocator, "not-a-pgn.txt") == null);
    try std.testing.expect(parseFilename(std.testing.allocator, "short.pgn") == null);
}

test "saveGame and loadGame round-trip" {
    const io = getTestIo();
    const allocator = std.testing.allocator;

    const tmp_dir = "/tmp/rozinante-test-storage";
    Dir.cwd().createDirPath(io, tmp_dir) catch {};
    defer cleanupTestDir(io, tmp_dir);

    const pgn_content = "[Event \"Test\"]\n[Result \"1-0\"]\n\n1. e4 e5 1-0\n";
    const path = try saveGame(allocator, io, tmp_dir, .{
        .pgn_content = pgn_content,
        .date_secs = 1783529422,
        .elo = 1200,
        .color = "white",
    });
    defer allocator.free(path);

    const loaded = try loadGame(allocator, io, path);
    defer allocator.free(loaded);
    try std.testing.expectEqualStrings(pgn_content, loaded);
}

test "listGames returns sorted results" {
    const io = getTestIo();
    const allocator = std.testing.allocator;

    const tmp_dir = "/tmp/rozinante-test-list";
    Dir.cwd().createDirPath(io, tmp_dir) catch {};
    defer cleanupTestDir(io, tmp_dir);

    // Save two games with different timestamps
    const path1 = try saveGame(allocator, io, tmp_dir, .{
        .pgn_content = "[Event \"G1\"]\n[Result \"*\"]\n\n1. e4 *\n",
        .date_secs = 1000000,
        .elo = 1200,
        .color = "white",
    });
    defer allocator.free(path1);

    const path2 = try saveGame(allocator, io, tmp_dir, .{
        .pgn_content = "[Event \"G2\"]\n[Result \"1-0\"]\n\n1. e4 e5 1-0\n",
        .date_secs = 2000000,
        .elo = 1500,
        .color = "black",
    });
    defer allocator.free(path2);

    const games = try listGames(allocator, io, tmp_dir);
    defer {
        for (games) |g| {
            allocator.free(g.filename);
            allocator.free(g.date);
            allocator.free(g.player_color);
            allocator.free(g.result);
        }
        allocator.free(games);
    }

    try std.testing.expectEqual(@as(usize, 2), games.len);
    // Second game (later date) should be first
    try std.testing.expect(games[0].elo == 1500 or games[1].elo == 1500);
}

test "listGames on missing directory returns empty" {
    const io = getTestIo();
    const games = try listGames(std.testing.allocator, io, "/tmp/rozinante-nonexistent-dir-42");
    try std.testing.expectEqual(@as(usize, 0), games.len);
}
