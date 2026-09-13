const std = @import("std");
const ids = @import("../shared/ids.zig");
const types = @import("types.zig");
const kyoku_mod = @import("kyoku.zig");
const engine = @import("engine/root.zig");

pub const CAPACITY = types.CAPACITY;

/// 整盘相位（多局之后才 finished）。
pub const GamePhase = enum {
    awaiting_players,
    playing,
    finished,
};

const Pending = struct {
    request_id: u32,
    seat: types.Seat,
};

/// 对局会话门面：GamePhase、pending、拼 Outcome。
pub const Desk = struct {
    players: [CAPACITY]ids.PlayerId,
    kyoku: kyoku_mod.Kyoku,
    game_phase: GamePhase = .awaiting_players,
    next_request_id: u32 = 1,
    pendings: [CAPACITY]?Pending = .{ null, null, null, null },

    event_buf: [64]types.Event = undefined,
    event_len: usize = 0,
    apply_buf: [64]types.Event = undefined,
    seat_buf: [CAPACITY]types.Seat = undefined,
    legal_bufs: [CAPACITY][32]types.Action = undefined,
    legal_lens: [CAPACITY]usize = .{ 0, 0, 0, 0 },
    legal_type_names: [16][]const u8 = undefined,
    legal_type_len: usize = 0,
    reason_buf: [64]u8 = undefined,

    pub fn init(players: *const [CAPACITY]ids.PlayerId) Desk {
        return .{
            .players = players.*,
            .kyoku = .init(),
        };
    }

    pub fn seatOf(self: *const Desk, player_id: ids.PlayerId) ?types.Seat {
        for (self.players, 0..) |pid, i| {
            if (pid == player_id) return @intCast(i);
        }
        return null;
    }

    pub fn beginGame(self: *Desk) !types.Outcome {
        if (self.game_phase != .awaiting_players) return error.InvalidGamePhase;
        self.game_phase = .playing;
        self.clearEvents();
        const produced = engine.onStartGame(&self.kyoku, &self.apply_buf);
        for (produced) |ev| self.push(ev);
        self.pushRequests();
        return self.outcome();
    }

    pub fn onAction(self: *Desk, player_id: ids.PlayerId, request_id: u32, action: types.Action) !types.Outcome {
        self.clearEvents();
        const slot = self.requirePending(request_id) orelse return self.outcome();
        const pending = self.pendings[slot].?;

        const seat = self.seatOf(player_id) orelse {
            return self.reject(slot, pending.seat, request_id, .rejected, action);
        };
        if (seat != pending.seat) {
            return self.reject(slot, pending.seat, request_id, .rejected, action);
        }
        if (!self.isLegal(slot, action)) {
            return self.reject(slot, seat, request_id, .rejected, action);
        }

        const produced = engine.apply(&self.kyoku, seat, action, &self.apply_buf) catch {
            return self.reject(slot, seat, request_id, .rejected, action);
        };
        return self.accept(slot, request_id, .accepted, null, produced);
    }

    pub fn onUnparseable(self: *Desk, player_id: ids.PlayerId, request_id: u32) !types.Outcome {
        self.clearEvents();
        const slot = self.requirePending(request_id) orelse return self.outcome();
        const pending = self.pendings[slot].?;
        const seat = self.seatOf(player_id) orelse pending.seat;
        return self.reject(slot, seat, request_id, .unparseable, null);
    }

    pub fn onTimeout(self: *Desk, request_id: u32) !types.Outcome {
        self.clearEvents();
        const slot = self.requirePending(request_id) orelse return self.outcome();
        const pending = self.pendings[slot].?;

        const action = engine.defaultAction(&self.kyoku, pending.seat) orelse {
            return self.reject(slot, pending.seat, request_id, .rejected, null);
        };
        const produced = engine.apply(&self.kyoku, pending.seat, action, &self.apply_buf) catch {
            return self.reject(slot, pending.seat, request_id, .rejected, null);
        };
        return self.accept(slot, request_id, .defaulted, action, produced);
    }

    /// 返回 pendings 下标；无效则已推 stale。
    fn requirePending(self: *Desk, request_id: u32) ?usize {
        for (self.pendings, 0..) |p, i| {
            if (p) |pending| {
                if (pending.request_id == request_id) return i;
            }
        }
        self.push(.{ .action_resolved = .{ .request_id = request_id, .status = .stale } });
        return null;
    }

    fn accept(
        self: *Desk,
        slot: usize,
        request_id: u32,
        status: types.ResolveStatus,
        defaulted_action: ?types.Action,
        produced: []const types.Event,
    ) types.Outcome {
        const budget = types.TimeBudget{};
        self.pendings[slot] = null;
        self.push(.{ .action_resolved = .{
            .request_id = request_id,
            .status = status,
            .action = if (status == .defaulted) defaulted_action else null,
            .bank_consumed_ms = if (status == .defaulted) budget.bank_ms else 0,
            .bank_ms = if (status == .defaulted) 0 else budget.bank_ms,
        } });
        for (produced) |ev| self.push(ev);
        self.noteEndGame(produced);
        if (self.game_phase == .playing and self.kyoku.phase != .idle) {
            self.pushRequests();
        }
        return self.outcome();
    }

    fn reject(
        self: *Desk,
        slot: usize,
        seat: types.Seat,
        request_id: u32,
        status: types.ResolveStatus,
        attempted: ?types.Action,
    ) types.Outcome {
        self.fillLegalTypes(slot);
        self.clearAllPendings();
        const reason = engine.chomboReason(&self.reason_buf, seat);
        self.push(.{ .action_resolved = .{
            .request_id = request_id,
            .status = status,
            .attempted = attempted,
            .reason = reason,
            .legal_types = if (status == .rejected) self.legal_type_names[0..self.legal_type_len] else null,
            .bank_ms = 0,
        } });
        const produced = engine.chombo(&self.kyoku, seat, reason, &self.apply_buf);
        for (produced) |ev| self.push(ev);
        self.noteEndGame(produced);
        if (self.game_phase == .playing and self.kyoku.phase != .idle) {
            self.pushRequests();
        }
        return self.outcome();
    }

    fn noteEndGame(self: *Desk, produced: []const types.Event) void {
        for (produced) |ev| {
            if (ev == .end_game) {
                self.game_phase = .finished;
                return;
            }
        }
    }

    fn fillLegalTypes(self: *Desk, slot: usize) void {
        self.legal_type_len = 0;
        const len = self.legal_lens[slot];
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const name = types.actionTypeName(self.legal_bufs[slot][i]);
            var seen = false;
            for (self.legal_type_names[0..self.legal_type_len]) |existing| {
                if (std.mem.eql(u8, existing, name)) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;
            self.legal_type_names[self.legal_type_len] = name;
            self.legal_type_len += 1;
        }
    }

    fn isLegal(self: *const Desk, slot: usize, action: types.Action) bool {
        const len = self.legal_lens[slot];
        for (self.legal_bufs[slot][0..len]) |legal| {
            if (types.actionEql(legal, action)) return true;
        }
        return false;
    }

    fn clearAllPendings(self: *Desk) void {
        self.pendings = .{ null, null, null, null };
    }

    /// 为仍需要出着且尚未挂 request 的座位挂 request。
    fn pushRequests(self: *Desk) void {
        const seats = engine.seatsNeedingAction(&self.kyoku, &self.seat_buf);
        // 清掉已不需要的 pending
        for (&self.pendings) |*slot| {
            if (slot.*) |p| {
                var still = false;
                for (seats) |s| {
                    if (s == p.seat) still = true;
                }
                if (!still) slot.* = null;
            }
        }

        for (seats) |seat| {
            if (self.hasPendingSeat(seat)) continue;
            const slot = self.freePendingSlot() orelse break;
            const legal = engine.legalActions(&self.kyoku, seat, &self.legal_bufs[slot]);
            self.legal_lens[slot] = legal.len;
            const request_id = self.next_request_id;
            self.next_request_id += 1;
            self.pendings[slot] = .{ .request_id = request_id, .seat = seat };
            self.push(.{ .action_requested = .{
                .seat = seat,
                .request_id = request_id,
                .legal_actions = self.legal_bufs[slot][0..self.legal_lens[slot]],
            } });
        }
    }

    fn hasPendingSeat(self: *const Desk, seat: types.Seat) bool {
        for (self.pendings) |p| {
            if (p) |pending| {
                if (pending.seat == seat) return true;
            }
        }
        return false;
    }

    fn freePendingSlot(self: *const Desk) ?usize {
        for (self.pendings, 0..) |p, i| {
            if (p == null) return i;
        }
        return null;
    }

    fn push(self: *Desk, event: types.Event) void {
        std.debug.assert(self.event_len < self.event_buf.len);
        self.event_buf[self.event_len] = event;
        self.event_len += 1;
    }

    fn clearEvents(self: *Desk) void {
        self.event_len = 0;
    }

    fn outcome(self: *Desk) types.Outcome {
        return .{ .events = self.event_buf[0..self.event_len] };
    }

    /// 测试/调试：任意一个 pending。
    fn anyPending(self: *const Desk) ?Pending {
        for (self.pendings) |p| {
            if (p) |pending| return pending;
        }
        return null;
    }
};

