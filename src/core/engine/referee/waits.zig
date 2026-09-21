//! 听牌扫描：纯形，不含振听与役。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const pai_util = @import("../pai.zig");
const standard = @import("standard.zig");
const special = @import("special.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

/// 当前手牌（荣和视角：不含进张）是否听牌。
pub fn isTenpai(ky: *const Kyoku, seat: Seat) bool {
    var waits: [34]bool = .{false} ** 34;
    fillWaits(ky, seat, &waits);
    for (waits) |w| {
        if (w) return true;
    }
    return false;
}

/// 写入全部听牌 kind。供振听 / 听牌判定共用。
pub fn fillWaits(ky: *const Kyoku, seat: Seat, waits: *[34]bool) void {
    const hand = ky.handSlice(seat);
    const fuuro_len = ky.players[seat].fuuro_len;
    const expect_closed: usize = @as(usize, 4 - fuuro_len) * 3 + 2;
    if (hand.len + 1 != expect_closed) return;

    var id: u8 = 0;
    while (id < 34) : (id += 1) {
        const cand = pai_util.fromKindId(id) orelse continue;
        if (special.hasSpecialShape(ky, seat, cand) or standard.hasStandardShape(ky, seat, cand)) {
            waits[id] = true;
        }
    }
}
