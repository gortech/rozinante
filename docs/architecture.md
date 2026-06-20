# Architecture

## Overview

Single Zig package, library/executable split:
- `src/root.zig` — library root; re-exports `chess` as the importable `rozinante` package.
- `src/main.zig` — executable entry point; hosts the TUI. Owns the Stockfish engine pointer (it needs allocator/io lifetime); `Game` holds the opponent as a plain enum, decoupling it from engine memory management.

## Module map

Each submodule is single-responsibility; a barrel file re-exports each directory.
- `src/chess.zig` → `src/chess/`: `piece.zig`, `square.zig`, `move.zig`, `board.zig`, `movegen.zig`, `rules.zig`, `perft.zig`.
- `src/tui.zig` → `src/tui/`: `renderer.zig`, `game.zig`, `input.zig`, `menu.zig`, `history.zig`, `viewer.zig`, `sprites.zig`.
- `src/persistence.zig` → `src/persistence/`: `pgn.zig` (SAN/PGN format, no FS deps), `storage.zig` (file I/O, dir resolution), `config.zig` (JSON prefs).
- `src/engine.zig` — Stockfish UCI subprocess management.
- `src/openings.zig` + `src/data/openings.tsv` — Lichess ECO opening book (3690 entries, CC0), `@embedFile`d at build time.

## Design patterns

- **Bit-packed enums:** `Piece` = `u4` (color bit 3, type bits 0-2, `empty`=15); `Color`=`u1`; `PieceType`/`File`/`Rank`=`u3`; `CastlingRights`=`packed struct(u4)`.
- **Board:** flat `[64]Piece`, rank-major (`a1=0 … h8=63`). Move generation is copy-on-write — `makeMove` returns a new `Board`; legality = apply the move, then reject if self-check. `MoveList` is stack-allocated, 256 capacity, no allocator.
- **TUI:** low-level vaxis API (`writeCell`, child windows), not the vxfw widget framework — the board is a custom grid renderer needing full cell control. Spinner animation during engine thinking uses `loop.tryEvent()` + a 100 ms `io.sleep` poll cycle (~10fps).
- **Engine threading:** `io.concurrent` for threaded move dispatch; the engine posts custom events to the vaxis Loop queue for immediate wakeup on move-ready (no polling for move detection). Subprocess I/O uses `Io.File.Reader/Writer.initStreaming` for pipe-backed buffered I/O. `findStockfish` validates a candidate path by spawn+kill (not `stat`), confirming the binary is actually executable.
- **Opening book:** two-tier lookup — longest UCI-prefix match (word-boundary enforced), then exact EPD (first 4 FEN fields) transposition fallback. `OpeningBook` (~300 KB) is arena/heap-allocated, never stack.
- **Persistence:** buffer-based `writePgn` returns `[]const u8` from a caller-provided buffer. Crash-safe saves via `Dir.createFileAtomic()` + `atomic.replace()` with `errdefer atomic.deinit(io)`. PGN filename format `YYYY-MM-DD_HHMMSS_eloXXXX_sColor.pgn` — the color field uses an `_s` prefix (`_swhite`, `_sblack`) to disambiguate it from elo digits. Resume replays parsed PGN moves through `executeMove()` rather than restoring board history directly, keeping derived state (SAN, opening detection) consistent.
- **Platform dirs:** `known_folders` — games in the data dir, config in the config dir.

## Decision log

- **TUI uses the low-level vaxis API, not vxfw.** The chess board is a custom grid renderer, not a composable widget tree; the low-level API gives full cell control for multi-row squares, colored highlights, and inline promotion UI. Revisit only if later work needs complex widget composition.
- **Persistence is a three-module layout** (`pgn.zig` format, `storage.zig` I/O, `config.zig` JSON prefs) behind the `persistence.zig` barrel, mirroring `src/chess/` and `src/tui/`. Each module is testable independently; `pgn.zig` has no filesystem dependencies.
- **Difficulty is Stockfish `Skill Level` (0–20), not `UCI_Elo`.** `UCI_Elo` floors at ~1320 CCRL, so the genuine-beginner floor is an app-side handicap that, at the lowest skills, substitutes a uniformly-random legal move for the engine's pick (seeded once at startup). The save filename keeps a CCRL-Elo field (via `skillToElo`) so the storage format is unchanged; resume maps it back with `eloToSkill`. Best-move hints momentarily raise `Skill Level` to 20 on the shared engine and restore it via `defer` — safe because hints never overlap the opponent search.
- **Theme is a runtime `var Palette`** (`renderer.Theme`) swapped wholesale by the menu selector for live preview; the container-scope `Theme` aliases in `menu/history/viewer/piece_preview` are *pointer* aliases (`&renderer.Theme`) so every render site reads the live palette. Classic reproduces the original RGBs exactly.
- **Post-game analysis caches in the PGN file.** Evaluation is mate-aware (`analysis.Eval = union(enum){ cp, mate }` + a saturating `toCp` that maps a mate to ±(`mate_base`−|N|), so a missed/allowed mate dominates any centipawn value instead of parsing as 0.00). A background full-strength `io.concurrent` pass — dispatched at game-end and on opening an un-analyzed game — rates each *player* move good/meh/bad by player-perspective centipawn loss (lichess cutoffs) and records the engine's best move + eval per position into a `GameAnalysis` (pure, allocator-free, in `src/analysis.zig`). It is persisted **in the saved game**: per-move `{roz: tier best=SAN eval cpl}` comments + one `[RozAnalysis "v1 plies=N bad=B meh=M acc=A"]` header tag, round-tripped through the parser (which now captures comments instead of discarding them) so files stay valid for standard PGN tools. Write-back is a **path-targeted** atomic overwrite of the opened file (`writeAnalyzedPgn`), not `saveGame` (which regenerates the filename). The multi-position pass is cancelled **cooperatively** (atomic flag + `await`), never `eng.stop()` — a stop write would race the worker's per-position UCI writes on the shared `stdin_writer`; the cancel is awaited on every screen exit before any other engine command, and a completeness marker (version + ply-count) is written only after a full pass so partial/foreign files re-analyze.

## Status & roadmap

Done: chess core (full rules), TUI board + local play, Stockfish UCI integration, opening DB, game persistence + config, live hints + difficulty + themes + take-back, post-game analysis & review (mate-aware eval, in-PGN analysis cache, replay-viewer overlays, game-end summary card, games-list trend). Next: Chess Clock.

Chess-rule correctness is test-covered: all piece movement, castling, en passant, promotion, check/checkmate/stalemate, fifty-move rule, insufficient material; perft depth 3 = 8,902 from the start position. **Threefold repetition is deferred** — it needs game-level position-hash history beyond the `Board` struct, to land with the later game-state management work.
