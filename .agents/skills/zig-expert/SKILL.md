---
name: zig-expert
description: >
  Zig 0.16.0 programming reference for building Rozinante — a TUI chess game in Zig.
  Covers the APIs and patterns actually used in this project: std.process.Init (Juicy Main),
  subprocess management (std.process.Child for Stockfish UCI), file I/O (PGN/JSON read/write),
  build-time data embedding (@embedFile for ECO database), enums/structs/unions for domain types,
  ArrayList/HashMap, JSON parsing, testing, error handling, and the build system.
  Use this skill whenever writing, reviewing, debugging, or modifying any Zig code in this project.
  Triggers on: any .zig file work, Zig compiler errors, build.zig changes, zig build failures,
  writing tests, designing data types, subprocess communication, or file format parsing.
  If the task involves Zig code, use this skill.
---

# Zig 0.16.0 Programming Reference

> **Pinned to Zig 0.16.0 stable.** Always verify APIs against local std source (`zig env` → `.std_dir`).

## Local Documentation

Run `zig env` to find paths. Key fields: `.lib_dir`, `.std_dir`, `.version`.

- **Language Reference**: `<lib_dir>/../doc/langref.html`
- **Std Library Source**: read files under `.std_dir` for API verification
- **Std Library Docs**: run `zig std` to start a local HTTP server

Check local docs before web search. When uncertain about an API, read the source file directly — Zig's stdlib is written to be readable.

---

## Program Entry: std.process.Init

Zig 0.16 provides allocator, I/O, and environment through the `main` parameter instead of globals.

```zig
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    // CLI arguments
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args, 0..) |arg, i| {
        std.log.info("arg[{d}] = {s}", .{ i, arg });
    }

    // Environment variables
    const home = init.environ_map.get("HOME");
}
```

### Init struct contents

```zig
pub const Init = struct {
    minimal: Minimal,
    arena: *std.heap.ArenaAllocator,  // process-lifetime, threadsafe
    gpa: Allocator,                   // general-purpose allocator
    io: Io,                           // I/O vtable
    environ_map: *Environ.Map,        // env vars (not threadsafe)
    preopens: Preopens,               // WASI preopens (void on native)
};
```

Any function that does I/O needs an `io` parameter. Any function that allocates needs an `allocator` parameter. Thread these through from `main`.

---

## Subprocess Management

This is how Stockfish UCI communication works — spawn a child process, write to its stdin, read from its stdout.

### Spawning a child process

```zig
const std = @import("std");

fn spawnEngine(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !std.process.Child {
    var child: std.process.Child = .{
        .allocator = allocator,
        .argv = &.{path},
        .stdin_behavior = .pipe,
        .stdout_behavior = .pipe,
        .stderr_behavior = .pipe,
    };
    try child.spawn(io);
    return child;
}
```

### Writing to child stdin

```zig
fn sendCommand(child: *std.process.Child, io: std.Io, cmd: []const u8) !void {
    const stdin = child.stdin orelse return error.StdinNotAvailable;
    try stdin.writeStreamingAll(io, cmd);
    try stdin.writeStreamingAll(io, "\n");
}
```

### Reading from child stdout

```zig
fn readLine(child: *std.process.Child, io: std.Io, buf: []u8) !?[]const u8 {
    const stdout = child.stdout orelse return error.StdoutNotAvailable;
    var reader = stdout.reader(.{});
    const line = reader.interface.readUntilDelimiter(io, buf, '\n') catch |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };
    return line;
}
```

### Waiting and cleanup

```zig
fn stopEngine(child: *std.process.Child, io: std.Io) void {
    sendCommand(child, io, "quit") catch {};
    _ = child.wait(io) catch {};
}
```

### Key points for UCI protocol

- UCI is line-based text: send `"uci\n"`, read until `"uciok\n"`
- Use `std.mem.startsWith(u8, line, "bestmove")` for response parsing
- Use `std.fmt.bufPrint` to format UCI commands: `"position startpos moves e2e4 e7e5\n"`
- Handle broken pipe (child crash) by catching write errors

---

## Enums, Structs, and Unions

These are the building blocks for chess types (Piece, Square, Move, Board).

### Enums

