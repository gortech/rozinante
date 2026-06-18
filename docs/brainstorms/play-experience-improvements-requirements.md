---
date: 2026-06-18
topic: play-experience-improvements
---

# Play-Experience Improvements

## Summary

A batch of six play-experience improvements to Rozinante: an unlimited take-back during active play, confirmation prompts before discarding or deleting a game, selectable full-palette themes, a genuinely beginner-level low difficulty, and fixes for the N-key menu lag and for best-move hints that don't reflect the true best move.

---

## Problem Frame

Rozinante is a chess learning game, but several rough edges undercut that goal today:

- **No way to take a move back.** A learner who blunders has no recovery; the game marches on. Experimentation — the core of learning — is impossible mid-game.
- **Destructive actions are silent.** Quitting mid-game, returning to the menu, and deleting a saved game all happen instantly with no guard, so a slip of a key throws away a game in progress or a stored one.
- **The "lowest" difficulty isn't low.** The menu offers Elo down to 200, but modern Stockfish floors `UCI_Elo` at roughly 1320 — so a beginner who picks the weakest setting still faces a ~1320 opponent and gets crushed. The slider's bottom half is a lie.
- **Best-move hints aren't the best move.** Hints are produced by the same engine instance that is deliberately weakened to the chosen difficulty, so the "best move" shown is a weak engine's pick and visibly differs from a third-party analysis app — exactly when a learner most needs a trustworthy answer.
- **The board has one fixed look**, and pressing N to return to the menu appears to do nothing until the next keypress.

The net effect: the learning aids and difficulty controls don't behave the way a learner expects, and ordinary actions feel unsafe or unresponsive.

---

## Requirements

**Take-back (undo)**
- R1. A dedicated Undo key (**U**) is available on the player's turn during an in-progress game, shown in the on-screen keybind hints as `U Undo`. Pressing it reverts the most recent move-pair — the engine's reply and the player's preceding move — returning control to the player's turn.
- R2. Undo is repeatable: pressing it again walks back another move-pair, down to the player's first move of the game. It never rewinds past that point — when the player is Black, the engine's opening move is never undone — so undo always lands on the player's turn for both colors.
- R3. Undo rewinds all recorded game state in lockstep — the move list / PGN record and the side-to-move — and immediately rewrites the on-disk save to the post-undo move list, resetting the auto-save high-water mark. A game saved, resumed, or crash-recovered after an undo therefore contains only the moves that remain on the board, never the taken-back ones. If undo empties the move list (back to the initial position), the on-disk save is deleted and resume state cleared — the zero-move auto-save guard would otherwise leave the stale full game on disk to resume.
- R4. After an undo, the learning aids recompute for the restored position: endangered-piece highlighting and the best-move hint reflect the current board, not the pre-undo one.
- R5. Undo is offered only on the player's turn in an in-progress game. It is inert while the engine is thinking and after the game has ended (reviewing a finished game is deferred to the Analysis feature).

**Confirmation prompts**
- R6. Quitting (quit key / Ctrl-C) while a game is *in progress* prompts for confirmation before exiting (Y/Enter confirms, N/Esc cancels — matching the existing resign prompt); declining returns to the game unchanged. "In progress" means an active game before checkmate, stalemate, or resignation; a finished-but-on-screen game quits without a prompt.
- R7. Leaving an in-progress game to return to the menu / start a new game (the N key) prompts for confirmation before abandoning it, using the same Y/Enter-confirms / N/Esc-cancels convention; declining returns to the game unchanged. Confirming a leave requires explicit Y/Enter, so the N keypress that opens the prompt never also dismisses it.
- R8. Deleting a saved game from the history list prompts for confirmation before removal (same convention); the prompt states the deletion is permanent. Declining keeps the game.
- R9. Quitting from the menu when no game is in progress exits immediately, with no prompt.

**Themes**
- R10. The player can choose from a set of visual themes — **Classic** (default), **Wood**, **Green**, and **Blue**. Each theme is a full-palette preset that swaps all colors together: board squares, piece colors, highlight/hint marks, and text/UI chrome. Every preset must keep all five highlight marks (cursor, legal-move, check, endangered, best-move hint) legible against its board squares and distinct from one another, so the learning aids never wash out.
  - Classic — the current scheme: deep indigo background, purple squares, lavender / near-black pieces.
  - Wood — warm walnut: brown & tan squares, cream & espresso pieces, dark warm background.
  - Green (tournament) — muted green & buff squares, off-white & charcoal pieces.
  - Blue (lichess-style) — steel-blue & pale-blue squares, white & navy pieces.
- R11. The selected theme is chosen from the menu — a list or cycle of the presets with a live color/board preview, focus defaulting to the persisted theme — and persisted in preferences, so it carries across sessions.
- R12. The current color scheme ships as one of the presets (the default), so existing users see no change unless they pick another theme.

