const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const seat_tiles = @import("seat_tiles.zig");
const wall = @import("wall.zig");
const window = @import("response_window.zig");
const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const Seat = types.Seat;
const Pai = types.Pai;
const ApplyError = types.ApplyError;

/// 暗槓は即めくり；明槓（大明・加）は打牌時（打牌イベント前）めくり。
pub const DoraReveal = enum {
    immediate,
    after_discard,
};

/// 杠后：按时机翻指示 / 岭上摸牌 / 进入 wait_act。
pub fn resolveKan(ky: *Kyoku, actor: Seat, out: []Event, start: usize, dora: DoraReveal) []Event {
    var n = start;
    switch (dora) {
        .immediate => n = appendRevealDora(ky, out, n),
        .after_discard => ky.pending_minkan_dora += 1,
    }

    const drawn = wall.drawRinshan(ky) orelse {
        return out[0..n];
    };

    seat_tiles.clearIppatsuAll(ky);
    ky.turn = actor;
    seat_tiles.addToHand(ky, actor, drawn);
    ky.drawn = drawn;
    ky.is_rinshan = true;
    ky.phase = .wait_act;
    ky.pending_kan = null;
    ky.pending_ankan = false;
    ky.response_pai = null;
    window.clear(ky);

    out[n] = .{ .tsumo = .{ .actor = actor, .pai = drawn } };
    n += 1;
    return out[0..n];
}

/// 明杠：下次打牌事件前翻齐待翻指示牌（可连续明杠累加）。
pub fn flushMinkanDora(ky: *Kyoku, out: []Event, start: usize) usize {
    var n = start;
    while (ky.pending_minkan_dora > 0) {
        ky.pending_minkan_dora -= 1;
        n = appendRevealDora(ky, out, n);
    }
    return n;
}

fn appendRevealDora(ky: *Kyoku, out: []Event, start: usize) usize {
    var n = start;
    if (wall.revealDora(ky)) |marker| {
        if (n < out.len) {
            out[n] = .{ .dora = .{ .dora_marker = marker } };
            n += 1;
        }
    }
    return n;
}

/// 暗杠落地；国士可抢则开窗，否则立刻翻指示并岭上。
pub fn applyAnkan(ky: *Kyoku, seat: Seat, consumed: [4]Pai, out: []Event) ApplyError![]Event {
    if (ky.drawn == null) return error.IllegalAction;
    if (!ky.yama.hasLive()) return error.IllegalAction;
    if (!seat_tiles.removeExactTiles(ky, seat, &consumed)) return error.IllegalAction;
    ky.drawn = null;
    seat_tiles.clearDoujunFuriten(ky, seat);
    var f: kyoku_mod.Fuuro = .{
        .kind = .ankan,
        .tile_len = 4,
        .from = null,
    };
    f.tiles = consumed;
    seat_tiles.addFuuro(ky, seat, f);
    ky.kan_count += 1;
    ky.claims_this_kyoku += 1;
    ky.is_first_turn = false;

    var n: usize = 0;
    out[n] = .{ .ankan = .{ .actor = seat, .consumed = consumed } };
    n += 1;

    window.openChankan(ky, seat, consumed[0], true);
    if (!window.anyOpen(ky)) {
        return resolveKan(ky, seat, out, n, .immediate);
    }
    return out[0..n];
}

/// 加杠：写事件；有抢则开窗，否则岭上（指示打牌后翻）。
pub fn applyKakan(ky: *Kyoku, seat: Seat, pai: Pai, consumed: [3]Pai, out: []Event) ApplyError![]Event {
    if (ky.drawn == null) return error.IllegalAction;
    if (!ky.yama.hasLive()) return error.IllegalAction;
    const hand_one = [_]Pai{pai};
    if (!seat_tiles.removeExactTiles(ky, seat, &hand_one)) return error.IllegalAction;
    if (!seat_tiles.upgradePonToKakan(ky, seat, pai, consumed)) return error.IllegalAction;
    ky.drawn = null;
    seat_tiles.clearDoujunFuriten(ky, seat);
    ky.kan_count += 1;
    ky.claims_this_kyoku += 1;
    ky.is_first_turn = false;

    var n: usize = 0;
    out[n] = .{ .kakan = .{ .actor = seat, .pai = pai, .consumed = consumed } };
    n += 1;

    window.openChankan(ky, seat, pai, false);
    if (!window.anyOpen(ky)) {
        return resolveKan(ky, seat, out, n, .after_discard);
    }
    return out[0..n];
}
