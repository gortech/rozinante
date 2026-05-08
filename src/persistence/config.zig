const std = @import("std");
const Io = std.Io;
const Dir = std.Io.Dir;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.persistence);

pub const Preferences = struct {
    stockfish_path: ?[]const u8 = null,
    default_elo: u16 = 1200,
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

    return .{
        .stockfish_path = if (parsed.value.stockfish_path) |p|
            (allocator.dupe(u8, p) catch null)
        else
            null,
        .default_elo = parsed.value.default_elo,
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
        .default_elo = prefs.default_elo,
        .default_color = prefs.default_color,
        .default_time_control = prefs.default_time_control,
    };

    const json_bytes = std.json.Stringify.valueAlloc(allocator, json_prefs, .{ .whitespace = .indent_2 }) catch |err| {
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

pub fn freePreferences(allocator: Allocator, prefs: *Preferences) void {
    if (prefs.stockfish_path) |p| {
        allocator.free(p);
        prefs.stockfish_path = null;
    }
    if (!std.mem.eql(u8, prefs.default_color, "white")) {
        allocator.free(prefs.default_color);
        prefs.default_color = "white";
    }
}

const JsonPreferences = struct {
    stockfish_path: ?[]const u8 = null,
    default_elo: u16 = 1200,
    default_color: []const u8 = "white",
    default_time_control: u16 = 0,
};

// --- Tests ---

fn getTestIo() Io {
    return std.Io.Threaded.global_single_threaded.io();
}

test "preferences round-trip" {
    const allocator = std.testing.allocator;
    const io = getTestIo();

    const tmp_dir = "/tmp/rozinante-test-config";
    Dir.cwd().createDirPath(io, tmp_dir) catch {};
    defer {
        Dir.cwd().deleteFile(io, "/tmp/rozinante-test-config/config.json") catch {};
        Dir.cwd().deleteFile(io, tmp_dir) catch {};
    }

    const prefs = Preferences{
        .stockfish_path = "/usr/bin/stockfish",
        .default_elo = 1500,
        .default_color = "black",
        .default_time_control = 300,
    };

    try savePreferences(allocator, io, prefs, tmp_dir);

    var loaded = loadPreferences(allocator, io, tmp_dir);
    defer freePreferences(allocator, &loaded);

    try std.testing.expectEqual(@as(u16, 1500), loaded.default_elo);
    try std.testing.expectEqualStrings("black", loaded.default_color);
    try std.testing.expectEqual(@as(u16, 300), loaded.default_time_control);
    try std.testing.expectEqualStrings("/usr/bin/stockfish", loaded.stockfish_path.?);
}

test "preferences defaults on missing file" {
    const io = getTestIo();
    const prefs = loadPreferences(std.testing.allocator, io, "/tmp/rozinante-nonexistent-config");

    try std.testing.expectEqual(@as(u16, 1200), prefs.default_elo);
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
    try std.testing.expectEqual(@as(u16, 1200), prefs.default_elo);
}
