#!/usr/bin/env python3
"""Download Lichess chess-openings TSV files and convert SAN moves to UCI."""

import csv
import io
import re
import sys
import urllib.request

import chess

BASE_URL = "https://raw.githubusercontent.com/lichess-org/chess-openings/master"
FILES = ["a.tsv", "b.tsv", "c.tsv", "d.tsv", "e.tsv"]


def strip_move_numbers(pgn: str) -> list[str]:
    return [tok for tok in pgn.split() if not re.match(r"^\d+\.", tok)]


def san_to_uci(pgn: str) -> str:
    board = chess.Board()
    uci_parts = []
    for san in strip_move_numbers(pgn):
        move = board.parse_san(san)
        uci_parts.append(move.uci())
        board.push(move)
    return " ".join(uci_parts)


def board_to_epd(pgn: str) -> str:
    board = chess.Board()
    for san in strip_move_numbers(pgn):
        board.push_san(san)
    fen = board.fen()
    # EPD = piece placement + active color + castling + en passant (no clocks)
    parts = fen.split()
    return " ".join(parts[:4])


def main():
    entries = []
    for filename in FILES:
        url = f"{BASE_URL}/{filename}"
        sys.stderr.write(f"Downloading {url}...\n")
        with urllib.request.urlopen(url) as resp:
            text = resp.read().decode("utf-8")

        reader = csv.DictReader(io.StringIO(text), delimiter="\t")
        for row in reader:
            eco = row["eco"]
            name = row["name"]
            pgn = row["pgn"]
            try:
                uci = san_to_uci(pgn)
                epd = board_to_epd(pgn)
            except Exception as e:
                sys.stderr.write(f"Skipping {eco} {name}: {e}\n")
                continue
            entries.append((eco, name, uci, epd))

    entries.sort(key=lambda e: (e[0], e[1]))

    sys.stderr.write(f"Total entries: {len(entries)}\n")

    writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    for eco, name, uci, epd in entries:
        writer.writerow([eco, name, uci, epd])


if __name__ == "__main__":
    main()
