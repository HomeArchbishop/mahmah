const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const seat_tiles = @import("seat_tiles.zig");
const wall = @import("wall.zig");
const round = @import("round.zig");
const legal = @import("legal.zig");
const window = @import("response_window.zig");
const kan = @import("kan.zig");
const ryuukyoku = @import("ryuukyoku.zig");
const kuikae = @import("kuikae.zig");
const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const Seat = types.Seat;
const Pai = types.Pai;
const ApplyError = types.ApplyError;

/// 打牌入河；有应手则开窗，否则 acceptRiichi → abort → dealNext。
pub fn resolveDiscard(ky: *Kyoku, seat: Seat, pai: Pai, tsumogiri: bool, out: []Event) ApplyError![]Event {
    if (kuikae.forbids(ky, pai)) return error.IllegalAction;
    if (!seat_tiles.removeFromHand(ky, seat, pai, tsumogiri)) return error.IllegalAction;
    seat_tiles.addToRiver(ky, seat, pai);
    seat_tiles.addToSutehai(ky, seat, pai);
    ky.drawn = null;
    ky.turn = seat; // unnecessary, but just keep it as an anchor
    kuikae.clear(ky);

    // 立直者再次打牌且未和 -> 清自己一发
    if (ky.players[seat].riichi) {
        ky.players[seat].ippatsu = false;
    }

    var n: usize = 0;
    // 明杠指示：与标准实现一致，在打牌事件之前翻
    n = kan.flushMinkanDora(ky, out, n);

    out[n] = .{ .dahai = .{ .actor = seat, .pai = pai, .tsumogiri = tsumogiri } };
    n += 1;

    if (ky.is_first_turn and ky.first_discards[seat] == null) {
        ky.first_discards[seat] = pai;
    }

    var all_discarded = true;
    for (ky.first_discards) |d| {
        if (d == null) all_discarded = false;
    }
    if (all_discarded or ky.claims_this_kyoku > 0) {
        ky.is_first_turn = false;
    }

    // 应手进张：先写入再探测（荣和/吃碰统一读 response_pai）
    ky.response_pai = pai;
    if (legal.hasClaimOpportunity(ky, seat)) {
        window.openDiscardResponse(ky, seat);
        return out[0..n];
    }
    ky.response_pai = null;
    return afterNoClaim(ky, out, n);
}

/// 立直宣言（仍 wait_act，下一着打牌）。
pub fn applyReach(ky: *Kyoku, seat: Seat, out: []Event) ApplyError![]Event {
    if (ky.pending_riichi != null) return error.IllegalAction;
    if (ky.players[seat].riichi) return error.IllegalAction;
    if (!ky.players[seat].isMenzen()) return error.IllegalAction;
    if (ky.scores[seat] < 1000) return error.IllegalAction;
    if (ky.drawn == null) return error.IllegalAction;
    if (ky.yama.liveRemaining() < 4) return error.IllegalAction;
    ky.pending_riichi = seat;
    out[0] = .{ .reach = .{ .actor = seat } };
    return out[0..1];
}

pub fn afterNoClaim(ky: *Kyoku, out: []Event, start: usize) []Event {
    var n = start;
    n = acceptRiichi(ky, out, n);
    if (ryuukyoku.isTochuAbortPending(ky)) {
        out[n] = .{ .ryukyoku = .{ .reason = ryuukyoku.tochuAbortReason(ky), .deltas = .{ 0, 0, 0, 0 } } };
        n += 1;
        return round.afterKyokuEnd(ky, out, n);
    }
    return dealNext(ky, out, n);
}

/// 立直承认：扣 1000、kyotaku+1、发 reach_accepted。
pub fn acceptRiichi(ky: *Kyoku, out: []Event, start: usize) usize {
    const seat = ky.pending_riichi orelse return start;
    ky.pending_riichi = null;
    const p = &ky.players[seat];
    // 河仅宣言打（无人曾鸣）→ 双立直
    p.double_riichi = p.river_len == 1 and ky.claims_this_kyoku == 0;
    p.riichi = true;
    p.ippatsu = true;
    ky.scores[seat] -= 1000;
    ky.kyotaku += 1;
    var n = start;
    out[n] = .{ .reach_accepted = .{ .actor = seat } };
    n += 1;
    return n;
}

fn dealNext(ky: *Kyoku, out: []Event, start: usize) []Event {
    var n = start;
    const next = round.nextSeat(ky.turn);
    const drawn = wall.drawLive(ky) orelse {
        return ryuukyoku.applyHowanpai(ky, out, n);
    };

    ky.turn = next;
    seat_tiles.addToHand(ky, next, drawn);
    ky.drawn = drawn;
    ky.is_rinshan = false;
    ky.phase = .wait_act;

    out[n] = .{ .tsumo = .{ .actor = next, .pai = drawn } };
    n += 1;
    return out[0..n];
}
