//! The persistent bottom keybind bar (R1-R6a): a one-row, full-width strip of
//! zellij-style key chips, drawn per-screen. Owns the chip data, the
//! context-sensitive chip sets, the priority-tail overflow drop, and renders
//! against the theme-invariant chip palette. Display-only: a dropped chip's key
//! stays functionally active in the input handlers.

const std = @import("std");
const vaxis = @import("vaxis");
const renderer = @import("renderer.zig");
const game_mod = @import("game.zig");
const Game = game_mod.Game;
const Window = vaxis.Window;

/// Reserved bar height in rows. Each screen subtracts this from its body and
/// pins the bar to the bottom row.
pub const height: u16 = 1;

pub const Chip = struct {
    key: []const u8,
    label: []const u8,
};

// Chip sets are ordered highest-priority-first (R6a: cursor/move > select >
// esc/back > quit > menu > the rest), so render() drops the overflow tail simply
// by stopping before the first chip that no longer fits.

const confirm_yn = [_]Chip{
    .{ .key = "Y", .label = "Yes" },
    .{ .key = "N", .label = "No" },
};

const game_promotion = [_]Chip{
    .{ .key = "\u{2190}\u{2192}", .label = "Piece" },
    .{ .key = "Enter", .label = "Place" },
    .{ .key = "Esc", .label = "Cancel" },
};

const game_engine_busy = [_]Chip{
    .{ .key = "R", .label = "Resign" },
    .{ .key = "F", .label = "Flip" },
    .{ .key = "Q", .label = "Quit" },
    .{ .key = "N", .label = "Menu" },
};

const game_normal = [_]Chip{
    .{ .key = "\u{2191}\u{2193}\u{2190}\u{2192}", .label = "Move" },
    .{ .key = "Enter", .label = "Select" },
    .{ .key = "Q", .label = "Quit" },
    .{ .key = "N", .label = "Menu" },
    .{ .key = "R", .label = "Resign" },
    .{ .key = "F", .label = "Flip" },
    .{ .key = "H", .label = "Hints" },
    .{ .key = "U", .label = "Undo" },
};

const game_over = [_]Chip{
    .{ .key = "R", .label = "Review" },
    .{ .key = "N", .label = "Menu" },
    .{ .key = "Q", .label = "Quit" },
};

const menu_chips = [_]Chip{
    .{ .key = "\u{2191}\u{2193}", .label = "Navigate" },
    .{ .key = "\u{2190}\u{2192}", .label = "Adjust" },
    .{ .key = "Enter", .label = "Select" },
    .{ .key = "Q", .label = "Quit" },
};

const review_full = [_]Chip{
    .{ .key = "\u{2190}\u{2192}", .label = "Step" },
    .{ .key = "Home/End", .label = "Jump" },
    .{ .key = "n/p", .label = "Key moment" },
    .{ .key = "F", .label = "Flip" },
    .{ .key = "Esc", .label = "Back" },
};

const review_basic = [_]Chip{
    .{ .key = "\u{2190}\u{2192}", .label = "Step" },
    .{ .key = "Home/End", .label = "Jump" },
    .{ .key = "F", .label = "Flip" },
    .{ .key = "Esc", .label = "Back" },
};

const history_browse = [_]Chip{
    .{ .key = "\u{2191}\u{2193}", .label = "Navigate" },
    .{ .key = "Enter", .label = "View" },
    .{ .key = "Esc", .label = "Back" },
    .{ .key = "Del", .label = "Remove" },
};

const history_empty = [_]Chip{
    .{ .key = "Esc", .label = "Back" },
};

