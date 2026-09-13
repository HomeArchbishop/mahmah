const std = @import("std");
const Sender = @import("../shared/sender.zig").Sender;
const ids = @import("../shared/ids.zig");
const RoomManager = @import("../room/room_manager.zig").RoomManager;
const room_mod = @import("../room/room.zig");
const table_mod = @import("table.zig");
const Table = table_mod.Table;
const protocol = @import("protocol.zig");

comptime {
    if (table_mod.CAPACITY != room_mod.CAPACITY) {
        @compileError("lobby table capacity must match game room capacity");
    }
}

pub const Lobby = struct {
    allocator: std.mem.Allocator,
    room_manager: *RoomManager,
    room_id_gen: *ids.RoomIdGen,
    player_id_gen: *ids.PlayerIdGen,
    connections: std.AutoHashMap(ids.ConnId, Sender),
    players: std.AutoHashMap(ids.PlayerId, ids.ConnId),
    tables: std.AutoHashMap(ids.RoomId, Table),
    /// Human currently seated at a waiting table.
    player_table: std.AutoHashMap(ids.PlayerId, ids.RoomId),

    pub fn init(
        allocator: std.mem.Allocator,
        room_manager: *RoomManager,
        room_id_gen: *ids.RoomIdGen,
        player_id_gen: *ids.PlayerIdGen,
    ) Lobby {
        return .{
            .allocator = allocator,
            .room_manager = room_manager,
            .room_id_gen = room_id_gen,
            .player_id_gen = player_id_gen,
            .connections = .init(allocator),
            .players = .init(allocator),
            .tables = .init(allocator),
            .player_table = .init(allocator),
        };
    }

    pub fn deinit(self: *Lobby) void {
        self.connections.deinit();
        self.players.deinit();
        self.tables.deinit();
        self.player_table.deinit();
    }

    pub fn onConnect(self: *Lobby, player_id: ids.PlayerId, conn_id: ids.ConnId, sender: Sender) !void {
        try self.connections.put(conn_id, sender);
        try self.players.put(player_id, conn_id);
        try self.sendWelcome(sender, player_id);
    }

    pub fn onMessage(self: *Lobby, player_id: ids.PlayerId, conn_id: ids.ConnId, data: []const u8) !void {
        const sender = self.connections.get(conn_id) orelse return;
        const request = protocol.parse(self.allocator, data) catch {
            if (protocol.peekRequestId(self.allocator, data)) |request_id| {
                return self.sendErr(sender, request_id, .bad_request);
            }
            return;
        };

        switch (request) {
            .ping => try self.sendPong(sender),
            .create_room => |r| try self.handleCreateRoom(player_id, sender, r.request_id),
            .join_room => |r| try self.handleJoinRoom(player_id, sender, r.request_id, r.room_id),
            .add_bot => |r| try self.handleAddBot(player_id, sender, r.request_id, r.room_id),
            .remove_bot => |r| try self.handleRemoveBot(player_id, sender, r.request_id, r.room_id, r.player_id),
            .start_game => |r| try self.handleStartGame(player_id, sender, r.request_id, r.room_id),
        }
    }

    pub fn onDisconnect(self: *Lobby, player_id: ids.PlayerId, conn_id: ids.ConnId) !void {
        _ = self.connections.remove(conn_id);
        if (self.players.get(player_id)) |current| {
            if (current == conn_id) {
                _ = self.players.remove(player_id);
                self.leaveWaitingTable(player_id);
            }
        }
    }

    fn handleCreateRoom(self: *Lobby, player_id: ids.PlayerId, sender: Sender, request_id: u32) !void {
        if (self.player_table.contains(player_id)) {
            return self.sendErr(sender, request_id, .conflict);
        }
        const room_id = self.room_id_gen.next();
        try self.tables.put(room_id, Table.init(room_id, player_id));
        errdefer _ = self.tables.remove(room_id);
        try self.player_table.put(player_id, room_id);
        try self.sendRoomCreated(sender, request_id, room_id);
    }

    fn handleJoinRoom(self: *Lobby, player_id: ids.PlayerId, sender: Sender, request_id: u32, room_id: ids.RoomId) !void {
        if (self.player_table.contains(player_id)) {
            return self.sendErr(sender, request_id, .conflict);
        }
        const table = self.tables.getPtr(room_id) orelse {
            return self.sendErr(sender, request_id, .not_found);
        };
        table.join(player_id) catch |err| {
            return self.sendErr(sender, request_id, mapErr(err));
        };
        try self.player_table.put(player_id, room_id);
        try self.sendRoomJoined(sender, request_id, room_id);
    }

    fn handleAddBot(self: *Lobby, player_id: ids.PlayerId, sender: Sender, request_id: u32, room_id: ids.RoomId) !void {
        const table = self.tables.getPtr(room_id) orelse {
            return self.sendErr(sender, request_id, .not_found);
        };
        const bot_id = self.player_id_gen.nextBot();
        table.addBot(player_id, bot_id) catch |err| {
            return self.sendErr(sender, request_id, mapErr(err));
        };
        try self.sendBotAdded(sender, request_id, room_id, bot_id);
    }

    fn handleRemoveBot(
        self: *Lobby,
        player_id: ids.PlayerId,
        sender: Sender,
        request_id: u32,
        room_id: ids.RoomId,
        bot_id: ids.PlayerId,
    ) !void {
        const table = self.tables.getPtr(room_id) orelse {
            return self.sendErr(sender, request_id, .not_found);
        };
        table.removeBot(player_id, bot_id) catch |err| {
            return self.sendErr(sender, request_id, mapErr(err));
        };
        try self.sendBotRemoved(sender, request_id, room_id, bot_id);
    }

    fn handleStartGame(self: *Lobby, player_id: ids.PlayerId, sender: Sender, request_id: u32, room_id: ids.RoomId) !void {
        const table = self.tables.getPtr(room_id) orelse {
            return self.sendErr(sender, request_id, .not_found);
        };
        table.markStarted(player_id) catch |err| {
            return self.sendErr(sender, request_id, mapErr(err));
        };

        var members: [table_mod.CAPACITY]ids.PlayerId = undefined;
        const list = table.copyMembers(&members);
        std.debug.assert(list.len == table_mod.CAPACITY);

        self.room_manager.openGame(room_id, &members) catch |err| {
            table.started = false;
            return self.sendErr(sender, request_id, mapErr(err));
        };

        try self.sendGameStarted(sender, request_id, room_id);
        try self.broadcastGameStarted(&members, player_id, room_id);
        self.finishTable(room_id);
    }

    fn broadcastGameStarted(
        self: *Lobby,
        members: *const [table_mod.CAPACITY]ids.PlayerId,
        except_player_id: ids.PlayerId,
        room_id: ids.RoomId,
    ) !void {
        for (members.*) |member_id| {
            if (member_id == except_player_id or ids.isBot(member_id)) continue;
            const conn_id = self.players.get(member_id) orelse continue;
            const peer = self.connections.get(conn_id) orelse continue;
            try self.sendGameStartedPush(peer, room_id);
        }
    }

    fn leaveWaitingTable(self: *Lobby, player_id: ids.PlayerId) void {
        const room_id = self.player_table.get(player_id) orelse return;
        const table = self.tables.getPtr(room_id) orelse {
            _ = self.player_table.remove(player_id);
            return;
        };
        if (table.started) return;

        table.leave(player_id);
        _ = self.player_table.remove(player_id);
        if (!table.hasHumans()) self.destroyTable(room_id);
    }

    fn finishTable(self: *Lobby, room_id: ids.RoomId) void {
        self.destroyTable(room_id);
    }

    fn destroyTable(self: *Lobby, room_id: ids.RoomId) void {
        const removed = self.tables.fetchRemove(room_id) orelse return;
        var members: [table_mod.CAPACITY]ids.PlayerId = undefined;
        for (removed.value.copyMembers(&members)) |member_id| {
            if (!ids.isBot(member_id)) {
                _ = self.player_table.remove(member_id);
            }
        }
    }

    fn mapErr(err: anyerror) protocol.ErrorCode {
        return switch (err) {
            error.NotFound => .not_found,
            error.Forbidden => .forbidden,
            error.Conflict => .conflict,
            error.Full => .full,
            error.NotBot => .not_bot,
            error.NotReady => .not_ready,
            error.AlreadyStarted => .already_started,
            else => .bad_request,
        };
    }

    fn sendWelcome(_: *Lobby, sender: Sender, player_id: ids.PlayerId) !void {
        var buf: [96]u8 = undefined;
        try sender.send(try protocol.writeWelcome(&buf, player_id));
    }

    fn sendPong(_: *Lobby, sender: Sender) !void {
        var buf: [32]u8 = undefined;
        try sender.send(try protocol.writePong(&buf));
    }

    fn sendRoomCreated(_: *Lobby, sender: Sender, request_id: u32, room_id: ids.RoomId) !void {
        var buf: [128]u8 = undefined;
        try sender.send(try protocol.writeRoomCreated(&buf, request_id, room_id));
    }

    fn sendRoomJoined(_: *Lobby, sender: Sender, request_id: u32, room_id: ids.RoomId) !void {
        var buf: [128]u8 = undefined;
        try sender.send(try protocol.writeRoomJoined(&buf, request_id, room_id));
    }

    fn sendBotAdded(_: *Lobby, sender: Sender, request_id: u32, room_id: ids.RoomId, bot_id: ids.PlayerId) !void {
        var buf: [160]u8 = undefined;
        try sender.send(try protocol.writeBotAdded(&buf, request_id, room_id, bot_id));
    }

    fn sendBotRemoved(_: *Lobby, sender: Sender, request_id: u32, room_id: ids.RoomId, bot_id: ids.PlayerId) !void {
        var buf: [160]u8 = undefined;
        try sender.send(try protocol.writeBotRemoved(&buf, request_id, room_id, bot_id));
    }

    fn sendGameStarted(_: *Lobby, sender: Sender, request_id: u32, room_id: ids.RoomId) !void {
        var buf: [128]u8 = undefined;
        try sender.send(try protocol.writeGameStarted(&buf, request_id, room_id));
    }

    fn sendGameStartedPush(_: *Lobby, sender: Sender, room_id: ids.RoomId) !void {
        var buf: [96]u8 = undefined;
        try sender.send(try protocol.writeGameStartedPush(&buf, room_id));
    }

    fn sendErr(_: *Lobby, sender: Sender, request_id: u32, code: protocol.ErrorCode) !void {
        var buf: [128]u8 = undefined;
        try sender.send(try protocol.writeErr(&buf, request_id, code));
    }
};
