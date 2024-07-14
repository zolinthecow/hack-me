const std = @import("std");

const Url = @import("url.zig").Url;

// this approach to matching method name comes from zhp
const GET_ = @as(u32, @bitCast([4]u8{ 'G', 'E', 'T', ' ' }));
const PUT_ = @as(u32, @bitCast([4]u8{ 'P', 'U', 'T', ' ' }));
const POST = @as(u32, @bitCast([4]u8{ 'P', 'O', 'S', 'T' }));
const HEAD = @as(u32, @bitCast([4]u8{ 'H', 'E', 'A', 'D' }));
const PATC = @as(u32, @bitCast([4]u8{ 'P', 'A', 'T', 'C' }));
const DELE = @as(u32, @bitCast([4]u8{ 'D', 'E', 'L', 'E' }));

pub const Request = struct {
    url: Url,
};
