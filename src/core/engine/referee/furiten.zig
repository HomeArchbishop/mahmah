//! 振听判定：同巡 + 舍张（听牌全集 ∩ 全舍张）。
//! 听牌集由 `waits` 提供；本模块不负责枚举听牌。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const pai_util = @import("../pai.zig");
const waits = @import("waits.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

/// 荣和视角是否振听（自摸勿调用；同巡或舍张∩听牌）。
pub fn isFuriten(ky: *const Kyoku, seat: Seat) bool {
    if (ky.players[seat].doujun_furiten) return true;
    return isSutehaiFuriten(ky, seat);
}

/// 13 张手牌任一听牌 kind 落在 sutehai 中则为舍张振听。
fn isSutehaiFuriten(ky: *const Kyoku, seat: Seat) bool {
    var wait_set: [34]bool = .{false} ** 34;
    waits.fillWaits(ky, seat, &wait_set);

    const p = &ky.players[seat];
    var i: u8 = 0;
    while (i < p.sutehai_len) : (i += 1) {
        const id = pai_util.kindId(p.sutehai[i]) orelse continue;
        if (wait_set[id]) return true;
    }
    return false;
}

test "sutehai furiten: discarded wait blocks other wait ron" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");
    const Pai = types.Pai;

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
    const Pai = types.Pai;

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
