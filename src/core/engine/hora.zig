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

/// 自摸和。
pub fn applyTsumo(ky: *Kyoku, seat: Seat, out: []Event) ApplyError![]Event {
    const pai = ky.drawn orelse return error.IllegalAction;
    var n: usize = 0;
    out[n] = .{ .hora = .{ .actor = seat, .target = seat, .pai = pai } };
    n += 1;

    const winners = [_]Seat{seat};
    referee.score.applyHoraScores(&ky.scores, &winners, seat, ky.oya, ky.honba, ky.kyotaku, true);
    ky.kyotaku = 0;

    const renchan = seat == ky.oya;
    if (renchan) ky.honba += 1 else ky.honba = 0;

    ky.drawn = null;
    return round.afterKyokuEndRenchan(ky, out, n, renchan);
}

/// 荣和（可多家）；调用前应手窗仍有效，本函数负责清窗。
pub fn applyRon(ky: *Kyoku, winners: []const Seat, out: []Event) ApplyError![]Event {
    const pai = ky.last_discard orelse return error.IllegalAction;
    const from = ky.last_discarder;

    var n: usize = 0;
    for (winners) |w| {
        out[n] = .{ .hora = .{ .actor = w, .target = from, .pai = pai } };
        n += 1;
    }

    referee.score.applyHoraScores(&ky.scores, winners, from, ky.oya, ky.honba, ky.kyotaku, false);
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
    ky.pending_riichi = null;
    ky.pending_minkan_dora = 0;
    ky.last_discard = null;
    ky.drawn = null;

    return round.afterKyokuEndRenchan(ky, out, n, dealer_win);
}