**Difficulty**
- R13. Difficulty is set by a single **Skill Level (0–20)** dial — no raw Elo and no exposed depth knob — with the approximate **engine (CCRL) Elo** shown beside it for information (Skill 0 ≈ 1320, Skill 19 ≈ 3191, Skill 20 = full strength), explicitly labelled **not human-comparable** (CCRL ~1320 already outplays a 1320-rated human). The engine derives its search caps (depth and move-time) from the chosen Skill Level — the existing `eloToDepth` / `eloToMovetime` ladders rekeyed onto Skill — and sets Stockfish's `Skill Level` directly rather than `UCI_Elo`, so the low end isn't re-floored at 1320; depth and time are internal, not a second control. Skill + depth bottom out at ~club strength, so the lowest Skill Levels additionally apply an **app-side move handicap** (an occasional random / sub-optimal legal move) — the lever that actually reaches genuine beginner play; its rate is calibrated in planning.
- R14. The difficulty setting governs only the opponent's playing strength; it must not weaken the analysis used for learning aids.

**Hints**
- R15. Best-move hints reflect the true best move from a full-strength search, independent of the selected difficulty.

**Input responsiveness**
- R16. Pressing N takes effect on that keypress — the resulting transition (the confirmation prompt while a game is in progress, otherwise the menu) renders immediately, without waiting for a subsequent key.

---

## Acceptance Examples

- AE1. **Covers R1, R2.** Given a game in progress on the player's turn after several moves, when the player presses Undo twice, the board returns two of the player's moves back — on the player's turn — with the engine's intervening replies removed.
- AE2. **Covers R3.** Given the player has undone two move-pairs and then saves the game, the saved PGN contains only the moves still on the board, not the taken-back ones.
- AE3. **Covers R4.** Given hints are enabled and a piece was marked endangered before an undo, when the player undoes back to a position where that piece is no longer attacked, the endangered highlight is gone.
- AE4. **Covers R5.** Given the game has ended in checkmate, when the player presses Undo, nothing happens.
- AE5. **Covers R6, R7.** Given a game in progress, when the player presses Quit (or N for the menu), a confirmation prompt appears; choosing "no" returns to the game unchanged.
- AE6. **Covers R9.** Given the menu with no game in progress, when the player presses Quit, the app exits with no prompt.
- AE7. **Covers R8.** Given the history list, when the player deletes a saved game and confirms, it is removed; declining leaves it in place.
- AE8. **Covers R13, R14, R15.** Given the lowest difficulty (Skill Level 0 — with its internally-derived depth/time floor and the beginner move-handicap applied), the opponent plays clearly beginner-level moves, while a requested best-move hint still shows a strong move.
- AE9. **Covers R16.** Given a game in progress, when the player presses N once, the confirmation prompt appears immediately, with no second keypress needed to render it.
- AE10. **Covers R10–R12.** Given the menu, when the player selects the Wood theme and relaunches the app, the board renders with the Wood palette (squares, pieces, highlight marks, and chrome all recolored together) and Wood stays selected, while a brand-new user still sees Classic.

---

## Success Criteria

- A genuine beginner can hold their own at the lowest difficulty, and opponent strength visibly scales as the Skill Level rises.
- Best-move hints match a strong reference engine's top move — they no longer diverge because of difficulty limiting.
- No in-progress game is discarded and no saved game is deleted without an explicit confirmation.
- A player can freely take moves back to explore alternatives during play without corrupting the saved record.
- A selected theme repaints the whole board and UI and persists across sessions; existing users see Classic unchanged by default.
- Downstream handoff: `ce-plan` can implement each R-ID without inventing user-facing behavior; the low-end move-handicap *rate* is the only researched unknown.

---

## Scope Boundaries

- Word-named difficulty tiers (Beginner / Club / Master) — rejected; difficulty is a single numeric Skill Level (0–20) with the approximate (engine/CCRL) Elo shown for reference.
- A separate user-facing search-depth knob — rejected; depth is derived internally from the Skill Level, not a second control the player sets.
- Per-component theming (board-only or pieces-only) — full-palette presets only.
- Redo / forward-step after an undo — not included.
- Undoing or stepping through a *finished* game — deferred to the future Analysis feature.
- In-game theme switching — themes are selected in the menu, not changed mid-game.
- A high-contrast / mono accessibility theme — considered, not in the initial preset set.

---

## Key Decisions