/// The chip set for the active game, mirroring `input.zig` `handleKeyPress`
/// precedence: a modal confirm (resign/quit/leave) wins over the engine-busy
/// set, so a resign prompt opened mid-search shows Y/N rather than the inert
/// R/F/Q/N chips. Engine-busy covers thinking *and* reconnecting (both gate
/// input); `.error` keeps the normal set.
pub fn gameChips(game: *const Game) []const Chip {
    if (game.resign_pending or game.quit_pending or game.leave_pending) return &confirm_yn;
    if (game.promotion_pending != null) return &game_promotion;
    if (game.engine_state == .thinking or game.engine_state == .reconnecting) return &game_engine_busy;
    if (game.game_phase == .ended) return &game_over;
    return &game_normal;
}

pub fn menuChips() []const Chip {
    return &menu_chips;
}

/// Review chips; `show_key_moments` (analysis ready AND at least one key moment)
/// gates the `n/p` chip, which is inert otherwise.
pub fn reviewChips(show_key_moments: bool) []const Chip {
    return if (show_key_moments) &review_full else &review_basic;
}

pub fn historyChips(total: usize, delete_pending: bool) []const Chip {
    if (delete_pending) return &confirm_yn;
    if (total == 0) return &history_empty;
    return &history_browse;
}

/// Display columns a string occupies (one per codepoint; matches `writeStr`,
/// which renders each grapheme at width 1).
fn displayWidth(text: []const u8) u16 {
    var w: u16 = 0;
    var i: usize = 0;
    while (i < text.len) {
        const b = text[i];
        const byte_len: usize = if (b < 0x80) 1 else if (b < 0xE0) 2 else if (b < 0xF0) 3 else 4;
        i += byte_len;
        w += 1;
    }
    return w;
}

/// Rendered width of one chip: " key " (padded) + " label".
fn chipWidth(chip: Chip) u16 {
    return displayWidth(chip.key) + displayWidth(chip.label) + 3;
}

/// How many leading chips fit in `width`, dropping the low-priority tail (R6a).
pub fn fittedCount(chips: []const Chip, width: u16) usize {
    var x: u16 = 0;
    var n: usize = 0;
    for (chips) |chip| {
        const w = chipWidth(chip);
        if (x + w > width) break;
        x += w + 1; // chip + one-column separator
        n += 1;
    }
    return n;
}

/// Draw the bar into `win` (a full-width, `height`-row window pinned at the
/// screen bottom). Chips lay left-to-right on the theme background; the
/// overflow tail is dropped (its keys remain active in the input handlers).
pub fn render(win: Window, chips: []const Chip) void {
    const bg = renderer.Theme.bg;
    var bx: u16 = 0;
    while (bx < win.width) : (bx += 1) {
        win.writeCell(bx, 0, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{ .bg = bg } });
    }

    const chip_style: vaxis.Cell.Style = .{ .fg = renderer.Theme.keybar_chip_fg, .bg = renderer.Theme.keybar_chip_bg };
    const label_style: vaxis.Cell.Style = .{ .fg = renderer.Theme.text_dim, .bg = bg };

    const n = fittedCount(chips, win.width);
    var x: u16 = 0;
    for (chips[0..n]) |chip| {
        x = renderer.writeStr(win, x, 0, " ", chip_style);
        x = renderer.writeStr(win, x, 0, chip.key, chip_style);
        x = renderer.writeStr(win, x, 0, " ", chip_style);
        x = renderer.writeStr(win, x, 0, " ", label_style);
        x = renderer.writeStr(win, x, 0, chip.label, label_style);
        x += 1; // separator
    }
}

const testing = std.testing;

fn hasKey(chips: []const Chip, key: []const u8) bool {
    for (chips) |c| {
        if (std.mem.eql(u8, c.key, key)) return true;
    }
    return false;
}

test "gameChips: normal human turn returns the full set, Move first" {
    var game = Game.init();
    const chips = gameChips(&game);
    try testing.expectEqual(@as(usize, 8), chips.len);
    try testing.expectEqualStrings("Move", chips[0].label);
    try testing.expect(hasKey(chips, "U")); // undo present on the human's turn
    try testing.expect(hasKey(chips, "H")); // hints present
}

