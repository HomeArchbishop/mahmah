//! 应手窗开关（不依赖 discard/kan/response，用于拆循环依赖）。
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const legal = @import("legal.zig");
const Kyoku = kyoku_mod.Kyoku;
const Seat = types.Seat;
const Pai = types.Pai;
const CAPACITY = types.CAPACITY;

pub fn clear(ky: *Kyoku) void {
    ky.response_open = .{ false, false, false, false };
    ky.response_done = .{ false, false, false, false };
    ky.response_choice = .{ null, null, null, null };
}

pub fn anyOpen(ky: *const Kyoku) bool {
    for (ky.response_open) |o| {
        if (o) return true;
    }
    return false;
}

/// 开打牌应手窗。
pub fn openDiscardResponse(ky: *Kyoku, discarder: Seat, pai: Pai) void {
    ky.phase = .wait_response;
    ky.last_discard = pai;
    ky.last_discarder = discarder;
    ky.pending_kan = null;
    clear(ky);
    var s: u8 = 0;
    while (s < CAPACITY) : (s += 1) {
        if (legal.seatHasClaim(ky, @intCast(s), discarder, pai, false)) {
            ky.response_open[s] = true;
        }
    }
}

/// 开抢杠窗（仅荣）。
pub fn openChankan(ky: *Kyoku, kan_actor: Seat, pai: Pai) void {
    ky.phase = .wait_response;
    ky.last_discard = pai;
    ky.last_discarder = kan_actor;
    ky.pending_kan = kan_actor;
    clear(ky);
    var s: u8 = 0;
    while (s < CAPACITY) : (s += 1) {
        if (s == kan_actor) continue;
        if (legal.seatHasClaim(ky, @intCast(s), kan_actor, pai, true)) {
            ky.response_open[s] = true;
        }
    }
}
