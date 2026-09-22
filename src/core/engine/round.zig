//! 局生命周期：开局、发牌、终局、连庄、进局（半庄：东场 + 南入）。
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

/// 返し点：东 4 终了时无人达到则南入。
pub const RETURN_SCORE: i32 = 30000;

/// 开一局：清标志、洗牌发牌、亲家摸第一张；写出 start_kyoku + tsumo。
pub fn initializeRound(ky: *Kyoku, out: []Event) []Event {
    std.debug.assert(out.len >= 2);
    clearRoundFlags(ky);
    resetPlayers(ky);
    wall.prepare(ky);
    return finishDeal(ky, out);
}

/// 牌山已由 `loadWall` 装好：发牌开局（不洗牌）。
pub fn initializeLoadedWall(ky: *Kyoku, out: []Event) []Event {
    std.debug.assert(out.len >= 2);
    clearRoundFlags(ky);
    resetPlayers(ky);
    return finishDeal(ky, out);
}

fn finishDeal(ky: *Kyoku, out: []Event) []Event {
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
    const markers = ky.doraMarkersSlice();
    var dora_owned: [types.DORA_MARKER_CAP]types.Pai = undefined;
    @memcpy(dora_owned[0..markers.len], markers);
    out[n] = .{ .start_kyoku = .{
        .bakaze = ky.bakaze,
        .dora_markers = dora_owned,
        .dora_markers_len = @intCast(markers.len),
        .kyoku = ky.kyoku,
        .honba = ky.honba,
        .kyotaku = ky.kyotaku,
        .oya = ky.oya,
        .scores = ky.scores,
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

/// 发牌：从亲家起，3 轮各 4 张 + 每人 1 张（共 52）。
fn deal(ky: *Kyoku) void {
    var round: u8 = 0;
    while (round < 3) : (round += 1) {
        var i: u8 = 0;
        while (i < CAPACITY) : (i += 1) {
            const seat: Seat = @intCast((@as(u8, ky.oya) + i) % CAPACITY);
            var k: u8 = 0;
            while (k < 4) : (k += 1) {
                const pai = wall.drawLive(ky) orelse unreachable;
                seat_tiles.addToHand(ky, seat, pai);
            }
        }
    }
    var i: u8 = 0;
    while (i < CAPACITY) : (i += 1) {
        const seat: Seat = @intCast((@as(u8, ky.oya) + i) % CAPACITY);
        const pai = wall.drawLive(ky) orelse unreachable;
        seat_tiles.addToHand(ky, seat, pai);
    }
}

fn clearRoundFlags(ky: *Kyoku) void {
    ky.pending_kan = null;
    ky.pending_ankan = false;
    ky.pending_riichi = null;
    ky.pending_minkan_dora = 0;
    ky.claims_this_kyoku = 0;
    ky.kan_count = 0;
    ky.first_discards = .{ null, null, null, null };
    ky.kuikae_len = 0;
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

/// 半庄终战（无西入）：
/// - 连庄不终战
/// - 东 4：有人 ≥ 返し点则终战，否则南入
/// - 南 4：终战
fn shouldEndGame(ky: *const Kyoku, renchan: bool) bool {
    if (renchan) return false;
    if (std.mem.eql(u8, ky.bakaze, "E") and ky.kyoku == 4) {
        return anyReachedReturn(ky);
    }
    if (std.mem.eql(u8, ky.bakaze, "S") and ky.kyoku == 4) {
        return true;
    }
    return false;
}

fn anyReachedReturn(ky: *const Kyoku) bool {
    for (ky.scores) |s| {
        if (s >= RETURN_SCORE) return true;
    }
    return false;
}

pub fn nextSeat(seat: Seat) Seat {
    return @intCast((@as(u8, seat) + 1) % CAPACITY);
}

test "shouldEndGame: east4 below return → 南入" {
    var ky = Kyoku.init();
    ky.bakaze = "E";
    ky.kyoku = 4;
    ky.scores = .{ 25000, 26000, 24000, 25000 };
    try std.testing.expect(!shouldEndGame(&ky, false));
}

test "shouldEndGame: east4 with return → end" {
    var ky = Kyoku.init();
    ky.bakaze = "E";
    ky.kyoku = 4;
    ky.scores = .{ 25000, 30000, 24000, 21000 };
    try std.testing.expect(!shouldEndGame(&ky, true));
    try std.testing.expect(shouldEndGame(&ky, false));
}

test "shouldEndGame: south4 → end" {
    var ky = Kyoku.init();
    ky.bakaze = "S";
    ky.kyoku = 4;
    ky.scores = .{ 20000, 20000, 20000, 40000 };
    try std.testing.expect(shouldEndGame(&ky, false));
    try std.testing.expect(!shouldEndGame(&ky, true));
}

test "afterKyokuEnd: east4 南入 advances to south1" {
    var ky = Kyoku.init();
    ky.bakaze = "E";
    ky.kyoku = 4;
    ky.oya = 3;
    ky.scores = .{ 25000, 25000, 25000, 25000 };
    ky.shuffle_seed = 1;
    var buf: [16]Event = undefined;
    const out = afterKyokuEnd(&ky, &buf, 0);
    try std.testing.expect(out[0] == .end_kyoku);
    try std.testing.expectEqualStrings("S", ky.bakaze);
    try std.testing.expectEqual(@as(u8, 1), ky.kyoku);
    try std.testing.expectEqual(@as(Seat, 0), ky.oya);
    try std.testing.expect(ky.phase == .wait_act);
    var saw_start = false;
    for (out) |ev| {
        if (ev == .start_kyoku) {
            saw_start = true;
            try std.testing.expectEqualStrings("S", ev.start_kyoku.bakaze);
            try std.testing.expectEqual(@as(u8, 1), ev.start_kyoku.kyoku);
        }
        try std.testing.expect(ev != .end_game);
    }
    try std.testing.expect(saw_start);
}

test "afterKyokuEnd: east4 reached return → end_game" {
    var ky = Kyoku.init();
    ky.bakaze = "E";
    ky.kyoku = 4;
    ky.oya = 0;
    ky.scores = .{ 31000, 23000, 23000, 23000 };
    var buf: [8]Event = undefined;
    const out = afterKyokuEnd(&ky, &buf, 0);
    try std.testing.expect(out.len == 2);
    try std.testing.expect(out[0] == .end_kyoku);
    try std.testing.expect(out[1] == .end_game);
    try std.testing.expect(ky.phase == .idle);
}
