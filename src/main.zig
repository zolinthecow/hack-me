const std = @import("std");
const Server = @import("http/server.zig").Server;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try Server.init(allocator, .{});
    defer server.deinit();

    try server.listen();
}
