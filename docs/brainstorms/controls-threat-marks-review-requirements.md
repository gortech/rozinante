---
date: 2026-06-20
topic: controls-threat-marks-review
---

# Controls, Threat Marks & Review Improvements

## Summary

Three independent TUI improvements: (1) replace the scattered, plain-text key hints with one persistent zellij-style keybind bar pinned to the bottom of every screen, with each key as a tagged, color-separated chip; (2) make the endangered-piece aid say *how* bad a threat is — orange when a piece is attacked but the exchange doesn't lose material, red when a static-exchange evaluation says the opponent wins material — and add a new blue pin mark for absolutely-pinned pieces of both colors; (3) let the review screen flip the board and show move-quality for the engine's moves, not just the player's.

---

## Problem Frame

Rozinante is a chess *learning* game, and three of its signals are currently muddier than they need to be for a beginner.

**Controls.** Key hints exist as four independent, ad-hoc footers — one in the menu (`src/tui/menu.zig`), two stacked lines at the bottom of the in-game info panel (`src/tui/renderer.zig`), one in the review screen (`src/tui/viewer.zig`), and one in the game-history screen (`src/tui/history.zig`). Keys are bare words (`Enter Select`, `R Resign`) separated only by spaces, with no visual chrome marking where a key ends and its label begins. The in-game hint row's vertical position shifts with panel content, the game-over screen swaps in a *different* footer, and modal prompts ("Resign? Y/N") appear mid-panel — so the controls are never in a predictable place, and a learner has to re-find them.

**Threat marks.** The endangered-piece aid flags a friendly piece with a single orange corner whenever it is attacked at all (`isSquareAttacked`, a boolean). It cannot distinguish "attacked but safely defended" from "you are about to lose this piece," and it has no concept of pins — the tactic beginners fall for most and never see coming. A boolean attacked-or-not aid under-teaches exactly where a learner needs the most help: a queen attacked by a pawn but "defended" by a rook reads identically to a well-guarded pawn.

**Review screen.** The replay viewer renders the board in one fixed orientation regardless of which color the player was, and its move-quality line appears only on the player's own plies — so a player reviewing as Black reads the board upside-down relative to play, and gets no quality read on the engine's replies that shaped the game.

---

## Actors

- A1. Player: plays and reviews games in the terminal; reads the keybind bar to know what they can do, the threat marks to judge danger, and the review screen to learn from a finished game. All three improvements optimize for this person.
- A2. Developer: runs `zig build preview` to judge the threat marks (the two-level endangered colors and the new pin mark) by eye; the audience for the gallery and legend additions.

---

## Requirements

**Keybind bar**

- R1. A single persistent keybind bar is pinned to the bottom of the terminal spanning its full width, present on every screen — menu, active game, review, and game history; on the active-game and review screens it sits below both the board and the info panel.
- R2. Each key renders as a discrete chip — a tagged key glyph (e.g. `Esc`, `↑↓←→`) with its own background color, visually separated from its neighbours (zellij-style), each paired with a short action label — so keys read as distinct badges, not a run of words.
- R2a. Chip background colors are theme-invariant (one palette shared across all themes, like the existing mark colors), and each chip background meets a minimum contrast against every theme's background and against the neighbour-separator, so chips stay legible on all four presets. A test analogous to the existing palette-distinctness test covers chip-vs-theme-background contrast. (Exact pill-vs-bracket style and spacing remain deferred — see Outstanding Questions.)
- R3. The bar's contents are context-sensitive: it shows exactly the keys valid in the current state (menu navigation, normal play, engine thinking, promotion, a confirm prompt, game-over, history browsing, history delete-confirm, review) and updates as the state changes. In engine-thinking only the resign, flip, quit, and menu chips are shown; the cursor, select, undo, and hint chips are suppressed (those inputs are inert).
- R4. Confirm prompts (resign / quit / leave-to-menu / delete-save in game, and delete in history) present their choices as key chips in the bar (`Y Yes`, `N No`). The existing Enter→Yes and Esc→No bindings remain active but are not shown as separate chips. The prompt's *question text* stays in the info panel (or the history list); the bar carries only the keys.
- R5. Transient game *status* — whose turn it is, "Check!", "Engine thinking…", and the promotion piece picker — stays in the info panel. The bar is keys only, never game state.
- R6. The bar's reserved height reduces the area available to the board and panel; every screen's terminal-too-small threshold accounts for the reserved row(s) so the bar never overlaps content — the shared `renderResizeMessage` helper (used by the game and review screens), the menu's own inline size check, and a new check on the history screen (which has none today).
- R6a. When the valid-key chip set exceeds the bar width, the bar drops chips from a fixed lowest-priority tail (priority order, highest kept first: cursor/move > Enter/select > Esc/back > Q quit > N menu > the rest), and the dropped keys remain active. The minimum supported terminal width is bumped so that in the widest required state (normal play with hints on) no chip in the priority head is dropped.

