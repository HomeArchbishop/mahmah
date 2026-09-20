//! 裁判公开门面：编排振听 → 牌形 → 役/符 → 得点。
//!
//! 子模块一词一事；外部只应 `@import` 本文件。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const special = @import("special.zig");
const standard = @import("standard.zig");
const furiten = @import("furiten.zig");
const yaku = @import("yaku.zig");
const fu = @import("fu.zig");
const points = @import("points.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

pub const kyushuKinds = special.kyushuKinds;
pub const chomboDeltas = points.chomboDeltas;
pub const horaDeltas = points.horaDeltas;
pub const HoraValue = points.HoraValue;

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
        if (yaku.hasYaku(ky, seat, tsumo, decomp)) return true;
    }
    return false;
}

/// 荣和是否国士形（含振听检查）。用于国士抢暗杠。
pub fn canKokushiRon(ky: *const Kyoku, seat: Seat) bool {
    if (furiten.isFuriten(ky, seat)) return false;
    return special.detectSpecialForm(ky, seat, false) == .kokushi;
}

/// 取最高点的和了番符（役/符可占位；多拆解取基本点最大）。
pub fn evaluateHora(ky: *const Kyoku, seat: Seat, tsumo: bool) HoraValue {
    if (special.detectSpecialForm(ky, seat, tsumo)) |form| {
        return switch (form) {
            .chiitoi => blk: {
                const y = yaku.yakuChiitoi(ky, seat, tsumo, .{});
                break :blk .{
                    .han = y.han,
                    .yakuman = y.yakuman,
                    .fu = fu.fuChiitoi(ky, seat, tsumo),
                };
            },
            .kokushi => blk: {
                const y = yaku.yakuKokushi(ky, seat, tsumo, .{});
                break :blk .{
                    .han = y.han,
                    .yakuman = y.yakuman,
                    .fu = fu.fuKokushi(ky, seat, tsumo),
                };
            },
        };
    }

    var best: HoraValue = .{};
    var best_bp: u32 = 0;
    var decomps_buf: [64]standard.StandardDecomp = undefined;
    const decomps = standard.standardDecomps(ky, seat, tsumo, &decomps_buf);
    for (decomps) |decomp| {
        const y = yaku.yakuStandard(ky, seat, tsumo, decomp);
        if (y.yakuman == 0 and y.han == 0) continue;
        const fu_n = fu.fuStandard(ky, seat, tsumo, decomp);
        const cand: HoraValue = .{ .han = y.han, .fu = fu_n, .yakuman = y.yakuman };
        const bp = points.basicPoints(cand.han, cand.fu, cand.yakuman);
        if (bp > best_bp) {
            best_bp = bp;
            best = cand;
        }
    }
    return best;
}

test {
    _ = special;
    _ = standard;
    _ = furiten;
    _ = yaku;
    _ = fu;
    _ = points;
}