```zig
const Color = enum {
    white,
    black,

    pub fn opposite(self: Color) Color {
        return switch (self) {
            .white => .black,
            .black => .white,
        };
    }
};

const PieceType = enum {
    king,
    queen,
    rook,
    bishop,
    knight,
    pawn,
};

const Piece = enum(u8) {
    empty = 0,
    white_king = 1,
    white_queen = 2,
    // ...
    black_pawn = 12,

    pub fn color(self: Piece) ?Color {
        if (self == .empty) return null;
        return if (@intFromEnum(self) <= 6) .white else .black;
    }

    pub fn pieceType(self: Piece) ?PieceType {
        if (self == .empty) return null;
        const raw = (@intFromEnum(self) - 1) % 6;
        return @enumFromInt(raw);
    }
};
```

### Structs

```zig
const Square = struct {
    file: u3,  // 0-7 (a-h)
    rank: u3,  // 0-7 (1-8)

    pub fn fromAlgebraic(s: []const u8) !Square {
        if (s.len != 2) return error.InvalidSquare;
        const file = std.math.sub(u8, s[0], 'a') catch return error.InvalidSquare;
        const rank = std.math.sub(u8, s[1], '1') catch return error.InvalidSquare;
        if (file > 7 or rank > 7) return error.InvalidSquare;
        return .{ .file = @intCast(file), .rank = @intCast(rank) };
    }

    pub fn toIndex(self: Square) u6 {
        return @as(u6, self.rank) * 8 + self.file;
    }
};

const Board = struct {
    squares: [64]Piece,
    active_color: Color,
    castling_rights: CastlingRights,
    en_passant: ?Square,
    halfmove_clock: u16,
    fullmove_number: u16,

    pub const initial = Board{
        .squares = initialPosition(),
        .active_color = .white,
        .castling_rights = CastlingRights.all,
        .en_passant = null,
        .halfmove_clock = 0,
        .fullmove_number = 1,
    };
};
```

### Packed structs (for bit fields)

```zig
const CastlingRights = packed struct(u4) {
    white_kingside: bool = false,
    white_queenside: bool = false,
    black_kingside: bool = false,
    black_queenside: bool = false,

    const all = CastlingRights{
        .white_kingside = true,
        .white_queenside = true,
        .black_kingside = true,
        .black_queenside = true,
    };

    const none = CastlingRights{};
};
```

### Tagged unions

```zig
const MoveType = union(enum) {
    normal,
    castle: CastleSide,
    en_passant,
    promotion: PieceType,
};

const Move = struct {
    from: Square,
    to: Square,
    move_type: MoveType,
};
```

### Comptime and generics

```zig
fn ArrayOf(comptime T: type, comptime len: usize) type {
    return struct {
        items: [len]T,
        count: usize = 0,

        pub fn append(self: *@This(), item: T) !void {
            if (self.count >= len) return error.Full;
            self.items[self.count] = item;
            self.count += 1;
        }

        pub fn slice(self: *const @This()) []const T {
            return self.items[0..self.count];
        }
    };
}

// Stack-allocated move list (no heap needed for move generation)
const MoveList = ArrayOf(Move, 256);
```

---

## Collections

### ArrayList

```zig
var list = try std.ArrayList(u8).initCapacity(gpa, 16);
defer list.deinit(gpa);

try list.append(gpa, 'a');
try list.appendSlice(gpa, "hello");
const owned = try list.toOwnedSlice(gpa);
defer gpa.free(owned);
```

### HashMap

```zig
var map = std.StringHashMap(u32).empty;
defer map.deinit(gpa);

try map.put(gpa, "key", 42);
const val = map.get("key") orelse 0;
```

### AutoHashMap (non-string keys)

```zig
var positions = std.AutoHashMap(u64, u8).empty;
defer positions.deinit(gpa);

// Track position hashes for threefold repetition
const hash = computeZobristHash(board);
const entry = try positions.getOrPut(gpa, hash);
if (!entry.found_existing) {
    entry.value_ptr.* = 1;
} else {
    entry.value_ptr.* += 1;
}
```

---

## String and Buffer Operations

Zig strings are `[]const u8` — slices of bytes. No special string type.

### Formatting into a buffer

```zig
var buf: [256]u8 = undefined;
const formatted = try std.fmt.bufPrint(&buf, "position startpos moves {s}\n", .{moves_str});
```

### Splitting and parsing

