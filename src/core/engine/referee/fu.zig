//! 符数。对外只暴露 `Form` + `countFu`；标准型按分项累加后进位。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const standard = @import("standard.zig");
const pai_util = @import("../pai.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;
const Decomp = standard.StandardDecomp;
const Block = standard.Block;

/// 与役判定相同的牌形类别。
pub const Form = enum {
    chiitoi,
    kokushi,
    standard,
};

/// 按牌形计符。标准型用 `decomp`；七对/国士可传 `.{}`。
pub fn countFu(ky: *const Kyoku, seat: Seat, tsumo: bool, form: Form, decomp: Decomp) u16 {
    return switch (form) {
        .chiitoi => 25,
        .kokushi => 0,
        .standard => fuStandard(ky, seat, tsumo, decomp),
    };
}

/// 标准型某一拆解的符。各分项自行判定，此处只汇总并进位到 10。
fn fuStandard(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) u16 {
    var raw: u16 = 0;
    const add = struct {
        fn f(dst: *u16, v: ?u16) void {
            if (v) |x| dst.* += x;
        }
    }.f;

    add(&raw, fuutei(ky, seat, tsumo, decomp));
    add(&raw, mentsu(ky, seat, tsumo, decomp));
    add(&raw, atama(ky, seat, tsumo, decomp));
    add(&raw, machi(ky, seat, tsumo, decomp));
    add(&raw, tsumofu(ky, seat, tsumo, decomp));
    add(&raw, menzenkafu(ky, seat, tsumo, decomp));

    // 副露平和形：仅副底 20 → 抬到 30（不进位特例）
    if (!ky.players[seat].isMenzen() and raw == 20) raw = 30;

    return roundUp10(raw);
}

/// 副底：固定 20。
fn fuutei(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?u16 {
    _ = ky;
    _ = seat;
    _ = tsumo;
    _ = decomp;
    return 20;
}

/// 面子符：刻/杠按暗明与幺九累加；顺子 0。
fn mentsu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?u16 {
    _ = ky;
    _ = seat;
    _ = tsumo;
    var sum: u16 = 0;
    for (decomp.blocks) |b| {
        sum += mentsuBlock(b);
    }
    if (sum == 0) return null;
    return sum;
}

fn mentsuBlock(b: Block) u16 {
    const yao = pai_util.isYaochuuhai(b.tiles[0]);
    return switch (b.kind) {
        .jantou, .shuntsu => 0,
        .kotsu => blk: {
            const closed = isAnkou(b);
            if (yao) break :blk if (closed) 8 else 4;
            break :blk if (closed) 4 else 2;
        },
        .kantsu => blk: {
            // 暗杠：`is_fuuro=false`；大明杠/加杠为 true
            const closed = !b.is_fuuro;
            if (yao) break :blk if (closed) 32 else 16;
            break :blk if (closed) 16 else 8;
        },
    };
}

/// 荣和进张完成的刻子算明刻；自摸或非进张块为暗刻。
fn isAnkou(b: Block) bool {
    if (b.is_fuuro) return false;
    if (b.winning != null and !b.winning_tsumo) return false;
    return true;
}

/// 雀头符：役牌对 2；连风对 4。
fn atama(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?u16 {
    _ = tsumo;
    const tile = decomp.blocks[0].tiles[0];
    var fu_n: u16 = 0;
    if (pai_util.isSangenpai(tile)) fu_n += 2;
    if (pai_util.sameKind(tile, ky.bakaze)) fu_n += 2;
    if (pai_util.sameKind(tile, jikaze(ky, seat))) fu_n += 2;
    if (fu_n == 0) return null;
    return fu_n;
}

/// 听牌符：嵌张 / 边张 / 单骑 各 2；两面 / 双碰 0。
fn machi(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?u16 {
    _ = ky;
    _ = seat;
    _ = tsumo;
    for (decomp.blocks) |b| {
        const winning = b.winning orelse continue;
        return switch (waitKind(b, winning)) {
            .kanchan, .penchan, .tanki => 2,
            .ryanmen, .shanpon => null,
        };
    }
    return null;
}

/// 自摸符：+2；平和自摸免除（保持 20）。
fn tsumofu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?u16 {
    if (!tsumo) return null;
    if (isPinfuShape(ky, seat, decomp)) return null;
    return 2;
}

/// 门前加符：门清荣和 +10。
fn menzenkafu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?u16 {
    _ = decomp;
    if (tsumo) return null;
    if (!ky.players[seat].isMenzen()) return null;
    return 10;
}

const WaitKind = enum { ryanmen, kanchan, penchan, tanki, shanpon };

fn waitKind(b: Block, winning: types.Pai) WaitKind {
    return switch (b.kind) {
        .jantou => .tanki,
        .kotsu, .kantsu => .shanpon,
        .shuntsu => shuntsuWait(b, winning),
    };
}

fn shuntsuWait(b: Block, winning: types.Pai) WaitKind {
    // 块内已按 kindId 升序：tiles[0..3) 为 r, r+1, r+2
    if (pai_util.sameKind(winning, b.tiles[1])) return .kanchan;
    const low = pai_util.rank(b.tiles[0]) orelse return .ryanmen;
    if (pai_util.sameKind(winning, b.tiles[0])) {
        // 789 听 7
        return if (low == 7) .penchan else .ryanmen;
    }
    // 123 听 3
    return if (low == 1) .penchan else .ryanmen;
}

/// 平和形（门清四顺、役牌雀头外、两面听）。供自摸符免除与测试复用。
fn isPinfuShape(ky: *const Kyoku, seat: Seat, decomp: Decomp) bool {
    if (!ky.players[seat].isMenzen()) return false;
    for (decomp.blocks) |b| {
        if (b.kind == .kotsu or b.kind == .kantsu) return false;
        if (b.kind == .jantou) {
            if (pai_util.isSangenpai(b.tiles[0])) return false;
            if (pai_util.sameKind(b.tiles[0], ky.bakaze)) return false;
            if (pai_util.sameKind(b.tiles[0], jikaze(ky, seat))) return false;
        }
        if (b.winning) |w| {
            if (waitKind(b, w) != .ryanmen) return false;
        }
    }
    return true;
}

fn jikaze(ky: *const Kyoku, seat: Seat) types.Pai {
    const winds = [_]types.Pai{ "E", "S", "W", "N" };
    return winds[(@as(u8, seat) + 4 - @as(u8, ky.oya)) % 4];
}

fn roundUp10(fu_n: u16) u16 {
    if (fu_n % 10 == 0) return fu_n;
    return fu_n + (10 - fu_n % 10);
}

test "countFu: chiitoi 25, kokushi 0" {
    const ky = Kyoku.init();
    try @import("std").testing.expectEqual(@as(u16, 25), countFu(&ky, 0, true, .chiitoi, .{}));
    try @import("std").testing.expectEqual(@as(u16, 0), countFu(&ky, 0, true, .kokushi, .{}));
}

test "countFu: pinfu tsumo 20 / ron 30" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    ky.is_first_turn = false;
    // 123m 456m 789p 22s 34s + 摸/荣 5s → 两面平和
    const tiles = [_]types.Pai{ "1m", "2m", "3m", "4m", "5m", "6m", "7p", "8p", "9p", "2s", "2s", "3s", "4s", "5s" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "5s";

    var buf: [64]Decomp = undefined;
    const decomps = standard.standardDecomps(&ky, 0, true, &buf);
    try std.testing.expect(decomps.len >= 1);
    try std.testing.expectEqual(@as(u16, 20), countFu(&ky, 0, true, .standard, decomps[0]));

    // 荣和：手牌去掉进张
    var ky2 = Kyoku.init();
    ky2.is_first_turn = false;
    ky2.phase = .wait_response;
    const closed = [_]types.Pai{ "1m", "2m", "3m", "4m", "5m", "6m", "7p", "8p", "9p", "2s", "2s", "3s", "4s" };
    for (closed) |t| seat_tiles.addToHand(&ky2, 0, t);
    ky2.response_pai = "5s";
    var buf2: [64]Decomp = undefined;
    const d2 = standard.standardDecomps(&ky2, 0, false, &buf2);
    try std.testing.expect(d2.len >= 1);
    try std.testing.expectEqual(@as(u16, 30), countFu(&ky2, 0, false, .standard, d2[0]));
}

test "countFu: menzen tsumo + ankou rounds to 30" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    ky.is_first_turn = false;
    // 111m 456m 789p 22s 34s + 摸 5s：暗刻中张 4 + 自摸 2 + 副底 20 = 26 → 30
    const tiles = [_]types.Pai{ "1m", "1m", "1m", "4m", "5m", "6m", "7p", "8p", "9p", "2s", "2s", "3s", "4s", "5s" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "5s";

    var buf: [64]Decomp = undefined;
    const decomps = standard.standardDecomps(&ky, 0, true, &buf);
    try std.testing.expect(decomps.len >= 1);
    try std.testing.expectEqual(@as(u16, 30), countFu(&ky, 0, true, .standard, decomps[0]));
}
