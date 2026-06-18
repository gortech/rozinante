---
date: 2026-06-18
type: feat
status: active
origin: docs/brainstorms/play-experience-improvements-requirements.md
---

# feat: Play-experience improvements (take-back, confirmations, themes, difficulty, hints, input)

## Summary

Implement the six play-experience fixes scoped in the origin requirements doc, in four phases that follow the brainstorm's build order. **Difficulty and hints land first** because they share the single Stockfish instance: difficulty becomes a Skill Level (0–20) dial whose engine strength comes from Stockfish `Skill Level` (not `UCI_Elo`, which floors at ~1320) plus an app-side move handicap for the genuine-beginner floor, and best-move hints are taken at full strength by momentarily lifting that limiter on the same engine. Then **take-back** (move-pair undo extending the existing `undoMove()` + save rewrite/delete), **confirmation prompts** (mirroring the existing resign prompt for quit / N→menu / delete-saved), and finally **themes** (a runtime-swappable full palette) and the **N-key menu-paint fix**.

The work touches `src/engine.zig`, `src/tui/game.zig`, `src/tui/input.zig`, `src/tui/menu.zig`, `src/tui/renderer.zig`, `src/tui/history.zig`, `src/persistence/config.zig`, and `src/main.zig`, building on patterns already in those files (the `resign_pending` modal, `board_history`, the `eloToDepth`/`eloToMovetime` ladders, the `Theme` palette).

---

## Problem Frame

Several rough edges undercut Rozinante's learning goal: no take-back, silent destructive actions, a "lowest" difficulty that still plays ~1320, hints produced by the deliberately-weakened engine, one fixed board look, and a one-keypress lag returning to the menu. Full pain narrative and rationale live in the origin doc (see Sources & References).

---

## Requirements Traceability

