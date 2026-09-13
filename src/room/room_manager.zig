const std = @import("std");
const ids = @import("../shared/ids.zig");
const room_mod = @import("room.zig");
const Room = room_mod.Room;

/// 管理进行中的对局 Room（每人一张 Desk）。等候组队在 lobby.Table。
pub const RoomManager = struct {
    allocator: std.mem.Allocator,
    rooms: std.AutoHashMap(ids.RoomId, Room),

    pub fn init(allocator: std.mem.Allocator) RoomManager {
        return .{
            .allocator = allocator,
            .rooms = .init(allocator),
        };
    }

    pub fn deinit(self: *RoomManager) void {
        var it = self.rooms.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.rooms.deinit();
    }

    pub fn get(self: *RoomManager, room_id: ids.RoomId) ?*Room {
        return self.rooms.getPtr(room_id);
    }

    /// 该 player 是否已在本局名单中（/ws/room 升级前的 403 检查）
    pub fn isPlayerAllowed(self: *RoomManager, room_id: ids.RoomId, player_id: ids.PlayerId) bool {
        const room = self.get(room_id) orelse return false;
        return room.contains(player_id);
    }

    /// lobby start_game 成功后：建 Room，挂 bot；齐人则 desk.beginGame。
    pub fn openGame(self: *RoomManager, room_id: ids.RoomId, players: *const [room_mod.CAPACITY]ids.PlayerId) !void {
        if (self.rooms.contains(room_id)) return error.Conflict;
        const room = Room.init(self.allocator, room_id, players);
        try self.rooms.put(room_id, room);
        const ptr = self.rooms.getPtr(room_id).?;
        errdefer {
            if (self.rooms.fetchRemove(room_id)) |entry| {
                var r = entry.value;
                r.deinit();
            }
        }
        try ptr.attachBotsAndStartIfReady();
    }
};