```zig
// Split a UCI response line
var iter = std.mem.splitSequence(u8, line, " ");
const token = iter.next() orelse return error.EmptyLine;
if (std.mem.eql(u8, token, "bestmove")) {
    const move_str = iter.next() orelse return error.MissingMove;
    // parse move_str...
}
```

### String comparison

```zig
if (std.mem.eql(u8, line, "uciok")) { ... }
if (std.mem.startsWith(u8, line, "info depth")) { ... }
```

### Number parsing

```zig
const depth = try std.fmt.parseInt(i32, depth_str, 10);
```

### Concatenation (allocating)

```zig
const full = try std.fmt.allocPrint(gpa, "{s} {s}", .{ first, second });
defer gpa.free(full);
```

---

## File I/O

### Reading an entire file

```zig
const contents = try std.Io.Dir.cwd().readFileAlloc(io, "game.pgn", gpa, .limited(1024 * 1024));
defer gpa.free(contents);
```

### Writing a file atomically

Atomic writes prevent data corruption on crash — critical for auto-save.

```zig
var atomic = try std.Io.File.Atomic.init(io, gpa, "game.pgn");
errdefer atomic.abort(io);
try atomic.file_writer.interface.print("{s}\n", .{pgn_content});
try atomic.commit(io);
```

### Opening and reading line-by-line

```zig
const file = try std.Io.Dir.cwd().openFile(io, "data.tsv", .{});
defer file.close(io);

var reader = file.reader(.{});
var buf: [4096]u8 = undefined;
while (true) {
    const line = reader.interface.readUntilDelimiter(io, &buf, '\n') catch |err| switch (err) {
        error.EndOfStream => break,
        else => return err,
    };
    // process line...
}
```

### Directory operations

```zig
// Create directory (ok if exists)
std.Io.Dir.cwd().makeDir(io, "data") catch |err| switch (err) {
    error.PathAlreadyExists => {},
    else => return err,
};

// List files in a directory
var dir = try std.Io.Dir.cwd().openDir(io, "games", .{ .iterate = true });
defer dir.close(io);
var iter = dir.iterate();
while (try iter.next()) |entry| {
    if (std.mem.endsWith(u8, entry.name, ".pgn")) {
        // found a PGN file
    }
}
```

### stdout / stderr

```zig
try std.Io.File.stdout().writeStreamingAll(io, "Hello\n");

var stdout_writer = std.Io.File.stdout().writer(.{});
try stdout_writer.interface.print("value: {d}\n", .{42});
```

---

## JSON (for user preferences)

### Parsing

```zig
const Preferences = struct {
    elo: u32 = 1500,
    stockfish_path: []const u8 = "stockfish",
    hints_enabled: bool = true,
    time_minutes: ?u32 = null,
};

const json_str = try readFileAlloc(io, "config.json", gpa, .limited(64 * 1024));
defer gpa.free(json_str);

const parsed = try std.json.parseFromSlice(Preferences, gpa, json_str, .{
    .ignore_unknown_fields = true,
});
defer parsed.deinit();

const prefs = parsed.value;
```

### Serialization

```zig
var out: std.Io.Writer.Allocating = .init(gpa);
defer out.deinit();
var stringify: std.json.Stringify = .{
    .writer = &out.writer,
    .options = .{ .whitespace = .indent_4 },
};
try stringify.write(prefs);
const json_output = out.written();
```

---

## Build-Time Data Embedding

The ECO opening database (~3500 entries, TSV) is embedded at build time using `@embedFile`.

### In build.zig

```zig
const exe = b.addExecutable(.{
    .name = "rozinante",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }),
});

// Option 1: @embedFile (simplest — file must be within source tree or declared as dependency)
// The file is available via @embedFile("data/openings.tsv") from any source file
// if the file is in the source tree relative to the importing file.

// Option 2: addAnonymousModule for data files outside the source tree
// exe.root_module.addAnonymousImport("openings", .{
//     .root_source_file = b.path("data/openings.tsv"),
// });
```

### Using embedded data

```zig
const opening_data = @embedFile("data/openings.tsv");

fn parseOpenings() []Opening {
    var iter = std.mem.splitSequence(u8, opening_data, "\n");
    _ = iter.next(); // skip header
    while (iter.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitSequence(u8, line, "\t");
        const eco = fields.next() orelse continue;
        const name = fields.next() orelse continue;
        const pgn = fields.next() orelse continue;
        const uci = fields.next() orelse continue;
        const epd = fields.next() orelse continue;
        // store opening...
    }
}
```

