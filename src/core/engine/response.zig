//! 应手结算：收集过/吃碰杠/荣，按优先级推进。
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const seat_tiles = @import("seat_tiles.zig");
const window = @import("response_window.zig");
const kan = @import("kan.zig");
const discard = @import("discard.zig");
const round = @import("round.zig");
const hora = @import("hora.zig");
const referee = @import("referee/root.zig");
const Kyoku = kyoku_mod.Kyoku;
const Action = types.Action;
const Event = types.Event;
const Seat = types.Seat;
const ApplyError = types.ApplyError;
const CAPACITY = types.CAPACITY;

/// 记录应手；全员答完后 settle。
pub fn applyWaitResponse(ky: *Kyoku, seat: Seat, action: Action, out: []Event) ApplyError![]Event {
    if (!ky.response_open[seat] or ky.response_done[seat]) return error.IllegalAction;

    switch (action) {
        .none, .chi, .pon, .daiminkan, .hora => {},
        else => return error.IllegalAction,
    }

    ky.response_done[seat] = true;
    ky.response_choice[seat] = action;

    if (!allResponded(ky)) return out[0..0];
    return settle(ky, out);
}

fn allResponded(ky: *const Kyoku) bool {
    var s: u8 = 0;
    while (s < CAPACITY) : (s += 1) {
        if (ky.response_open[s] and !ky.response_done[s]) return false;
    }
    return true;
}

fn settle(ky: *Kyoku, out: []Event) ApplyError![]Event {
    markDoujunOnMissedRon(ky);

    var ron_seats: [CAPACITY]Seat = undefined;
    var ron_n: usize = 0;
    var s: u8 = 0;
    while (s < CAPACITY) : (s += 1) {
        if (!ky.response_open[s]) continue;
        const choice = ky.response_choice[s] orelse continue;
        if (choice == .hora) {
            ron_seats[ron_n] = @intCast(s);
            ron_n += 1;
        }
    }

    if (ron_n >= 3) {
        var n: usize = 0;
        out[n] = .{ .ryukyoku = .{ .reason = "sanchahou", .deltas = .{ 0, 0, 0, 0 } } };
        n += 1;
        window.clear(ky);
        ky.pending_kan = null;
        ky.pending_ankan = false;
        ky.response_pai = null;
        return round.afterKyokuEnd(ky, out, n);
    }

    if (ron_n > 0) {
        return hora.applyRon(ky, ron_seats[0..ron_n], out);
    }

    // 抢杠结算完毕，无人荣和
    if (ky.pending_kan) |actor| {
        const ankan = ky.pending_ankan;
        window.clear(ky);
        ky.pending_kan = null;
        ky.pending_ankan = false;
        return kan.resolveKan(ky, actor, out, 0, if (ankan) .immediate else .after_discard);
    }

    var call_seat: ?Seat = null;
    var call_action: ?Action = null;
    s = 0;
    while (s < CAPACITY) : (s += 1) { // look for pon/daiminkan
        if (!ky.response_open[s]) continue;
        const choice = ky.response_choice[s] orelse continue;
        switch (choice) {
            .pon, .daiminkan => {
                call_seat = @intCast(s);
                call_action = choice;
                break;
            },
            else => {},
        }
    }
    if (call_seat == null) { // otherwise chi
        s = 0;
        while (s < CAPACITY) : (s += 1) {
            if (!ky.response_open[s]) continue;
            const choice = ky.response_choice[s] orelse continue;
            if (choice == .chi) {
                call_seat = @intCast(s);
                call_action = choice;
                break;
            }
        }
    }

    if (call_seat) |cs| {
        return applyCall(ky, cs, call_action.?, out);
    }

    window.clear(ky);
    ky.response_pai = null;
    return discard.afterNoClaim(ky, out, 0);
}

fn applyCall(ky: *Kyoku, seat: Seat, action: Action, out: []Event) ApplyError![]Event {
    const pai = ky.response_pai orelse return error.IllegalAction;
    const target = ky.response_from;
    _ = seat_tiles.popRiver(ky, target);
    // 吃碰杠消去同巡（河仍 pop；舍张 sutehai 保留）
    seat_tiles.clearDoujunFuriten(ky, seat);

    seat_tiles.clearIppatsuAll(ky);
    ky.claims_this_kyoku += 1;
    ky.is_first_turn = false;
    ky.pending_riichi = null;

    var n: usize = 0;
    switch (action) {
        .chi => |c| {
            if (!types.paiEql(c.pai, pai)) return error.IllegalAction;
            if (!seat_tiles.removeExactTiles(ky, seat, &c.consumed)) return error.IllegalAction;
            var f: kyoku_mod.Fuuro = .{ .kind = .chi, .tile_len = 3, .from = target };
            f.tiles[0] = c.consumed[0];
            f.tiles[1] = c.consumed[1];
            f.tiles[2] = pai;
            seat_tiles.addFuuro(ky, seat, f);
            out[n] = .{ .chi = .{ .actor = seat, .target = target, .pai = pai, .consumed = c.consumed } };
            n += 1;
            return enterWaitActAfterCall(ky, seat, out, n);
        },
        .pon => |c| {
            if (!types.paiEql(c.pai, pai)) return error.IllegalAction;
            if (!seat_tiles.removeExactTiles(ky, seat, &c.consumed)) return error.IllegalAction;
            var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = target };
            f.tiles[0] = c.consumed[0];
            f.tiles[1] = c.consumed[1];
            f.tiles[2] = pai;
            seat_tiles.addFuuro(ky, seat, f);
            out[n] = .{ .pon = .{ .actor = seat, .target = target, .pai = pai, .consumed = c.consumed } };
            n += 1;
            return enterWaitActAfterCall(ky, seat, out, n);
        },
        .daiminkan => |c| {
            if (!ky.yama.hasLive()) return error.IllegalAction;
            if (!types.paiEql(c.pai, pai)) return error.IllegalAction;
            if (!seat_tiles.removeExactTiles(ky, seat, &c.consumed)) return error.IllegalAction;
            var f: kyoku_mod.Fuuro = .{ .kind = .daiminkan, .tile_len = 4, .from = target };
            f.tiles[0] = c.consumed[0];
            f.tiles[1] = c.consumed[1];
            f.tiles[2] = c.consumed[2];
            f.tiles[3] = pai;
            seat_tiles.addFuuro(ky, seat, f);
            ky.kan_count += 1;
            out[n] = .{ .daiminkan = .{ .actor = seat, .target = target, .pai = pai, .consumed = c.consumed } };
            n += 1;
            window.clear(ky);
            ky.response_pai = null;
            return kan.resolveKan(ky, seat, out, n, .after_discard);
        },
        else => return error.IllegalAction,
    }
}

fn enterWaitActAfterCall(ky: *Kyoku, seat: Seat, out: []Event, n: usize) []Event {
    window.clear(ky);
    ky.response_pai = null;
    ky.drawn = null;
    ky.turn = seat;
    ky.phase = .wait_act;
    ky.is_rinshan = false;
    return out[0..n];
}

/// 应手窗内可荣却未选 hora → 同巡振听。
fn markDoujunOnMissedRon(ky: *Kyoku) void {
    var s: u8 = 0;
    while (s < CAPACITY) : (s += 1) {
        if (!ky.response_open[s]) continue;
        const choice = ky.response_choice[s] orelse continue;
        if (choice == .hora) continue;
        const seat: Seat = @intCast(s);
        const could = if (ky.pending_ankan)
            referee.canKokushiRon(ky, seat)
        else
            referee.canAgari(ky, seat, false);
        if (could) {
            ky.players[seat].doujun_furiten = true;
        }
    }
}
