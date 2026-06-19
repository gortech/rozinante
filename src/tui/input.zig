const vaxis = @import("vaxis");
const game_mod = @import("game.zig");
const Game = game_mod.Game;

pub const Action = enum {
    quit,
    render,
    none,
    resign,
    new_game,
    toggle_hints,
    undo,
    review,
};

/// Resolve a Y/N modal keypress: true = confirm (y/enter), false = cancel
/// (n/esc), null = neither (leave the prompt open).
pub fn confirmKey(key: vaxis.Key) ?bool {
    if (key.matches('y', .{}) or key.matches(vaxis.Key.enter, .{})) return true;
    if (key.matches('n', .{}) or key.matches(vaxis.Key.escape, .{})) return false;
    return null;
}

pub fn handleKeyPress(game: *Game, key: vaxis.Key) Action {
    // Modal confirmations take precedence: resolve the open prompt before anything else.
    if (game.resign_pending) {
        if (confirmKey(key)) |yes| {
            game.resign_pending = false;
            return if (yes) .resign else .render;
        }
        return .none;
    }
    if (game.quit_pending) {
        if (confirmKey(key)) |yes| {
            game.quit_pending = false;
            return if (yes) .quit else .render;
        }
        return .none;
    }
    if (game.leave_pending) {
        if (confirmKey(key)) |yes| {
            game.leave_pending = false;
            return if (yes) .new_game else .render;
        }
        return .none;
    }

    // Quit / leave-to-menu: instant when the game is over, confirm while in progress.
    // Before the thinking gate so they work mid-search, but deferred during promotion
    // (like the resign trigger) so the confirm prompt can't hide behind the promotion UI.
    if (game.promotion_pending == null) {
        if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
            if (game.game_phase == .playing) {
                game.quit_pending = true;
                return .render;
            }
            return .quit;
        }
        if (key.matches('n', .{})) {
            if (game.game_phase == .playing) {
                game.leave_pending = true;
                return .render;
            }
            return .new_game;
        }
    }

    // During engine thinking, only allow the resign prompt and flip (plus the above).
    if (game.engine_state == .thinking or game.engine_state == .reconnecting) {
        if (key.matches('r', .{})) {
            game.resign_pending = true;
            return .render;
        }
        if (key.matches('f', .{})) {
            game.flipBoard();
            return .render;
        }
        return .none;
    }

    // Promotion input mode
    if (game.promotion_pending != null) {
        if (key.matches(vaxis.Key.left, .{})) {
            game.cyclePromotionPrev();
            return .render;
        }
        if (key.matches(vaxis.Key.right, .{})) {
            game.cyclePromotionNext();
            return .render;
        }
        if (key.matches(vaxis.Key.enter, .{})) {
            game.confirmPromotion();
            return .render;
        }
        if (key.matches(vaxis.Key.escape, .{})) {
            game.cancelPromotion();
            return .render;
        }
        return .none;
    }

    if (key.matches(vaxis.Key.up, .{})) {
        game.moveCursor(0, 1);
        return .render;
    }
    if (key.matches(vaxis.Key.down, .{})) {
        game.moveCursor(0, -1);
        return .render;
    }
    if (key.matches(vaxis.Key.left, .{})) {
        game.moveCursor(-1, 0);
        return .render;
    }
    if (key.matches(vaxis.Key.right, .{})) {
        game.moveCursor(1, 0);
        return .render;
    }

    if (key.matches(vaxis.Key.enter, .{})) {
        game.selectSquare();
        return .render;
    }
    if (key.matches(vaxis.Key.escape, .{})) {
        game.cancelSelection();
        return .render;
    }

    if (key.matches('r', .{})) {
        if (game.game_phase == .playing) {
            game.resign_pending = true;
            return .render;
        }
        return .review; // on a finished game, R opens the analysis review
    }
    if (key.matches('f', .{})) {
        game.flipBoard();
        return .render;
    }
    if (key.matches('h', .{})) return .toggle_hints;
    if (key.matches('u', .{})) {
        if (game.game_phase == .playing and game.isHumanTurn()) {
            game.undoMovePair();
            return .undo;
        }
        return .none;
    }

    return .none;
}