- **Difficulty = single Skill Level dial (depth derived) + low-end handicap, Elo shown for info:** the raw Elo slider is dropped because `UCI_Elo` and `Skill Level` are the *same* internal lever, both floored at ~1320 (Skill 0 ≈ 1320 CCRL; commit a08b8d4 / issue #4717). The player sets one Skill Level (0–20); the engine derives its depth/time caps from it (the existing `eloToDepth` / `eloToMovetime` ladders rekeyed onto Skill) and sets `Skill Level` directly rather than `UCI_Elo`, showing the approximate CCRL Elo for reference — depth and time are internal, not a second exposed knob. Skill + depth bottom out at ~club strength, so the lowest Skill Levels also apply an app-side move handicap — the lever that actually reaches genuine beginner play.
- **Hints always run at full strength:** difficulty must never weaken the learning aid. The hint search must neutralize *every* strength limiter actually in effect for the opponent — `UCI_LimitStrength`, `Skill Level`, and any depth/movetime cap — or run on a separate unrestricted engine, restoring them before the opponent's next move. Toggling `UCI_LimitStrength` alone is insufficient if the low end is weakened via `Skill Level`.
- **Full-palette theme presets:** one preset swaps the entire palette (squares, pieces, marks, chrome) for cohesion. Note: `Theme` is currently compile-time `pub const` fields referenced statically across `renderer.zig` / `main.zig`, so runtime selection means threading a runtime-chosen theme value (or a comptime switch over const sets) through the render calls — not an in-place struct swap; scope R10–R12 accordingly. Initial set: Classic (default), Wood, Green, Blue.
- **Unlimited take-back to the player's turn:** best fits a learning game and always lands on the player's move; one-shot or single-ply undo were considered and dropped.
- **Confirm on any in-progress-game discard:** quit and N→menu both prompt mid-game, as does deleting a save; quitting from the menu with no game does not prompt. The quit and N→menu prompts guard against an accidental or disruptive quit, not data loss — per-move auto-save plus crash-recovery resume already persist and restore an in-progress game, so their copy must not claim the game will be lost. The delete-saved-game prompt (R8) is the exception: deletion is permanent and unrecoverable, so its copy must say so.
- **Suggested build order:** the difficulty floor (R13) and full-strength hints (R15) land first — they share one engine and most directly serve the learning goal — then undo (R1–R5) and confirmations (R6–R9); themes (R10–R12) and the N-key fix (R16) are independent finishers.

---

## Dependencies / Assumptions

- The weak low end cannot come from `UCI_Elo` or `Skill Level`: per the Stockfish maintainers these are the *same* internal lever, both floored at ~1320 (Skill 0 ≈ 1320 CCRL; commit a08b8d4 / issue #4717). `getMove()` already maxes search-limiting at the bottom (`eloToDepth(200)=1`, `eloToMovetime(200)=25ms`), and even depth-1 / Skill-0 is ~club strength on the (human-hot) CCRL scale. Reaching a true beginner therefore needs app-side handicapping — e.g. injecting an occasional random or sub-optimal legal move — not a Stockfish option.
- Theme selection adds a new persisted preference field in `config.json`, alongside the existing `stockfish_path` / `default_color` / `default_time_control` (and the Skill Level field that replaces `default_elo` — see below).
- Difficulty persistence shifts from `default_elo` to a single Skill Level (0–20) in `config.json`; depth is derived from Skill (not stored) and the displayed Elo from the CCRL table (not stored). On upgrade an existing `default_elo` is mapped to the nearest Skill Level via the CCRL table (or difficulty resets with a note), and `_elo`-tagged saved games resume by mapping their stored Elo to a Skill Level.
- The difficulty menu must replace the current Elo slider (`menu.zig` `elo_min` / `elo_max` / `elo_step`, `GameConfig.elo`) with a single Skill Level (0–20) selector that shows the derived CCRL Elo beside it.
- Undo does not need to replay the move list: `Game` already stores per-ply board snapshots in `board_history` and provides a single-ply `undoMove()` that restores from them. The move-pair undo (R1/R2) extends that helper, and also rewinds `move_history` / `move_count` (used for PGN).
- The N-key lag is render ordering in the menu loop, not a main-loop flush: on `.new_game` the code does `continue :main_loop`, and the menu loop calls `loop.nextEvent()` (blocking) *before* painting the menu, so the menu first appears only after the next key. The fix renders the menu once before the blocking event read.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R13][Needs research] Calibration of the low-end move-handicap — the random / sub-optimal-move injection rate (plus search caps) that yields genuine beginner play — since `UCI_Elo` and `Skill Level` both floor at ~1320 and cannot reach a true novice on their own. Calibrate against the installed Stockfish.
- [Affects R15][Technical] Whether the hint search resets all active limiters (`UCI_LimitStrength` + `Skill Level` + depth/movetime) on the shared engine with an exception-safe restore (`defer`), or spawns a second unrestricted engine — toggling `UCI_LimitStrength` alone is insufficient.
- [Affects R16][Technical] The precise render/flush timing in the main loop that causes the N-key lag.
