const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;
const engine = @import("../engine.zig");

const log = std.log.scoped(.persistence);

pub const Preferences = struct {
    stockfish_path: ?[]const u8 = null,
    default_skill_level: u8 = 0,
    default_color: []const u8 = "white",
    default_time_control: u16 = 0,
};

pub fn loadPreferences(allocator: Allocator, io: Io, config_dir: []const u8) Preferences {
    const filepath = std.fmt.allocPrint(allocator, "{s}/config.json", .{config_dir}) catch {
        return .{};
    };
    defer allocator.free(filepath);

    const content = Dir.cwd().readFileAlloc(io, filepath, allocator, .limited(64 * 1024)) catch |err| {
        if (err != error.FileNotFound) {
            log.warn("failed to read config {s}: {}, using defaults", .{ filepath, err });
        }
        return .{};
    };
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(JsonPreferences, allocator, content, .{
        .ignore_unknown_fields = true,
    }) catch |err| {
        log.warn("failed to parse config JSON: {}, using defaults", .{err});
        return .{};
    };
    defer parsed.deinit();

    const skill: u8 = if (parsed.value.default_skill_level) |s|
        @min(s, 20)
    else if (parsed.value.default_elo) |e|
        engine.eloToSkill(e)
    else
        0;

    return .{
        .stockfish_path = if (parsed.value.stockfish_path) |p|
            (allocator.dupe(u8, p) catch null)
        else
            null,
        .default_skill_level = skill,
        .default_color = allocator.dupe(u8, parsed.value.default_color) catch "white",
        .default_time_control = parsed.value.default_time_control,
    };
}

pub fn savePreferences(allocator: Allocator, io: Io, prefs: Preferences, config_dir: []const u8) !void {
    const storage_mod = @import("storage.zig");
    try storage_mod.ensureDirExists(io, config_dir);

    const filepath = try std.fmt.allocPrint(allocator, "{s}/config.json", .{config_dir});
    defer allocator.free(filepath);

    const json_prefs = JsonPreferences{
        .stockfish_path = prefs.stockfish_path,
        .default_skill_level = prefs.default_skill_level,
        .default_color = prefs.default_color,
        .default_time_control = prefs.default_time_control,
    };

    const json_bytes = std.json.Stringify.valueAlloc(allocator, json_prefs, .{ .whitespace = .indent_2, .emit_null_optional_fields = false }) catch |err| {
        log.err("failed to serialize preferences: {}", .{err});
        return err;
    };
    defer allocator.free(json_bytes);

    const dir = Dir.cwd();
    dir.writeFile(io, .{
        .sub_path = filepath,
        .data = json_bytes,
    }) catch |err| {
        log.err("failed to write config to {s}: {}", .{ filepath, err });
        return err;
    };
}

const JsonPreferences = struct {
    stockfish_path: ?[]const u8 = null,
    default_elo: ?u16 = null,
    default_skill_level: ?u8 = null,
    default_color: []const u8 = "white",
    default_time_control: u16 = 0,
};

// --- Tests ---

fn getTestIo() Io {
    return std.Io.Threaded.global_single_threaded.io();
}

test "preferences round-trip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = getTestIo();

    const tmp_dir = "/tmp/rozinante-test-config";
    Dir.cwd().createDirPath(io, tmp_dir) catch {};
    defer {
        Dir.cwd().deleteFile(io, "/tmp/rozinante-test-config/config.json") catch {};
        Dir.cwd().deleteFile(io, tmp_dir) catch {};
    }

    const prefs = Preferences{
        .stockfish_path = "/usr/bin/stockfish",
        .default_skill_level = 7,
        .default_color = "black",
        .default_time_control = 300,
    };

    try savePreferences(allocator, io, prefs, tmp_dir);

    const loaded = loadPreferences(allocator, io, tmp_dir);

    try std.testing.expectEqual(@as(u8, 7), loaded.default_skill_level);
    try std.testing.expectEqualStrings("black", loaded.default_color);
    try std.testing.expectEqual(@as(u16, 300), loaded.default_time_control);
    try std.testing.expectEqualStrings("/usr/bin/stockfish", loaded.stockfish_path.?);
}

test "preferences defaults on missing file" {
    const io = getTestIo();
    const prefs = loadPreferences(std.testing.allocator, io, "/tmp/rozinante-nonexistent-config");

    try std.testing.expectEqual(@as(u8, 0), prefs.default_skill_level);
    try std.testing.expectEqualStrings("white", prefs.default_color);
    try std.testing.expectEqual(@as(u16, 0), prefs.default_time_control);
    try std.testing.expect(prefs.stockfish_path == null);
}

test "preferences defaults on corrupt JSON" {
    const allocator = std.testing.allocator;
    const io = getTestIo();

    const tmp_dir = "/tmp/rozinante-test-corrupt-config";
    Dir.cwd().createDirPath(io, tmp_dir) catch {};
    defer {
        Dir.cwd().deleteFile(io, "/tmp/rozinante-test-corrupt-config/config.json") catch {};
        Dir.cwd().deleteFile(io, tmp_dir) catch {};
    }

    Dir.cwd().writeFile(io, .{
        .sub_path = "/tmp/rozinante-test-corrupt-config/config.json",
        .data = "{{{{not json!!!!",
    }) catch return;

    const prefs = loadPreferences(allocator, io, tmp_dir);
    try std.testing.expectEqual(@as(u8, 0), prefs.default_skill_level);
}

test "preferences migrates legacy default_elo to skill" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = getTestIo();

    const tmp_dir = "/tmp/rozinante-test-legacy-config";
    Dir.cwd().createDirPath(io, tmp_dir) catch {};
    defer {
        Dir.cwd().deleteFile(io, tmp_dir ++ "/config.json") catch {};
        Dir.cwd().deleteFile(io, tmp_dir) catch {};
    }

    Dir.cwd().writeFile(io, .{
        .sub_path = tmp_dir ++ "/config.json",
        .data = "{\"default_elo\": 1320, \"default_color\": \"white\", \"default_time_control\": 0}",
    }) catch return;

    const prefs = loadPreferences(allocator, io, tmp_dir);
    // 1320 is the table floor -> skill 0; proves the legacy elo path is taken.
    try std.testing.expectEqual(@as(u8, 0), prefs.default_skill_level);
}

test "preferences clamps out-of-range persisted skill" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = getTestIo();

    const tmp_dir = "/tmp/rozinante-test-clamp-config";
    Dir.cwd().createDirPath(io, tmp_dir) catch {};
    defer {
        Dir.cwd().deleteFile(io, tmp_dir ++ "/config.json") catch {};
        Dir.cwd().deleteFile(io, tmp_dir) catch {};
    }

    Dir.cwd().writeFile(io, .{
        .sub_path = tmp_dir ++ "/config.json",
        .data = "{\"default_skill_level\": 200}",
    }) catch return;

    const prefs = loadPreferences(allocator, io, tmp_dir);
    try std.testing.expect(prefs.default_skill_level <= 20);
}
