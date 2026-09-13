const std = @import("std");
const ids = @import("../shared/ids.zig");
const Lobby = @import("../lobby/lobby.zig").Lobby;
const RoomManager = @import("../room/room_manager.zig").RoomManager;

pub const ConnKind = union(enum) {
    lobby,
    room: u64,
};

pub const Context = struct {
    player_id: ids.PlayerId,
    conn_id: ids.ConnId,
    kind: ConnKind,
    lobby: *Lobby,
    room_manager: *RoomManager,
    allocator: std.mem.Allocator,
};
