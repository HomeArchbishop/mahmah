//! 闭张牌列组装：自摸用手牌；荣和为手牌 + 进张。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");

const Pai = types.Pai;
const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

/// 组装闭张。`tsumo=true` 时忽略 `winning`（手牌已含摸牌）。
pub fn collectClosed(
    ky: *const Kyoku,
    seat: Seat,
    tsumo: bool,
    winning: Pai,
    buf: *[14]Pai,
) ?[]const Pai {
    const hand = ky.handSlice(seat);
    if (tsumo) {
        if (hand.len > 14) return null;
        return hand;
    }
    if (hand.len >= 14) return null;
    @memcpy(buf[0..hand.len], hand);
    buf[hand.len] = winning;
    return buf[0 .. hand.len + 1];
}

/// 进张取自 `drawn` / `response_pai`。
pub fn collectClosedFromKy(
    ky: *const Kyoku,
    seat: Seat,
    tsumo: bool,
    buf: *[14]Pai,
) ?[]const Pai {
    const winning = (if (tsumo) ky.drawn else ky.response_pai) orelse return null;
    return collectClosed(ky, seat, tsumo, winning, buf);
}
