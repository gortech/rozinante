pub const renderer = @import("tui/renderer.zig");
pub const game = @import("tui/game.zig");
pub const input = @import("tui/input.zig");
pub const sprites = @import("tui/sprites.zig");
pub const menu = @import("tui/menu.zig");
pub const history = @import("tui/history.zig");
pub const viewer = @import("tui/viewer.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
