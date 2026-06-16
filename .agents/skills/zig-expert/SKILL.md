---
name: zig-expert
description: >
  Zig 0.16.0 programming reference for the Rozinante TUI chess game. Covers the
  APIs and patterns this project actually uses: std.Io threading, std.process
  subprocess I/O, known_folders, std.json, atomic file writes, scoped logging,
  arena allocator, the build system (build.zig / build.zig.zon), std.testing,
  barrel modules, and bit-packed enums. Use it whenever writing, reviewing,
  debugging, or modifying any Zig code here — .zig edits, compiler errors,
  zig build failures, writing tests, designing data types, subprocess
  communication, file I/O, JSON parsing, or file-format parsing. If the task
  involves Zig code, use this skill.
updated: 2026-06-16
references: []
---

# Zig Expert

Patterns for Rozinante's Zig 0.16.0 TUI chess application.

> **Pinned to Zig 0.16.0 stable.** Always verify APIs against local std source (`zig env` → `.std_dir`).

## Workflow

When this skill triggers:

1. **Decide** — check decision trees below to select the right approach
2. **Apply** — implement using Rozinante conventions (Io threading, explicit allocators, barrel modules)
3. **Verify** — run `zig build test --summary all`

## Local Documentation

Run `zig env` to find paths. Key fields: `.lib_dir`, `.std_dir`, `.version`.

- **Language Reference**: `<lib_dir>/../doc/langref.html`
- **Std Library Source**: read files under `.std_dir` for API verification
- **Std Library Docs**: run `zig std` to start a local HTTP server

Check local docs before web search. When uncertain about an API, read the source file directly — Zig's stdlib is written to be readable.

## Core Rules

Rules that complement (not duplicate) CLAUDE.md/AGENTS.md. The reasoning matters more than the rule — once you know *why*, you can apply it to cases this list doesn't name.

**MUST:**
- Thread `io: std.Io` from `main(init)` into any function that does I/O — Zig 0.16 makes I/O an injected value, so threading it is what keeps the backend swappable and lets tests run against a single-threaded io.
- Thread the allocator explicitly (no globals, no hidden state) — the caller owns lifetime, and tests can substitute a leak-detecting allocator.
- `defer` the cleanup immediately after each allocation — acquire and release sit together, so no later code path can forget it.
- Prefer stack allocation for fixed-size data (buffers, small arrays) — no allocator, no failure path, nothing to leak.
- Use `ArenaAllocator` for groups of allocations that share a lifetime — free them in one shot instead of tracking each.
- Use `GeneralPurposeAllocator` in tests — it surfaces leaks the production allocator silently tolerates.
- `errdefer` on error paths — releases a half-built resource without repeating the cleanup in every branch.
- Handle errors explicitly — propagate with `try` internally; `switch` on them at boundaries where you can add context.
- Discard unused bindings with `_ = value;` — the compiler rejects unused locals, so this is required, not stylistic.
- Log via `std.log.scoped(.tag)`, not `std.debug.print`, in production — scoped tags are filterable and route through the configured log function.

**MUST NOT:**
- `@panic` in production — return an error so the caller decides; the only panic handler here exists to restore the terminal on the way down.
- Global mutable state — pass context through parameters so behavior stays testable and thread-safe.
- `undefined` without immediate initialization — only for buffers about to be filled; reading `undefined` is UB.
- Skip allocator threading on collections — every mutating method needs the allocator passed in.

## Decision Trees

```
Allocator choice? ─┬─► Process-lifetime data ───────────► init.arena.allocator()
                   ├─► Dynamic collections (Game state) ─► init.gpa (thread through)
                   ├─► Temporary batch work ─────────────► local ArenaAllocator over gpa
                   ├─► Fixed-size buffers ───────────────► stack: var buf: [N]u8 = undefined;
                   └─► Tests ───────────────────────────► std.testing.allocator (leak-detecting)
```

```
I/O pattern? ──────┬─► File read ──────────────────────► Dir.cwd().readFileAlloc(io, path, alloc, .limited(max))
                   ├─► File write (safe) ──────────────► dir.createFileAtomic(io, name, .{}) → write → .replace(io)
                   ├─► File write (simple) ────────────► dir.writeFile(io, .{ .sub_path = path, .data = bytes })
                   ├─► Directory creation ─────────────► Dir.cwd().createDirPath(io, path)
                   ├─► Directory listing ──────────────► dir.iterate() → iter.next(io)
                   ├─► Stdout (app output) ────────────► Io.File.Writer.init(.stdout(), io, &buf)
                   ├─► Subprocess stdin/stdout ────────► File.Writer/Reader.initStreaming(pipe, io, &buf)
                   ├─► Stderr (debug only) ────────────► std.debug.print (unbuffered, no io needed)
                   ├─► Logging ────────────────────────► std.log.scoped(.tag).info/warn/err
                   └─► Any I/O operation ──────────────► needs `io: std.Io` parameter
```

```
Error handling? ───┬─► Internal propagation ────────────► try (propagate to caller)
                   ├─► Boundary with user ──────────────► switch on error, log, provide context
                   ├─► Cleanup on error ────────────────► errdefer (resource release)
                   ├─► Expected absence ────────────────► optional (?T) + orelse / if-unwrap
                   ├─► Graceful fallback (e.g. config) ─► catch |err| { log.warn(...); return defaults; }
                   └─► Known-impossible state ──────────► unreachable (debug panic, release UB)
```

