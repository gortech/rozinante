---
date: 2026-06-17
topic: chessboard-highlight-redesign
---

# Chessboard Highlight Redesign

## Summary

Replace the board's full-cell background-fill highlights with a pieces-first visual language: status shows as outlines, corners, and a single center dot so a piece is never covered, and several signals can read on one square at once. Add a static visual gallery to `src/piece_preview.zig` so the new treatments can be judged by eye via `zig build preview`.

---

## Problem Frame

Rozinante's board highlights every relevant square by flooding the whole cell with a background color — selected square, legal moves, check, endangered-piece hints, best-move hints, the engine's last move, and capture flashes all paint the entire cell. At normal play size (cells ~9 wide × 4 tall, with the piece sprite in the center) this is visually invasive: the color block competes with, and partially obscures, the piece itself, and the board reads as a field of colored tiles rather than as pieces.

Two structural limits make it worse. First, the highlight is applied as the cell's background, so it sits directly behind/around the piece you're trying to read — most painfully for check, where the full-red fill obscures the very king you need to see to escape. Second, only one highlight can show per square: the renderer resolves a single winning color by priority, so when a square is several things at once (a legal move that is also endangered and also the engine's suggested target), the player only ever sees the top-priority one.

Because "less invasive" is an aesthetic judgment, it can't be verified by an assertion or in headless CI (the TUI also can't launch without a real terminal), so there is currently no fast way to see and iterate on highlight appearance short of playing a full game.

---

## Actors

- A1. Player: plays the game in the terminal; reads the board to identify pieces, see their legal moves, and act on hints. The highlight language is optimized for this person.
- A2. Developer: runs `zig build preview` to inspect and iterate on highlight appearance; the audience for the gallery.

---

## Requirements

**Highlight language — cross-cutting**

- R1. Highlights render as marks at a square's edges, corners, or center — never as a full-cell background fill. The (chess-correct) base square color shows through, and a piece occupying the square is never visually covered. Because the centered sprite fills the full height of the default 4-row cell, border-position marks live in the inner free side column (leaving the outer corner cells for corner marks) — not a full top/bottom perimeter.
- R11. Corner and center marks occupy positions distinct from the border family — within each free side strip, border bars take the inner column while corner marks own the outer corner cells — so several marks co-exist on one square by construction with no priority engine (e.g., a center legal-move mark plus a bottom-left endangered corner plus a top-right best-move corner). Collisions within the border family resolve by precedence (R12).
- R12. The border family — R2 selected, R5 capture, R6 check, R10 capture flash, and R9's faint, fading edge bars — all occupy the same inner-side-column position and cannot compose, so they resolve by a fixed single-winner precedence (highest wins): check (R6) > capture flash (R10) > selected (R2) > capture bars (R5) > engine-last-move (R9). Corner ownership is likewise fixed so hints never collide with the cursor (see Key Decisions).
- R17. Marks that can share a cell position must be distinguishable by shape or pattern, not color alone (e.g., selected vs capture; endangered vs best-move), so the language stays legible under low-contrast terminals or color-vision deficiency. Exact shapes settle in the gallery.

**Highlight language — per-state treatment**

Each row has a stable R-ID for back-reference. "Position" is where in the cell the mark sits, not the exact glyph (glyph choice is deferred to planning).