test "gameChips: engine-thinking shows only resign/flip/quit/menu (R3)" {
    var game = Game.init();
    game.engine_state = .thinking;
    const chips = gameChips(&game);
    try testing.expectEqual(@as(usize, 4), chips.len);
    try testing.expect(hasKey(chips, "R") and hasKey(chips, "F") and hasKey(chips, "Q") and hasKey(chips, "N"));
    try testing.expect(!hasKey(chips, "U")); // undo suppressed (inert)
    try testing.expect(!hasKey(chips, "H")); // hints suppressed (inert)
}

test "gameChips: reconnecting uses the engine-busy set; error keeps normal" {
    var game = Game.init();
    game.engine_state = .reconnecting;
    try testing.expectEqual(@as(usize, 4), gameChips(&game).len);
    game.engine_state = .@"error";
    try testing.expectEqual(@as(usize, 8), gameChips(&game).len);
}

test "gameChips: confirm prompt returns Y/N (R4)" {
    var game = Game.init();
    game.resign_pending = true;
    const chips = gameChips(&game);
    try testing.expectEqual(@as(usize, 2), chips.len);
    try testing.expectEqualStrings("Y", chips[0].key);
    try testing.expectEqualStrings("N", chips[1].key);
}

test "gameChips: a resign confirm opened while thinking wins over engine-busy" {
    var game = Game.init();
    game.engine_state = .thinking;
    game.resign_pending = true;
    const chips = gameChips(&game);
    try testing.expectEqual(@as(usize, 2), chips.len);
    try testing.expectEqualStrings("Yes", chips[0].label);
}

test "gameChips: game over shows Review/Menu/Quit" {
    var game = Game.init();
    game.game_phase = .ended;
    const chips = gameChips(&game);
    try testing.expect(hasKey(chips, "R") and hasKey(chips, "N") and hasKey(chips, "Q"));
    try testing.expectEqualStrings("Review", chips[0].label);
}

test "reviewChips: n/p only when key moments exist" {
    try testing.expect(hasKey(reviewChips(true), "n/p"));
    try testing.expect(!hasKey(reviewChips(false), "n/p"));
}

test "historyChips: empty -> Esc only; delete-confirm -> Y/N; browse otherwise" {
    try testing.expectEqual(@as(usize, 1), historyChips(0, false).len);
    try testing.expectEqualStrings("Esc", historyChips(0, false)[0].key);
    try testing.expect(hasKey(historyChips(3, true), "Y"));
    try testing.expect(hasKey(historyChips(3, false), "Del"));
}

test "fittedCount: keeps the priority head and drops the tail (R6a)" {
    // The full normal set in a generous width keeps everything.
    try testing.expectEqual(game_normal.len, fittedCount(&game_normal, 240));
    // A width that fits only a few keeps a prefix (the priority head) and < all.
    const partial = fittedCount(&game_normal, 30);
    try testing.expect(partial > 0 and partial < game_normal.len);
    // Too small for even one chip renders nothing, no crash.
    try testing.expectEqual(@as(usize, 0), fittedCount(&game_normal, 1));
}

test "palette: keybar chip bg clears a contrast delta from every theme bg (R2a)" {
    const min_delta2: u32 = 60 * 60;
    for ([_]renderer.ThemeId{ .classic, .wood, .green, .blue }) |id| {
        const p = renderer.palette(id);
        try testing.expect(colorDist2(p.keybar_chip_bg, p.bg) >= min_delta2);
        // The key glyph must read against its own chip background.
        try testing.expect(colorDist2(p.keybar_chip_fg, p.keybar_chip_bg) >= min_delta2);
    }
}

fn colorDist2(a: vaxis.Cell.Color, b: vaxis.Cell.Color) u32 {
    var sum: u32 = 0;
    for (0..3) |k| {
        const d = @as(i32, a.rgb[k]) - @as(i32, b.rgb[k]);
        sum += @intCast(d * d);
    }
    return sum;
}
