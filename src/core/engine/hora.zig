//! 自摸 / 荣和结算（写 hora、得点、连庄、终局）。
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const round = @import("round.zig");
const referee = @import("referee/root.zig");
const window = @import("response_window.zig");
const wall = @import("wall.zig");
const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const Seat = types.Seat;
const Pai = types.Pai;
const ApplyError = types.ApplyError;
const CAPACITY = types.CAPACITY;
const DORA_MARKER_CAP = types.DORA_MARKER_CAP;

/// 自摸和。
pub fn applyTsumo(ky: *Kyoku, seat: Seat, out: []Event) ApplyError![]Event {
    const pai = ky.drawn orelse return error.IllegalAction;
    const value = referee.evaluateHora(ky, seat, true);
    const deltas = referee.horaDeltas(seat, seat, ky.oya, value, ky.honba, ky.kyotaku, true);

    var n: usize = 0;
    out[n] = makeHoraEvent(ky, seat, seat, pai, deltas, true);
    n += 1;

    applyScoreDeltas(ky, deltas);
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

    // 宣言牌被荣：立直不成立（不扣 1000、无 reach_accepted）
    ky.pending_riichi = null;

    var n: usize = 0;
    // 各家按自身最高点计；供托只给第一家
    for (winners, 0..) |w, i| {
        const value = referee.evaluateHora(ky, w, false);
        const sticks: u8 = if (i == 0) ky.kyotaku else 0;
        const deltas = referee.horaDeltas(w, from, ky.oya, value, ky.honba, sticks, false);
        out[n] = makeHoraEvent(ky, w, from, pai, deltas, false);
        n += 1;
        applyScoreDeltas(ky, deltas);
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
    ky.pending_minkan_dora = 0;
    ky.response_pai = null;
    ky.drawn = null;

    return round.afterKyokuEndRenchan(ky, out, n, dealer_win);
}

fn makeHoraEvent(
    ky: *const Kyoku,
    actor: Seat,
    target: Seat,
    pai: Pai,
    deltas: [CAPACITY]i32,
    tsumo: bool,
) Event {
    var ura: [DORA_MARKER_CAP]Pai = undefined;
    var ura_len: u8 = 0;
    if (ky.players[actor].riichi) {
        const slice = wall.fillUraMarkers(ky, &ura);
        ura_len = @intCast(slice.len);
    }
    return .{ .hora = .{
        .actor = actor,
        .target = target,
        .pai = pai,
        .deltas = deltas,
        .ura_markers = ura,
        .ura_markers_len = ura_len,
        .tsumo = tsumo,
    } };
}

fn applyScoreDeltas(ky: *Kyoku, deltas: [CAPACITY]i32) void {
    var i: u8 = 0;
    while (i < CAPACITY) : (i += 1) {
        ky.scores[i] += deltas[i];
    }
}
