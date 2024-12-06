// Organize the exports, ex: `pub const Grid = @import("./util/Grid.zig");`
const A = struct {
    a: u8,
};

test {
    const std = @import("std");
    std.testing.refAllDeclsRecursive(@This());
}