| Origin item | Where addressed |
|---|---|
| R1, R2 (Undo key, move-pair, repeatable, both-color floor) | U4 |
| R3 (undo rewrites/deletes save, resets high-water mark) | U5 |
| R4 (aids recompute after undo) | U4 (endangered + opening + clear stale), main dispatch |
| R5 (undo inert while thinking / after end) | U4 (input gate + floor no-op) |
| R6 (quit-in-progress confirm; finished game quits silently) | U6 |
| R7 (N→menu confirm; N keypress can't also dismiss) | U6 |
| R8 (delete-saved confirm; states permanence) | U6 (history) |
| R9 (quit from menu exits, no prompt) | U6 (existing menu behavior preserved) |
| R10, R12 (full-palette presets; Classic default unchanged) | U7 |
| R11 (theme chosen in menu w/ preview, persisted) | U7 |
| R13 (single Skill Level dial; engine derives caps; low-end handicap) | U1, U2 |
| R14 (difficulty governs opponent only, not aids) | U1 (boundary), U3 |
| R15 (full-strength hints) | U3 |
| R16 (N takes effect on that keypress) | U6 (in-progress prompt), U8 (no-game menu paint) |
| AE1 (covers R1, R2) | U4 |
| AE2 (covers R3) | U5 |
| AE3 (covers R4) | U4 |
| AE4 (covers R5) | U4 |
| AE5 (covers R6, R7) | U6 |
| AE6 (covers R9) | U6 |
| AE7 (covers R8) | U6 |
| AE8 (covers R13, R14, R15) | U1+U2 (opponent) / U3 (hint) |
| AE9 (covers R16) | U6 (prompt on first N) + U8 (menu paint) |
| AE10 (covers R10–R12) | U7 |

**Origin acceptance examples:** AE1–AE10 (origin doc). No A-IDs / F-IDs defined in origin.

---

## Scope Boundaries

Carried from the origin doc (non-goals this plan does not build):

- No word-named difficulty tiers and no separate user-facing depth knob — difficulty is one Skill Level (0–20), depth/time derived internally.
- No per-component theming (board-only / pieces-only); full-palette presets only.
- No redo / forward-step after undo.
- No undo or step-through of a *finished* game (deferred to the future Analysis feature).
- No in-game theme switching (themes are chosen in the menu).
- No high-contrast / mono accessibility theme in the initial set.

### Deferred to Follow-Up Work

- None. All six improvements ship in this plan.

---

## Context & Research

### Relevant Code and Patterns

- **Difficulty / engine:** `src/engine.zig` — `Engine.elo`, `uciHandshake()` sets `UCI_LimitStrength`+`UCI_Elo`; `getMove()` sends `go depth {eloToDepth(elo)} movetime {eloToMovetime(elo)}`; `analyze(board, ms)` runs on the *same* engine (the R15 bug); `eloToDepth`/`eloToMovetime` ladders (clamped 200–2800); `restart()` re-handshakes. Two construction sites in `src/main.zig` (`Engine.init(io, path, game_elo)`), resume and new-game flows.
- **Undo:** `src/tui/game.zig` — `Game.undoMove()` already pops `board_history`/`board_count`, decrements `move_count`, resets phase/result; does *not* clear hints, refresh opening, or clear `engine_last_move`. `executeMove()` pushes `board_history` then increments `board_count` and `move_count` in lockstep. `player_color` is on `Game`. `computeEndangered()`, `clearHints()`, `updateOpening()` (private) exist.
- **Confirmations:** `src/tui/input.zig` — `resign_pending` modal is the template (Y/Enter confirm, N/Esc cancel); `Action` enum; the unconditional `q`/Ctrl-C → `.quit` at the top; the thinking-state gate (lines ~31–41); `n` → `.new_game`. `src/tui/renderer.zig` `renderInfoPanel` renders the resign prompt string. `src/tui/history.zig` `HistoryScreen.handleInput` returns `.delete` immediately on `Key.delete`; `src/main.zig` `runGameHistory` `.delete` branch calls `storage.deleteGame` + `removeAtCursor`.
- **Themes:** `src/tui/renderer.zig` `Theme` is a `pub const` namespace (`Theme.bg`, `Theme.dark_square`, …) referenced across `renderer.zig`, `menu.zig`, `main.zig`, `viewer.zig`, `history.zig`. Hardcoded selection backgrounds `{40,30,70}` appear in `menu.zig` `highlightRow` and `history.zig` row rendering. `src/piece_preview.zig` already hosts a highlight-mark gallery (`zig build preview`) — the established visual-verification vehicle.
- **Persistence:** `src/persistence/config.zig` `Preferences`/`JsonPreferences` (`default_elo: u16`), `loadPreferences` parses with `ignore_unknown_fields = true`. `src/persistence/storage.zig` filename `…_elo{d}_s{color}.pgn`, `SaveGameData.elo`, `GameInfo.elo`, resume parses elo from filename. `src/main.zig` `autoSave()` overwrites `current_save_path` with full PGN; the game loop's auto-save fires only on `move_count > prev_move_count`.
- **N-key lag:** `src/main.zig` menu loop (`while (!menu_done)`) calls `loop.nextEvent()` (blocking) *before* painting the menu.

### Institutional Learnings

- None — `docs/solutions/` does not exist in this repo.

### External References

- Stockfish strength behavior (researched during brainstorm): `UCI_Elo` and `Skill Level` are the same internal lever, both floored at ~1320 CCRL (Stockfish issue #4717, commit a08b8d4). Sub-1320 beginner play is unreachable via any Stockfish option and requires app-side move handicapping. See origin Dependencies/Assumptions.

---

## Key Technical Decisions

- **Strength via `Skill Level`, display/persist via CCRL Elo (U1).** Replace `Engine.elo: u16` with `skill: u8` (0–20). The handshake sends `setoption name Skill Level value {skill}` and drops `UCI_LimitStrength`/`UCI_Elo` (they re-floor the low end at 1320). The existing `eloToDepth`/`eloToMovetime` ladders stay, fed once at the boundary by `skillToElo(skill)` — so **both** search caps scale with the dial (avoids the move-time floor that rekeying only depth would leave). `skillToElo` is the CCRL reference table; its value is shown beside the dial (labelled not human-comparable) and written to the save filename's `elo` field, so `storage.zig`'s format is unchanged. Resume maps the filename's elo back via `eloToSkill`.
- **Beginner floor via app-side handicap (U2).** Skill 0 + depth still bottoms out at ~club strength, so the lowest Skill Levels occasionally substitute a random / sub-optimal *legal* move for the engine's pick. The mechanism is committed here; the **rate** is calibrated at implementation against the installed Stockfish (execution-time, see Deferred).
- **Full-strength hints reuse the one engine (U3).** `analyze()` runs on the opponent engine, which now carries `Skill Level {skill}`. The hint search momentarily raises `Skill Level` to 20 (full) and restores `{skill}` with an exception-safe `defer`. No second subprocess. *Safe because* the hint is dispatched only on the human's turn and `cancelAnalysis` runs before any opponent `getMove`, so hint and opponent search never overlap on the shared engine — `ponytail:` single engine, add a second instance only if hints ever need to run during the opponent's move.
- **Move-pair undo extends `undoMove()` (U4).** A new `undoMovePair()` calls `undoMove()` twice (engine reply + player move), clearing stale hints and `engine_last_move` and refreshing the opening readout. The `.undo` handler in `main.zig` then **cancels any in-flight hint analysis first** (mirroring `.toggle_hints` / `.new_game`, *not* the post-engine-move block — a hint search for the pre-undo board may still be running and would otherwise set a stale `hint_best_move`), then recomputes endangered + re-dispatches when hints are enabled. The floor is `move_count == 0` for a White player and `move_count == 1` for a Black player (the engine's opening move is never popped), so undo always lands on the player's turn for both colors.
- **Save tracks undo by detecting any `move_count` change (U5).** The game loop's auto-save guard changes from `> prev_move_count` to `!= prev_move_count`: a decrease rewrites the save from the remaining moves, and reaching `move_count == 0` deletes the save file and clears the resume pointer (the zero-move auto-save guard would otherwise leave the stale full game on disk).
- **Confirmations mirror the resign modal (U6).** Add `quit_pending` / `leave_pending` to `Game` and a `delete_pending` to `HistoryScreen`, all using the resign convention (Y/Enter confirm, N/Esc cancel). Setting a pending flag returns `.render` so the prompt paints on the triggering keypress (a single N can't both open and dismiss). Quit/leave prompts must **not** claim the game is lost (per-move auto-save + crash recovery persist it); the delete prompt **must** state the deletion is permanent.
- **Runtime themes by swapping a module-level palette (U7).** Promote `Theme` from a `pub const` namespace to a module-level `pub var Theme: Palette` whose fields keep the current names. Direct `renderer.Theme.bg` uses stay valid, but the four files that alias the symbol at container scope (`const Theme = renderer.Theme;` in `menu.zig`, `history.zig`, `viewer.zig`, `piece_preview.zig`) must become **pointer aliases** (`const Theme = &renderer.Theme;`) — a `const` initializer can't read a runtime `var`, and a value copy would snapshot a stale palette and defeat live preview. Zig auto-derefs `Theme.bg` through the pointer, so per-use call sites are unchanged and read live. A `ThemeId` enum + `palette(id)` returns each preset (Classic = today's values); the menu selector assigns `renderer.Theme = palette(id)` (live preview for free) and persists the id. `ponytail:` one global palette, fine because exactly one theme is active at a time; revisit only if per-window themes are ever needed.
- **N-key menu paint (U8).** Reorder the `src/main.zig` menu loop to paint before the blocking `nextEvent()`, so the menu (or the in-progress confirm prompt, via U6) appears on the keypress that triggers it.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

**Difficulty data flow (U1/U2).** The dial value is the single source of truth; everything else derives:

```
Skill Level (0..20)  ── skillToElo() ──▶  CCRL Elo  ──┬─▶ shown beside dial (info)
        │                                              ├─▶ eloToDepth() ─┐
        │                                              └─▶ eloToMovetime()─┤─▶ go depth/movetime
        └── setoption Skill Level value {skill} ────────────────────────────▶ opponent strength
        └── (skill ≤ floor) app-side handicap: sometimes replace engine pick with random legal move
```

**Undo index model (U4).** `board_history[i]` is the board *before* ply `i`; `board_count == move_count`. From a player-turn state, popping two plies lands on the previous player-turn state:

| Player | Plies (turn owner) | Player-turn states | Undo floor (never pop below) |
|---|---|---|---|
| White | 0:W 1:B 2:W 3:B … | `move_count` even (0,2,4) | `move_count == 0` |
| Black | 0:W(engine) 1:B 2:W 3:B … | `move_count` odd (1,3,5) | `move_count == 1` (keep engine's opening) |

`undoMovePair()` no-ops when `move_count - floor < 2`.

**Full-strength hint toggle (U3).**

```
analyzeFullStrength(board):
    send "setoption name Skill Level value 20"
    defer send "setoption name Skill Level value {self.skill}"   // restores even on error
    return analyze(board, strong_movetime)
```

---

## Implementation Units

### U1. Skill Level difficulty dial + engine wiring + config migration

**Goal:** Replace the Elo slider with a single Skill Level (0–20) dial; the engine's opponent strength comes from Stockfish `Skill Level`, with depth/move-time derived from the dial and the CCRL Elo shown for info.

**Requirements:** R13 (dial + derived caps), R14 (opponent-only boundary)

**Dependencies:** None

**Files:**
- Modify: `src/engine.zig` (field `skill: u8`, handshake, `getMove`, `restart`; add `skillToElo`/`eloToSkill`)
- Modify: `src/tui/menu.zig` (`GameConfig`, `Menu.selected_*`, `ActiveField`, `handleInput`, `render`, `getConfig`)
- Modify: `src/persistence/config.zig` (`Preferences`/`JsonPreferences` Skill field + migration)
- Modify: `src/main.zig` (both `Engine.init` sites; menu→engine wiring; save-filename elo from `skillToElo`; resume elo→skill; **and every `prefs.default_elo` / `menu_config.elo` site rekeyed to skill** — the crash-recovery resume default, the menu selector init (`selected_skill = prefs.default_skill_level`), the history-resume defaults, and the start-time persistence block that compares/writes the changed difficulty pref)
- Test: `src/engine.zig`, `src/tui/menu.zig`, `src/persistence/config.zig` (inline tests)

**Approach:**
- `Engine`: store `skill: u8`. `uciHandshake()` sends `setoption name Skill Level value {skill}`; remove the `UCI_LimitStrength`/`UCI_Elo` commands. `getMove()` keeps `go depth {eloToDepth(e)} movetime {eloToMovetime(e)}` where `e = skillToElo(skill)`. `restart()` unchanged beyond re-handshake.
- `skillToElo(u8) u16`: CCRL table (0≈1320 … 19≈3191, 20→a sentinel "max"). `eloToSkill(u16) u8`: nearest-skill inverse (monotonic), used for migration and resume.
- `menu.zig`: rename the Elo field to a Skill Level field (`selected_skill: u8`, min 0 / max 20 / step 1), `ActiveField.skill`; render `Skill Level: N  (~Elo XXXX)` (or "Max" at 20); `GameConfig.skill_level: u8`.
- `config.zig`: `Preferences.default_skill_level: u8`; `JsonPreferences` keeps an optional `default_elo: ?u16` plus `default_skill_level: ?u8` so old configs migrate: skill present → **clamp to 0..20 and** use it; else map `default_elo` via `eloToSkill`; else a low default. Stop writing `default_elo`. A persisted skill outside 0..20 (hand-edited / corrupt config) is clamped on load, never passed raw to `skillToElo` or the handshake — matching the existing corrupt-JSON→defaults posture.
- `main.zig`: derive `game_skill` (new) and `game_elo = skillToElo(game_skill)` for the save filename/header; resume sets `game_skill = eloToSkill(resume_elo)`.

**Patterns to follow:** existing `eloToDepth`/`eloToMovetime` ladders and their tests; the `menu.zig` Elo selector + its clamping test; `config.zig` round-trip / defaults tests.

**Test scenarios:**
- Happy path: `skillToElo(0) == 1320`; `skillToElo` monotonically non-decreasing across 0..20; `skillToElo(20)` is the max sentinel.
- Edge: `eloToSkill(1320) == 0`; `eloToSkill` of a legacy `1200` clamps to `0`; round-trip `eloToSkill(skillToElo(s)) == s` for representative `s`.
- Edge: a persisted `default_skill_level` outside 0..20 (e.g. `200`) loads clamped into range, so it never indexes the `skillToElo` table out of bounds on menu render.
- Edge: `menu` skill clamps at 0 on left and 20 on right (mirror the existing elo-clamp test); `getConfig()` returns the selected skill.
- Edge: `config` round-trip persists/loads `default_skill_level`; loading a config with only `default_elo` (no skill) yields the `eloToSkill`-mapped skill; missing file yields the low default.
- Integration (engine subprocess, verify via run): a higher Skill Level visibly plays stronger; opponent strength scales with the dial.

**Verification:** `zig build test` green; running the game shows a Skill Level dial with a CCRL Elo readout, and old configs / saved games open without error.

---

### U2. App-side beginner move handicap

**Goal:** Make the lowest Skill Levels reach genuine-beginner play by occasionally substituting a random / sub-optimal legal move for the engine's pick.

**Requirements:** R13 (beginner floor)

**Dependencies:** U1

**Files:**
- Modify: `src/engine.zig` (pure `handicapRate` / `pickHandicapMove` helpers); `src/main.zig` (own + seed-once a `std.Random.DefaultPrng`; apply the handicap at the opponent-move seam where `engine_result.move` is produced)
- Test: `src/engine.zig` (inline, pure helpers)

**Approach:**
- Add pure helpers: `handicapRate(skill: u8) u8` (per-skill probability, 0 above a threshold) and `pickHandicapMove(board, rng) Move` (a uniformly-random legal move via `chess.legalMoves`). A single persistent `std.Random.DefaultPrng`, owned at game-loop scope in `main.zig` and seeded **once** at startup from the time idiom the codebase already uses for its random-color pick (`@as(u64, @bitCast(Io.Timestamp.now(io, .real).nanoseconds))` — note `std.crypto.random` does **not** exist in this repo's Zig 0.16 std), is threaded into the seam: after the engine returns its move, if `skill` is low and `prng.random()` fires under the rate, replace it with `pickHandicapMove`. (The codebase has no RNG today; re-seeding per move would be deterministic — seed exactly once.)
- Keep the seam at the move boundary (where `engine_result.move` is produced) so it never touches the analysis/hint path (R14).
- `ponytail:` a uniform random legal move is the floor lever; replace with a "blunder-weighted" pick only if calibration shows uniform-random feels too erratic.

**Test scenarios:**
- Happy path: `handicapRate(0) > 0`; `handicapRate(20) == 0`; rate is non-increasing in skill.
- Edge: `pickHandicapMove` returns a move present in `chess.legalMoves(board)` for several positions (including a position with a single legal move → returns that move).
- Edge: with a seeded RNG, handicap fires deterministically at skill 0 and never at a high skill.
- Covers AE8 (opponent half): at Skill Level 0 with the handicap, the opponent's chosen move can be a non-engine legal move.

**Verification:** `zig build test` green; at the lowest difficulty the opponent makes clearly beginner-level moves (calibrated against the installed Stockfish during implementation).

---

### U3. Full-strength best-move hints

**Goal:** Best-move hints reflect a full-strength search regardless of the selected difficulty.

**Requirements:** R15 (full-strength hint), R14 (aids unweakened)

**Dependencies:** U1

**Files:**
- Modify: `src/engine.zig` (`analyzeFullStrength` wrapping `analyze` with a Skill Level raise + `defer` restore)
- Modify: `src/main.zig` (`analysisWork` calls the full-strength path)
- Test: `src/engine.zig` (inline) + integration

**Approach:**
- Add `analyzeFullStrength(board, movetime)`: send `setoption name Skill Level value 20`, `defer` send `setoption name Skill Level value {self.skill}` (restores even on `EngineTimeout`/`EngineDead`), then run the existing `analyze`. `analysisWork` in `main.zig` switches to this path.
- Rely on the existing dispatch invariant: hints fire only on the human's turn and `cancelAnalysis` precedes `dispatchEngineMove`, so the raise/restore never races the opponent search on the shared engine.

**Test scenarios:**
- Integration (engine subprocess, verify via run — matches the repo convention that engine I/O is integration-tested, e.g. the `findStockfish` test note): with difficulty at Skill 0, an enabled hint shows a strong move while the opponent still plays weakly; after a hint, the opponent's next move is unaffected (Skill Level restored).
- Covers AE8 (hint half): lowest difficulty + requested hint still shows a strong move.

**Verification:** at low difficulty the best-move hint matches a strong reference engine's top move (no longer diverging), and opponent strength is unchanged after a hint.

---

### U4. Move-pair undo (take-back) core

**Goal:** A dedicated Undo key (U) on the player's turn reverts the last move-pair, repeatable down to the player's first move, with learning aids recomputed for the restored position.

**Requirements:** R1, R2, R4, R5

**Dependencies:** None

**Files:**
- Modify: `src/tui/game.zig` (`undoMovePair`; clears stale hints + `engine_last_move` and refreshes the opening — endangered is recomputed by `main.zig`'s `.undo` handler, see Approach)
- Modify: `src/tui/input.zig` (`Action.undo`; `u` key gated to playing + human turn)
- Modify: `src/tui/renderer.zig` (add `U Undo` to the keybind hints in `renderInfoPanel`)
- Modify: `src/main.zig` (handle `.undo`: cancel in-flight analysis, recompute endangered + re-dispatch full-strength analysis)
- Test: `src/tui/game.zig`, `src/tui/input.zig` (inline)

**Approach:**
- `undoMovePair()`: `floor = if (player_color == .black) 1 else 0`; if `move_count - floor < 2` return; else call `undoMove()` twice. Then `clearHints()`, clear `engine_last_move`, call `updateOpening()` so the opening readout matches the restored line.
- `input.zig`: add `.undo`; `if (key.matches('u', .{}))` → only when `game.game_phase == .playing and game.isHumanTurn()` call `game.undoMovePair()` and return `.undo`, else `.none`. The existing thinking-state gate already makes `u` inert while the engine is thinking; the phase check makes it inert after the game ends (R5).
- `main.zig` `.undo`: first `cancelAnalysis(io, eng, &analysis_future, &analysis_pending)` — a hint search for the *pre-undo* board may be in flight (`engine_move_ready` dispatches one for the human's turn), and the post-engine-move block does **not** cancel because `analysis_pending` is false there; on the undo path it can be true and would set a stale `hint_best_move`. Then, if `hints_enabled`, `computeEndangered()` and re-dispatch full-strength analysis (mirror `.toggle_hints`). Persistence handled by U5.

**Patterns to follow:** existing `undoMove()`; the `executeMove`→`.render`→engine-dispatch flow; `clearHints`/`computeEndangered`.

**Test scenarios:**
- Covers AE1: White player, two plies played, `undoMovePair()` → `move_count` down by 2, White to move, board equals the pre-move snapshot; repeating from four plies reaches `move_count == 0`.
- Covers R2 (Black floor): Black player, after engine-opening + player + engine (3 plies), `undoMovePair()` → `move_count == 1`, Black to move; a second `undoMovePair()` is a no-op (engine opening preserved).
- Covers AE4 / R5: from a state with `move_count - floor < 2` (e.g. White player at `move_count == 1`, or just the engine opening for Black), `undoMovePair()` does nothing.
- Covers R4 (stale-hint guard): pressing Undo while a best-move analysis for the pre-undo position is in flight must not leave a `hint_best_move` from that old position on the restored board — the `.undo` handler cancels analysis before recompute (integration: exercise undo within the post-engine-move hint window).
- Covers AE3 / R4: craft a position where a piece is endangered, undo to a position where it is not, then `computeEndangered()` → that square is no longer flagged; `hint_best_move` is cleared by the undo.
- Edge: after `undoMovePair`, `game_phase == .playing` and `result == null` even if the undone move had ended the game.
- Input: `u` returns `.none` when `game_phase == .ended`; returns `.undo` on the human's turn while playing.

**Verification:** `zig build test` green; pressing U in a live game walks the position back a move-pair at a time to the player's first move and stops, with `U Undo` shown in the keybind hints and aids reflecting the restored board.

---

### U5. Undo persistence (save rewrite / delete)

**Goal:** Undo rewrites the on-disk save to the remaining moves and resets the auto-save high-water mark; undoing to the initial position deletes the save and clears resume state.

**Requirements:** R3

**Dependencies:** U4

**Files:**
- Modify: `src/main.zig` (generalize the game-loop auto-save guard; add the zero-move delete branch)
- Test: `src/persistence/pgn.zig` or `src/tui/game.zig` (inline, via `writePgn` on post-undo state) + integration

**Approach:**
- Change the loop's `if (game_state.move_count > prev_move_count)` to `!= prev_move_count`. On change set `prev_move_count = game_state.move_count`; if `move_count == 0`, `storage.deleteGame(current_save_path)` and clear `current_save_path` (so crash-recovery won't resurface it); otherwise call `autoSave` (which already overwrites `current_save_path` with the full PGN of `move_history[0..move_count]`).
- This reuses `autoSave`'s existing full-rewrite behavior; the only new logic is the decrease/zero handling.

**Patterns to follow:** existing `autoSave` overwrite path; `storage.deleteGame`; `storage.saveGame`/`loadGame` round-trip tests.

**Test scenarios:**
- Covers AE2: play four plies on a `Game`, `undoMovePair()`, then `pgn.writePgn(&buf, header, move_history[0..move_count], board_history[0..move_count+1])` (4-arg signature — a stack `buf: [N]u8` and a `pgn.PgnHeader{}`, or assert through `autoSave`) → the PGN move text contains only the two remaining plies, not the taken-back ones.
- Edge: a forward move still triggers a save (the `!=` guard preserves the existing behavior).
- Integration: undo to the initial position deletes the save file and the game no longer appears as resumable on next launch.

**Verification:** after undo, the saved PGN (and any resume) contains only the moves left on the board; undoing to the start removes the save.

---

### U6. Confirmation prompts (quit, N→menu, delete-saved)

**Goal:** Guard the three destructive actions with confirmation prompts using the existing resign convention, while keeping menu-quit and finished-game-quit instant.

**Requirements:** R6, R7, R8, R9, R16 (in-progress branch — confirm prompt renders on the triggering keypress)

**Dependencies:** None

**Files:**
- Modify: `src/tui/game.zig` (`quit_pending`, `leave_pending` flags + init)
- Modify: `src/tui/input.zig` (modal handling + conditional quit / N triggers)
- Modify: `src/tui/renderer.zig` (`renderInfoPanel` prompt strings)
- Modify: `src/tui/history.zig` (`delete_pending` + handleInput ordering + render prompt)
- Test: `src/tui/input.zig`, `src/tui/history.zig` (inline)

**Approach:**
- `input.zig`: handle `resign_pending` (existing), then `quit_pending`, then `leave_pending` modals (Y/Enter → `.quit` / `.new_game`; N/Esc → clear + `.render`). The `q`/Ctrl-C trigger and the `n` trigger set their pending flag (returning `.render`) **only when `game_phase == .playing`**, otherwise pass through to immediate `.quit` / `.new_game`. Place the quit/leave triggers so they're reachable during engine thinking (still in progress).
- `renderInfoPanel`: add prompt strings mirroring the resign line. Quit/leave copy must not imply data loss (e.g. `Quit game? Y/Enter = Yes  N/Esc = No`, `Leave to menu? Y/Enter = Yes  N/Esc = No`). 
- `history.zig`: add `delete_pending`; on `Key.delete` set it (re-renders via the history loop's top-of-loop render) instead of returning `.delete`; while pending, Y/Enter returns `.delete` and N/Esc cancels — and this check must precede the Esc/`q`→`.back` handling so Esc cancels the delete rather than leaving the screen. Render a `Delete permanently? Y/Enter = Yes  N/Esc = No` prompt (states permanence per R8).

**Patterns to follow:** `resign_pending` in `input.zig` + its prompt in `renderInfoPanel`; the `HistoryScreen` action/render structure.

**Test scenarios:**
- Covers AE5: game playing, `q` → `quit_pending` set and action is `.render` (not `.quit`); then `n` → cleared, `.render` (back to game); the `q`→`y` path returns `.quit`.
- Covers R7 / AE9: game playing, `n` (new-game key) → `leave_pending` set, `.render`; then `y` → `.new_game`; a separate `n` cancels. (A single N press opens but cannot dismiss.)
- Covers R6 (finished game): `game_phase == .ended`, `q` → `.quit` with no prompt.
- Covers R9: menu quit is unchanged (existing `menu.handleInput` `q` → `.quit`).
- Covers AE7 / R8: history with games, `Key.delete` → `delete_pending` set, no removal yet; `y` → `.delete`; `n`/Esc → cancel (no `.delete`, screen not exited).

**Verification:** `zig build test` green; quitting or pressing N mid-game shows a prompt that cancels back to the game; deleting a saved game asks first and says the deletion is permanent; quitting from the menu or a finished game is instant.

---

### U7. Selectable full-palette themes

**Goal:** The player picks from Classic (default), Wood, Green, and Blue full-palette themes in the menu (with live preview), persisted across sessions; Classic reproduces today's look exactly.

**Requirements:** R10, R11, R12

**Dependencies:** None

**Files:**
- Modify: `src/tui/renderer.zig` (`Palette` struct; `ThemeId` enum; presets; `pub var Theme: Palette`; `palette(id)`)
- Modify: `src/tui/menu.zig` (pointer alias `const Theme = &renderer.Theme;`; theme selector field initialized from prefs; `GameConfig.theme_id`; live preview; selection-bg from palette)
- Modify: `src/tui/history.zig` (pointer alias `const Theme = &renderer.Theme;`; selection-bg from palette)
- Modify: `src/tui/viewer.zig` (pointer alias `const Theme = &renderer.Theme;` — render-only, no behavior change)
- Modify: `src/persistence/config.zig` (`theme` string pref + `ThemeId` from/to string)
- Modify: `src/main.zig` (at the top of `main_loop`, apply the palette and init the menu theme selector together from prefs; persist on menu start)
- Modify: `src/piece_preview.zig` (pointer alias `const Theme = &renderer.Theme;`; render the mark gallery per theme for visual verification)
- Test: `src/tui/renderer.zig`, `src/persistence/config.zig`, `src/tui/menu.zig` (inline)

**Approach:**
- Define `Palette` with the current `Theme` field names plus a `selection_bg` field (replacing the hardcoded `{40,30,70}` in `menu.zig`/`history.zig`). Convert `Theme` from a const namespace to `pub var Theme: Palette = palette(.classic)`. Direct `renderer.Theme.bg` uses are unchanged; the four container-scope aliases (`menu.zig`, `history.zig`, `viewer.zig`, `piece_preview.zig`) change from `const Theme = renderer.Theme;` to `const Theme = &renderer.Theme;` (pointer — auto-derefs at each `Theme.bg` use and reads live). `ThemeId { classic, wood, green, blue }` with `label`/`fromString`/`toString`; `palette(id)` returns each preset; Classic = today's exact RGBs.
- Wood/Green/Blue presets per the origin descriptions; exact RGBs are tunable at implementation but must satisfy R10: all five mark colors (cursor, legal, check, endangered, hint-best) pairwise-distinct and distinct from both square colors, verified by the gallery.
- `menu.zig`: a Theme field **initialized from `prefs.theme` on menu entry** (mirroring the existing `selected_elo`/`selected_color` init); left/right cycles `ThemeId`, assigning `renderer.Theme = renderer.palette(id)` (the menu repaints in the new palette → live preview) and recording the selection; `GameConfig.theme_id`.
- `config.zig`: `Preferences.theme: []const u8 = "classic"` (+ JSON field), parsed to `ThemeId`; unknown/missing → classic.
- `main.zig`: at the top of `main_loop`, where `menu_state` is recreated each iteration (alongside the existing `selected_elo`/`selected_color` init), set **both** `menu_state.selected_theme` and `renderer.Theme = renderer.palette(ThemeId.fromString(prefs.theme))` — applying the palette per menu-entry rather than once before the loop keeps the global palette in sync with the freshly-initialized selector even after a preview-then-resume (a previewed-but-unstarted theme is re-normalized on the next menu entry); persist the chosen theme on new-game start.

**Patterns to follow:** the existing `Theme` field set; `menu.zig` selector fields + `fakeKey` test; `config.zig` `default_color` string handling and its round-trip test; the existing `piece_preview.zig` gallery.

**Test scenarios:**
- Covers R12: `palette(.classic)` equals today's `Theme` values (assert a few anchor fields: `bg == {15,15,35}`, `dark_square == {55,40,100}`, `light_square == {105,70,150}`).
- Covers R10: for every preset, the five mark colors are pairwise-distinct and differ from `dark_square`/`light_square` (pure RGB inequality).
- Covers AE10: `config` round-trips `theme = "wood"`; `ThemeId.fromString`/`toString` round-trip; unknown string → `classic`.
- Edge: `menu` theme field cycles classic→wood→green→blue→classic on right and reverses on left; `getConfig()` returns the selected `theme_id`.
- Covers AE10 (focus default): on menu entry with a persisted `theme = "wood"`, the menu's theme selector field equals Wood, not the Classic struct default.
- Visual (gallery): `zig build preview` shows each theme's board + all five marks legibly.

**Verification:** `zig build test` green; selecting Wood and relaunching renders the board, pieces, marks, and chrome in the Wood palette with Wood still selected, while a fresh config shows Classic; the gallery confirms every theme keeps the marks legible and distinct.

---

### U8. N-key menu responsiveness

**Goal:** Pressing N (when no game is in progress, or after confirming a leave) shows the menu on that keypress rather than after the next one.

**Requirements:** R16

**Dependencies:** None (complements U6, which handles the in-progress confirm-prompt render)

**Files:**
- Modify: `src/main.zig` (reorder the menu loop to paint before the blocking `nextEvent()`)
- Test: behavioral verification (main loop)

**Approach:**
- In the `while (!menu_done)` loop, move the `win.clear(); menu_state.render(win); vx.render(...)` block to the top of the loop body, before `loop.nextEvent()`, so the menu paints on entry (and after returning from the history sub-screen) rather than only after the next key.

**Patterns to follow:** the `runGameHistory`/`runGameViewer` loops, which already render before their blocking `nextEvent()`.

**Test scenarios:**
- `Test expectation: none — main()-loop render ordering, not unit-testable.` The in-progress face of R16 (prompt renders on the first N) is unit-covered by U6 (AE9); this unit's no-game face is verified behaviorally.

**Verification:** from a game, pressing N → (after the U6 confirm) the menu appears immediately; launching into the menu shows it without needing a keypress.

---

## System-Wide Impact

- **Interaction graph:** the opponent-move seam (`engineWork`/`dispatchEngineMove`) gains the handicap (U2); the analysis seam (`analysisWork`/`dispatchAnalysis`) gains the full-strength toggle (U3); the game-loop key dispatch gains `.undo` and the quit/leave modals (U4, U6); the menu and history loops gain a theme selector / delete confirm (U6, U7).
- **Error propagation:** the hint Skill-Level raise must restore on every exit path (`defer`); a failed save rewrite/delete on undo is logged and non-fatal (matches existing `autoSave` behavior).
- **State lifecycle risks:** `board_count`/`move_count` must stay in lockstep through undo (they do — `undoMove` decrements both); the auto-save high-water mark (`prev_move_count`) must be reset on undo to avoid a stale save (U5); a zero-move undo must delete the file so crash recovery doesn't resurrect it.
- **API surface parity:** `Engine.init`'s third parameter changes from `elo` to `skill` — both call sites in `main.zig` plus any test must move together. The save filename keeps its `elo` field (fed by `skillToElo`), so `storage.zig` and existing saves stay compatible.
- **Integration coverage:** engine strength, handicap-in-play, full-strength hints, and the menu N-paint are exercised by running the game (engine subprocess), consistent with the repo's convention that Stockfish behavior is integration-verified.
- **Unchanged invariants:** the chess core (`src/chess/`), PGN format, opening book, viewer, and the highlight-mark rendering model are untouched; Classic theme reproduces today's exact look.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Beginner handicap rate is empirical and can't be set at plan time | Commit the mechanism now; calibrate the rate at implementation against the installed Stockfish (deferred, see below) |
| Hint Skill-Level raise leaks (engine left at full strength) if a send fails | `defer` the restore; the dispatch invariant prevents overlap with the opponent search |
| Theme `var` swap mid-render could tear if rendering were concurrent | Rendering is main-thread only; the engine threads never render — safe |
| `Engine.init` signature change misses a call site | `lsp references` before editing; both `main.zig` sites + tests updated together |
| Config migration drops a returning user's difficulty | `eloToSkill(default_elo)` maps the legacy value; missing → low default with no crash |

---

## Phased Delivery

### Phase A — Difficulty & Hints (U1 → U2 → U3)
Land first: they share the one Stockfish instance and most directly serve the learning goal. U2 and U3 both depend on U1's Skill model.

### Phase B — Take-back (U4 → U5)
U5 depends on U4's `undoMovePair`.

### Phase C — Confirmations (U6)
Independent; mirrors the resign modal across three sites.

### Phase D — Themes & Polish (U7, U8)
Independent finishers. U8 complements U6 for the full R16 behavior.

---

## Open Questions

### Resolved During Planning

- *How to reach sub-1320 beginner play?* — `Skill Level` (not `UCI_Elo`) for opponent strength + an app-side move handicap for the floor (U1/U2).
- *Shared engine vs second engine for full-strength hints?* — Shared engine, momentary Skill-Level raise with `defer` restore; safe because hints never overlap the opponent search (U3).
- *N-key lag root cause?* — Menu loop blocks before its first paint; reorder to paint first (U8); the in-progress prompt renders via U6.
- *Theme runtime selection without rewriting every render call?* — Promote `Theme` to a module-level `var Palette` (U7).
- *Difficulty persistence migration?* — Map legacy `default_elo` via `eloToSkill`; keep the save filename's `elo` field via `skillToElo` (U1).

### Deferred to Implementation

- **[R13] Beginner move-handicap rate** — the exact injection rate (and which low Skill Levels apply it) that yields genuine-beginner play, calibrated against the installed Stockfish. Execution-time, needs real games.
- **Exact Wood/Green/Blue RGB values** — tunable during implementation, gated on the gallery's legibility check and the pairwise-distinct test (U7).
- **`skillToElo` table values for mid-range Skill Levels** — the CCRL anchors (0≈1320, 19≈3191, 20=max) are fixed; intermediate values are filled and sanity-checked at implementation.

---

## Sources & References

- **Origin document:** [docs/brainstorms/play-experience-improvements-requirements.md](docs/brainstorms/play-experience-improvements-requirements.md)
- Related code: `src/engine.zig`, `src/tui/game.zig`, `src/tui/input.zig`, `src/tui/menu.zig`, `src/tui/renderer.zig`, `src/tui/history.zig`, `src/persistence/config.zig`, `src/persistence/storage.zig`, `src/main.zig`, `src/piece_preview.zig`
- External: Stockfish strength behavior — issue #4717, commit a08b8d4 (see origin Dependencies/Assumptions)
