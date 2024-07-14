const std = @import("std");

const MAX_EVENTS = 1024;

const EventType = enum { Read, Write };

const Callback = struct {
    context: *anyopaque,
    func: *const fn (*anyopaque, std.posix.fd_t) void,
};

const Event = struct {
    fd: std.posix.fd_t,
    type: EventType,
    callback: Callback,
};

pub const EventLoop = struct {
    events: std.ArrayList(Event),
    poll_fds: std.ArrayList(std.posix.pollfd),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .events = std.ArrayList(Event).init(allocator),
            .poll_fds = std.ArrayList(std.posix.pollfd).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit();
        self.poll_fds.deinit();
    }

    pub fn register_event(self: *Self, fd: std.posix.fd_t, event_type: EventType, context: anytype, comptime callback: fn (@TypeOf(context), std.posix.fd_t) void) !void {
        const cb = Callback{
            .context = context,
            .func = @ptrCast(&callback),
        };

        try self.events.append(.{ .fd = fd, .type = event_type, .callback = cb });
        try self.poll_fds.append(.{
            .fd = fd,
            .events = if (event_type == .Read) std.posix.POLL.IN else std.posix.POLL.OUT,
            .revents = 0,
        });
    }

    pub fn run(self: *Self) !void {
        while (true) {
            const timeout = -1;
            const ready = try std.posix.poll(self.poll_fds.items, timeout);
            if (ready == 0) continue;

            for (0.., self.poll_fds.items) |i, pollfd| {
                if (pollfd.revents == 0) continue;

                // Okay since you *should* have the same number of events as poll_fds
                const event = self.events.items[i];
                if ((pollfd.revents & std.posix.POLL.IN) != 0 and event.type == .Read) {
                    event.callback.func(event.callback.context, event.fd);
                } else if ((pollfd.revents & std.posix.POLL.OUT) != 0 and event.type == .Write) {
                    event.callback.func(event.callback.context, event.fd);
                }
            }
        }
    }
};
