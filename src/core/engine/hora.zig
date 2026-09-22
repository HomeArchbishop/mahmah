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
    const deltas = referee.horaDeltas(seat, seat, ky.oya, value, ky.honba, ky.kyotaku, true, ky.rules.kiriage_mangan);

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
/// 多家时按放铳者下家起的座位序结算；供托与本场只给第一家。
pub fn applyRon(ky: *Kyoku, winners: []const Seat, out: []Event) ApplyError![]Event {
    const pai = ky.response_pai orelse return error.IllegalAction;
    const from = ky.response_from;

    // 宣言牌被荣：立直不成立（不扣 1000、无 reach_accepted）
    ky.pending_riichi = null;

    var ordered: [CAPACITY]Seat = undefined;
    const n_win = orderRonWinners(from, winners, &ordered);

    var n: usize = 0;
    for (ordered[0..n_win], 0..) |w, i| {
        const value = referee.evaluateHora(ky, w, false);
        const first = i == 0;
        const sticks: u8 = if (first) ky.kyotaku else 0;
        const honba: u8 = if (first) ky.honba else 0;
        const deltas = referee.horaDeltas(w, from, ky.oya, value, honba, sticks, false, ky.rules.kiriage_mangan);
        out[n] = makeHoraEvent(ky, w, from, pai, deltas, false);
        n += 1;
        applyScoreDeltas(ky, deltas);
    }
    ky.kyotaku = 0;

    var dealer_win = false;
    for (ordered[0..n_win]) |w| {
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

/// 放铳者下家起，按巡目排序和了者（上家取り）。
fn orderRonWinners(from: Seat, winners: []const Seat, out: *[CAPACITY]Seat) usize {
    var n: usize = 0;
    var step: u8 = 1;
    while (step <= 3) : (step += 1) {
        const seat: Seat = @intCast((@as(u8, from) + step) % CAPACITY);
        for (winners) |w| {
            if (w == seat) {
                out[n] = w;
                n += 1;
                break;
            }
        }
    }
    return n;
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