**Threat marks — endangered escalation**

- R7. The endangered aid marks a friendly **non-king** piece (the side to move's) at two severities: orange when the piece is attacked but the opponent does not strictly win material by capturing it (SEE ≤ 0), red when the capture sequence strictly wins material for the opponent (SEE > 0). An even trade (SEE = 0) is orange, not red. The king is excluded from the aid — check remains the king's danger signal (R9).
- R8a. The orange/red verdict is decided by static-exchange evaluation (SEE) — simulate the capture sequence using cheapest-attacker-first ordering and piece values — not by a raw attacker-vs-defender count.
- R8b. SEE is x-ray-aware: a sliding attacker or defender behind a captured front piece is revealed and counted (it falls out of re-scanning the position after each capture).
- R8c. SEE is pin-aware: a defender pinned to its own king may recapture only along the pin ray, and the king may not recapture into check. The shared pin detector therefore returns the **pin direction** per pinned piece, not just a boolean — the pin hint (R10/R11) ignores the direction; SEE consults it to allow ray-aligned recaptures.
- R9. Endangered marks remain friendly-only (and never mark the king) and keep their existing bottom-left corner position; only the color escalates orange → red. The boolean field becomes a three-state level (none / orange / red).

**Threat marks — pin hint**

- R10. A pin hint marks any absolutely-pinned piece — a piece pinned against its own king by an enemy sliding piece — with a blue mark in the top-left corner of the square.
- R11. The pin hint marks pinned pieces of *both* colors with the same blue mark: a friendly pinned piece ("you are pinned — defend or unpin it") and an enemy pinned piece ("you have pinned it — exploit it"). It is the only aid that marks both sides.
- R12. Endangered (orange/red) and pin (blue) are togglable learning aids shown only when hints are enabled, recomputed for the current position on the same refresh as the existing aids.

**Threat marks — color and gallery**

- R13. The two new mark colors — the blue pin and the escalation red for endangered — are theme-invariant (shared across all themes like the other marks). Each new color is pairwise-distinct, by a stated perceptual delta, from every other mark color (cursor, legal, check, flash, endangered orange, best-move, and the other new color) on every theme preset; the endangered red in particular must read distinctly from the existing check red and flash red. The perceptual-delta requirement applies only to pairs involving a new color — existing-vs-existing pairs keep the current bare-inequality check, so no shipped color is retuned. The existing palette-distinctness test is extended to add the two new colors and flash to the compared set under this rule.
- R14. The preview gallery (`zig build preview`) and its legend gain the pin mark and the two-level endangered colors, including representative combinations — at minimum a square that is simultaneously pinned (blue top-left) and endangered (red bottom-left).

**Review screen**

- R15. The review screen flips board orientation on `F`, matching the active game's flip key; the chosen orientation persists while stepping through the game.
- R15a. On entry, the review screen defaults the board to the player's own perspective (`flipped = (player_color == .black)`); `F` toggles from that default, and within a session the chosen orientation persists across leaving and re-entering review. Orientation does not persist across program restarts.
- R16. The move-quality line ("Move ✓ good / ✗ blunder") is shown for engine plies as well as player plies, derived from each ply's already-computed centipawn loss using the same tier thresholds.

---

## Acceptance Examples

- AE1. **Covers R7, R8a.** Given hints on, a White queen on d4 defended only by a rook on d1 and attacked by a Black pawn on c5: the queen shows the **red** endangered corner — SEE: pawn takes queen, rook takes pawn → the opponent nets ≈ +8. (A raw count shows only orange: one attacker equals one defender. This is the under-warning the aid must fix.)
- AE2. **Covers R7, R8a.** Given hints on, a White pawn on e4 defended by a pawn and attacked by two Black rooks doubled on the e-file: the pawn shows the **orange** corner, not red — SEE: the first capture loses a rook for a pawn, so the opponent wins no material despite outnumbering the defender 2-to-1.
- AE3. **Covers R8c.** Given an attacked friendly piece whose only defender is pinned to its own king, when SEE runs, the pinned piece is not counted as a recapturer, so the attacked piece rates red.
- AE4. **Covers R10, R11.** Given a Black bishop pinning a White knight to the White king, with hints on: the White knight shows a blue top-left mark; symmetrically, when a White piece pins a Black piece to the Black king, that Black piece shows the same blue mark.
- AE5. **Covers R3, R4.** Given the player presses `R` to resign, when the confirm prompt appears, the bottom bar shows `Y Yes` and `N No` chips while the info panel shows the "Resign?" question.
- AE6. **Covers R15.** Given the review screen, when the player presses `F`, the board flips orientation and stays flipped while stepping forward and backward.
- AE7. **Covers R16.** Given an analyzed game, when the player steps to a position reached by an *engine* move, the "Move" quality line is shown for that engine move.
- AE8. **Covers R7.** Given hints on, a White knight on e5 defended by a pawn and attacked by a Black knight (an even trade — knight takes knight, pawn recaptures, net 0): the knight shows the **orange** corner, not red.
- AE9. **Covers R8c.** Given White king e1 and White rook e2 pinned by a Black rook on the open e-file: for SEE the pinned rook is not frozen on that file — it may still recapture *along* the pin ray (up the e-file, including capturing the pinning rook). So an exchange on an e-file square the rook defends along the file counts the rook as a legal recapturer; only an off-ray recapture is forbidden (contrast AE3, where the lone defender would have to leave its pin ray).
- AE10. **Covers R1, R5.** Given the menu and the review screens, the keybind bar is present at the bottom in the same location, and no info panel or screen body duplicates a key chip the bar already shows.
- AE11. **Covers R6.** Given a terminal at the minimum supported size, when any screen renders, the board/content does not overlap the keybind bar.
- AE12. **Covers R14.** Given `zig build preview`, the gallery shows a square that is simultaneously pinned (blue top-left) and endangered-red (bottom-left), plus a legend entry for each new color.
- AE13. **Covers R8b.** Given hints on, a White bishop on d4 defended once by a pawn, attacked by a Black bishop on g7 with a Black queen behind it on h8 (same a1-h8 diagonal): the bishop shows **red**. A single up-front attacker snapshot counts only the bishop (net 0 → orange), but x-ray-aware SEE reveals the queen once the front bishop captures and vacates g7, so the opponent nets material → red.

---

## Success Criteria

- A player always finds the controls in the same place on every screen, and can tell a key from its label at a glance.
- A learner can distinguish "this piece is genuinely losing material" (red) from "this piece is attacked but fine" (orange), and can see at a glance which pieces — theirs or the engine's — are pinned.
- Reviewing as either color, the player can orient the board to their own perspective and read move quality for both sides' moves.
- The two-level endangered colors and the pin mark are judgeable via `zig build preview` without launching a game (A2).
- Handoff: `ce-plan` can implement every item without inventing behavior — each mark has a defined color, corner, trigger, and gallery target; SEE's semantics are pinned by the worked acceptance examples, which double as test positions; the bar's placement, chip styling, context-switching, and height reservation are specified.

---

## Scope Boundaries

- No new keybindings except the review-screen flip (R15); the bar re-presents existing keys, it does not add commands.
- SEE is used only for the endangered orange/red verdict. It does **not** change move generation — `legalMoves` stays brute-force (make-move + king-in-check), per the project's stated clarity-over-optimization ethos.
- The pin hint covers absolute pins only (pinned to the own king). Relative pins, skewers, forks, and discovered attacks are not detected.
- Skewer / discovered-attack detection and post-game tactical *annotations* are out of scope. The pin detector is designed strictly for its two in-scope consumers (SEE pin-awareness and the pin hint); any future-feature reuse is a side effect, not a design constraint on its API.
- The theme palette is otherwise unchanged except for **two new mark colors** — the blue pin and the escalation red for endangered; it does not retune existing colors.
- The promotion piece picker stays an in-panel widget; it is not moved into the bar.
- The engine move-quality line reuses the existing good/meh/bad tiers and glyphs; no new rating vocabulary.
- The three areas (keybind bar, threat marks, review screen) are independent and independently shippable: planning may sequence or ship them as separate units. In particular the shallow review-screen changes (R15/R16) and the keybind bar are not gated on the deeper SEE + pin work (R7-R14) and should not wait on its fidelity questions.

---

## Key Decisions

- **Global bottom bar over an in-panel fixed row.** A persistent full-width bar at the bottom of every screen (the user's choice over pinning a constant panel row) gives one predictable location across menu, game, and review, and matches the zellij status-bar model the user referenced.
- **Red means "you lose material" (SEE), not "more attackers" (count).** The count rule errs both ways; its worst failure is *under*-warning — a high-value piece attacked by a low-value one reads as calm orange (equal bodies) when it is the textbook beginner blunder (AE1). SEE makes red mean the thing the aid exists to teach.
- **x-ray + pin-aware SEE, with the static absolute-pin detector as the shared baseline.** A new absolute-pin detector in `src/chess/` serves *both* the SEE pin-awareness (R8c) and the pin hint (R10/R11) — one primitive, two consumers — but it returns the **pin direction** per pinned piece, not merely a boolean: the hint needs only presence, while SEE needs the ray to allow a pinned piece's legal along-the-ray recapture. x-ray awareness falls out of re-scanning the position after each capture (the outward-sliding attacker scan reveals the piece behind). Whether SEE also recomputes pins *mid-exchange* (dynamic) on top of the static baseline is a deferred fidelity question (below).
- **Pin = blue, top-left corner, both colors.** Top-left is free in the live `drawMarks`: the cursor uses edge *midpoints*, not corners (the highlight-redesign doc's "corner brackets" evolved into mid-edge segments in shipped code). The corner budget becomes: top-left = pin, top-right = best-move, bottom-left = endangered, bottom-right = free. The blue pin corner composes over the border outline's top-left glyph exactly as endangered already composes at bottom-left (Layer 3 hint corners over Layer 1 border). Marking both colors is intentional per the user's spec.
- **Bar carries keys; panel keeps status and the promotion picker.** Keeps the bar a stable, scannable control legend rather than a mixed status line.

---

## Dependencies / Assumptions

- Builds on the shipped highlight-redesign mark language (`src/tui/renderer.zig` `drawMarks`: layered corners/edges, `Marks` struct, `squareMarks`). Verified: the four corners and edge-midpoint cursor are as described above, so the top-left pin corner does not collide with any existing mark.
- No piece-value table exists in the chess core today (verified — only `rules.isInsufficientMaterial` counts piece *types* without valuing them). SEE adds one.
- `chess.isSquareAttacked` returns a bool only (verified, `src/chess/movegen.zig`). SEE adds a value-ordered cheapest-attacker scan and the absolute-pin detector; there is no existing pin detection (movegen proves legality by brute force).
- The review screen currently hardcodes `flipped = false` (verified, `src/tui/viewer.zig`), and `analysis` computes a per-ply `cpl` for *every* ply with `tier` left null on engine plies (verified, `src/analysis.zig`). R16 derives the engine line's tier from the existing `cpl` via the same thresholds — no new engine work.
- The bottom bar reserves 1-2 terminal rows. The board is 49 rows tall at the default cell size; the minimum supported terminal size and the resize-message threshold may need a small bump to fit the bar.
- SEE for a per-square overlay is the right tool (fast, pure, every-move); the Stockfish engine is not queried per piece for this — its role stays the post-game analysis pass.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R8c][Technical] Exact SEE pin fidelity: the **static** absolute-pin baseline (pins computed once on the current position) is in scope and shared with the pin hint. Whether to also recompute pins *mid-exchange* (dynamic — catching pins that form or dissolve as pieces leave during the capture sequence) is an effort-vs-correctness call best made in planning with the AE positions as a test bench. Dynamic adds roughly the same logic again plus a much larger test matrix, for a rare edge case most engines deliberately skip; the recommendation is to ship static and upgrade only if a flagged position proves visibly wrong.
- [Affects R8a, R8c][Technical] Piece values for SEE (standard P1 N3 B3 R5 Q9, king effectively infinite) and how an exchange involving the king terminates.
- [Affects R2][Technical] Exact chip rendering in a truecolor terminal — bracket style vs background-fill pill, per-key vs per-category colors, and spacing — iterated against how it looks, in the spirit of the existing preview workflow.
- [Affects R1, R6][Technical] Whether the bar lives as a child window owned by the top-level layout (so menu/game/viewer all reserve the same rows) or is drawn per-screen; and the exact reserved height (one row vs two).
- [Affects R14][Technical] Gallery layout for the added marks within the existing `~104×64` preview budget.