`@embedFile` produces a `*const [N]u8` — it's comptime-known, no allocation needed. The data lives in the binary's read-only section.

---

## Build System

### build.zig.zon

```zig
.{
    .name = .rozinante,  // enum literal, not a string
    .fingerprint = 0x...,  // required in 0.16
    .version = "0.1.0",
    .dependencies = .{
        .libvaxis = .{
            .url = "https://...",
            .hash = "...",
        },
        .known_folders = .{
            .url = "https://...",
            .hash = "...",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

### Adding dependencies in build.zig

```zig
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis_dep = b.dependency("libvaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "rozinante",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "vaxis", .module = vaxis_dep.module("vaxis") },
            },
        }),
    });

    b.installArtifact(exe);

    // Test step
    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

### Running

```bash
zig build              # build
zig build run          # build and run
zig build test         # run tests
zig build test --test-timeout 500ms  # with timeout
```

---

## Testing

### Basic tests

```zig
const std = @import("std");
const testing = std.testing;

test "pawn moves from starting position" {
    const board = Board.initial;
    const moves = legalMoves(board);

    // 16 pawn pushes + 4 knight moves = 20
    try testing.expectEqual(@as(usize, 20), moves.count);
}

test "castling requires unmoved king" {
    var board = Board.initial;
    board.castling_rights.white_kingside = false;
    const moves = legalMoves(board);
    // verify kingside castle not in move list
    for (moves.slice()) |m| {
        try testing.expect(m.move_type != .castle or m.move_type.castle != .kingside);
    }
}
```

### Testing with allocator (leak detection)

```zig
test "no memory leaks in move generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        try testing.expect(check == .ok);
    }
    const allocator = gpa.allocator();

    var list = try std.ArrayList(Move).initCapacity(allocator, 64);
    defer list.deinit(allocator);
    // ...
}
```

### Test organization

```zig
// In src/chess/board.zig — tests at bottom of the file
test "initial board has 32 pieces" {
    const board = Board.initial;
    var count: u32 = 0;
    for (board.squares) |piece| {
        if (piece != .empty) count += 1;
    }
    try std.testing.expectEqual(@as(u32, 32), count);
}

// Or in a separate test file that imports the module
// src/chess/board_test.zig
const board_mod = @import("board.zig");
const Board = board_mod.Board;

test "makeMove updates active color" {
    // ...
}
```

Tests run with `zig build test`. All `test` blocks in files reachable from the test root are discovered automatically. Use `@import` to pull in test files from the root.

---

## Error Handling

Zig uses error unions (`!T`) and error sets. No exceptions, no try-catch.

### Error sets

```zig
const ChessError = error{
    InvalidSquare,
    IllegalMove,
    InvalidFen,
    InvalidPgn,
};

const EngineError = error{
    StdinNotAvailable,
    StdoutNotAvailable,
    EngineNotResponding,
    UnexpectedResponse,
};
```

### Error unions and propagation

```zig
fn makeMove(board: Board, move: Move) ChessError!Board {
    if (!isLegalMove(board, move)) return error.IllegalMove;
    // apply move...
    return new_board;
}

fn playTurn(board: Board, move: Move) !Board {
    // try propagates the error to the caller
    const new_board = try makeMove(board, move);
    try saveGame(new_board);
    return new_board;
}
```

### errdefer (cleanup on error)

```zig
fn initEngine(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Engine {
    var child = try spawnEngine(gpa, io, path);
    errdefer stopEngine(&child, io);  // cleanup if anything below fails

    try sendCommand(&child, io, "uci");
    try waitForResponse(&child, io, "uciok");

    return Engine{ .child = child };
}
```

### Switch on errors

```zig
const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |err| switch (err) {
    error.FileNotFound => {
        std.log.warn("config not found at {s}, using defaults", .{path});
        return Preferences{};
    },
    error.AccessDenied => {
        std.log.err("permission denied: {s}", .{path});
        return err;
    },
    else => return err,
};
```

### Optional values

```zig
const piece = board.at(square);
if (piece) |p| {
    // p is non-null Piece
} else {
    // square is empty
}

// orelse for defaults
const ep_square = board.en_passant orelse return;
```

