const movegen = @import("movegen.zig");
const board_mod = @import("board.zig");

const Board = board_mod.Board;

pub fn perft(b: *const Board, depth: u32) u64 {
    if (depth == 0) return 1;

    const moves = movegen.legalMoves(b);
    if (depth == 1) return moves.len;

    var nodes: u64 = 0;
    for (moves.slice()) |m| {
        const child = movegen.makeMove(b.*, m);
        nodes += perft(&child, depth - 1);
    }
    return nodes;
}

test {
    _ = @import("perft_test.zig");
}
