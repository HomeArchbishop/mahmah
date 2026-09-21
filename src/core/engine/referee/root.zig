//! 裁判公开门面：振听 → 牌形 → 役/符 → 得点（仅结算相关判定）。
//!
//! 子模块一词一事；外部只应 `@import` 本文件。
//! 着法可否（立直/杠/九种等）由 engine 自行判定，不经本模块。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const special = @import("special.zig");
const standard = @import("standard.zig");
const furiten = @import("furiten.zig");
const waits = @import("waits.zig");
const yaku = @import("yaku.zig");
const fu = @import("fu.zig");
const points = @import("points.zig");
const pai_util = @import("../pai.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

pub const chomboDeltas = points.chomboDeltas;
pub const horaDeltas = points.horaDeltas;
pub const notenDeltas = points.notenDeltas;
pub const HoraValue = points.HoraValue;
pub const isTenpai = waits.isTenpai;

/// 流局满贯形：河牌全幺九，且舍张从未被鸣（`sutehai_len == river_len`）。
pub fn isNagashi(ky: *const Kyoku, seat: Seat) bool {
    const p = &ky.players[seat];
    if (p.river_len == 0) return false;
    if (p.sutehai_len != p.river_len) return false;
    var i: u8 = 0;
    while (i < p.river_len) : (i += 1) {
        if (!pai_util.isYaochuuhai(p.river[i])) return false;
    }
    return true;
}

/// 座位当前能否和了。`tsumo=true` 自摸；`false` 荣和（进张为 `response_pai`）。
///
/// 荣和：先振听，过则看形与役。自摸不判振听。
/// 1. 七对 / 国士形 → 和（形即役）
/// 2. 标准拆解：有役则和
pub fn canAgari(ky: *const Kyoku, seat: Seat, tsumo: bool) bool {
    if (!tsumo and furiten.isFuriten(ky, seat)) return false;

    if (special.detectSpecialForm(ky, seat, tsumo)) |_| return true;

    var decomps_buf: [64]standard.StandardDecomp = undefined;
    const decomps = standard.standardDecomps(ky, seat, tsumo, &decomps_buf);
    for (decomps) |decomp| {
        const y = yaku.countYaku(ky, seat, tsumo, .standard, decomp);
        if (y.yakuman > 0 or y.han > 0) return true;
    }
    return false;
}

/// 荣和是否国士形（含振听检查）。用于国士抢暗杠。
pub fn canKokushiRon(ky: *const Kyoku, seat: Seat) bool {
    if (furiten.isFuriten(ky, seat)) return false;
    return special.detectSpecialForm(ky, seat, false) == .kokushi;
}

/// 取最高点的和了番符（多拆解取基本点最大）。
pub fn evaluateHora(ky: *const Kyoku, seat: Seat, tsumo: bool) HoraValue {
    if (special.detectSpecialForm(ky, seat, tsumo)) |form| {
        const yform: yaku.Form = switch (form) {
            .chiitoi => .chiitoi,
            .kokushi => .kokushi,
        };
        const y = yaku.countYaku(ky, seat, tsumo, yform, .{});
        const fform: fu.Form = switch (form) {
            .chiitoi => .chiitoi,
            .kokushi => .kokushi,
        };
        const fu_n = fu.countFu(ky, seat, tsumo, fform, .{});
        return .{ .han = y.han, .yakuman = y.yakuman, .fu = fu_n };
    }

    var best: HoraValue = .{};
    var best_bp: u32 = 0;
    var decomps_buf: [64]standard.StandardDecomp = undefined;
    const decomps = standard.standardDecomps(ky, seat, tsumo, &decomps_buf);
    for (decomps) |decomp| {
        const y = yaku.countYaku(ky, seat, tsumo, .standard, decomp);
        if (y.yakuman == 0 and y.han == 0) continue;
        const fu_n = fu.countFu(ky, seat, tsumo, .standard, decomp);
        const cand: HoraValue = .{ .han = y.han, .fu = fu_n, .yakuman = y.yakuman };
        const bp = points.basicPoints(cand.han, cand.fu, cand.yakuman);
        if (bp > best_bp) {
            best_bp = bp;
            best = cand;
        }
    }
    return best;
}

test "isNagashi: river yaochuu and unclaimed" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    seat_tiles.addToRiver(&ky, 0, "1m");
    seat_tiles.addToSutehai(&ky, 0, "1m");
    seat_tiles.addToRiver(&ky, 0, "E");
    seat_tiles.addToSutehai(&ky, 0, "E");
    try std.testing.expect(isNagashi(&ky, 0));

    seat_tiles.addToRiver(&ky, 0, "5p");
    seat_tiles.addToSutehai(&ky, 0, "5p");
    try std.testing.expect(!isNagashi(&ky, 0));
}

test "isNagashi: claimed discard breaks" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    seat_tiles.addToRiver(&ky, 0, "1m");
    seat_tiles.addToSutehai(&ky, 0, "1m");
    _ = seat_tiles.popRiver(&ky, 0);
    try std.testing.expect(!isNagashi(&ky, 0));
}

test {
    _ = special;
    _ = standard;
    _ = furiten;
    _ = waits;
    _ = yaku;
    _ = fu;
    _ = points;
}
