# Zig 0.16 notes

API pitfalls and conventions this codebase already hit on Zig 0.16.0. Check here before writing `std.mem` trims, `std.Io`/`Writer` code, `@embedFile`, or anonymous-struct returns.

- **`std.mem.trimRight` → `std.mem.trimEnd`** (renamed). `Writer.flush()` no longer takes a `self` parameter. Watch for similar `std.mem` / `Io` Writer renames.
- **`@embedFile` cannot resolve paths outside the module's package root.** Data files for `src/` modules must live under `src/` (hence `src/data/openings.tsv`, not a repo-root `data/`). No `build.zig` change needed when the file is within the module root.
- **Each anonymous struct literal is a distinct type**, causing declaration-vs-return type mismatches. Use named structs (e.g. `MovetextResult`) for returns.
- **The new `std.Io.Writer` lacks `print()`.** Persistence uses a buffer-return approach (`writePgn` returns `[]const u8` from a caller buffer) instead, which also matches the project's stack-allocation conventions.
