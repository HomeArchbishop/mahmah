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
const CAPACITY = types.CAPACITY;

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

    if (legal.hasClaimOpportunity(ky, seat, pai)) {
        window.openDiscardResponse(ky, seat, pai);
        return out[0..n];
    }

    return afterNoClaim(ky, out, n);
}

/// 立直宣言（仍 wait_act，下一着打牌）。
pub fn applyReach(ky: *Kyoku, seat: Seat, out: []Event) ApplyError![]Event {
    if (ky.pending_riichi != null) return error.IllegalAction;
    if (ky.players[seat].riichi) return error.IllegalAction;
    if (!ky.players[seat].isMenzen()) return error.IllegalAction;
    if (ky.scores[seat] < 1000) return error.IllegalAction;
    if (ky.drawn == null) return error.IllegalAction;
    ky.pending_riichi = seat;
    out[0] = .{ .reach = .{ .actor = seat } };
    return out[0..1];
}

pub fn afterNoClaim(ky: *Kyoku, out: []Event, start: usize) []Event {
    var n = start;
    n = acceptRiichi(ky, out, n);
    if (checkTochuRyukyoku(ky)) {
        out[n] = .{ .ryukyoku = .{ .reason = tochuRyukyokuReason(ky), .deltas = .{ 0, 0, 0, 0 } } };
        n += 1;
        return round.afterKyokuEnd(ky, out, n);
    }
    return dealNext(ky, out, n);
}

/// 立直承认：扣 1000、kyotaku+1、发 reach_accepted。
fn acceptRiichi(ky: *Kyoku, out: []Event, start: usize) usize {
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

fn tochuRyukyokuReason(ky: *const Kyoku) []const u8 {
    if (fourWinds(ky)) return "sufonrenda";
    if (fourKans(ky)) return "suukaikan";
    if (fourRiichi(ky)) return "suuchariichi";
    return "abort";
}

/// 四风连打 / 四杠散了 / 四立直（途中流局）。
fn checkTochuRyukyoku(ky: *const Kyoku) bool {
    return fourWinds(ky) or fourKans(ky) or fourRiichi(ky);
}

fn fourWinds(ky: *const Kyoku) bool {
    const d0 = ky.first_discards[0] orelse return false;
    if (!@import("pai.zig").isKazehai(d0)) return false;
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
    return players_with_kan >= 2 and ky.kan_count >= 4;
}

fn fourRiichi(ky: *const Kyoku) bool {
    for (ky.players) |p| {
        if (!p.riichi) return false;
    }
    return true;
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
