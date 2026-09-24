const std = @import("std");
const ids = @import("../shared/ids.zig");
const Sender = @import("../shared/sender.zig").Sender;
const core = @import("../core/root.zig");
const protocol = @import("protocol.zig");
const bot = @import("../bot/root.zig");

pub const CAPACITY = core.CAPACITY;

const Deadline = struct {
    request_id: u32,
    due_ms: i64,
};

/// 对局 WS 房间：连接表 + MJAI；齐人后 beginGame（engine 自行开局）。
pub const Room = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    id: ids.RoomId,
    players: [CAPACITY]ids.PlayerId,
    desk: core.Desk,
    connections: std.AutoHashMap(ids.PlayerId, Sender),
    bots: std.AutoHashMap(ids.PlayerId, *bot.BotAgent),
    flushing_bot_replies: bool = false,
    catch_up: [CAPACITY]std.ArrayListUnmanaged([]u8) = .{ .empty, .empty, .empty, .empty },
    mutex: std.Io.Mutex = .init,
    /// 每个座位当前 pending 的截止时刻（单调时钟毫秒）。
    deadlines: [CAPACITY]?Deadline = .{ null, null, null, null },

    /// 仅建桌；指针稳定后须 `attachBotsAndStartIfReady`。
    pub fn init(allocator: std.mem.Allocator, io: std.Io, id: ids.RoomId, players: *const [CAPACITY]ids.PlayerId) Room {
        return .{
            .allocator = allocator,
            .io = io,
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
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.attachBotsAndStartIfReadyLocked();
    }

    pub fn contains(self: *const Room, player_id: ids.PlayerId) bool {
        for (self.players) |pid| {
            if (pid == player_id) return true;
        }
        return false;
    }

    pub fn onConnect(self: *Room, player_id: ids.PlayerId, conn_id: ids.ConnId, sender: Sender) !void {
        _ = conn_id;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.bindSender(player_id, sender);
        try self.beginIfAllSeatsConnected();
    }

    pub fn onMessage(self: *Room, player_id: ids.PlayerId, conn_id: ids.ConnId, data: []const u8) !void {
        _ = conn_id;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        try self.handleMessage(player_id, data);
    }

    pub fn onDisconnect(self: *Room, player_id: ids.PlayerId, conn_id: ids.ConnId) !void {
        _ = conn_id;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (ids.isBot(player_id)) return;
        _ = self.connections.remove(player_id);
    }

    /// 定时器线程调用：到期则 desk.onTimeout（摸切 / 过），不经 bot。
    pub fn pollTimeouts(self: *Room, now_ms: i64) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        var due: [CAPACITY]u32 = undefined;
        var n: usize = 0;
        for (&self.deadlines) |*slot| {
            const d = slot.* orelse continue;
            if (now_ms < d.due_ms) continue;
            due[n] = d.request_id;
            n += 1;
            slot.* = null;
        }
        for (due[0..n]) |rid| {
            const outcome = try self.desk.onTimeout(rid, now_ms);
            try self.deliverOutcome(outcome);
        }
    }

    fn attachBotsAndStartIfReadyLocked(self: *Room) !void {
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

    fn handleMessage(self: *Room, player_id: ids.PlayerId, data: []const u8) !void {
        const now_ms = monoMillis(self.io);
        const parsed = protocol.parseAction(self.allocator, data) catch {
            // 解析失败或缺 request_id：丢掉，只回 unparseable ack，pending 不动
            const rid = protocol.peekRequestId(self.allocator, data) orelse 0;
            const outcome = try self.desk.onUnparseable(player_id, rid);
            try self.deliverOutcome(outcome);
            return;
        };
        const outcome = try self.desk.onAction(player_id, parsed.request_id, parsed.action, now_ms);
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

        // 对局牌山：用系统熵作洗牌种子（局间再 +1）
        var seed: u64 = undefined;
        self.io.random(std.mem.asBytes(&seed));
        self.desk.kyoku.shuffle_seed = seed;

        const now_ms = monoMillis(self.io);
        const outcome = try self.desk.beginGame(now_ms);
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
                .action_resolved => |r| {
                    const msg = try protocol.encodeEvent(event, &buf);
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

    /// 把 Outcome 编成 MJAI 发出；末尾消化 bot 待回包，再对齐超时截止。
    fn deliverOutcome(self: *Room, outcome: core.Outcome) !void {
        var buf: [4096]u8 = undefined;
        for (outcome.events) |event| {
            switch (event) {
                .start_game => continue,
                .action_requested => |r| {
                    const msg = try protocol.encodeEventForSeat(event, r.seat, &buf);
                    try self.sendToSeat(r.seat, msg);
                },
                .action_resolved => |r| {
                    const msg = try protocol.encodeEvent(event, &buf);
                    try self.sendToSeat(r.seat, msg);
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
        self.syncDeadlines();
    }

    /// 按 desk 当前 pending 挂 / 清截止；截止 = issued_at + deadline_ms。
    fn syncDeadlines(self: *Room) void {
        var live: [CAPACITY]?struct { rid: u32, due_ms: i64 } = .{ null, null, null, null };
        var refs: [CAPACITY]core.PendingRef = undefined;
        for (self.desk.listPendings(&refs)) |p| {
            live[p.seat] = .{
                .rid = p.request_id,
                .due_ms = p.issued_at_ms + @as(i64, @intCast(p.deadline_ms)),
            };
        }
        for (0..CAPACITY) |seat| {
            if (live[seat]) |info| {
                if (self.deadlines[seat]) |d| {
                    if (d.request_id == info.rid) continue;
                }
                self.deadlines[seat] = .{
                    .request_id = info.rid,
                    .due_ms = info.due_ms,
                };
            } else {
                self.deadlines[seat] = null;
            }
        }
    }

    /// 取出 bot 入队回包并走 handleMessage；嵌套调用直接返回。
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
                try self.handleMessage(agent.player_id, bytes);
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

fn monoMillis(io: std.Io) i64 {
    return std.Io.Clock.awake.now(io).toMilliseconds();
}
