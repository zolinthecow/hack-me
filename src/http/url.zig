// https://www.talisman.org/~erlkonig/misc/lunatech%5Ewhat-every-webdev-must-know-about-url-encoding/
// Urls are a lot more complex than I thought

const std = @import("std");

pub const Url = struct {
    raw: []const u8 = "",
    path: []const u8 = "",
    path_segments: []PathSegment = undefined,
    query: []const u8 = "",
    query_params: ?std.StringHashMap([]const u8),
    fragment: []const u8 = "",

    const UrlParts = enum { Path, Query, Fragment };

    const PathSegment = struct {
        name: []const u8,
        params: ?std.StringHashMap([]const u8),
    };

    pub fn parse(raw: []const u8) !Url {
        var path: []const u8 = "";
        var query: []const u8 = "";
        var fragment: []const u8 = "";

        var part_processing: UrlParts = .Path;
        for (0.., raw) |i, char| {
            switch (part_processing) {
                .Path => {
                    if (char == '?') {
                        if (i == 0) {
                            return error.InvalidUrl;
                        }
                        path = raw[0..i];
                        query = raw[i + 1 ..];
                        part_processing = .Query;
                        break;
                    }
                },
                .Query => {
                    if (char == '#') {
                        query = query[0 .. i - path.len - 1];
                        fragment = raw[i + 1 ..];
                        part_processing = .Fragment;
                        break;
                    }
                },
                .Fragment => {},
            }
        }

        return .{
            .raw = raw,
            .path = path,
            .path_segments = undefined,
            .query = query,
            .query_params = undefined,
            .fragment = fragment,
        };
    }

    const UnescapedResult = struct {
        value: []const u8,
        allocator: ?std.mem.Allocator = null,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            if (self.allocator) |alloc| {
                alloc.free(self.value);
            }
        }
    };

    // As defined by RFC 3983 you URL encoded characters are now UTF-8 which means
    // they can now be multi-byte characters
    fn unescape(allocator: std.mem.Allocator, input: []const u8, segment: UrlParts) !UnescapedResult {
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
                break;
            } else {
                i += 1;
            }
        }

        // Try not to do unnecessary allocations
        if (!needs_modification) {
            return .{ .value = input };
        }

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
        std.debug.print("Got past unicode {s}\n", .{input});

        // Make sure its all valid UTF-8
        _ = std.unicode.Utf8View.init(raw_bytes.items) catch {
            return error.InvalidUtf8;
        };

        const owned_slice = try raw_bytes.toOwnedSlice();
        return .{
            .value = owned_slice,
            .allocator = allocator,
        };
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
        const url = try Url.parse("/");
        try testing.expectEqualStrings("/", url.raw);
        try testing.expectEqualStrings("/", url.path);
        try testing.expectEqualStrings("", url.query);
    }
    {
        // random /'s
        const url = try Url.parse("/abc/de/f");
        try testing.expectEqualStrings("/abc/de/f", url.raw);
        try testing.expectEqualStrings("/abc/de/f", url.path);
        try testing.expectEqualStrings("", url.query);
    }
    {
        // root with query
        const url = try Url.parse("/?urmom=fat");
        try testing.expectEqualStrings("/?urmom=fat", url.raw);
        try testing.expectEqualStrings("/", url.path);
        try testing.expectEqualStrings("urmom=fat", url.query);
    }
    {
        // path and query
        const url = try Url.parse("/abc?urmom=fat");
        try testing.expectEqualStrings("/abc?urmom=fat", url.raw);
        try testing.expectEqualStrings("/abc", url.path);
        try testing.expectEqualStrings("urmom=fat", url.query);
    }
    {
        // root and empty query
        const url = try Url.parse("/?");
        try testing.expectEqualStrings("/?", url.raw);
        try testing.expectEqualStrings("/", url.path);
        try testing.expectEqualStrings("", url.query);
    }
    {
        // path and empty query
        const url = try Url.parse("/abc?");
        try testing.expectEqualStrings("/abc?", url.raw);
        try testing.expectEqualStrings("/abc", url.path);
        try testing.expectEqualStrings("", url.query);
    }
}

test "url: unescape" {
    {
        // Invalid URL
        const input = "%";
        try testing.expectError(error.InvalidEscapeSequence, Url.unescape(testing.allocator, input, .Path));
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
        var result = try Url.unescape(testing.allocator, input, .Path);
        defer result.deinit();

        try testing.expectEqualStrings(input, result.value);
        try testing.expect(result.allocator == null);
    }
    {
        // Unicode escapes
        const escaped_str = "Hello+G%C3%BCnter";
        const unescaped_str = "Hello Günter";
        var res = try Url.unescape(testing.allocator, escaped_str, .Query);
        defer res.deinit();

        try testing.expectEqualStrings(unescaped_str, res.value);
        try testing.expect(res.allocator != null);
    }
    {
        // Unicode escapes and + symbol in path
        const escaped_str = "Hello+G%C3%BCnter";
        const unescaped_str = "Hello+Günter";
        var res = try Url.unescape(testing.allocator, escaped_str, .Path);
        defer res.deinit();

        try testing.expectEqualStrings(unescaped_str, res.value);
        try testing.expect(res.allocator != null);
    }
    {
        const input = "%F0%9F%98%80 smile";
        var result = try Url.unescape(testing.allocator, input, .Path);
        defer result.deinit();

        try testing.expectEqualStrings("😀 smile", result.value);
        try testing.expect(result.allocator != null);
    }
}
