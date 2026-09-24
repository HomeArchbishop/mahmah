//! 流局附加结算包装：荒牌 exhaustive_draw、九种九牌、途中流局判定。
//!
//! # 依赖（单向）
//! - 本模块 → `referee`（听牌 / 流满判定、得点）
//! - 本模块 → `round.afterKyokuEnd*`（局终推进）
//! - `discard.dealNext` → `applyHowanpai`
//! - `apply` → `applyKyushu`
//! - `discard` / `legal` → `isTochuAbortPending`（四风四杠四立直）
//!
//! # 不依赖本模块
//! - `round` 本身（仅 `afterKyokuEnd*`）
//! - `response` 三家和
//! - `hora`（和了另路）
//!
//! 途中流局仍直接写 `ryukyoku` 事件后调 `round.afterKyokuEnd`。
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const round = @import("round.zig");
const referee = @import("referee/root.zig");
const pai_util = @import("pai.zig");

const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const ApplyError = types.ApplyError;
const CAPACITY = types.CAPACITY;

/// 四风连打 / 四杠散了 / 四立直已成立（打牌后仅可荣，否则流局）。
pub fn isTochuAbortPending(ky: *const Kyoku) bool {
    return (ky.rules.abort_sufuurenta and fourWinds(ky)) or
        (ky.rules.abort_suukansansen and fourKans(ky)) or
        (ky.rules.abort_suucha_riichi and fourRiichi(ky));
}

pub fn tochuAbortReason(ky: *const Kyoku) []const u8 {
    if (ky.rules.abort_sufuurenta and fourWinds(ky)) return "sufuurenta";
    if (ky.rules.abort_suukansansen and fourKans(ky)) return "suukansansen";
    if (ky.rules.abort_suucha_riichi and fourRiichi(ky)) return "suucha_riichi";
    return "abort";
}

fn fourWinds(ky: *const Kyoku) bool {
    const d0 = ky.first_discards[0] orelse return false;
    if (!pai_util.isKazehai(d0)) return false;
    var s: u8 = 1;
    while (s < CAPACITY) : (s += 1) {
        const d = ky.first_discards[s] orelse return false;
        if (!types.paiEql(d, d0)) return false;
    }
    return true;
}

fn fourKans(ky: *const Kyoku) bool {
    if (ky.kan_count < 4) return false;
    var owners: [CAPACITY]u8 = .{0} ** CAPACITY;
    for (ky.players, 0..) |p, si| {
        var i: u8 = 0;
        while (i < p.fuuro_len) : (i += 1) {
            switch (p.fuuro[i].kind) {
                .daiminkan, .ankan, .kakan => owners[si] += 1,
                else => {},
            }
        }
    }
    var players_with_kan: u8 = 0;
    for (owners) |o| {
        if (o > 0) players_with_kan += 1;
    }
    return players_with_kan >= 2;
}

fn fourRiichi(ky: *const Kyoku) bool {
    for (ky.players) |p| {
        if (!p.riichi) return false;
    }
    return true;
}

/// 九种九牌流局（0 点；本场 +1；不连庄）。亮申报者手牌。
pub fn applyKyushu(ky: *Kyoku, seat: types.Seat, out: []Event) ApplyError![]Event {
    if (!ky.rules.abort_kyushu) return error.IllegalAction;
    if (!ky.is_first_turn) return error.IllegalAction;
    var reveal: [CAPACITY]bool = .{false} ** CAPACITY;
    reveal[seat] = true;
    var n: usize = 0;
    out[n] = .{ .ryukyoku = .{
        .reason = "kyushu_kyuhai",
        .deltas = .{ 0, 0, 0, 0 },
        .tehais = ky.tehaisReveal(reveal),
    } };
    n += 1;
    ky.honba += 1;
    return round.afterKyokuEnd(ky, out, n);
}

/// 荒牌流局：有流满则按自摸满贯结算并跳过听牌罚符；否则听牌/不听。
/// 供托保留；本场 +1；亲听牌或亲流满则连庄。听牌（及流满）座位亮牌。
pub fn applyHowanpai(ky: *Kyoku, out: []Event, start: usize) []Event {
    var nagashi: [CAPACITY]bool = .{false} ** CAPACITY;
    var tenpai: [CAPACITY]bool = .{false} ** CAPACITY;
    var any_nagashi = false;
    var s: u8 = 0;
    while (s < CAPACITY) : (s += 1) {
        nagashi[s] = referee.isNagashi(ky, @intCast(s));
        tenpai[s] = referee.isTenpai(ky.handSlice(@intCast(s)), ky.players[s].fuuro_len);
        if (nagashi[s]) any_nagashi = true;
    }

    var deltas: [CAPACITY]i32 = .{ 0, 0, 0, 0 };
    if (any_nagashi) {
        s = 0;
        while (s < CAPACITY) : (s += 1) {
            if (!nagashi[s]) continue;
            const part = referee.horaDeltas(
                @intCast(s),
                @intCast(s),
                ky.oya,
                .{ .han = 5 },
                ky.honba,
                0,
                true,
                ky.rules.kiriage_mangan,
            );
            var i: u8 = 0;
            while (i < CAPACITY) : (i += 1) deltas[i] += part[i];
        }
    } else {
        deltas = referee.notenDeltas(tenpai);
    }

    applyScoreDeltas(ky, deltas);

    // riichienv wire：听牌罚符为 0 时，仍把已在 reach_accepted 扣过的立直棒
    // 写进 deltas（-1000×立直者），但不再改 scores（供托已在 kyotaku）。
    var wire_deltas = deltas;
    if (deltasAreZero(deltas)) {
        var i: u8 = 0;
        while (i < CAPACITY) : (i += 1) {
            if (ky.players[i].riichi) wire_deltas[i] -= 1000;
        }
    }

    const renchan = tenpai[ky.oya] or nagashi[ky.oya];
    ky.honba += 1;

    var reveal: [CAPACITY]bool = .{false} ** CAPACITY;
    s = 0;
    while (s < CAPACITY) : (s += 1) {
        reveal[s] = tenpai[s] or nagashi[s];
    }

    var n = start;
    out[n] = .{ .ryukyoku = .{
        .reason = "exhaustive_draw",
        .deltas = wire_deltas,
        .tehais = ky.tehaisReveal(reveal),
    } };
    n += 1;
    return round.afterKyokuEndRenchan(ky, out, n, renchan);
}

fn deltasAreZero(d: [CAPACITY]i32) bool {
    return d[0] == 0 and d[1] == 0 and d[2] == 0 and d[3] == 0;
}

fn applyScoreDeltas(ky: *Kyoku, deltas: [CAPACITY]i32) void {
    var i: u8 = 0;
    while (i < CAPACITY) : (i += 1) {
        ky.scores[i] += deltas[i];
    }
}