const std = @import("std");
const chess = @import("../chess.zig");

fn fakeKey(codepoint: u21, mods: vaxis.Key.Modifiers) vaxis.Key {
    return .{ .codepoint = codepoint, .mods = mods };
}

test "input: u takes back a move-pair on the human's turn" {
    var game = Game.init();
    game.executeMove(chess.Square.init(.e, .@"2"), chess.Square.init(.e, .@"4"), null);
    game.executeMove(chess.Square.init(.e, .@"7"), chess.Square.init(.e, .@"5"), null);
    try std.testing.expectEqual(@as(usize, 2), game.move_count);

    const action = handleKeyPress(&game, fakeKey('u', .{}));
    try std.testing.expectEqual(Action.undo, action);
    try std.testing.expectEqual(@as(usize, 0), game.move_count);
}

test "input: u is inert after the game ends" {
    var game = Game.init();
    game.game_phase = .ended;
    try std.testing.expectEqual(Action.none, handleKeyPress(&game, fakeKey('u', .{})));
}

test "input: q in progress opens quit confirm, not immediate quit (AE5)" {
    var game = Game.init();
    try std.testing.expectEqual(Action.render, handleKeyPress(&game, fakeKey('q', .{})));
    try std.testing.expect(game.quit_pending);
    try std.testing.expectEqual(Action.render, handleKeyPress(&game, fakeKey('n', .{})));
    try std.testing.expect(!game.quit_pending);
    _ = handleKeyPress(&game, fakeKey('q', .{}));
    try std.testing.expectEqual(Action.quit, handleKeyPress(&game, fakeKey('y', .{})));
}

test "input: q on a finished game quits instantly (R6)" {
    var game = Game.init();
    game.game_phase = .ended;
    try std.testing.expectEqual(Action.quit, handleKeyPress(&game, fakeKey('q', .{})));
    try std.testing.expect(!game.quit_pending);
}

test "input: n in progress opens leave confirm; a single N cannot dismiss it (R7/AE9)" {
    var game = Game.init();
    try std.testing.expectEqual(Action.render, handleKeyPress(&game, fakeKey('n', .{})));
    try std.testing.expect(game.leave_pending);
    try std.testing.expectEqual(Action.render, handleKeyPress(&game, fakeKey('n', .{})));
    try std.testing.expect(!game.leave_pending);
    _ = handleKeyPress(&game, fakeKey('n', .{}));
    try std.testing.expectEqual(Action.new_game, handleKeyPress(&game, fakeKey('y', .{})));
}

test "input: n on a finished game returns to menu instantly" {
    var game = Game.init();
    game.game_phase = .ended;
    try std.testing.expectEqual(Action.new_game, handleKeyPress(&game, fakeKey('n', .{})));
    try std.testing.expect(!game.leave_pending);
}

test "input: r reviews a finished game, resigns an in-progress one" {
    var game = Game.init();
    try std.testing.expectEqual(Action.render, handleKeyPress(&game, fakeKey('r', .{})));
    try std.testing.expect(game.resign_pending);
    var ended = Game.init();
    ended.game_phase = .ended;
    try std.testing.expectEqual(Action.review, handleKeyPress(&ended, fakeKey('r', .{})));
}

test "input: q during promotion does not open a hidden quit confirm" {
    var game = Game.init();
    game.promotion_pending = .{
        .from = chess.Square.init(.e, .@"7"),
        .to = chess.Square.init(.e, .@"8"),
        .selected_idx = 0,
    };
    const action = handleKeyPress(&game, fakeKey('q', .{}));
    try std.testing.expectEqual(Action.none, action);
    try std.testing.expect(!game.quit_pending);
}
