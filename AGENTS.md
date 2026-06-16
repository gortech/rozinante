# Rozinante

Terminal chess learning game in Zig: play Stockfish at a chosen Elo with togglable learning aids (endangered-piece highlighting, best-move hints, opening identification), save games to PGN, and replay with per-move engine analysis. Also a vehicle for learning Zig — the code favors clarity over maximum optimization.

## Build & test

- `zig build` — compile the `rozinante` executable
- `zig build run` — build and run
- `zig build test` — all tests (module + executable passes, run in parallel); 216 currently pass
- `zig build preview` — piece sprite preview

## Stack

- Zig 0.16.0 (minimum, pinned in `build.zig.zon`).
- Build dependencies (`build.zig.zon`): `vaxis` (libvaxis 0.6.0, terminal UI) and `known_folders` (platform dirs). Stockfish is a **runtime** UCI-subprocess dependency, not a build dependency.

## Layout

Library/executable split: `src/root.zig` (library, re-exports `chess` as the `rozinante` package) and `src/main.zig` (executable, hosts the TUI). Barrel files re-export each directory:
- `src/chess.zig` → `src/chess/` — pieces, squares, moves, movegen, rules, perft
- `src/tui.zig` → `src/tui/` — renderer, game loop, input, menu, history, viewer, sprites
- `src/persistence.zig` → `src/persistence/` — pgn, storage, config
- `src/engine.zig` — Stockfish UCI subprocess; `src/openings.zig` + `src/data/openings.tsv` — embedded ECO opening book

## Reference docs

Read on demand (these are not loaded into context automatically):
- `docs/architecture.md` — architecture, design patterns, decision log, status/roadmap. Read before changing module structure, board representation, TUI rendering, engine threading, the opening book, or persistence.
- `docs/zig-0.16-notes.md` — Zig 0.16 API pitfalls this codebase already hit. Read before using `std.mem` trims, `std.Io`/`Writer`, `@embedFile`, or anonymous-struct returns.
