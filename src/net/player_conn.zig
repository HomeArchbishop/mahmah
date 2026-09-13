const std = @import("std");
const ws = @import("websocket");
const Sender = @import("../shared/sender.zig").Sender;
const context = @import("context.zig");
const Context = context.Context;

pub const PlayerConn = struct {
    ctx: *Context,
    conn: *ws.Conn,

    pub fn init(conn: *ws.Conn, ctx: *Context) !PlayerConn {
        return .{ .ctx = ctx, .conn = conn };
    }

    pub fn afterInit(self: *PlayerConn) !void {
        const sender = self.asSender();
        switch (self.ctx.kind) {
            .lobby => try self.ctx.lobby.onConnect(self.ctx.player_id, self.ctx.conn_id, sender),
            .room => |rid| if (self.ctx.room_manager.get(rid)) |room|
                try room.onConnect(self.ctx.player_id, self.ctx.conn_id, sender),
        }
    }

    pub fn clientMessage(self: *PlayerConn, data: []const u8) !void {
        switch (self.ctx.kind) {
            .lobby => try self.ctx.lobby.onMessage(self.ctx.player_id, self.ctx.conn_id, data),
            .room => |rid| if (self.ctx.room_manager.get(rid)) |room|
                try room.onMessage(self.ctx.player_id, self.ctx.conn_id, data),
        }
    }

    pub fn close(self: *PlayerConn) void {
        switch (self.ctx.kind) {
            .lobby => self.ctx.lobby.onDisconnect(self.ctx.player_id, self.ctx.conn_id) catch {},
            .room => |rid| if (self.ctx.room_manager.get(rid)) |room|
                room.onDisconnect(self.ctx.player_id, self.ctx.conn_id) catch {},
        }
        self.ctx.allocator.destroy(self.ctx);
    }

    fn asSender(self: *PlayerConn) Sender {
        return .{ .ptr = self, .send_fn = sendImpl };
    }

    fn sendImpl(ptr: *anyopaque, data: []const u8) !void {
        const self: *PlayerConn = @ptrCast(@alignCast(ptr));
        try self.conn.write(data);
    }
};
