//! 流局附加结算包装：荒牌 howanpai、九种九牌。
//!
//! # 依赖（单向）
//! - 本模块 → `referee`（听牌 / 流满判定、得点）
//! - 本模块 → `round.afterKyokuEnd*`（局终推进）
//! - `discard.dealNext` → `applyHowanpai`
//! - `apply` → `applyKyushu`
//!
//! # 不依赖本模块
//! - `round` 本身（仅 `afterKyokuEnd*`）
//! - 途中流局：`discard` 四风四杠四立直、`response` 三家和
//! - `hora`（和了另路）
//!
//! 途中流局仍直接写 `ryukyoku` 事件后调 `round.afterKyokuEnd`。
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const round = @import("round.zig");
const referee = @import("referee/root.zig");

const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const ApplyError = types.ApplyError;
const CAPACITY = types.CAPACITY;

/// 九种九牌流局（0 点；本场 +1；不连庄）。
pub fn applyKyushu(ky: *Kyoku, out: []Event) ApplyError![]Event {
    if (!ky.is_first_turn) return error.IllegalAction;
    var n: usize = 0;
    out[n] = .{ .ryukyoku = .{ .reason = "kyushukyuhai", .deltas = .{ 0, 0, 0, 0 } } };
    n += 1;
    ky.honba += 1;
    return round.afterKyokuEnd(ky, out, n);
}

/// 荒牌流局：有流满则按自摸满贯结算并跳过听牌罚符；否则听牌/不听。
/// 供托保留；本场 +1；亲听牌或亲流满则连庄。
pub fn applyHowanpai(ky: *Kyoku, out: []Event, start: usize) []Event {
    var nagashi: [CAPACITY]bool = .{false} ** CAPACITY;
    var tenpai: [CAPACITY]bool = .{false} ** CAPACITY;
    var any_nagashi = false;
    var s: u8 = 0;
    while (s < CAPACITY) : (s += 1) {
        nagashi[s] = referee.isNagashi(ky, @intCast(s));
        tenpai[s] = referee.isTenpai(ky, @intCast(s));
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
            );
            var i: u8 = 0;
            while (i < CAPACITY) : (i += 1) deltas[i] += part[i];
        }
    } else {
        deltas = referee.notenDeltas(tenpai);
    }

    applyScoreDeltas(ky, deltas);

    const renchan = tenpai[ky.oya] or nagashi[ky.oya];
    ky.honba += 1;

    var n = start;
    out[n] = .{ .ryukyoku = .{ .reason = "howanpai", .deltas = deltas } };
    n += 1;
    return round.afterKyokuEndRenchan(ky, out, n, renchan);
}

fn applyScoreDeltas(ky: *Kyoku, deltas: [CAPACITY]i32) void {
    var i: u8 = 0;
    while (i < CAPACITY) : (i += 1) {
        ky.scores[i] += deltas[i];
    }
}