test "desk beginGame then dahai" {
    const players = [_]u64{ 1, 2, 3, 4 };
    var desk = Desk.init(&players);

    const started = try desk.beginGame();
    try std.testing.expect(desk.game_phase == .playing);
    try std.testing.expect(started.events.len >= 2);
    const pending = desk.anyPending().?;
    const rid = pending.request_id;
    const pai = desk.kyoku.drawn.?;
    const out = try desk.onAction(1, rid, .{ .dahai = .{ .pai = pai, .tsumogiri = true } });
    var saw_accepted = false;
    var saw_dahai = false;
    for (out.events) |ev| {
        switch (ev) {
            .action_resolved => |r| {
                if (r.status == .accepted) saw_accepted = true;
            },
            .dahai => saw_dahai = true,
            else => {},
        }
    }
    try std.testing.expect(saw_accepted);
    try std.testing.expect(saw_dahai);
}

test "desk reject illegal then chombo continues next kyoku" {
    const players = [_]u64{ 1, 2, 3, 4 };
    var desk = Desk.init(&players);
    _ = try desk.beginGame();
    const rid = desk.anyPending().?.request_id;

    const out = try desk.onAction(1, rid, .none);
    var saw_rejected = false;
    var saw_ryukyoku = false;
    var saw_end_kyoku = false;
    var saw_start_kyoku = false;
    var saw_end_game = false;
    for (out.events) |ev| {
        switch (ev) {
            .action_resolved => |r| {
                if (r.status == .rejected) saw_rejected = true;
            },
            .ryukyoku => saw_ryukyoku = true,
            .end_kyoku => saw_end_kyoku = true,
            .start_kyoku => saw_start_kyoku = true,
            .end_game => saw_end_game = true,
            else => {},
        }
    }
    try std.testing.expect(saw_rejected);
    try std.testing.expect(saw_ryukyoku);
    try std.testing.expect(saw_end_kyoku);
    try std.testing.expect(saw_start_kyoku);
    try std.testing.expect(!saw_end_game);
    try std.testing.expect(desk.kyoku.phase == .wait_act);
    try std.testing.expect(desk.game_phase == .playing);
}

test "desk timeout defaults" {
    const players = [_]u64{ 1, 2, 3, 4 };
    var desk = Desk.init(&players);
    _ = try desk.beginGame();
    const rid = desk.anyPending().?.request_id;

    const out = try desk.onTimeout(rid);
    var saw_defaulted = false;
    for (out.events) |ev| {
        switch (ev) {
            .action_resolved => |r| {
                if (r.status == .defaulted) saw_defaulted = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_defaulted);
}
