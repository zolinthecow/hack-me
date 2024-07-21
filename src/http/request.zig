const std = @import("std");

const Url = @import("url.zig").Url;

pub const Protocol = enum {
    HTTP11,
    HTTP2, // Support later
};
pub const ProtocolMap = std.StaticStringMap(Protocol).initComptime(.{
    .{ "HTTP/1.1", .HTTP11 },
    .{ "HTTP/2", .HTTP2 },
});

pub const Method = enum {
    GET,
    PUT,
    POST,
    PATCH,
    DELETE,
};
pub const MethodMap = std.StaticStringMap(Method).initComptime(.{
    .{ "GET", .GET },
    .{ "PUT", .PUT },
    .{ "POST", .POST },
    .{ "PATCH", .PATCH },
    .{ "DELETE", .DELETE },
});

pub const ContentType = enum {
    IMAGEPNG,
    APPLICATIONJSON,
    TEXTHTML,
};

pub const Request = struct {
    method: Method,
    url: Url,
    protocol: Protocol,
    headers: std.StringHashMap([]const u8),
    body: []const u8 = "",

    // Feels like you should be able to use an arena
    // allocator for requests since once the request
    // is done you can just deallocate everything
    arena: std.mem.Allocator,

    const Self = @This();

    pub fn init(request: []const u8, arena: std.mem.Allocator) !Request {
        var method: Method = undefined;
        var url: Url = undefined;
        var protocol: Protocol = undefined;
        var headers = std.StringHashMap([]const u8).init(arena);
        errdefer headers.deinit();
        var body = std.ArrayList(u8).init(arena);
        errdefer body.deinit();

        var remaining_body_length: usize = 0;

        var request_lines_it = std.mem.split(u8, request, "\r\n");

        const ProcessingPart = enum {
            RequestLine,
            Headers,
            Body,
        };
        var processing_part: ProcessingPart = .RequestLine;
        while (request_lines_it.next()) |line| {
            switch (processing_part) {
                // method + url + url
                .RequestLine => {
                    var word_ct: usize = 0;
                    var line_it = std.mem.split(u8, line, " ");
                    while (line_it.next()) |word| {
                        switch (word_ct) {
                            0 => {
                                method = MethodMap.get(word) orelse return error.InvalidHTTPMethod;
                            },
                            1 => {
                                url = try Url.parse(arena, word);
                            },
                            2 => {
                                protocol = ProtocolMap.get(word) orelse return error.InvalidHTTPMethod;
                            },
                            3 => {
                                // EOS
                                continue;
                            },
                            else => return error.InvalidRequest,
                        }
                        word_ct += 1;
                    }
                    processing_part = .Headers;
                },
                .Headers => {
                    if (line.len == 0) {
                        processing_part = .Body;
                        continue;
                    }
                    if (std.mem.indexOf(u8, line, ":")) |colon_idx| {
                        const name = std.mem.trim(u8, line[0..colon_idx], " ");
                        const value = std.mem.trim(u8, line[colon_idx + 1 ..], " ");
                        try headers.put(name, value);

                        if (std.mem.eql(u8, name, "Content-Length")) {
                            remaining_body_length = try std.fmt.parseInt(usize, value, 10);
                        }
                    } else {
                        try headers.put(line, "");
                    }
                },
                .Body => {
                    const to_append = if (line.len > remaining_body_length) line[0..remaining_body_length] else line;
                    try body.appendSlice(to_append);
                    remaining_body_length -= to_append.len;
                    if (remaining_body_length == 0) {
                        // Finished
                        break;
                    }
                },
            }
        }

        const body_owned_slice = try body.toOwnedSlice();
        return .{
            .method = method,
            .url = url,
            .protocol = protocol,
            .headers = headers,
            .body = body_owned_slice,
            .arena = arena,
        };
    }
};

const testing = std.testing;

test "request: parse" {
    {
        const message = "GET /index.html HTTP/1.1 \r\n" ++
            "Host: www.example.com \r\n" ++
            "\r\n" ++
            "This is the body";

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        const request = try Request.init(message, arena.allocator());
        try testing.expectEqualStrings(request.body, "");
    }
    {
        const message = "GET /index.html HTTP/1.1 \r\n" ++
            "Host: www.example.com \r\n" ++
            "Content-Length: 16\r\n" ++
            "\r\n" ++
            "This is the body";

        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var request = try Request.init(message, arena.allocator());

        try testing.expect(request.method == .GET);
        try testing.expect(request.protocol == .HTTP11);
        try testing.expectEqualStrings("/index.html", request.url.raw);
        try testing.expectEqualStrings("www.example.com", request.headers.get("Host").?);
        try testing.expectEqualStrings("This is the body", request.body);
    }
}
