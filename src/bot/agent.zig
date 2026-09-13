const std = @import("std");
const ids = @import("../shared/ids.zig");
const Sender = @import("../shared/sender.zig").Sender;

/// 进程内 stub bot：实现 Sender；回包由 Room.flushBotReplies 取出。
pub const BotAgent = struct {
    allocator: std.mem.Allocator,
    player_id: ids.PlayerId,
    pending_reply: ?[]u8 = null,

    pub fn create(allocator: std.mem.Allocator, player_id: ids.PlayerId) !*BotAgent {
        const self = try allocator.create(BotAgent);
        self.* = .{
            .allocator = allocator,
            .player_id = player_id,
        };
        return self;
    }

    pub fn destroy(self: *BotAgent) void {
        if (self.pending_reply) |p| self.allocator.free(p);
        self.allocator.destroy(self);
    }

    pub fn sender(self: *BotAgent) Sender {
        return .{ .ptr = self, .send_fn = sendImpl };
    }

    pub fn takePending(self: *BotAgent) ?[]u8 {
        const p = self.pending_reply orelse return null;
        self.pending_reply = null;
        return p;
    }

    fn sendImpl(ptr: *anyopaque, data: []const u8) anyerror!void {
        const self: *BotAgent = @ptrCast(@alignCast(ptr));
        try self.onServerMessage(data);
    }

    fn onServerMessage(self: *BotAgent, data: []const u8) !void {
        const parsed = try std.json.parseFromSlice(Inbound, self.allocator, data, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_if_needed,
        });
        defer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.type, "request_action")) return;
        const request_id = parsed.value.request_id orelse return;
        const actions = parsed.value.possible_actions orelse return;
        const reply = try buildReply(self.allocator, request_id, actions) orelse return;
        if (self.pending_reply) |old| self.allocator.free(old);
        self.pending_reply = reply;
    }
};

const Inbound = struct {
    type: []const u8,
    request_id: ?u32 = null,
    possible_actions: ?[]ActionJson = null,
};

const ActionJson = struct {
    type: []const u8,
    pai: ?[]const u8 = null,
    tsumogiri: ?bool = null,
};

fn buildReply(allocator: std.mem.Allocator, request_id: u32, actions: []ActionJson) !?[]u8 {
    var chosen: ?ActionJson = null;
    for (actions) |a| {
        if (std.mem.eql(u8, a.type, "dahai")) {
            if (a.tsumogiri == true) {
                chosen = a;
                break;
            }
            if (chosen == null) chosen = a;
        }
    }
    if (chosen == null) {
        for (actions) |a| {
            if (std.mem.eql(u8, a.type, "none")) {
                chosen = a;
                break;
            }
        }
    }
    const a = chosen orelse return null;
    if (std.mem.eql(u8, a.type, "dahai")) {
        const pai = a.pai orelse return null;
        if (a.tsumogiri == true) {
            return try std.fmt.allocPrint(allocator, "{{\"type\":\"dahai\",\"pai\":\"{s}\",\"tsumogiri\":true,\"request_id\":{d}}}", .{ pai, request_id });
        }
        return try std.fmt.allocPrint(allocator, "{{\"type\":\"dahai\",\"pai\":\"{s}\",\"request_id\":{d}}}", .{ pai, request_id });
    }
    if (std.mem.eql(u8, a.type, "none")) {
        return try std.fmt.allocPrint(allocator, "{{\"type\":\"none\",\"request_id\":{d}}}", .{request_id});
    }
    return null;
}