| R-ID | State | Treatment | Position |
|---|---|---|---|
| R2 | Selected square | continuous edge bars | inner side column (col 1 / col 7) |
| R3 | Cursor (roaming focus) | corner brackets | top-left + bottom-right corners (the two hints don't use) |
| R4 | Legal move → empty target | center mark (a single cell may not register — set a minimum size in the gallery) | center |
| R5 | Legal move → capture (occupied) | broken/dashed edge bars | inner side column (col 1 / col 7); piece stays visible |
| R6 | Check (active king) | bold red edge bars | inner side column (col 1 / col 7); king stays visible |
| R7 | Endangered piece (hint) | colored corner | bottom-left corner |
| R8 | Best move from+to (hint) | colored corner | top-right corner |
| R9 | Engine's last move from+to | faint, fading edge bars | inner side column (col 1 / col 7); lowest border precedence |
| R10 | Capture flash (transient FX) | brief edge-bar pulse | inner side column (col 1 / col 7) |

**Preview gallery**

- R13. Extend `src/piece_preview.zig` with a static highlight gallery, runnable via `zig build preview`, that displays every state in R2–R10.
- R14. The gallery shows the key combinations, at minimum: one square that is simultaneously a legal move + endangered + best-move target; and one square that is both selected and under the cursor.
- R15. The gallery shows marks on both a light and a dark base square, and both with a piece present and on an empty square, and renders at the default play cell size (9 wide × 4 tall, matching the renderer's `RenderOptions`) — not `piece_preview.zig`'s current larger cells — so legibility and non-invasiveness are judged at the geometry players actually see.
- R16. The gallery includes a legend mapping each mark to its meaning.

---

## Acceptance Examples

- AE1. **Covers R4, R5.** Given a piece is selected with a legal move to an empty square and a legal capture of an enemy piece, when the board renders, the empty target shows a center dot and the capture square shows broken edge bars with the enemy piece fully visible.
- AE2. **Covers R5, R7, R8, R11.** Given hints are enabled and one square is at once a legal move, an endangered piece, and the best-move target — the endangered piece means the square is occupied, so the legal move is a capture — when the board renders, that square shows the capture bars (enemy piece visible), a bottom-left endangered corner, and a top-right best-move corner together.
- AE3. **Covers R6, R12.** Given the active king is in check on a square that is also the selected square, when the board renders, the square shows the bold red check bars (check takes precedence over the selected bars) and the king remains visible.
- AE4. **Covers R2, R3.** Given a piece is selected and the cursor is on a different square, when the board renders, the selected square shows continuous edge bars and the cursor square shows corner brackets — visibly distinct from each other.

---

## Success Criteria

- At default play size the board reads pieces-first: a player can identify every piece at a glance, highlights inform without dominating, and check is clearly marked while the king stays visible.
- A developer can see and judge every highlight state and the key combinations via `zig build preview`, without launching a full game.
- Handoff: `ce-plan` can implement each requirement without inventing visual behavior — every state has a defined treatment, cell position, composition rule, and a gallery target to match.
- Marks are deliberately subtle (pieces-first); the gallery is where each signal — especially the safety-critical check and endangered hints — is confirmed noticeable enough at play size. If a mark proves too easy to miss there, its size is revisited in the gallery rather than reverting to a full-cell fill.

---

## Scope Boundaries

- "Dim the unreachable squares" during piece selection (the de-emphasis / inversion idea) — deferred; it layers cleanly on top of this language later.
- Automated or headless highlight assertions — out of scope; verification is the visual gallery only.
- Interactive toggling, snapshot/golden-image infrastructure, or scenario configuration in the preview tool — out; the gallery is a static render.
- No new highlight states or hint types beyond those listed.
- The Theme color palette is unchanged — this moves where/how marks are drawn, not the colors.
- Board orientation/flip behavior, sprite art, and rank/file labels are unchanged.

---

## Key Decisions

- Selected = continuous edge bars, cursor = corner brackets: the user specified an outline for the selected square (realized as continuous side-column bars), so the roaming cursor takes a distinct shape so the two never read alike.
- Corner budget is fixed: endangered owns the bottom-left corner, best-move owns the top-right, and the cursor uses the remaining top-left/bottom-right corners — so the cursor can co-exist with both hints on the same square without collision.
- Captures = broken/dashed edge bars (not a full ring or a center dot): the side-column position keeps the targeted enemy piece visible, and the broken pattern distinguishes a capture target from the selected square's continuous bars without relying on color.
- Check = bold red edge bars in the side columns (not a fill or a full box): at the default 4-row cell a full perimeter would overdraw the king, so the side columns keep the king visible while staying urgent.
- Composition is real for corner/center marks only (distinct positions, stack with no priority engine); the border family shares the side-column position and resolves by the fixed precedence in R12. This refines the earlier "replaces single-winner priority" framing — single-winner still applies within the border family.
- Border marks use the side columns, not full boxes: at the default 9×4 cell the 4-row sprite fills the full height, so a full perimeter would cover the piece; border-position marks are confined to the left/right edge columns the centered 5-wide sprite never occupies.
- Marks stay subtle even for safety-critical signals (no hard salience floor): the pieces-first goal takes priority, so "unmissable" was softened to "clearly marked." The gallery validates that check and endangered remain noticeable; sizes are tuned there if needed.
- Reuse the existing Theme highlight colors: the scope is mark placement, not palette.
- Highlight verification is visual via the preview gallery: "less invasive" is an aesthetic judgment only a human can make, so a runnable gallery is the right (and only) verification vehicle.

---

## Dependencies / Assumptions

- At the default 9×4 cell the centered 5-wide sprite occupies columns 2–6, leaving columns 0–1 and 7–8 free across all four rows. Border-position marks (R2/R5/R6/R9/R10) take the inner free column on each side (col 1 / col 7); corner marks (R3 cursor, R7 endangered, R8 best-move) own the outer corner cells (col 0 / col 8); the center mark (R4) sits in the sprite-free center. So border bars and corner marks never share a cell, and the piece (cols 2–6) is never covered.
- "Capture" = a legal move whose target square is occupied by an opponent piece; this is already derivable from board state.
- The capture flash and engine-last-move fade are animated; the static gallery shows a representative single frame, not the animation.
- Best-move and engine-last-move each cover two squares (from + to), matching current behavior.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R1–R12][Technical] How should highlights degrade in the small non-sprite cell mode (cells < 5×4), where sub-cell marks may not fit? Candidate: a muted edge/outline tint fallback, or a minimum supported size. Decide during implementation.
- [Affects R2, R3, R4, R5, R6, R7, R8, R9, R10][Technical] Exact terminal glyphs/cells for the edge bars (continuous, broken/dashed, bold red, faint/fading, pulse), corner brackets, corner marks, and center mark (e.g., quadrant blocks vs box-drawing vs colored cells) — choose during implementation against how they render in a truecolor terminal, iterating in the gallery.
