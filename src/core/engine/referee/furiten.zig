//! 振听判定：同巡 + 舍张（听牌全集 ∩ 全舍张）。
//! 与牌形无关：任一听牌曾被打出即振听，挡掉所有荣和。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const pai_util = @import("../pai.zig");
const standard = @import("standard.zig");
const special = @import("special.zig");

const Pai = types.Pai;
const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

/// 荣和视角是否振听（自摸勿调用；同巡或舍张∩听牌）。
pub fn isFuriten(ky: *const Kyoku, seat: Seat) bool {
    if (ky.players[seat].doujun_furiten) return true;
    return isSutehaiFuriten(ky, seat);
}

/// 13 张手牌任一听牌 kind 落在 sutehai 中则为舍张振听。
fn isSutehaiFuriten(ky: *const Kyoku, seat: Seat) bool {
    var waits: [34]bool = .{false} ** 34;
    fillWaits(ky, seat, &waits);

    const p = &ky.players[seat];
    var i: u8 = 0;
    while (i < p.sutehai_len) : (i += 1) {
        const id = pai_util.kindId(p.sutehai[i]) orelse continue;
        if (waits[id]) return true;
    }
    return false;
}

/// 当前手牌（荣和视角：不含进张）的全部听牌 kind。
fn fillWaits(ky: *const Kyoku, seat: Seat, waits: *[34]bool) void {
    const hand = ky.handSlice(seat);
    const fuuro_len = ky.players[seat].fuuro_len;
    const expect_closed: usize = @as(usize, 4 - fuuro_len) * 3 + 2;
    if (hand.len + 1 != expect_closed) return;

    var id: u8 = 0;
    while (id < 34) : (id += 1) {
        const cand = pai_util.fromKindId(id) orelse continue;
        if (fuuro_len == 0 and hand.len == 13) {
            var closed_buf: [14]Pai = undefined;
            @memcpy(closed_buf[0..13], hand[0..13]);
            closed_buf[13] = cand;
            const closed = closed_buf[0..14];
            if (special.isChiitoi(closed) or special.isKokushi(closed)) {
                waits[id] = true;
                continue;
            }
        }
        if (standard.hasStandardShape(ky, seat, cand)) {
            waits[id] = true;
        }
    }
}

test "sutehai furiten: discarded wait blocks other wait ron" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    // 听 4p/7p；舍过 4p → 荣 7p 仍振听
    const tiles = [_]Pai{ "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "6p" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    seat_tiles.addToSutehai(&ky, 0, "4p");
    ky.response_pai = "7p";

    try std.testing.expect(isSutehaiFuriten(&ky, 0));
    try std.testing.expect(isFuriten(&ky, 0));
}

test "sutehai furiten: claimed discard still counts" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    const tiles = [_]Pai{ "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "6p" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    seat_tiles.addToRiver(&ky, 0, "4p");
    seat_tiles.addToSutehai(&ky, 0, "4p");
    _ = seat_tiles.popRiver(&ky, 0);
    ky.response_pai = "7p";

    try std.testing.expect(ky.players[0].river_len == 0);
    try std.testing.expect(ky.players[0].sutehai_len == 1);
    try std.testing.expect(isFuriten(&ky, 0));
}
