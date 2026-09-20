//! 自摸 / 荣和结算（写 hora、得点、连庄、终局）。
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const round = @import("round.zig");
const referee = @import("referee/root.zig");
const window = @import("response_window.zig");
const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const Seat = types.Seat;
const ApplyError = types.ApplyError;
const CAPACITY = types.CAPACITY;

/// 自摸和。
pub fn applyTsumo(ky: *Kyoku, seat: Seat, out: []Event) ApplyError![]Event {
    const pai = ky.drawn orelse return error.IllegalAction;
    var n: usize = 0;
    out[n] = .{ .hora = .{ .actor = seat, .target = seat, .pai = pai } };
    n += 1;

    const value = referee.evaluateHora(ky, seat, true);
    applyScoreDeltas(ky, referee.horaDeltas(seat, seat, ky.oya, value, ky.honba, ky.kyotaku, true));
    ky.kyotaku = 0;

    const renchan = seat == ky.oya;
    if (renchan) ky.honba += 1 else ky.honba = 0;

    ky.drawn = null;
    return round.afterKyokuEndRenchan(ky, out, n, renchan);
}

/// 荣和（可多家）；调用前应手窗仍有效，本函数负责清窗。
pub fn applyRon(ky: *Kyoku, winners: []const Seat, out: []Event) ApplyError![]Event {
    const pai = ky.response_pai orelse return error.IllegalAction;
    const from = ky.response_from;

    var n: usize = 0;
    for (winners) |w| {
        out[n] = .{ .hora = .{ .actor = w, .target = from, .pai = pai } };
        n += 1;
    }

    // 各家按自身最高点计；供托只给第一家
    for (winners, 0..) |w, i| {
        const value = referee.evaluateHora(ky, w, false);
        const sticks: u8 = if (i == 0) ky.kyotaku else 0;
        applyScoreDeltas(ky, referee.horaDeltas(w, from, ky.oya, value, ky.honba, sticks, false));
    }
    ky.kyotaku = 0;

    var dealer_win = false;
    for (winners) |w| {
        if (w == ky.oya) dealer_win = true;
    }
    if (dealer_win) {
        ky.honba += 1;
    } else {
        ky.honba = 0;
    }

    window.clear(ky);
    ky.pending_kan = null;
    ky.pending_ankan = false;
    ky.pending_riichi = null;
    ky.pending_minkan_dora = 0;
    ky.response_pai = null;
    ky.drawn = null;

    return round.afterKyokuEndRenchan(ky, out, n, dealer_win);
}

fn applyScoreDeltas(ky: *Kyoku, deltas: [CAPACITY]i32) void {
    var i: u8 = 0;
    while (i < CAPACITY) : (i += 1) {
        ky.scores[i] += deltas[i];
    }
}
