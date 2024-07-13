const std = @import("std");
const server = @import("http/server.zig");

pub fn main() !void {
    var s = try server.Server.init(.{});
    try s.listen();
}
