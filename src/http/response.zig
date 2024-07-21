const std = @import("std");

const c = @cImport({
    @cInclude("time.h");
});

const Request = @import("request.zig").Request;

const server_pkg = @import("server.zig");
const Method = server_pkg.Method;
const MethodMap = server_pkg.MethodMap;
const Protocol = server_pkg.Protocol;
const ProtocolMap = server_pkg.ProtocolMap;

// Subset of https://developer.mozilla.org/en-US/docs/Web/HTTP/Status#client_error_responses
pub const StatusCode = std.StaticStringMap([]const u8).initComptime(.{
    .{ "200", "200 Ok" },
    .{ "201", "201 Created" },
    .{ "202", "202 Accepted" },
    .{ "203", "203 Non-Authoritative Information" },
    .{ "204", "204 No Content" },
    .{ "205", "205 Reset Content" },
    .{ "206", "206 Partial Content" },
    .{ "300", "300 Multiple Choices" }, // Return URLs seperated by \n
    .{ "301", "301 Moved Permanently" }, // Must return new URL in body
    .{ "302", "302 Found" },
    .{ "303", "303 See Other" },
    .{ "304", "304 Not Modified" },
    .{ "400", "400 Bad Request" },
    .{ "401", "401 Unauthorized" },
    .{ "403", "403 Forbidden" },
    .{ "404", "404 Not Found" },
    .{ "500", "500 Internal Server Error" },
    .{ "501", "501 Not Implemented" }, // Gonna be using this a lot lol
    .{ "502", "502 Bad Gateway" },
    .{ "504", "504 Gateway Timeout" },
});

pub const Response = struct {
    sock: std.posix.fd_t,
    request: *Request,
    arena: std.mem.Allocator, // Just like Request, arena should be fine

    const Self = @This();

    pub fn init(arena: std.mem.Allocator, sock: std.posix.fd_t, request: *Request) Self {
        return .{
            .sock = sock,
            .request = request,
            .arena = arena,
        };
    }

    const ResponseParts = struct {
        status_code: []const u8 = "200",
        body: []const u8 = "",
        headers: ?std.StringHashMap([]const u8),
    };

    pub fn send_response(self: *Self, response: ResponseParts) !void {
        const response_body = try build_response(response);
        try std.posix.write(self.sock, response_body);

        if (self.request.protocol == .HTTP10 or std.mem.eql(self.request.headers.get("Connection").?, "close")) {
            std.posix.close(self.sock);
        }
    }

    fn build_response(self: *Self, response_parts: ResponseParts) ![]const u8 {
        var response_list = std.ArrayList(u8).init(self.arena);
        errdefer response_list.deinit();

        const status_code = StatusCode.get(response_parts.status_code) orelse return error.InvalidStatusCode;
        try response_list.writer().print("{s}\r\n", .{status_code});

        const date = try getHttpDate();
        try response_list.writer().print("Date: {s}\r\nServer: Zerver\r\n", .{date});

        if (response_parts.headers) |headers| {
            var headers_it = headers.iterator();
            while (headers_it.next()) |header| {
                try response_list.writer().print("{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
            }
        }

        try response_list.appendSlice("\r\n");

        try response_list.appendSlice(response_parts.body);

        const owned_part = try response_list.toOwnedSlice();
        return owned_part;
    }

    fn getHttpDate() ![29]u8 {
        const epoch_seconds = std.time.timestamp();
        return getHttpDateFromTimestamp(epoch_seconds);
    }

    fn getHttpDateFromTimestamp(epoch_seconds: i64) ![29]u8 {
        var buffer: [29]u8 = undefined;

        // Get the GMT time
        const time_info = c.gmtime(&epoch_seconds);
        if (time_info == null) return error.TimeConversionFailed;

        // Format the time string
        const written = c.strftime(&buffer, buffer.len, "%a, %d %b %Y %H:%M:%S GMT", time_info);

        if (written != 0) return error.TimeFormattingFailed;

        return buffer;
    }
};

const testing = std.testing;

test "response: date formatting" {
    {
        const date = try Response.getHttpDateFromTimestamp(1606780800); // 2020-12-01 00:00:00 GMT
        try testing.expectEqualStrings("Tue, 01 Dec 2020 00:00:00 GMT", &date);
    }
}

test "response: response building" {
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const message = "GET /index.html HTTP/1.1 \r\n" ++
            "Host: www.example.com \r\n" ++
            "Content-Length: 16\r\n" ++
            "\r\n" ++
            "This is the body";

        var request = try Request.init(message, allocator);
        var response = Response.init(allocator, 0, &request);

        var headers = std.StringHashMap([]const u8).init(allocator);
        try headers.put("Content-Type", "text/plain");

        const response_parts = Response.ResponseParts{
            .status_code = "200",
            .body = "Hello, World!",
            .headers = headers,
        };

        const built_response = try response.build_response(response_parts);

        // Check if the response contains expected parts
        try testing.expect(std.mem.indexOf(u8, built_response, "200 Ok") != null);
        try testing.expect(std.mem.indexOf(u8, built_response, "Content-Type: text/plain") != null);
        try testing.expect(std.mem.indexOf(u8, built_response, "Hello, World!") != null);
    }

    // Test status code mapping
    {
        const status = StatusCode.get("404").?;
        try testing.expectEqualStrings("404 Not Found", status);
    }
}
