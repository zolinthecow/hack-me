const std: type = @import("std");
const testing = std.testing;

pub const Config = struct {
    port: ?u16 = null,
    address: ?[]const u8 = null,
};

pub const Server = struct {
    config: Config,

    const Self = @This();

    pub fn init(config: Config) !Self {
        var server_config = config;
        if (config.port == null) {
            server_config.port = 8000;
        }
        if (config.address == null) {
            server_config.address = "127.0.0.1";
        }

        return Server{ .config = server_config };
    }

    pub fn listen(self: *Server) !void {
        // ---Bind to socket---
        const address = blk: {
            const listen_port = self.config.port.?;
            const listen_address = self.config.address.?;
            break :blk try std.net.Address.parseIp4(listen_address, listen_port);
        };
        std.debug.print("Starting server at {}..\n", .{address});
        // instantiate an IPv4 TCP socket
        const sock = try std.posix.socket(address.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        defer std.posix.close(sock);

        // Allow reuse address
        try std.posix.setsockopt(sock, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        {
            std.debug.print("Binding to socket..\n", .{});
            try std.posix.bind(sock, &address.any, address.getOsSockLen());
            try std.posix.listen(sock, 128);
        }

        std.debug.print("Waiting for connections..\n", .{});
        while (true) {
            const client_socket = try std.posix.accept(sock, null, null, 0);
            defer std.posix.close(client_socket);

            var buffer: [1024]u8 = undefined;
            const received_bytes = try std.posix.recv(client_socket, &buffer, 0);
            if (received_bytes > 0) {
                std.debug.print("Received {d} bytes: {s}\n", .{ received_bytes, buffer[0..received_bytes] });
            }
        }
    }
};
