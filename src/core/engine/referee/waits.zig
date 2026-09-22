//! 听牌扫描：纯形，不含振听与役。
const types = @import("../../types.zig");
const pai_util = @import("../pai.zig");
const standard = @import("standard.zig");
const special = @import("special.zig");

const Pai = types.Pai;
const Seat = types.Seat;
const Kyoku = @import("../../kyoku.zig").Kyoku;

/// 手里未亮的牌是否听牌（不含吃碰杠；不含进张）。
pub fn isTenpai(closed: []const Pai, fuuro_len: u8) bool {
    const expect_closed: usize = @as(usize, 4 - fuuro_len) * 3 + 2;
    if (closed.len + 1 != expect_closed) return false;

    var id: u8 = 0;
    while (id < 34) : (id += 1) {
        const cand = pai_util.fromKindId(id) orelse continue;
        if (fuuro_len == 0) {
            var full: [14]Pai = undefined;
            if (closed.len >= full.len) continue;
            @memcpy(full[0..closed.len], closed);
            full[closed.len] = cand;
            const slice = full[0 .. closed.len + 1];
            if (special.isChiitoi(slice) or special.isKokushi(slice)) return true;
        }
        if (standard.hasStandardShape(closed, fuuro_len, cand)) return true;
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
        if (fuuro_len == 0) {
            var full: [14]Pai = undefined;
            @memcpy(full[0..hand.len], hand);
            full[hand.len] = cand;
            if (special.isChiitoi(full[0 .. hand.len + 1]) or special.isKokushi(full[0 .. hand.len + 1])) {
                waits[id] = true;
                continue;
            }
        }
        if (standard.hasStandardShape(hand, fuuro_len, cand)) {
            waits[id] = true;
        }
    }
}