---

## Common Patterns for This Project

### Passing context through layers

```zig
// Thread allocator and io from main through the call stack
const Game = struct {
    board: Board,
    moves: std.ArrayList(Move),
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) !Game {
        return .{
            .board = Board.initial,
            .moves = try std.ArrayList(Move).initCapacity(gpa, 128),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *Game) void {
        self.moves.deinit(self.gpa);
    }

    pub fn applyMove(self: *Game, move: Move) !void {
        self.board = try makeMove(self.board, move);
        try self.moves.append(self.gpa, move);
    }
};
```

### Iterators

```zig
fn squareIterator() SquareIterator {
    return .{ .index = 0 };
}

const SquareIterator = struct {
    index: u7,

    pub fn next(self: *SquareIterator) ?Square {
        if (self.index >= 64) return null;
        defer self.index += 1;
        return Square{
            .file = @intCast(self.index % 8),
            .rank = @intCast(self.index / 8),
        };
    }
};
```

### Lookup tables (comptime-generated)

```zig
// Generate attack tables at compile time
const knight_attacks: [64]u64 = comptime blk: {
    var table: [64]u64 = .{0} ** 64;
    for (0..64) |sq| {
        // compute knight attack bitboard for each square
        table[sq] = computeKnightAttacks(sq);
    }
    break :blk table;
};
```

### Converting between UCI strings and moves

```zig
pub fn moveToUci(move: Move, buf: *[5]u8) []const u8 {
    buf[0] = 'a' + move.from.file;
    buf[1] = '1' + move.from.rank;
    buf[2] = 'a' + move.to.file;
    buf[3] = '1' + move.to.rank;
    if (move.move_type == .promotion) {
        buf[4] = switch (move.move_type.promotion) {
            .queen => 'q',
            .rook => 'r',
            .bishop => 'b',
            .knight => 'n',
            else => unreachable,
        };
        return buf[0..5];
    }
    return buf[0..4];
}
```

---

## Common Compiler Errors

| Error | Cause | Fix |
|---|---|---|
| `expected N argument(s), found M` | Missing allocator arg on collection methods | Pass `gpa` as first arg to `append`, `deinit`, etc. |
| `no field named 'init' in ArrayList` | Old API | Use `initCapacity(gpa, n)` instead of `init(gpa)` |
| `fingerprint field missing` | Old build.zig.zon | Add `.fingerprint = 0x...` and use `.name = .rozinante` (enum literal) |
| `no field named 'getStdOut'` | Old I/O API | Use `std.Io.File.stdout()` |
| `no member named 'fixedBufferStream'` | Removed | Use `std.Io.Writer.fixed(&buf)` |
| `expected type '*const Io'` | Function needs io parameter | Thread `io` from `main(init)` |
| `type depends on itself for alignment` | Self-referential alignment | Remove `@alignOf(@This())` or restructure |
| `unused local constant` | Zig rejects unused bindings | Use `_ = value;` to discard, or remove the binding |

---

## Debugging Tips

### Debug printing

```zig
std.debug.print("board state: {any}\n", .{board});
std.debug.print("move: {s}\n", .{moveToUci(move, &buf)});
```

`std.debug.print` writes to stderr, bypasses buffering, works even when stdout is piped. Use it for development; remove before committing.

### Unreachable and assertions

```zig
// Compiler-checked unreachable (optimized out in ReleaseSafe+)
unreachable;

// Runtime assertion (panics with message in debug, undefined behavior in release)
std.debug.assert(index < 64);
```

### @breakpoint

```zig
@breakpoint();  // triggers debugger breakpoint (SIGTRAP)
```

---

## Memory Management Rules

1. **Every allocation has a matching deallocation.** Use `defer` immediately after allocation.
2. **Prefer stack allocation** for fixed-size data (move lists, buffers, board state).
3. **Use `ArenaAllocator`** for groups of allocations with the same lifetime.
4. **Use `GeneralPurposeAllocator`** in tests for leak detection.
5. **`errdefer`** for cleanup on error paths — complements `defer` for the success path.

```zig
// Arena pattern for batch operations
var arena = std.heap.ArenaAllocator.init(gpa);
defer arena.deinit();
const scratch = arena.allocator();
// all allocations from scratch are freed together
```
