//! 符数（占位）：按形分别给出符。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const standard = @import("standard.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

/// 标准型符数。TODO：副露/门清/雀头/嵌张等。
pub fn fuStandard(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: standard.StandardDecomp) u16 {
    _ = ky;
    _ = seat;
    _ = tsumo;
    _ = decomp;
    return 30;
}

/// 七对符数（固定 25）。
pub fn fuChiitoi(ky: *const Kyoku, seat: Seat, tsumo: bool) u16 {
    _ = ky;
    _ = seat;
    _ = tsumo;
    return 25;
}

/// 国士符数（役满不计符；占位）。
pub fn fuKokushi(ky: *const Kyoku, seat: Seat, tsumo: bool) u16 {
    _ = ky;
    _ = seat;
    _ = tsumo;
    return 0;
}
