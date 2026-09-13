const std = @import("std");
const ids = @import("../shared/ids.zig");
const Sender = @import("../shared/sender.zig").Sender;
const core = @import("../core/root.zig");
const protocol = @import("protocol.zig");
const bot = @import("../bot/root.zig");

pub const CAPACITY = core.CAPACITY;

/// 对局 WS 房间：连接表 + MJAI；齐人后 beginGame（engine 自行开局）。
pub const Room = struct {
    allocator: std.mem.Allocator,
    id: ids.RoomId,
    players: [CAPACITY]ids.PlayerId,
    desk: core.Desk,
    connections: std.AutoHashMap(ids.PlayerId, Sender),
    bots: std.AutoHashMap(ids.PlayerId, *bot.BotAgent),
    flushing_bot_replies: bool = false,
    catch_up: [CAPACITY]std.ArrayListUnmanaged([]u8) = .{ .empty, .empty, .empty, .empty },

    /// 仅建桌；指针稳定后须 `attachBotsAndStartIfReady`。
    pub fn init(allocator: std.mem.Allocator, id: ids.RoomId, players: *const [CAPACITY]ids.PlayerId) Room {
        return .{
            .allocator = allocator,
            .id = id,
            .players = players.*,
            .desk = core.Desk.init(players),
            .connections = .init(allocator),
            .bots = .init(allocator),
        };
    }

    pub fn deinit(self: *Room) void {
        var bit = self.bots.iterator();
        while (bit.next()) |entry| {
            entry.value_ptr.*.destroy();
        }
        self.bots.deinit();
        for (&self.catch_up) |*lane| {
            for (lane.items) |msg| self.allocator.free(msg);
            lane.deinit(self.allocator);
        }
        self.connections.deinit();
    }

    /// 为 bot 座位挂 Sender；齐人则开局（须在 Room 已入 map 后调用）。
    pub fn attachBotsAndStartIfReady(self: *Room) !void {
        for (self.players) |pid| {
            if (!ids.isBot(pid)) continue;
            if (self.bots.contains(pid)) continue;
            const agent = try bot.BotAgent.create(self.allocator, pid);
            errdefer agent.destroy();
            try self.bots.put(pid, agent);
            try self.bindSender(pid, agent.sender());
        }
        try self.beginIfAllSeatsConnected();
    }

    pub fn contains(self: *const Room, player_id: ids.PlayerId) bool {
        for (self.players) |pid| {
            if (pid == player_id) return true;
        }
        return false;
    }

    pub fn onConnect(self: *Room, player_id: ids.PlayerId, conn_id: ids.ConnId, sender: Sender) !void {
        _ = conn_id;
        try self.bindSender(player_id, sender);
        try self.beginIfAllSeatsConnected();
    }

    pub fn onMessage(self: *Room, player_id: ids.PlayerId, conn_id: ids.ConnId, data: []const u8) !void {
        _ = conn_id;
        const parsed = protocol.parseAction(self.allocator, data) catch {
            if (protocol.peekRequestId(self.allocator, data)) |rid| {
                const outcome = try self.desk.onUnparseable(player_id, rid);
                try self.deliverOutcome(outcome);
            }
            return;
        };
        const outcome = try self.desk.onAction(player_id, parsed.request_id, parsed.action);
        try self.deliverOutcome(outcome);
    }

    pub fn onDisconnect(self: *Room, player_id: ids.PlayerId, conn_id: ids.ConnId) !void {
        _ = conn_id;
        if (ids.isBot(player_id)) return;
        _ = self.connections.remove(player_id);
    }

    pub fn onTimeout(self: *Room, request_id: u32) !void {
        const outcome = try self.desk.onTimeout(request_id);
        try self.deliverOutcome(outcome);
    }

    fn bindSender(self: *Room, player_id: ids.PlayerId, sender: Sender) !void {
        const seat = self.desk.seatOf(player_id) orelse return;
        try self.connections.put(player_id, sender);

        var buf: [128]u8 = undefined;
        try sender.send(try protocol.encodeStartGame(seat, &buf));

        if (self.desk.game_phase != .awaiting_players) {
            for (self.catch_up[seat].items) |msg| {
                try sender.send(msg);
            }
        }
    }

    fn allSeatsConnected(self: *const Room) bool {
        for (self.players) |pid| {
            if (!self.connections.contains(pid)) return false;
        }
        return true;
    }

    fn beginIfAllSeatsConnected(self: *Room) !void {
        if (self.desk.game_phase != .awaiting_players) return;
        if (!self.allSeatsConnected()) return;

        const outcome = try self.desk.beginGame();
        try self.recordCatchUp(outcome);
        try self.deliverOutcome(outcome);
    }

    fn recordCatchUp(self: *Room, outcome: core.Outcome) !void {
        var buf: [4096]u8 = undefined;
        for (outcome.events) |event| {
            switch (event) {
                .start_game => continue,
                .action_requested => |r| {
                    const msg = try protocol.encodeEventForSeat(event, r.seat, &buf);
                    try self.appendCatchUp(r.seat, msg);
                },
                else => {
                    var seat: u8 = 0;
                    while (seat < CAPACITY) : (seat += 1) {
                        const s: core.Seat = @intCast(seat);
                        const msg = try protocol.encodeEventForSeat(event, s, &buf);
                        try self.appendCatchUp(s, msg);
                    }
                },
            }
        }
    }

    fn appendCatchUp(self: *Room, seat: core.Seat, msg: []const u8) !void {
        const owned = try self.allocator.dupe(u8, msg);
        errdefer self.allocator.free(owned);
        try self.catch_up[seat].append(self.allocator, owned);
    }

    /// 把 Outcome 编成 MJAI 发出；末尾消化 bot 待回包。
    fn deliverOutcome(self: *Room, outcome: core.Outcome) !void {
        var buf: [4096]u8 = undefined;
        for (outcome.events) |event| {
            switch (event) {
                .start_game => continue,
                .action_requested => |r| {
                    const msg = try protocol.encodeEventForSeat(event, r.seat, &buf);
                    try self.sendToSeat(r.seat, msg);
                },
                .action_resolved => {
                    const msg = try protocol.encodeEvent(event, &buf);
                    try self.broadcast(msg);
                },
                .start_kyoku, .tsumo, .ryukyoku => {
                    var seat: u8 = 0;
                    while (seat < CAPACITY) : (seat += 1) {
                        const s: core.Seat = @intCast(seat);
                        const msg = try protocol.encodeEventForSeat(event, s, &buf);
                        try self.sendToSeat(s, msg);
                    }
                },
                else => {
                    const msg = try protocol.encodeEvent(event, &buf);
                    try self.broadcast(msg);
                },
            }
        }
        try self.flushBotReplies();
    }

    /// 取出 bot 入队回包并走 onMessage；嵌套调用直接返回。
    fn flushBotReplies(self: *Room) anyerror!void {
        if (self.flushing_bot_replies) return;
        self.flushing_bot_replies = true;
        defer self.flushing_bot_replies = false;

        while (true) {
            var progressed = false;
            var it = self.bots.iterator();
            while (it.next()) |entry| {
                const agent = entry.value_ptr.*;
                const bytes = agent.takePending() orelse continue;
                defer agent.allocator.free(bytes);
                progressed = true;
                try self.onMessage(agent.player_id, 0, bytes);
            }
            if (!progressed) break;
        }
    }

    fn sendToSeat(self: *Room, seat: core.Seat, msg: []const u8) !void {
        const player_id = self.players[seat];
        const sender = self.connections.get(player_id) orelse return;
        try sender.send(msg);
    }

    fn broadcast(self: *Room, msg: []const u8) !void {
        var it = self.connections.iterator();
        while (it.next()) |entry| {
            try entry.value_ptr.send(msg);
        }
    }
};
