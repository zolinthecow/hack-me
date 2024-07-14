const std: type = @import("std");
const testing = std.testing;
const posix = std.posix;

const EventLoop = @import("event_loop.zig").EventLoop;
const Request = @import("request.zig").Request;

pub const Config = struct {
    port: ?u16 = null,
    address: ?[]const u8 = null,
};

pub const Server = struct {
    config: Config,
    _event_loop: EventLoop,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) !Self {
        var server_config = config;
        if (config.port == null) {
            server_config.port = 8000;
        }
        if (config.address == null) {
            server_config.address = "127.0.0.1";
        }

        const evl = EventLoop.init(allocator);

        return Server{ .config = server_config, ._event_loop = evl };
    }

    pub fn deinit(self: *Self) void {
        self._event_loop.deinit();
    }

    pub fn listen(self: *Self) !void {
        // ---Bind to socket---
        const address = blk: {
            const listen_port = self.config.port.?;
            const listen_address = self.config.address.?;
            break :blk try std.net.Address.parseIp4(listen_address, listen_port);
        };
        std.debug.print("Starting server at {}..\n", .{address});
        // instantiate an IPv4 TCP socket
        const sock = try posix.socket(address.any.family, posix.SOCK.STREAM, posix.IPPROTO.TCP);
        defer posix.close(sock);

        // Allow reuse address
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        {
            std.debug.print("Binding to socket..\n", .{});
            try posix.bind(sock, &address.any, address.getOsSockLen());
            try posix.listen(sock, 128);
        }

        std.debug.print("Waiting for connections..\n", .{});
        try self._event_loop.register_event(sock, .Read, self, Server.accept_callback);
        try self._event_loop.run();
    }

    fn read_callback(self: *Self, sock: posix.fd_t) void {
        var buffer: [1024]u8 = undefined;
        const bytes_read = posix.read(sock, &buffer) catch |err| {
            std.debug.print("Error reading: {}\n", .{err});
            return;
        };
        std.debug.print("Read {} bytes: {s}\n", .{ bytes_read, buffer[0..bytes_read] });

        const address = blk: {
            const listen_port = self.config.port.?;
            const listen_address = self.config.address.?;

            break :blk std.net.Address.parseIp4(listen_address, listen_port) catch |err| {
                std.debug.print("Error parsing address: {}\n", .{err});
                // Provide a default address as fallback
                break :blk std.net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 8000);
            };
        };
        std.debug.print("temp {}\n", .{address});
    }

    fn accept_callback(self: *Self, sock: posix.fd_t) void {
        const client_fd = posix.accept(sock, null, null, 0) catch |err| {
            std.debug.print("Error accpeting connections: {}\n", .{err});
            return;
        };

        std.debug.print("Accepted new connection\n", .{});
        self._event_loop.register_event(client_fd, .Read, self, Server.read_callback) catch |err| {
            std.debug.print("Error registering client: {}\n", .{err});
            posix.close(client_fd);
        };
    }
};
