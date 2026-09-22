//! 局内牌理公开接口（Desk：`@import("engine/root.zig")`）。
const std = @import("std");
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const round = @import("round.zig");
const apply_mod = @import("apply.zig");
const referee = @import("referee/root.zig");
const legal = @import("legal.zig");
const window = @import("response_window.zig");
const kuikae = @import("kuikae.zig");
const wall = @import("wall.zig");

const Kyoku = kyoku_mod.Kyoku;
const Action = types.Action;
const Event = types.Event;
const Seat = types.Seat;
const ApplyError = types.ApplyError;

/// 当前座位可执行的着法列表（写入 `out`，返回子切片）。
pub fn legalActions(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    return legal.fillLegal(ky, seat, out);
}

/// 超时代打：wait_act 优先摸切；wait_response 为 none。
pub fn defaultAction(ky: *const Kyoku, seat: Seat) ?Action {
    var buf: [32]Action = undefined;
    const acts = legalActions(ky, seat, &buf);
    if (acts.len == 0) return null;
    if (ky.phase == .wait_response) {
        for (acts) |a| {
            if (a == .none) return a;
        }
    }
    for (acts) |a| {
        if (a == .dahai and a.dahai.tsumogiri) return a;
    }
    return acts[0];
}

/// 哪些座位现在需要 request_action（写入 out）。
pub fn seatsNeedingAction(ky: *const Kyoku, out: []Seat) []Seat {
    return legal.seatsNeeding(ky, out);
}

/// 整盘开始：initializeRound（不推进局数）。
pub fn onStartGame(ky: *Kyoku, out: []Event) []Event {
    return round.initializeRound(ky, out);
}

/// 装入本引擎布局的 136 张（不洗牌、不发牌）。
pub const loadWall = wall.loadWall;

/// 牌山已 `loadWall`：发牌开局。
pub fn onStartLoadedWall(ky: *Kyoku, out: []Event) []Event {
    return round.initializeLoadedWall(ky, out);
}

/// 落地一着：按 phase 分发。
pub fn apply(ky: *Kyoku, seat: Seat, action: Action, out: []Event) ApplyError![]Event {
    return switch (ky.phase) {
        .wait_act => apply_mod.applyWaitAct(ky, seat, action, out),
        .wait_response => apply_mod.applyWaitResponse(ky, seat, action, out),
        .idle => error.IllegalAction,
    };
}

pub fn chomboReason(buf: []u8, offender: Seat) []const u8 {
    return std.fmt.bufPrint(buf, "Error: Illegal Action by Player {d}", .{offender}) catch "Error: Illegal Action";
}

/// 非法着罚符：ryukyoku → end_kyoku → initializeRound（同 out）。
pub fn chombo(ky: *Kyoku, offender: Seat, reason: []const u8, out: []Event) []Event {
    std.debug.assert(out.len >= 4);
    ky.drawn = null;
    ky.pending_kan = null;
    ky.pending_ankan = false;
    ky.pending_riichi = null;
    ky.pending_minkan_dora = 0;
    ky.response_pai = null;
    kuikae.clear(ky);
    window.clear(ky);

    var n: usize = 0;
    out[n] = .{ .ryukyoku = .{
        .reason = reason,
        .deltas = referee.chomboDeltas(offender, ky.oya),
    } };
    n += 1;
    return round.afterKyokuEnd(ky, out, n);
}

test {
    _ = @import("wall.zig");
    _ = @import("referee/root.zig");
    _ = @import("ryuukyoku.zig");
    _ = @import("kuikae.zig");
}

test "onStartGame deals 13 and draws for oya" {
    var ky = Kyoku.init();
    ky.shuffle_seed = 42;
    var buf: [8]Event = undefined;
    const ev = onStartGame(&ky, &buf);
    try std.testing.expect(ev.len == 2);
    try std.testing.expect(ky.phase == .wait_act);
    try std.testing.expect(ky.players[0].tehai_len == 14);
    try std.testing.expect(ky.players[1].tehai_len == 13);
    try std.testing.expect(ky.drawn != null);
    try std.testing.expect(ky.yama.live_i == 53);
}

test "dahai then next tsumo" {
    var ky = Kyoku.init();
    ky.shuffle_seed = 7;
    var buf: [8]Event = undefined;
    _ = onStartGame(&ky, &buf);
    const pai = ky.drawn.?;
    var out: [16]Event = undefined;
    const produced = try apply(&ky, 0, .{ .dahai = .{ .pai = pai, .tsumogiri = true } }, &out);
    try std.testing.expect(produced.len >= 2);
    try std.testing.expect(produced[0] == .dahai);
    // 可能进入 wait_response；否则有 tsumo
    if (ky.phase == .wait_act) {
        try std.testing.expect(produced[produced.len - 1] == .tsumo);
        try std.testing.expect(ky.turn == 1);
        try std.testing.expect(ky.players[0].tehai_len == 13);
        try std.testing.expect(ky.players[0].river_len == 1);
    } else {
        try std.testing.expect(ky.phase == .wait_response);
    }
}

test "chombo ends kyoku then starts next" {
    var ky = Kyoku.init();
    ky.shuffle_seed = 1;
    var buf: [16]Event = undefined;
    _ = onStartGame(&ky, &buf);
    const oya_before = ky.oya;
    var out: [16]Event = undefined;
    const produced = chombo(&ky, 0, "chombo", &out);
    var saw_end_kyoku = false;
    var saw_start_kyoku = false;
    for (produced) |ev| {
        switch (ev) {
            .end_kyoku => saw_end_kyoku = true,
            .start_kyoku => saw_start_kyoku = true,
            else => {},
        }
    }
    try std.testing.expect(saw_end_kyoku);
    try std.testing.expect(saw_start_kyoku);
    try std.testing.expect(ky.phase == .wait_act);
    try std.testing.expect(ky.oya == @as(Seat, @intCast((@as(u8, oya_before) + 1) % 4)));
}

test "pon claim then wait_act for caller" {
    const seat_tiles = @import("seat_tiles.zig");

    var ky = Kyoku.init();
    ky.phase = .wait_act;
    ky.turn = 0;
    ky.oya = 0;
    seat_tiles.addToHand(&ky, 0, "2m");
    seat_tiles.addToHand(&ky, 0, "1m");
    ky.drawn = "1m";
    seat_tiles.addToHand(&ky, 1, "1m");
    seat_tiles.addToHand(&ky, 1, "1m");
    seat_tiles.addToHand(&ky, 1, "3m");

    var out: [16]Event = undefined;
    const d = try apply(&ky, 0, .{ .dahai = .{ .pai = "1m", .tsumogiri = true } }, &out);
    try std.testing.expect(d[0] == .dahai);
    try std.testing.expect(ky.phase == .wait_response);
    try std.testing.expect(ky.response_open[1]);

    const mid = try apply(&ky, 1, .{ .pon = .{ .pai = "1m", .consumed = .{ "1m", "1m" } } }, &out);
    try std.testing.expect(mid[0] == .pon);
    try std.testing.expect(ky.phase == .wait_act);
    try std.testing.expect(ky.turn == 1);
    try std.testing.expect(ky.drawn == null);
    try std.testing.expect(ky.players[1].fuuro_len == 1);

    // 食替
    try std.testing.expectError(error.IllegalAction, apply(&ky, 1, .{ .dahai = .{ .pai = "1m" } }, &out));
    _ = try apply(&ky, 1, .{ .dahai = .{ .pai = "3m" } }, &out);
    try std.testing.expectEqual(@as(u8, 0), ky.kuikae_len);
}
