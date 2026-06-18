---
date: 2026-06-17
type: feat
status: active
origin: docs/brainstorms/chessboard-highlight-redesign-requirements.md
---

# feat: Pieces-first board highlight redesign

## Summary

Replace the board renderer's single-winner, full-cell background-fill highlights with a per-position **mark** language: the base square color and piece sprite always render, and status is overlaid as edge bars (in the cell's inner free columns), corner marks, and a center dot — so a piece is never covered and several signals can read on one square at once. Add a static highlight gallery to the `zig build preview` tool so every state and key combination can be judged by eye at real play geometry.

The change is concentrated in `src/tui/renderer.zig` (the mark model, selection logic, and drawing) and `src/piece_preview.zig` (the gallery). It builds directly on the `renderBoardCore` structure introduced in the recent renderer refactor.

---

## Problem Frame

Today `squareHighlight` (`src/tui/renderer.zig:55`) returns one `?Color` by priority, and `renderBoardCore` (`src/tui/renderer.zig:134`) paints the **whole cell** with `squareHighlight orelse base`. Two consequences (see origin Problem Frame):

1. The highlight color sits behind/around the centered piece sprite, competing with and partially obscuring it — worst for check, whose full-red fill hides the king the player needs to see.
2. Only one signal shows per square; when a square is several things at once (a legal move that is also endangered and the engine's suggested target), the player sees only the top-priority one.

This plan moves status off the cell background and onto sub-cell marks at distinct positions, so the piece stays clear and co-occurring signals compose. "Less invasive" is an aesthetic judgment, so the verification vehicle is a runnable visual gallery, not appearance assertions.

---

## Requirements Traceability

| Origin item | Where addressed |
|---|---|
| R1 (marks not full-cell; piece never covered) | U1 (model), U2 (overlay on base+sprite) |
| R11 (corner/center compose; border family is the exception) | U1 (mark independence + border resolution), U2 (rendering), U3 (gallery) |
| R12 (border precedence: check > flash > selected > capture > engine) | U1 (`resolveBorder`) |
| R17 (distinguishable by shape/pattern, not color alone) | U2 (pattern per border style), U3 (gallery confirms) |
| R2–R10 (per-state treatments) | U1 (state → mark mapping), U2 (drawing), U3 (gallery) |
| R13–R16 (gallery: all states, combos, light/dark, with/without piece, legend) | U3 |
| AE1–AE4 | U1 test scenarios (data level) + U3 gallery (visual) |
| A1 Player / A2 Developer | Player reads the live board (U2); Developer uses the gallery (U3) |
| Outstanding Q #1 (small-cell degradation) | Resolved — see Key Technical Decisions #5 (9×4 is the enforced minimum) |
| Outstanding Q #2 (exact glyphs/cells) | Deferred to implementation — see Outstanding Questions |

---

## High-Level Technical Design

*This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

**Cell geometry (fixed 9 wide × 4 tall).** The centered 5-wide sprite occupies columns 2–6, leaving columns 0–1 and 7–8 free across all four rows. Marks are placed so they never share a cell with each other or the sprite:

```
        col 0    col 1     cols 2-6     col 7    col 8
row 0  [corner] [ bar ]  [           ] [ bar ]  [corner]   <- TL corner, TR corner
row 1  [      ] [ bar ]  [  sprite   ] [ bar ]  [      ]
row 2  [      ] [ bar ]  [  cols 2-6 ] [ bar ]  [      ]
row 3  [corner] [ bar ]  [           ] [ bar ]  [corner]   <- BL corner, BR corner
                                        center mark: middle of cols 2-6 (empty squares only)
```

- **Border family** → inner columns (col 1 and col 7), all rows. Single-winner (they share this position).
- **Corner marks** → the four outer corner cells: cursor = TL + BR, endangered = BL, best-move = TR. These compose (distinct cells).
- **Center mark** → middle of the sprite area, only when the square is empty (no sprite to cover).

**Mark model (directional sketch).** A pure value computed per square, plus a pure drawer shared by the board and the gallery:

```
BorderStyle = enum { selected, capture, check, flash, engine }  // each maps to a Theme color + a fill pattern
Marks = struct {
    border:     ?BorderStyle = null,  // winner of border precedence; drawn in cols 1 & 7
    cursor:     bool = false,         // corner brackets at TL + BR
    endangered: bool = false,         // bottom-left corner
    best_move:  bool = false,         // top-right corner
    center:     bool = false,         // center dot (empty legal target only)
}

squareMarks(game, sq_idx) -> Marks   // game state  -> marks   (U1, testable)
drawMarks(win, cx, ry, opts, marks)  // marks -> cells drawn   (U2, pure, reused by gallery)
```

`squareMarks` resolves `border` by precedence (check > flash > selected > capture > engine), sets `center` when `legal_targets[sq]` and the square is empty, sets `border = .capture` when `legal_targets[sq]` and the square is occupied, and sets the corner flags from cursor/hint state. `drawMarks` renders base+sprite-independent overlays into the fixed cell positions above. Pattern (continuous vs broken vs faint vs pulse) distinguishes border styles beyond color alone (R17); exact graphemes/patterns are settled in the gallery.

---

## Implementation Units

### U1. Mark model and selection logic

**Goal:** Introduce the `Marks` value type and a pure `squareMarks(game, sq_idx)` that maps game state to marks, implementing the border precedence and the legal-target empty/capture split. Old rendering path stays intact (this unit only adds; U2 switches over).

**Requirements:** R1, R11, R12, R2–R10 (state→mark mapping); AE1–AE4 (data level).

**Dependencies:** none.

**Files:**
- `src/tui/renderer.zig` — add `pub const BorderStyle`, `pub const Marks`, `pub fn squareMarks`, and a pure `resolveBorder` helper; add `test` blocks.

**Approach:**
- Mirror the existing precedence-chain style of `squareHighlight` (`src/tui/renderer.zig:55-94`) and reuse the same game accessors (`flash_square`/`flash_timer`, `engine_last_move`, `cursor`, `selected`, `legal_targets`, `isKingInCheck`/`activeKingSquare`, `hints_enabled`, `hint_best_move`, `hint_endangered`, `board.squares`).
- **New** border precedence order (R12), which differs from today's `squareHighlight` order — cursor and legal targets and hints leave the border family: `resolveBorder` returns the highest of check → flash → selected → capture → engine, or null.
- Capture vs empty split (AE1): `legal_targets[sq]` with `board.squares[sq] != .empty` → contributes `capture` to the border resolution; `legal_targets[sq]` with an empty square → `center = true`.
- Corner flags are independent of `border` and of each other (R11 composition): `cursor` from `game.cursor`; `endangered`/`best_move` gated on `hints_enabled`.
- Keep `resolveBorder` parameterized on plain flags (not the whole `Game`) so the precedence is unit-testable without constructing full game state where practical.
- Make `Marks` and `BorderStyle` `pub` — the gallery (U3) constructs `Marks` directly.

**Patterns to follow:** existing `squareHighlight` chain and `Game` field access in `src/tui/renderer.zig`.

**Test scenarios** (inline `test` blocks in `src/tui/renderer.zig`; run by `zig build test`):
- Covers AE1. Empty legal target → `center == true`, `border == null`. Occupied (enemy) legal target → `border == .capture`, `center == false`.
- Covers AE2. Hints enabled; square is a legal capture + endangered + best-move target → `border == .capture` **and** `endangered == true` **and** `best_move == true` (corners compose with the border).
- Covers AE3. Square is the in-check active king **and** the selected square → `border == .check` (check outranks selected).
- Covers AE4. Selected (not cursor) square → `border == .selected`, `cursor == false`. Cursor (not selected) square → `cursor == true`, `border == null`.
- Border precedence ordering (full chain check > flash > selected > capture > engine): selected + engine → `.selected`; flash (timer > 0) + selected → `.flash`; check + flash → `.check`; capture + engine → `.capture`; selected + capture (data model allows both set) → `.selected`; engine-last-move alone → `.engine`.
- Hints disabled: `endangered`/`best_move` stay false even when `hint_endangered[sq]` / `hint_best_move` would match.
- Flash gating: `flash_square == sq` but `flash_timer == 0` → flash does not win the border.
- Empty quiet square with nothing active → all `Marks` fields default (no marks).

**Verification:** `zig build test` passes including the new cases; `zig build` still compiles (old render path untouched).

### U2. Render marks over base + sprite

**Goal:** Switch `renderBoardCore` from full-cell highlight fill to base-color fill + sprite + mark overlay, via a pure `drawMarks` reused by the gallery. Remove the old `squareHighlight` whole-cell tint.

**Requirements:** R1, R2–R10, R17 (pattern distinction in drawing).

**Dependencies:** U1.

**Files:**
- `src/tui/renderer.zig` — add `pub fn drawMarks(win, cx, ry, opts, marks)`; modify `renderBoardCore` (`:111-181`); delete `squareHighlight` (`:55-94`) **and the five obsolete `squareHighlight` test blocks (`:414-483`)** once unused — their single-winner precedence assertions (e.g. cursor > endangered) no longer hold under composing marks and are superseded by U1's `squareMarks` tests.

**Approach:**
- In `renderBoardCore`'s per-cell body: set `bg = base` (drop `squareHighlight orelse base`); draw the sprite/glyph as today; then, when `highlight` is non-null, call `drawMarks(win, cx, ry, opts, squareMarks(g, sq_idx))`.
- `drawMarks` writes only the mark cells over the already-drawn base/sprite: border style → both inner columns (col 1, col 7) using its Theme color and fill pattern; corner flags → the four outer corner cells; center → the center cell. It must not touch the sprite columns (2–6) except the center cell on empty squares.
- Distinguish border styles by **pattern as well as color** (R17): e.g., continuous (selected) = all rows filled; broken/dashed (capture) = alternating rows; faint (engine) = dim; bold (check) = full-intensity; pulse (flash) = timer-driven. Exact patterns/graphemes are settled in the gallery (Outstanding Questions); this unit establishes the placement and the color mapping to existing `Theme.highlight_*` values.
- Marks render only at the fixed 9×4 cell (see Key Technical Decisions #5). `drawMarks` derives the col 1 / col 7 / corner positions from `opts`, so it is valid only at width 9 — gate the overlay on the 9×4 geometry (e.g. `cell_w >= 9`), not merely on `use_sprites` (which is also true at 6×4). This is a load-bearing invariant: the only `highlight != null` caller is the live board at 9×4 (the viewer passes `null`), so no degraded path is reachable, and a hypothetical future sub-9-wide highlight caller then draws nothing rather than misplacing col-7 writes.
- The static viewer (`src/tui/viewer.zig:88`) passes `null` highlight and is unaffected — no marks there.

**Patterns to follow:** the existing `renderBoardCore` cell loop and `win.writeCell` usage (`src/tui/renderer.zig:127-167`); `sprites.stamp` for the piece.

**Test expectation:** none -- visual rendering. Verified via the gallery (U3) and by playing a game; appearance is judged by eye per the origin scope boundary. The data that drives it is covered by U1's tests.

**Verification:** `zig build` compiles with `squareHighlight` removed and no dead-reference warnings; `zig build test` compiles and passes once the obsolete `squareHighlight` test blocks are removed; `zig build run` shows the live board with marks (piece visible, base color through, check as red bars not a fill).

### U3. Highlight gallery in the preview tool

**Goal:** Extend `src/piece_preview.zig` with a static highlight gallery that renders every state and the key combinations using the **same** `drawMarks` routine, at 9×4 geometry, with a legend. This *adds* the gallery rather than removing the existing piece-sprite preview — the gallery's with-piece samples build on the sprite display, which is retained (origin R13 says "extend").

**Requirements:** R13, R14, R15, R16, R17 (visual confirmation); A2 (developer audience).

**Dependencies:** U2 (uses `pub drawMarks` + `Marks`).

**Files:**
- `src/piece_preview.zig` — build the gallery; change `cell_h` from 5 to 4 to match play geometry (`:47`).
- `AGENTS.md` — update the `zig build preview` line to note it now also shows the highlight gallery (the piece-sprite preview is retained).

**Approach:**
- Reuse the existing layout scaffolding (`fillRect`, `sprites.stamp`, label drawing in `:99-129`) but drive each sample square through `renderer.drawMarks` with a hand-constructed `Marks` value, so the gallery shows the real rendering and cannot drift from the board (origin success criterion).
- Lay out one labeled sample per state R2–R10 (selected, cursor, legal-empty, capture, check, endangered, best-move, engine-last-move, capture-flash), plus the key combinations (R14): a square that is legal-capture + endangered + best-move; a square that is selected + under the cursor; and the maximal stack — cursor + legal-capture + endangered + best-move at once (all four corners + both bar columns), the truest test that the corners compose without homogenizing into an undifferentiated border.
- Render each sample on **both** a light and a dark base square, and **both** with a piece sprite present and on an empty square (R15), so legibility and non-invasiveness are visible in every case.
- Add a legend (R16) mapping each mark to its meaning. Keep `q: quit` behavior.
- Mind vertical extent (see Risks): 12 samples × 4 variants at 9×4, plus the retained sprite preview and legend, overruns a standard 24-row terminal. Pack each sample's four variants into a 2×2 sub-block (two 9-wide sub-columns × two 4-row sub-rows = one 18×8 block); four blocks per row × three rows fit an 80×24 terminal with room for labels and the legend. If a taller single-column layout is preferred instead, document a minimum preview height.

**Patterns to follow:** the current `piece_preview.zig` render loop, `fillRect`, `sprites.stamp`, and label rendering (`:99-143`); base colors from `Theme`.

**Test expectation:** none -- the gallery is itself the visual verification artifact; correctness is judged by eye via `zig build preview`.

**Verification:** `zig build preview` launches and shows all R2–R10 states, all three key combinations (including the maximal four-corner stack), on light and dark squares, with and without a piece, plus a legend — every mark legible and no mark covering a piece.

---

## Key Technical Decisions

- **Mark model replaces the single-winner whole-cell tint** (origin R1, R11). `squareHighlight -> ?Color` (whole-cell) becomes `squareMarks -> Marks` (per-position), overlaid on an always-rendered base + sprite. This is the core behavior change; the board no longer tints whole cells.
- **Border family is single-winner; corners and center compose** (origin R12, R11). The border styles share the inner-column position and resolve by precedence check > flash > selected > capture > engine; corner/center marks occupy distinct cells and always co-exist.
- **Legal targets split by occupancy** (origin R4/R5, AE1). Empty target → center dot; occupied target → capture border bars, keeping the enemy piece visible. Occupancy comes from `board.squares`.
- **One pure `drawMarks`, shared by the board and the gallery** (origin Success Criteria). The gallery renders through the same drawing code, so what a developer judges is exactly what ships — no reimplementation drift.
- **Cell size is fixed at 9×4, the enforced minimum playable window** (resolves origin Outstanding Q #1, per user confirmation). The mark layout targets exactly this geometry. There is no degraded sub-cell-mark fallback — below the minimum window the existing resize message already shows, and marks render only on the live board (the static viewer passes no highlight). Outstanding Q #1's "muted tint / minimum size" options are therefore moot.
- **Reuse existing `Theme.highlight_*` colors; distinguish co-located marks by pattern too** (origin R17, palette-unchanged boundary). Only placement and pattern change, not the palette.
- **Unit-test the mark-selection logic; keep appearance gallery-verified.** This extends the origin's intent rather than overriding its boundary: the origin excludes *visual appearance* assertions ("verification is the visual gallery only"), while U1's tests assert boolean fields on a pure `Marks` data struct (precedence winner, capture/empty split, corner composition) — not rendering output — a logically distinct category. Confirmed with the user during planning. Visual appearance stays judged by eye in the gallery (U2/U3).
- **Exact graphemes and fill patterns deferred to gallery iteration** (origin Outstanding Q #2). The plan fixes placement and color mapping; the precise characters and row patterns for each border style are chosen against a real truecolor terminal in the gallery.

---

## System-Wide Impact

- `src/tui/renderer.zig` — core change: mark model, selection, drawing; `squareHighlight` removed.
- `src/piece_preview.zig` — extended with the highlight gallery; the existing piece-sprite preview is retained (sprites also appear under marks via R15).
- **Live board appearance changes for players** (A1) — intended: pieces-first, check as red bars, co-occurring hints. **The static game viewer is unaffected** (`src/tui/viewer.zig` passes `null` highlight).
- `AGENTS.md` — one-line description of `zig build preview` updated.
- `Theme` palette, board orientation/flip, sprite art, and rank/file labels are untouched (origin scope boundary).

---

## Scope Boundaries

Carried from the origin document:
- "Dim the unreachable squares" during selection (the inversion idea) — **deferred**.
- Interactive toggling, snapshot/golden-image infrastructure, or scenario configuration in the preview tool — **out**; the gallery is a static render.
- No new highlight states or hint types beyond R2–R10.
- Theme color palette unchanged.
- Board orientation/flip, sprite art, and rank/file labels unchanged.

Refined from the origin's "verification is the visual gallery only" boundary:
- Visual **appearance** is verified only by eye in the gallery — no pixel/appearance assertions. This plan extends that intent (it does not override it) with one logically distinct addition: automated unit tests of the **non-visual mark-selection logic** in U1 (precedence, capture/empty split, corner composition), which assert data-struct fields, not rendering output. Confirmed with the user.

### Deferred to Follow-Up Work
- None. The work is self-contained in the two files above plus the one-line AGENTS.md touch.

---

## Risks & Mitigation

- **Pattern legibility in a 1-column × 4-row strip.** Continuous vs broken vs faint vs bold-vs-pulse must read distinctly in a narrow strip. Mitigation: the gallery (U3) shows all border styles side by side on light and dark squares; patterns/graphemes are tuned there before shipping (origin success criterion #4).
- **Adjacency ambiguity.** A selected bar (col 1) sits one cell from a cursor corner (col 0); `highlight_selected` and `highlight_cursor` are near-identical magentas. Mitigation: R17 shape distinction (continuous bar vs corner bracket) plus the gallery's selected+cursor combination view (R14) — flagged in the round-2 review and carried here.
- **Behavior change to the live board.** Removing the whole-cell tint visibly changes play. Intended per the origin; no mitigation needed beyond the gallery sign-off.
- **Gallery vertical extent.** At 9×4 cells with R15's four variants per sample, plus the retained sprite preview and legend, a one-column-per-variant layout needs ~40+ rows and clips the lower states (check, endangered, best-move, engine, flash, and the combinations) on a standard 80×24 terminal — directly undermining the success criterion that a developer can see *every* state. Mitigation: U3 packs each sample's four variants into a 2×2 sub-block so the whole gallery fits 80×24; if a taller layout is chosen instead, document the minimum preview height in `AGENTS.md` alongside the `zig build preview` note.

---

## Verification

- `zig build` — compiles after each unit; clean after `squareHighlight` removal in U2.
- `zig build test` — U1's mark-selection tests pass (the AE1–AE4 and precedence cases above); the five obsolete `squareHighlight` test blocks are removed in U2, so the suite count shifts (those drop, U1's cases are added) — the suite stays green at the new count, not the old 216.
- `zig build preview` — the gallery renders every state R2–R10, all three key combinations, on light and dark base squares, with and without a piece, plus a legend; verify by eye that no mark covers a piece and that border styles are mutually distinguishable.
- `zig build run` — play a few moves: confirm selection bars, legal-move dots/capture bars, check red bars (king visible), and that hints compose on a shared square.

---

## Outstanding Questions (deferred to implementation)

- Exact terminal graphemes/cells for each mark (edge bars, corner brackets, center dot) — quadrant blocks vs box-drawing vs colored background cells — chosen in the gallery against a real truecolor terminal (origin Outstanding Q #2).
- The precise per-style fill pattern and intensity: continuous (selected), broken/dashed (capture), bold (check), faint/fading (engine), pulse (flash) — tuned visually in the gallery so each is distinct (R17).
- En-passant capture: the captured pawn's target square is empty, so by the occupancy rule a legal en-passant move shows the empty-target center dot, not capture bars — no distinct capture indicator. This matches today's behavior (the old highlight showed every legal target identically) and is not a regression; confirm in the gallery that it reads acceptably, and treat a dedicated en-passant indicator as out of scope unless the gallery shows it's confusing.

---

## Dependencies / Sequencing

U1 → U2 → U3 (strict order). U1 adds the model and tests with the old render path intact; U2 switches the renderer over and removes `squareHighlight`; U3 builds the gallery on U2's public `drawMarks`/`Marks`. No external dependencies; no new packages (`vaxis`, `known_folders` unchanged).
