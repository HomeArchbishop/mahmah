const std = @import("std");
const ids = @import("../shared/ids.zig");
const room_mod = @import("room.zig");
const Room = room_mod.Room;

/// 管理进行中的对局 Room（每人一张 Desk）。等候组队在 lobby.Table。
pub const RoomManager = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    rooms: std.AutoHashMap(ids.RoomId, Room),
    mutex: std.Io.Mutex = .init,
    running: std.atomic.Value(bool) = .init(false),
    timer_thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) RoomManager {
        return .{
            .allocator = allocator,
            .io = io,
            .rooms = .init(allocator),
        };
    }

    pub fn deinit(self: *RoomManager) void {
        self.stopTimer();
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        var it = self.rooms.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.rooms.deinit();
    }

    pub fn startTimer(self: *RoomManager) !void {
        if (self.timer_thread != null) return;
        self.running.store(true, .release);
        self.timer_thread = try std.Thread.spawn(.{}, timerMain, .{self});
    }

    pub fn stopTimer(self: *RoomManager) void {
        self.running.store(false, .release);
        if (self.timer_thread) |t| {
            t.join();
            self.timer_thread = null;
        }
    }

    pub fn get(self: *RoomManager, room_id: ids.RoomId) ?*Room {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.rooms.getPtr(room_id);
    }

    /// 该 player 是否已在本局名单中（/ws/room 升级前的 403 检查）
    pub fn isPlayerAllowed(self: *RoomManager, room_id: ids.RoomId, player_id: ids.PlayerId) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const room = self.rooms.getPtr(room_id) orelse return false;
        return room.contains(player_id);
    }

    /// lobby start_game 成功后：建 Room，挂 bot；齐人则 desk.beginGame。
    pub fn openGame(self: *RoomManager, room_id: ids.RoomId, players: *const [room_mod.CAPACITY]ids.PlayerId) !void {
        self.mutex.lockUncancelable(self.io);
        if (self.rooms.contains(room_id)) {
            self.mutex.unlock(self.io);
            return error.Conflict;
        }
        const room = Room.init(self.allocator, self.io, room_id, players);
        try self.rooms.put(room_id, room);
        const ptr = self.rooms.getPtr(room_id).?;
        self.mutex.unlock(self.io);

        ptr.attachBotsAndStartIfReady() catch |err| {
            self.mutex.lockUncancelable(self.io);
            if (self.rooms.fetchRemove(room_id)) |entry| {
                var r = entry.value;
                r.deinit();
            }
            self.mutex.unlock(self.io);
            return err;
        };
    }

    fn timerMain(self: *RoomManager) void {
        while (self.running.load(.acquire)) {
            self.io.sleep(.fromMilliseconds(50), .awake) catch {};
            self.pollAllTimeouts();
        }
    }

    fn pollAllTimeouts(self: *RoomManager) void {
        const now_ms = monoMillis(self.io);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        var it = self.rooms.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.pollTimeouts(now_ms) catch {};
        }
    }
};

fn monoMillis(io: std.Io) i64 {
    return std.Io.Clock.awake.now(io).toMilliseconds();
}
