//! 局生命周期：开局、发牌、终局、连庄、进局。
const std = @import("std");
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const wall = @import("wall.zig");
const seat_tiles = @import("seat_tiles.zig");
const window = @import("response_window.zig");
const Kyoku = kyoku_mod.Kyoku;
const Event = types.Event;
const Seat = types.Seat;
const CAPACITY = types.CAPACITY;

/// 开一局：清标志、洗牌发牌、亲家摸第一张；写出 start_kyoku + tsumo。
pub fn initializeRound(ky: *Kyoku, out: []Event) []Event {
    std.debug.assert(out.len >= 2);
    clearRoundFlags(ky);
    resetPlayers(ky);
    wall.prepare(ky);
    deal(ky);
    _ = wall.revealDora(ky) orelse unreachable;

    ky.phase = .wait_act;
    ky.turn = ky.oya;
    ky.drawn = null;
    ky.is_first_turn = true;
    ky.is_rinshan = false;

    const first = wall.drawLive(ky) orelse unreachable;
    seat_tiles.addToHand(ky, ky.oya, first);
    ky.drawn = first;

    var n: usize = 0;
    out[n] = .{ .start_kyoku = .{
        .bakaze = ky.bakaze,
        .dora_markers = ky.doraMarkersSlice(),
        .kyoku = ky.kyoku,
        .honba = ky.honba,
        .kyotaku = ky.kyotaku,
        .oya = ky.oya,
        .tehais = ky.tehaisForEvent(),
    } };
    n += 1;
    out[n] = .{ .tsumo = .{ .actor = ky.oya, .pai = first } };
    n += 1;
    return out[0..n];
}

fn resetPlayers(ky: *Kyoku) void {
    for (&ky.players) |*p| {
        p.tehai_len = 0;
        p.river_len = 0;
        p.sutehai_len = 0;
        p.fuuro_len = 0;
        p.riichi = false;
        p.ippatsu = false;
        p.double_riichi = false;
        p.doujun_furiten = false;
    }
    ky.drawn = null;
}

fn deal(ky: *Kyoku) void {
    var n: u8 = 0;
    var r: u8 = 0;
    while (r < 13) : (r += 1) {
        var seat: u8 = 0;
        while (seat < CAPACITY) : (seat += 1) {
            seat_tiles.addToHand(ky, @intCast(seat), ky.yama.tiles[wall.liveTileIndex(n)]);
            n += 1;
        }
    }
    ky.yama.live_i = n;
}

fn clearRoundFlags(ky: *Kyoku) void {
    ky.pending_kan = null;
    ky.pending_ankan = false;
    ky.pending_riichi = null;
    ky.pending_minkan_dora = 0;
    ky.claims_this_kyoku = 0;
    ky.kan_count = 0;
    ky.first_discards = .{ null, null, null, null };
    ky.response_pai = null;
    window.clear(ky);
    for (&ky.players) |*p| {
        p.ippatsu = false;
        p.riichi = false;
        p.double_riichi = false;
        p.fuuro_len = 0;
        p.sutehai_len = 0;
        p.doujun_furiten = false;
    }
}

/// 局终后推进亲家/局数（非连庄时轮庄）。
fn advanceRoundMeta(ky: *Kyoku, renchan: bool) void {
    if (!renchan) {
        ky.oya = @intCast((@as(u8, ky.oya) + 1) % CAPACITY);
        ky.kyoku += 1;
        if (ky.kyoku > 4) {
            ky.kyoku = 1;
            ky.bakaze = nextBakaze(ky.bakaze);
        }
    }
}

fn nextBakaze(bakaze: types.Pai) types.Pai {
    if (std.mem.eql(u8, bakaze, "E")) return "S";
    if (std.mem.eql(u8, bakaze, "S")) return "W";
    if (std.mem.eql(u8, bakaze, "W")) return "N";
    return "E";
}

/// 写入 end_kyoku，再 initializeRound（轮庄）。
pub fn afterKyokuEnd(ky: *Kyoku, out: []Event, start: usize) []Event {
    return afterKyokuEndRenchan(ky, out, start, false);
}

/// renchan=true 时不轮庄、不进局数。
pub fn afterKyokuEndRenchan(ky: *Kyoku, out: []Event, start: usize, renchan: bool) []Event {
    std.debug.assert(out.len >= start + 1);
    var n = start;
    out[n] = .end_kyoku;
    n += 1;

    if (shouldEndGame(ky, renchan)) {
        ky.phase = .idle;
        out[n] = .{ .end_game = .{ .scores = ky.scores } };
        n += 1;
        return out[0..n];
    }

    advanceRoundMeta(ky, renchan);
    ky.shuffle_seed +%= 1;
    const rest = initializeRound(ky, out[n..]);
    return out[0 .. n + rest.len];
}

fn shouldEndGame(ky: *const Kyoku, renchan: bool) bool {
    if (renchan) return false;
    return std.mem.eql(u8, ky.bakaze, "E") and ky.kyoku == 4;
}

pub fn nextSeat(seat: Seat) Seat {
    return @intCast((@as(u8, seat) + 1) % CAPACITY);
}
