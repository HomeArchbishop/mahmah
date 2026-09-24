const std = @import("std");

pub const Sender = struct {
    ptr: *anyopaque,
    send_fn: *const fn (*anyopaque, []const u8) anyerror!void,
    close_fn: ?*const fn (*anyopaque) void = null,

    pub fn send(self: Sender, data: []const u8) !void {
        return self.send_fn(self.ptr, data);
    }

    pub fn close(self: Sender) void {
        if (self.close_fn) |f| f(self.ptr);
    }
};