```
Testing? ──────────┬─► Unit test ───────────────────────► test "name" { ... } at bottom of file
                   ├─► Test I/O setup ─────────────────► std.Io.Threaded.global_single_threaded.io()
                   ├─► Allocation test ─────────────────► std.testing.allocator (detects leaks)
                   ├─► Test discovery ─────────────────► std.testing.refAllDecls(@This()) in root module
                   ├─► Assertions ──────────────────────► std.testing.expectEqual / expectEqualStrings / expect
                   └─► Run ─────────────────────────────► zig build test [--summary all]
```

```
Build system? ─────┬─► Add a dependency ────────────────► zig fetch --save <url> + b.dependency("name", .{})
                   ├─► Wire dependency module ──────────► dep.module("name") → add to .imports
                   ├─► Expose a module ─────────────────► b.addModule("name", .{...})
                   ├─► Internal module ─────────────────► b.createModule(.{...}) (no name, no export)
                   ├─► Import module in source ─────────► .imports = &.{.{.name = "x", .module = dep}}
                   └─► Run ─────────────────────────────► zig build | zig build run | zig build test
```

```
JSON? ─────────────┬─► Parse JSON string ──────────────► std.json.parseFromSlice(T, alloc, bytes, .{})
                   ├─► Serialize to JSON ──────────────► std.json.Stringify.valueAlloc(alloc, val, .{ .whitespace = .indent_2 })
                   └─► Unknown fields ─────────────────► .{ .ignore_unknown_fields = true }
```

```
Platform dirs? ────┬─► User data dir ──────────────────► known_folders.getPath(io, alloc, environ, .data)
                   ├─► User config dir ────────────────► known_folders.getPath(io, alloc, environ, .local_configuration)
                   └─► Environment map ────────────────► std.process.Environ.Map (passed from init)
```

## Rozinante Conventions

**Barrel modules:** Each subsystem has a root file that re-exports submodules. Include a test block with `refAllDecls` for test discovery.

```zig
// src/persistence.zig (barrel)
pub const pgn = @import("persistence/pgn.zig");
pub const storage = @import("persistence/storage.zig");
pub const config = @import("persistence/config.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
```

**Bit-packed enums:** `Piece` is `u4` (color in bit 3, type in bits 0-2, `empty = 15`). `Color` is `u1`, `PieceType` is `u3`, `CastlingRights` is `packed struct(u4)`.

**Scoped logging:** Use `const log = std.log.scoped(.tag);` at module level. Tags in use: `.engine`, `.persistence`, `.hints`.

**Buffer-based output:** Prefer returning `[]const u8` from a caller-provided `[]u8` buffer over allocating. Matches the project's stack-allocation conventions (e.g. `writePgn`, `generateFilename`).

**Atomic writes for crash safety:** Use `dir.createFileAtomic(io, name, .{ .replace = true })` → `atomic.file.writeStreamingAll(io, data)` → `atomic.replace(io)` with `errdefer atomic.deinit(io)`.

**Subprocess I/O:**
```zig
const child = try process.spawn(io, .{
    .argv = &.{path},
    .stdin = .pipe, .stdout = .pipe, .stderr = .ignore,
});
var stdin_writer = File.Writer.initStreaming(child.stdin.?, io, &buf);
var stdout_reader = File.Reader.initStreaming(child.stdout.?, io, &buf);
```

**Concurrency:** Use `io.concurrent()` instead of `std.Thread` for I/O tasks. Post custom events to the vaxis Loop queue for UI wakeup.

## Common Compiler Errors

| Error | Cause | Fix |
|---|---|---|
| `expected N argument(s), found M` | Missing `allocator` or `io` arg | Most collection methods and I/O functions need allocator/io as first arg |
| `no field named 'init' in ArrayList` | Old API | Use `.empty` or `initCapacity(gpa, n)` |
| `fingerprint field missing` | Old build.zig.zon | Add `.fingerprint = 0x...` and use `.name = .rozinante` (enum literal) |
| `no field named 'getStdOut'` | Old I/O API | Use `std.Io.File.stdout()` |
| `expected type '*const Io'` | Function needs io parameter | Thread `io` from `main(init)` |
| `unused local constant` | Zig rejects unused bindings | Use `_ = value;` to discard, or remove the binding |
| `parameter shadows declaration` | Param name matches a method in the same scope | Use abbreviated param names (`c` for color, `pt` for piece_type) |
| anonymous struct type mismatch | Anonymous struct literals are distinct types | Use a named struct for return types |

## Zig 0.16.0 API Gotchas

These were discovered during Rozinante development — verify against local std source if unsure:

| Old API | 0.16.0 API | Notes |
|---|---|---|
| `std.mem.trimRight` | `std.mem.trimEnd` | Renamed |
| `writer.flush(self)` | `writer.flush()` | No self parameter |
| `std.time.nanoTimestamp` | `Io.Timestamp.now(.awake)` | Clock API moved |
| `std.io` (direct stderr) | `std.log.scoped(.tag)` | Use logging, not direct stderr |
| `@embedFile("../data/x")` | `@embedFile("data/x")` | Paths relative to module's package root, not file |

**`@embedFile` path rule:** Cannot resolve paths outside the module's package root. Data files must live under `src/` (e.g. `src/data/openings.tsv`), not at the repo root.

**Test I/O:** Tests that need an `Io` instance use:
```zig
fn getTestIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}
```

## When NOT to Use

- Build/lint/test commands → use CLAUDE.md/AGENTS.md
- Zig language fundamentals (ownership, slices, comptime basics) → training data + local std source
- External tool configuration → use CLAUDE.md/AGENTS.md

---

Adapted from [Jeffallan/claude-skills/rust-engineer](https://github.com/Jeffallan/claude-skills/tree/main/skills/rust-engineer) — MIT license.
