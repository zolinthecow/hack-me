// https://www.talisman.org/~erlkonig/misc/lunatech%5Ewhat-every-webdev-must-know-about-url-encoding/
// Urls are a lot more complex than I thought

const std = @import("std");

pub const Url = struct {
    raw: []const u8,
    path: []const u8,
    path_segments: []const PathSegment,
    query: []const u8,
    query_params: std.StringHashMap([]const u8),
    fragment: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Url) void {
        self.allocator.free(self.raw);
        self.allocator.free(self.path);
        self.allocator.free(self.query);
        self.allocator.free(self.fragment);
        var qp_it = self.query_params.iterator();
        while (qp_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.query_params.deinit();
        for (self.path_segments) |seg| {
            self.allocator.free(seg.name);
            if (seg.params) |params| {
                var params_to_free = params;
                params_to_free.deinit();
            }
        }
        self.allocator.free(self.path_segments);
    }

    const UrlParts = enum { Path, Query, Fragment };

    const PathSegment = struct {
        name: []const u8,
        params: ?std.StringHashMap([]const u8),
    };

    pub fn parse(allocator: std.mem.Allocator, raw: []const u8) !Url {
        var raw_path: []const u8 = raw;
        var raw_query: []const u8 = "";
        var fragment: []const u8 = "";

        var part_processing: UrlParts = .Path;
        for (0.., raw) |i, char| {
            switch (part_processing) {
                .Path => {
                    if (char == '?') {
                        if (i == 0) {
                            return error.InvalidUrl;
                        }
                        raw_path = raw[0..i];
                        raw_query = raw[i + 1 ..];
                        part_processing = .Query;
                        break;
                    }
                },
                .Query => {
                    if (char == '#') {
                        raw_query = raw_query[0 .. i - raw_path.len - 1];
                        fragment = raw[i + 1 ..];
                        part_processing = .Fragment;
                        break;
                    }
                },
                .Fragment => {},
            }
        }

        const unescaped_path_res = try unescape(allocator, raw_path, .Path);
        var path_it = std.mem.splitSequence(u8, raw_path, "/");
        var path_segments = std.ArrayList(PathSegment).init(allocator);
        errdefer path_segments.deinit();
        while (path_it.next()) |seg| {
            if (std.mem.eql(u8, seg, "")) {
                continue;
            }
            try path_segments.append(.{
                .name = try unescape(allocator, seg, .Path),
                // I'll implement this when I find a use case for them
                .params = null,
            });
        }

        const unescaped_query_res = try unescape(allocator, raw_query, .Query);
        var query_params = std.StringHashMap([]const u8).init(allocator);
        errdefer query_params.deinit();
        var query_it = std.mem.split(u8, raw_query, "&");
        while (query_it.next()) |seg| {
            if (std.mem.eql(u8, seg, "")) {
                continue;
            }
            var key: []const u8 = "";
            var value: []const u8 = "";
            if (std.mem.indexOfScalar(u8, seg, '=')) |idx| {
                key = seg[0..idx];
                if (idx + 1 < seg.len) {
                    value = seg[idx + 1 ..];
                }
            } else {
                key = seg;
            }
            try query_params.put(try unescape(allocator, key, .Query), try unescape(allocator, value, .Query));
        }

        const owned_path_segments = try path_segments.toOwnedSlice();
        return .{
            .raw = try allocator.dupe(u8, raw),
            .path = unescaped_path_res,
            .path_segments = owned_path_segments,
            .query = unescaped_query_res,
            .query_params = query_params,
            .fragment = fragment,
            .allocator = allocator,
        };
    }

    // As defined by RFC 3983 you URL encoded characters are now UTF-8 which means
    // they can now be multi-byte characters
    fn unescape(allocator: std.mem.Allocator, input: []const u8, segment: UrlParts) ![]const u8 {
        var needs_modification = false;

        var i: usize = 0;
        while (i < input.len) {
            if (input[i] == '%') {
                if (i + 2 < input.len and HEX_CHAR[input[i + 1]] and HEX_CHAR[input[i + 2]]) {
                    needs_modification = true;
                    i += 3;
                } else {
                    return error.InvalidEscapeSequence;
                }
            } else if (input[i] == '+' and segment == .Query) {
                needs_modification = true;
                i += 1;
            } else {
                i += 1;
            }
        }

        // TODO: Figure out how to only deallocate when it is allocated.
        // // Try not to do unnecessary allocations
        // if (!needs_modification) {
        //     return input;
        // }

        var raw_bytes = std.ArrayList(u8).init(allocator);
        errdefer raw_bytes.deinit();

        i = 0;
        while (i < input.len) {
            if (input[i] == '%' and i + 2 < input.len) {
                const hex1 = input[i + 1];
                const hex2 = input[i + 2];
                if (HEX_CHAR[hex1] and HEX_CHAR[hex2]) {
                    const decoded = (HEX_DECODE[hex1] << 4) | HEX_DECODE[hex2];
                    try raw_bytes.append(decoded);
                    i += 3;
                }
            } else if (input[i] == '+' and segment == .Query) {
                try raw_bytes.append(' ');
                i += 1;
            } else {
                try raw_bytes.append(input[i]);
                i += 1;
            }
        }

        // Make sure its all valid UTF-8
        _ = std.unicode.Utf8View.init(raw_bytes.items) catch {
            return error.InvalidUtf8;
        };

        const owned_slice = try raw_bytes.toOwnedSlice();
        return owned_slice;
    }
};

