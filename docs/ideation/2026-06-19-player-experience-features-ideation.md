---
date: 2026-06-19
topic: player-experience-features
focus: a feature that adds good value/experience to the player
mode: repo-grounded
---

# Ideation: Player Value/Experience Features

## Grounding Context

**Codebase Context.** Rozinante is a terminal (TUI) chess *learning* game in Zig; the player plays Stockfish (UCI subprocess) at a chosen Skill Level with togglable learning aids. Branch `feat/better_ux` at time of ideation.

Already built (not re-proposed): Skill-Level difficulty dial + app-side beginner handicap, color pick; mid-game aids (endangered-piece highlight, full-strength best-move hint, opening identification); cursor/legal-move/check marks; full rules **except threefold repetition**; move-pair take-back; PGN save/browse/replay step-through; selectable themes; quit/leave/delete confirmation prompts; per-move auto-save + crash-recovery resume.

Roadmap / known gaps that ideation targeted: threefold-repetition detection (deferred); **Live Hints + Chess Clock** (roadmap "Next" — a `default_time_control` config field exists with no UI/logic); **Replay Mode with Analysis** (roadmap "then" — stepping exists, per-move eval/accuracy does not); no eval/who's-winning display; no feedback on the player's *own* move quality; no graduated hints; no tactics/puzzles/drills; no cross-game progress/stats; no redo-after-undo; no FEN/PGN import; no coordinate/notation training.

Feasibility anchors: `Game` already stores per-ply `board_history` snapshots + `move_history` → cheap to hash positions (repetition/redo), iterate for post-game analysis, and re-instantiate positions for drills. Stockfish UCI yields `score cp`/`mate` + PV per position (MultiPV available); the best-move hint already demonstrates the "momentarily run full-strength, restore via `defer`" pattern. PGN supports NAGs/comments (not currently written).

> External prior-art (lichess move classification & eval bar, chess.com Game Review accuracy %, chesstempo/listudy SRS, graduated hints) is from orchestrator domain knowledge — the web-research agent was unavailable this run (model 404). Verify exact centipawn thresholds / accuracy formulas before relying on specific numbers.

## Topic Axes

- A. In-game guidance — live aids while a game is active
- B. Post-game review — learning from a finished game
- C. Practice & progression — skill-building beyond one game
- D. Game setup & modes — how a game starts and what variety exists
- E. Rules & game flow — rules completeness and in-game flow smoothness

## Ranked Ideas

### 1. Post-Game Analysis & Review
**Description:** At game end, run an async (`io.concurrent`) Stockfish eval pass over the per-ply `board_history`, classify each player move by centipawn-loss vs the engine's best (inaccuracy/mistake/blunder), and write NAGs + comments into the PGN. The replay viewer gains jump-to-key-moments (largest eval swings) and a game-end accuracy card (accuracy %, worst 3 moves). Cross-game accuracy/progress trend then derives nearly free.
**Axis:** B (keystone — clusters 5, 6, and most of B consume it)
**Basis:** `direct:` roadmap "Replay Mode with Analysis"; "PGN supports comments/NAGs but they are not currently written"; "Stockfish UCI yields `info … score cp <n>` … cheap" over snapshots that already exist. Converged in 6/6 frames.
**Rationale:** One pipeline turns blunder drills, accuracy %, key-moment navigation, and progress trend from separate builds into additive consumers — the highest downstream yield of any single investment. PGN annotation also makes games portable to standard GUIs.
**Downsides:** the largest single build; sync-on-game-end vs background-async decision; analysis latency on long games.
**Confidence:** 90%
**Complexity:** Medium-High
**Status:** Unexplored

### 2. Instant Move-Quality Feedback
**Description:** The instant the player commits a move, flash a non-blocking quality tag (`Best / Inaccuracy / Mistake / !! Blunder` + cp delta) on the status line, reusing the hint's "momentary full-strength eval, restore via `defer`" pattern. Design fork to resolve in brainstorm: a continuous eval bar, and/or a pre-commit "blunder fence" that asks for confirmation on catastrophic moves.
**Axis:** A
**Basis:** `direct:` gap "No feedback on the player's OWN move quality during or after play (endangered highlight only shows opponent threats — not 'you just hung your queen')". Converged in 5/6 frames.
**Rationale:** Closes the action→consequence loop while the position is still in working memory — the single most-requested training signal in chess apps, and the core missing connection for a learning game.
**Downsides:** +1 engine eval per player move (latency); risk of becoming a crutch; threshold calibration; choosing the variant (flash vs eval bar vs fence).
**Confidence:** 85%
**Complexity:** Medium
**Status:** Unexplored

