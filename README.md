# Rozinante

A terminal chess game where you play [Stockfish](https://stockfishchess.org/) at the strength you choose, with learning aids you can switch on and off as you go.

> Named after *Rocinante*, Don Quixote's bony but loyal steed — a fittingly humble mount for an earnest side-quest. (For its author, that quest is learning [Zig](https://ziglang.org/).)

> **Status: work in progress.** Playable, but not finished or packaged for release yet. Expect rough edges.

## Features

- **Play Stockfish at a chosen difficulty** — a single Skill Level dial spanning genuine-beginner (with an app-side move handicap below Stockfish's rating floor) to full strength; pick your color (white, black, or random) from the menu.
- **Learning aids, toggled mid-game** — highlight your pieces currently under attack and show Stockfish's suggested best move, on demand.
- **Opening identification** — names the opening from an embedded Lichess ECO book (3690 lines).
- **Full chess rules** — castling, en passant, promotion, check/checkmate/stalemate, and the fifty-move rule. (Threefold repetition is not detected yet.)
- **Save, browse, and replay** — games are written to PGN; a history browser lets you reopen past games and step through them move by move.
- **Take back moves** — press U on your turn to undo a move-pair, repeatable to the start of the game; the saved PGN rewrites to match.
- **Selectable board themes** — Classic, Wood, Green, and Blue full palettes, chosen in the menu with live preview and remembered across sessions.
- **Confirmation prompts** — quitting or leaving a game in progress, and deleting a saved game, ask first.

## Requirements

- **Zig 0.16.0** or newer.
- **[Stockfish](https://stockfishchess.org/download/)** installed and available — Rozinante drives it as a UCI subprocess at runtime.
- A terminal with truecolor support.

## Build & run

```sh
zig build        # compile the rozinante executable
zig build run    # build and run
zig build test   # run the test suite
```

## Project layout

Single Zig package, library/executable split, with each directory fronted by a barrel file:

- `src/chess/` — board representation, move generation, and rules.
- `src/tui/` — terminal UI: board renderer, game loop, input, menus, history, and replay viewer (built on [libvaxis](https://github.com/rockorager/libvaxis)).
- `src/persistence/` — PGN format, game storage, and config.
- `src/engine.zig` — Stockfish UCI subprocess management.
- `src/openings.zig` + `src/data/openings.tsv` — the embedded opening book.

See [`docs/architecture.md`](docs/architecture.md) for the design and decision log.

## License

Licensed under the [MIT License](LICENSE).

The bundled opening book (`src/data/openings.tsv`) is derived from [Lichess opening data](https://github.com/lichess-org/chess-openings) and is in the public domain (CC0).
