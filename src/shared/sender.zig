const std = @import("std");

pub const Sender = struct {
    ptr: *anyopaque,
    send_fn: *const fn (*anyopaque, []const u8) anyerror!void,

    pub fn send(self: Sender, data: []const u8) !void {
        return self.send_fn(self.ptr, data);
    }
};
