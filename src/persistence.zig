pub const pgn = @import("persistence/pgn.zig");
pub const storage = @import("persistence/storage.zig");
pub const config = @import("persistence/config.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
