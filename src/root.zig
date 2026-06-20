//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const chess = @import("chess.zig");
pub const engine = @import("engine.zig");
pub const openings = @import("openings.zig");
pub const tui = @import("tui.zig");
pub const persistence = @import("persistence.zig");
pub const analysis = @import("analysis.zig");

test {
    std.testing.refAllDecls(@This());
}
