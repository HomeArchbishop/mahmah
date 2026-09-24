const std = @import("std");
const ids = @import("../shared/ids.zig");

/// Wire-level lobby messages. No business rules here.
pub const ErrorCode = enum {
    bad_request,
    not_found,
    forbidden,
    conflict,
    full,
    not_bot,
    not_ready,
    already_started,

    pub fn str(self: ErrorCode) []const u8 {
        return switch (self) {
            .bad_request => "bad_request",
            .not_found => "not_found",
            .forbidden => "forbidden",
            .conflict => "conflict",
            .full => "full",
            .not_bot => "not_bot",
            .not_ready => "not_ready",
            .already_started => "already_started",
        };
    }
};

pub const Request = union(enum) {
    ping,
    create_room: struct { request_id: u32 },
    join_room: struct { request_id: u32, room_id: ids.RoomId },
    add_bot: struct { request_id: u32, room_id: ids.RoomId },
    remove_bot: struct { request_id: u32, room_id: ids.RoomId, player_id: ids.PlayerId },
    start_game: struct { request_id: u32, room_id: ids.RoomId },
};

const Envelope = struct {
    type: []const u8,
    request_id: ?u32 = null,
    room_id: ?ids.RoomId = null,
    player_id: ?ids.PlayerId = null,
};

pub fn parse(allocator: std.mem.Allocator, data: []const u8) !Request {
    const parsed = try std.json.parseFromSlice(Envelope, allocator, data, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_if_needed,
    });
    defer parsed.deinit();
    const env = parsed.value;

    if (std.mem.eql(u8, env.type, "ping")) return .ping;

    const request_id = env.request_id orelse return error.BadRequest;

    if (std.mem.eql(u8, env.type, "create_room")) {
        return .{ .create_room = .{ .request_id = request_id } };
    }
    if (std.mem.eql(u8, env.type, "join_room")) {
        const room_id = env.room_id orelse return error.BadRequest;
        return .{ .join_room = .{ .request_id = request_id, .room_id = room_id } };
    }
    if (std.mem.eql(u8, env.type, "add_bot")) {
        const room_id = env.room_id orelse return error.BadRequest;
        return .{ .add_bot = .{ .request_id = request_id, .room_id = room_id } };
    }
    if (std.mem.eql(u8, env.type, "remove_bot")) {
        const room_id = env.room_id orelse return error.BadRequest;
        const player_id = env.player_id orelse return error.BadRequest;
        return .{ .remove_bot = .{ .request_id = request_id, .room_id = room_id, .player_id = player_id } };
    }
    if (std.mem.eql(u8, env.type, "start_game")) {
        const room_id = env.room_id orelse return error.BadRequest;
        return .{ .start_game = .{ .request_id = request_id, .room_id = room_id } };
    }
    return error.BadRequest;
}

pub fn peekRequestId(allocator: std.mem.Allocator, data: []const u8) ?u32 {
    const parsed = std.json.parseFromSlice(Envelope, allocator, data, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_if_needed,
    }) catch return null;
    defer parsed.deinit();
    return parsed.value.request_id;
}

pub fn writeWelcome(buf: []u8, player_id: ids.PlayerId) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"welcome\",\"player_id\":{d}}}", .{player_id});
}

pub fn writePong(buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"pong\"}}", .{});
}

pub fn writeRoomCreated(buf: []u8, request_id: u32, room_id: ids.RoomId, is_host: bool) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"room_created\",\"request_id\":{d},\"room_id\":{d},\"is_host\":{s}}}", .{
        request_id, room_id, if (is_host) "true" else "false",
    });
}

pub fn writeRoomJoined(buf: []u8, request_id: u32, room_id: ids.RoomId, is_host: bool) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"room_joined\",\"request_id\":{d},\"room_id\":{d},\"is_host\":{s}}}", .{
        request_id, room_id, if (is_host) "true" else "false",
    });
}

pub fn writeMemberJoined(buf: []u8, room_id: ids.RoomId, player_id: ids.PlayerId, is_host: bool) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"member_joined\",\"room_id\":{d},\"player_id\":{d},\"is_host\":{s}}}", .{
        room_id, player_id, if (is_host) "true" else "false",
    });
}

pub fn writeMemberLeft(buf: []u8, room_id: ids.RoomId, player_id: ids.PlayerId, is_host: bool) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"member_left\",\"room_id\":{d},\"player_id\":{d},\"is_host\":{s}}}", .{
        room_id, player_id, if (is_host) "true" else "false",
    });
}

pub fn writeBotAdded(buf: []u8, request_id: u32, room_id: ids.RoomId, player_id: ids.PlayerId) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"bot_added\",\"request_id\":{d},\"room_id\":{d},\"player_id\":{d}}}", .{ request_id, room_id, player_id });
}

pub fn writeBotRemoved(buf: []u8, request_id: u32, room_id: ids.RoomId, player_id: ids.PlayerId) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"bot_removed\",\"request_id\":{d},\"room_id\":{d},\"player_id\":{d}}}", .{ request_id, room_id, player_id });
}

pub fn writeGameStarted(buf: []u8, request_id: u32, room_id: ids.RoomId) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"game_started\",\"request_id\":{d},\"room_id\":{d}}}", .{ request_id, room_id });
}

pub fn writeGameStartedPush(buf: []u8, room_id: ids.RoomId) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"game_started\",\"room_id\":{d}}}", .{room_id});
}

pub fn writeErr(buf: []u8, request_id: u32, code: ErrorCode) ![]const u8 {
    return std.fmt.bufPrint(buf, "{{\"type\":\"err\",\"request_id\":{d},\"code\":\"{s}\"}}", .{ request_id, code.str() });
}
