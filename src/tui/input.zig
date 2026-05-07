const vaxis = @import("vaxis");
const Game = @import("game.zig").Game;

pub const Action = enum {
    quit,
    render,
    none,
};

pub fn handleKeyPress(game: *Game, key: vaxis.Key) Action {
    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) return .quit;

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

    if (key.matches('u', .{})) {
        game.undoMove();
        return .render;
    }
    if (key.matches('n', .{})) {
        game.newGame();
        return .render;
    }
    if (key.matches('f', .{})) {
        game.flipBoard();
        return .render;
    }

    return .none;
}
