pub const pgn = @import("persistence/pgn.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
