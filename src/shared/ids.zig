const std = @import("std");

pub const PlayerId = u64;
pub const RoomId = u64;
pub const ConnId = u64;

const BOT_FLAG: PlayerId = 1 << 63;

pub fn isBot(player_id: PlayerId) bool {
    return player_id & BOT_FLAG != 0;
}

pub const PlayerIdGen = struct {
    real_counter: std.atomic.Value(u64) = .init(1),
    bot_counter: std.atomic.Value(u64) = .init(1),

    pub fn nextReal(self: *PlayerIdGen) PlayerId {
        return self.real_counter.fetchAdd(1, .monotonic);
    }

    pub fn nextBot(self: *PlayerIdGen) PlayerId {
        return self.bot_counter.fetchAdd(1, .monotonic) | BOT_FLAG;
    }
};

pub const ConnIdGen = struct {
    counter: std.atomic.Value(u64) = .init(1),

    pub fn next(self: *ConnIdGen) ConnId {
        return self.counter.fetchAdd(1, .monotonic);
    }
};

pub const RoomIdGen = struct {
    counter: std.atomic.Value(u64) = .init(1),

    pub fn next(self: *RoomIdGen) RoomId {
        return self.counter.fetchAdd(1, .monotonic);
    }
};
