const vaxis = @import("vaxis");
const game_mod = @import("game.zig");
const Game = game_mod.Game;

pub const Action = enum {
    quit,
    render,
    none,
    resign,
    new_game,
};

pub fn handleKeyPress(game: *Game, key: vaxis.Key) Action {
    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) return .quit;

    // Resign confirmation mode
    if (game.resign_pending) {
        if (key.matches('y', .{}) or key.matches(vaxis.Key.enter, .{})) {
            game.resign_pending = false;
            return .resign;
        }
        if (key.matches('n', .{}) or key.matches(vaxis.Key.escape, .{})) {
            game.resign_pending = false;
            return .render;
        }
        return .none;
    }

    // During engine thinking, only allow quit, resign prompt, flip
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
        return .none;
    }
    if (key.matches('n', .{})) return .new_game;
    if (key.matches('f', .{})) {
        game.flipBoard();
        return .render;
    }

    return .none;
}
