---
name: zig-expert
description: >
  Zig 0.16.0 programming reference for building Rozinante — a TUI chess game in Zig.
  Covers the APIs and patterns actually used in this project: std.process.Init entry point,
  buffered I/O, arena allocator, build system (build.zig / build.zig.zon), testing with
  std.testing (including fuzz), and module structure.
  Use this skill whenever writing, reviewing, debugging, or modifying any Zig code in this project.
  Triggers on: any .zig file work, Zig compiler errors, build.zig changes, zig build failures,
  writing tests, designing data types, subprocess communication, or file format parsing.
  If the task involves Zig code, use this skill.
allowed-tools:
  - Read
  - Bash
  - Write
updated: 2026-05-06
references: []
---

# Zig Expert

Patterns for Rozinante's Zig 0.16.0 TUI chess application.

> **Pinned to Zig 0.16.0 stable.** Always verify APIs against local std source (`zig env` → `.std_dir`).

## Workflow

When this skill triggers:

1. **Decide** — check decision trees below to select the right approach
2. **Apply** — implement using Rozinante conventions (Init threading, explicit allocators)
3. **Verify** — run `zig build test`

## Local Documentation

Run `zig env` to find paths. Key fields: `.lib_dir`, `.std_dir`, `.version`.

- **Language Reference**: `<lib_dir>/../doc/langref.html`
- **Std Library Source**: read files under `.std_dir` for API verification
- **Std Library Docs**: run `zig std` to start a local HTTP server

Check local docs before web search. When uncertain about an API, read the source file directly — Zig's stdlib is written to be readable.

## Core Rules

Rules that complement (not duplicate) CLAUDE.md/AGENTS.md:

**MUST:**
- Thread `io` from `main(init)` to any function that does I/O
- Thread allocator explicitly — no globals, no hidden state
- `defer` immediately after every allocation for cleanup
- Prefer stack allocation for fixed-size data (buffers, small arrays)
- Use `ArenaAllocator` for groups of allocations with the same lifetime
- Use `GeneralPurposeAllocator` in tests for leak detection
- `errdefer` for cleanup on error paths
- Explicit error handling — switch on errors at boundaries, propagate with `try` internally
- Unused bindings → `_ = value;` (compiler rejects unused locals)

**MUST NOT:**
- `@panic` in production code — return errors instead
- Global mutable state — pass context through parameters
- `undefined` without immediate initialization — only use for buffers about to be filled
- Ignore allocator threading — collections need allocator passed to every mutating method

## Decision Trees

```
Allocator choice? ─┬─► Process-lifetime data ───────────► init.arena.allocator()
                   ├─► Dynamic collections (Game state) ─► init.gpa (thread through)
                   ├─► Temporary batch work ─────────────► local ArenaAllocator over gpa
                   ├─► Fixed-size buffers ───────────────► stack: var buf: [N]u8 = undefined;
                   └─► Tests ───────────────────────────► std.testing.allocator (leak-detecting)
```

```
I/O pattern? ──────┬─► Stdout (app output) ────────────► Io.File.Writer.init(.stdout(), io, &buf)
                   ├─► Stderr (debug) ──────────────────► std.debug.print (unbuffered, no io needed)
                   ├─► Logging ─────────────────────────► std.log.info/warn/err (no io needed)
                   └─► Any I/O operation ───────────────► needs `io: std.Io` parameter
```

```
Error handling? ───┬─► Internal propagation ────────────► try (propagate to caller)
                   ├─► Boundary with user ──────────────► switch on error, log, provide context
                   ├─► Cleanup on error ────────────────► errdefer (resource release)
                   ├─► Expected absence ────────────────► optional (?T) + orelse / if-unwrap
                   └─► Known-impossible state ──────────► unreachable (debug panic, release UB)
```

```
Testing? ──────────┬─► Unit test ───────────────────────► test "name" { ... } at bottom of file
                   ├─► Allocation test ─────────────────► std.testing.allocator (detects leaks)
                   ├─► Fuzz test ───────────────────────► std.testing.fuzz({}, fn, .{})
                   ├─► Assertions ──────────────────────► std.testing.expectEqual / expect
                   └─► Run ─────────────────────────────► zig build test [--fuzz]
```

```
Build system? ─────┬─► Add a dependency ────────────────► build.zig.zon .dependencies + b.dependency()
                   ├─► Expose a module ─────────────────► b.addModule("name", .{...})
                   ├─► Internal module ─────────────────► b.createModule(.{...}) (no name, no export)
                   ├─► Import module in source ─────────► .imports = &.{.{.name = "x", .module = dep}}
                   └─► Run ─────────────────────────────► zig build | zig build run | zig build test
```

## Common Compiler Errors

| Error | Cause | Fix |
|---|---|---|
| `expected N argument(s), found M` | Missing allocator arg on collection methods | Pass `gpa` as first arg to `append`, `deinit`, etc. |
| `no field named 'init' in ArrayList` | Old API | Use `.empty` or `initCapacity(gpa, n)` |
| `fingerprint field missing` | Old build.zig.zon | Add `.fingerprint = 0x...` and use `.name = .rozinante` (enum literal) |
| `no field named 'getStdOut'` | Old I/O API | Use `std.Io.File.stdout()` |
| `expected type '*const Io'` | Function needs io parameter | Thread `io` from `main(init)` |
| `unused local constant` | Zig rejects unused bindings | Use `_ = value;` to discard, or remove the binding |

## When NOT to Use

- Build/lint/test commands → use CLAUDE.md/AGENTS.md
- Zig language fundamentals (ownership, slices, comptime basics) → training data + local std source
- External tool configuration → use CLAUDE.md/AGENTS.md

---

Adapted from [Jeffallan/claude-skills/rust-engineer](https://github.com/Jeffallan/claude-skills/tree/main/skills/rust-engineer) — MIT license.