### 3. Graduated Hints
**Description:** Replace the single full-move hint with a tiered reveal on repeated `H` within a move: (1) nudge / which piece, (2) destination area, (3) full move (today's behavior). Reset per move; track hint depth per game as an independence signal surfaced in the end-of-game summary.
**Axis:** A
**Basis:** `direct:` gap "No graduated/progressive hints (the hint shows the full best move directly)" + `external:` graduated nudges (lichess/chess.com Coach). Converged in 6/6 frames — universal.
**Rationale:** Converts the current answer-key into actual teaching — the learner does part of the calculation before each reveal. Highest learning-per-line-of-code: reuses highlight infra + a small key-state machine.
**Downsides:** defining the tier-1 threat phrase (from PV/eval swing) is the only non-trivial piece; decide whether hint counts feed an accuracy score.
**Confidence:** 88%
**Complexity:** Low
**Status:** Unexplored

### 4. Personal Blunder Drill
**Description:** Harvest blunder/mistake positions (FEN + best move) from idea #1's pipeline into a local corpus in the persistence dir. A Drill mode (main menu) re-presents them with the live keyboard flow ("find the better move"), grades the response against the stored engine move, and re-queues near-misses on a spaced-repetition schedule. The corpus self-populates from every game played.
**Axis:** C
**Basis:** `direct:` gap "No tactics/puzzles, no standalone practice/drills"; storage already available. `external:` lichess "Learn from your mistakes", chesstempo/listudy SRS trainers. Converged in 5/6 frames. Depends on #1.
**Rationale:** Transfer is highest when the material is the learner's own mistakes in positions they actually reached; the corpus compounds the more they play, with zero external puzzle curation.
**Downsides:** requires #1 first; SRS scheduling and multi-move-line validation can scope-creep.
**Confidence:** 80%
**Complexity:** Medium-High
**Status:** Unexplored

### 5. Threefold Repetition + Redo (shared position-hash chain)
**Description:** Add an 8-byte position hash per ply (board + side-to-move + castling rights + en-passant square) alongside `board_history`. A linear scan over the hash array yields threefold-repetition claim/auto-draw (the one named rules gap); the same chain enables redo-after-undo (push popped board/move onto a redo stack, cleared on any new move) and serves as the blunder-corpus dedup key.
**Axis:** E
**Basis:** `direct:` gaps "Full chess rules EXCEPT threefold repetition" and "No redo-after-undo (deferred)"; architecture: per-ply snapshots already exist so "the data is largely there". Converged in 3/6 frames.
**Rationale:** Fixes a genuine rules-correctness omission (games can currently loop forever in drawn positions) *and* an expected UX affordance, with one ~1.6 KB/game structure — the highest-yield rules investment.
**Downsides:** the hash must correctly include castling/ep/side-to-move; draw-claim UX (auto-accept vs claimable prompt vs annotate-only) is an open decision.
**Confidence:** 85%
**Complexity:** Low-Medium
**Status:** Unexplored

### 6. Chess Clock / Timed Mode
**Description:** Activate the existing `default_time_control` config stub as a functional clock: selectable time controls (rapid 10+0, blitz 5+3, untimed) at game setup; the player's clock counts down on their turn and freezes on the engine's; the engine consumes a simulated per-move time; flag (clock to 0) = loss-on-time. A small sidebar widget shows both clocks; disabling reproduces current untimed behavior.
**Axis:** D
**Basis:** `direct:` roadmap "Live Hints + Chess Clock — Next; a `default_time_control` config field already exists but there is no clock UI/logic". 1/6 frames but explicitly roadmap-aligned.
**Rationale:** Most learners are preparing for timed online/club play; practicing only with unlimited time builds a non-transferable habit, and the config hook signals the feature was already intended.
**Downsides:** lower direct *learning* value than the other survivors; engine think-time simulation + event-loop timer integration are the real work.
**Confidence:** 78%
**Complexity:** Medium
**Status:** Unexplored

## Rejection Summary

| # | Idea | Reason Rejected |
|---|------|-----------------|
| 1 | Live eval bar; pre-commit blunder fence | Folded into #2 as design variants |
| 2 | Key-moment nav; game-end accuracy card; guess-the-move; cross-game accuracy sparkline | Consumers of #1's pipeline — folded into #1 (and #4) |
| 3 | Interactive opening trainer / book-exit alert / teaching-line opponent | Distinct opening-study surface; better as a brainstorm variant — defer |
| 4 | Adaptive difficulty (win-rate or CPL based) | Opaque auto-behavior layered over the just-shipped Skill dial; brainstorm variant |
| 5 | Branching variation tree ("never lose a line") | High-complexity undo→rose-tree refactor; the leaner redo in #5 covers near-term need — defer |
| 6 | Free analysis sandbox + FEN entry; endgame/position drill | New study mode; lower learning-per-effort — defer (revisit with FEN import) |
| 7 | Blindfold / notation-only mode | Niche; too hard for the beginner core audience — defer |
| 8 | Notation incidental-acquisition overlay | Low-impact aid; could ride along with #3's UI work later |
| 9 | Timed puzzle rush | Needs a curated embedded puzzle set; #4 yields puzzle value from the player's own games without curation — #4 dominates now |
| 10 | Move-rejection tutor ("why can't I move there"); minimum-think-time gate | Tactical polish below the ambition floor vs survivors — good quick-wins later |

All five axes (A–E) have at least one survivor — no axis-coverage gap.