const HEX_CHAR = blk: {
    var all = std.mem.zeroes([255]bool);
    for ('a'..('f' + 1)) |b| all[b] = true;
    for ('A'..('F' + 1)) |b| all[b] = true;
    for ('0'..('9' + 1)) |b| all[b] = true;
    break :blk all;
};
const HEX_DECODE = blk: {
    var all = std.mem.zeroes([255]u8);
    for ('a'..('z' + 1)) |b| all[b] = b - 'a' + 10;
    for ('A'..('Z' + 1)) |b| all[b] = b - 'A' + 10;
    for ('0'..('9' + 1)) |b| all[b] = b - '0';
    break :blk all;
};

const testing = std.testing;
test "url: parse" {
    {
        // root
        var url = try Url.parse(testing.allocator, "/");
        defer url.deinit();
        try testing.expectEqualStrings("/", url.raw);
        try testing.expectEqualStrings("/", url.path);
        try testing.expectEqualStrings("", url.query);
        try testing.expectEqual(true, url.query_params.count() == 0);
        try testing.expectEqual(true, url.path_segments.len == 0);
    }
    {
        // random /'s
        var url = try Url.parse(testing.allocator, "/abc/de/f");
        defer url.deinit();
        try testing.expectEqualStrings("/abc/de/f", url.raw);
        try testing.expectEqualStrings("/abc/de/f", url.path);
        try testing.expectEqualStrings("", url.query);
        try testing.expectEqual(true, url.query_params.count() == 0);
        try testing.expectEqual(true, url.path_segments.len == 3);
    }
    {
        // root with query
        var url = try Url.parse(testing.allocator, "/?urmom=fat");
        defer url.deinit();
        try testing.expectEqualStrings("/?urmom=fat", url.raw);
        try testing.expectEqualStrings("/", url.path);
        try testing.expectEqualStrings("urmom=fat", url.query);
        try testing.expectEqual(true, std.mem.eql(u8, url.query_params.get("urmom").?, "fat"));
        try testing.expectEqual(true, url.path_segments.len == 0);
    }
    {
        // path and query
        var url = try Url.parse(testing.allocator, "/abc?urmom=fat");
        defer url.deinit();
        try testing.expectEqualStrings("/abc?urmom=fat", url.raw);
        try testing.expectEqualStrings("/abc", url.path);
        try testing.expectEqualStrings("urmom=fat", url.query);
        try testing.expectEqual(true, std.mem.eql(u8, url.query_params.get("urmom").?, "fat"));
        try testing.expectEqual(true, url.path_segments.len == 1);
    }
    {
        // root and empty query
        var url = try Url.parse(testing.allocator, "/?");
        defer url.deinit();
        try testing.expectEqualStrings("/?", url.raw);
        try testing.expectEqualStrings("/", url.path);
        try testing.expectEqualStrings("", url.query);
        try testing.expectEqual(true, url.query_params.count() == 0);
        try testing.expectEqual(true, url.path_segments.len == 0);
    }
    {
        // path and empty query
        var url = try Url.parse(testing.allocator, "/abc?");
        defer url.deinit();
        try testing.expectEqualStrings("/abc?", url.raw);
        try testing.expectEqualStrings("/abc", url.path);
        try testing.expectEqualStrings("", url.query);
        try testing.expectEqual(true, url.query_params.count() == 0);
        try testing.expectEqual(true, url.path_segments.len == 1);
    }
    {
        // escaped full url
        var url = try Url.parse(testing.allocator, "/blue+light%20blue?blue%2Blight+blue=you");
        defer url.deinit();
        try testing.expectEqualStrings("/blue+light%20blue?blue%2Blight+blue=you", url.raw);
        try testing.expectEqualStrings("/blue+light blue", url.path);
        try testing.expectEqualStrings("blue+light blue=you", url.query);
        try testing.expectEqual(true, std.mem.eql(u8, url.query_params.get("blue+light blue").?, "you"));
        try testing.expectEqual(true, url.path_segments.len == 1);
    }
    {
        // escaped full url with only param query param
        var url = try Url.parse(testing.allocator, "/blue+light%20blue?blue%2Blight+blue");
        defer url.deinit();
        try testing.expectEqualStrings("/blue+light%20blue?blue%2Blight+blue", url.raw);
        try testing.expectEqualStrings("/blue+light blue", url.path);
        try testing.expectEqualStrings("blue+light blue", url.query);
        try testing.expectEqual(true, std.mem.eql(u8, url.query_params.get("blue+light blue").?, ""));
        try testing.expectEqual(true, url.path_segments.len == 1);
    }
}

test "url: unescape" {
    {
        // Invalid URL
        try testing.expectError(error.InvalidEscapeSequence, Url.unescape(testing.allocator, "%", .Path));
    }
    {
        // Invalid escape sequence at end
        const input = "hello%2";
        try testing.expectError(error.InvalidEscapeSequence, Url.unescape(testing.allocator, input, .Path));
    }
    {
        // Invalid and valid
        const input = "valid%20escape%2invalid";
        try testing.expectError(error.InvalidEscapeSequence, Url.unescape(testing.allocator, input, .Path));
    }
    {
        // Invalid unicode
        const input = "valid%H0escape%2invalid";
        try testing.expectError(error.InvalidEscapeSequence, Url.unescape(testing.allocator, input, .Path));
    }
    {
        // No modification needed
        const input = "hello world";
        var allocator = testing.allocator;
        const result = try Url.unescape(allocator, input, .Path);

        try testing.expectEqualStrings(input, result);

        allocator.free(result);
    }
    {
        // Unicode escapes
        const escaped_str = "Hello+G%C3%BCnter";
        const unescaped_str = "Hello Günter";
        var allocator = testing.allocator;
        const res = try Url.unescape(allocator, escaped_str, .Query);

        try testing.expectEqualStrings(unescaped_str, res);
        allocator.free(res);
    }
    {
        // Unicode escapes and + symbol in path
        const escaped_str = "Hello+G%C3%BCnter";
        const unescaped_str = "Hello+Günter";
        var allocator = testing.allocator;
        const res = try Url.unescape(allocator, escaped_str, .Path);

        try testing.expectEqualStrings(unescaped_str, res);
        allocator.free(res);
    }
    {
        const input = "%F0%9F%98%80 smile";
        var allocator = testing.allocator;
        const result = try Url.unescape(allocator, input, .Path);

        try testing.expectEqualStrings("😀 smile", result);
        allocator.free(result);
    }
}
