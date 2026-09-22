//! 牌山：洗牌仍为扁平 `tiles[136]`（种子可复现）；读写按下述真实垛序。
//!
//! # 布局（常量切：61 活垛 + 7 死垛）
//! - 每垛 2 张，数组下标 `2*s` = 底，`2*s+1` = 顶
//! - 活山垛 `0..60`：摸牌顺序为每垛先顶后底（第 n 张下标 `n ^ 1`）
//! - 死山垛 `61..67`（局部 `0..6`）：局部 0 侧岭上，局部 2..6 为表宝顶 / 里宝底
//!
//! 发牌、活山摸、岭上、翻表宝均走同一套下标函数，便于渲染与复现对齐。
const std = @import("std");
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const Kyoku = kyoku_mod.Kyoku;
const Yama = kyoku_mod.Yama;
const Pai = types.Pai;
const WALL_LEN = kyoku_mod.WALL_LEN;
const LIVE_WALL_LEN = kyoku_mod.LIVE_WALL_LEN;
const DORA_MARKER_CAP = kyoku_mod.DORA_MARKER_CAP;

/// 死山起始全局垛号（之前为活山）。
pub const DEAD_STACK0: u8 = @intCast(LIVE_WALL_LEN / 2);
/// 第一张表宝在死山局部垛号（从岭上侧数第 3 垛）。
const DORA_STACK_LOCAL0: u8 = 2;

/// 活山第 `n` 张（先顶后底）在 `tiles` 中的下标。
pub fn liveTileIndex(n: u8) u8 {
    std.debug.assert(n < LIVE_WALL_LEN);
    return n ^ 1;
}

/// 第 `i` 张表宝指示（顶）下标。
pub fn doraTopIndex(i: u8) u8 {
    std.debug.assert(i < DORA_MARKER_CAP);
    const stack: u8 = DEAD_STACK0 + DORA_STACK_LOCAL0 + i;
    return stack * 2 + 1;
}

/// 第 `i` 张里宝指示（同垛底）下标。
pub fn uraBottomIndex(i: u8) u8 {
    std.debug.assert(i < DORA_MARKER_CAP);
    const stack: u8 = DEAD_STACK0 + DORA_STACK_LOCAL0 + i;
    return stack * 2;
}

/// 第 `n` 张岭上牌下标（死山岭上侧先顶后底，最多 4）。
pub fn rinshanTileIndex(n: u8) u8 {
    std.debug.assert(n < 4);
    const local_stack = n / 2;
    const top_first = n % 2 == 0;
    const stack: u8 = DEAD_STACK0 + local_stack;
    return if (top_first) stack * 2 + 1 else stack * 2;
}

/// 写入当前已翻表宝对应的里宝指示（同垛底）。
pub fn fillUraMarkers(ky: *const Kyoku, buf: *[DORA_MARKER_CAP]Pai) []const Pai {
    const n = ky.yama.dora_markers_len;
    var i: u8 = 0;
    while (i < n) : (i += 1) {
        buf[i] = ky.yama.tiles[uraBottomIndex(i)];
    }
    return buf[0..n];
}

/// 按标准牌组填满 136 张牌山（含赤宝与字牌）。
fn fill(yama: *Yama) void {
    const suits = [_]u8{ 'm', 'p', 's' };
    var i: usize = 0;
    for (suits) |suit| {
        var rank: u8 = 1;
        while (rank <= 9) : (rank += 1) {
            var copy: u8 = 0;
            while (copy < 4) : (copy += 1) {
                if (rank == 5 and copy == 0) {
                    yama.tiles[i] = switch (suit) {
                        'm' => "5mr",
                        'p' => "5pr",
                        else => "5sr",
                    };
                } else {
                    yama.tiles[i] = normalTile(rank, suit);
                }
                i += 1;
            }
        }
    }
    const honors = [_]Pai{ "E", "S", "W", "N", "P", "F", "C" };
    for (honors) |h| {
        var copy: u8 = 0;
        while (copy < 4) : (copy += 1) {
            yama.tiles[i] = h;
            i += 1;
        }
    }
    std.debug.assert(i == WALL_LEN);
}

fn normalTile(rank: u8, suit: u8) Pai {
    return switch (suit) {
        'm' => switch (rank) {
            1 => "1m",
            2 => "2m",
            3 => "3m",
            4 => "4m",
            5 => "5m",
            6 => "6m",
            7 => "7m",
            8 => "8m",
            else => "9m",
        },
        'p' => switch (rank) {
            1 => "1p",
            2 => "2p",
            3 => "3p",
            4 => "4p",
            5 => "5p",
            6 => "6p",
            7 => "7p",
            8 => "8p",
            else => "9p",
        },
        else => switch (rank) {
            1 => "1s",
            2 => "2s",
            3 => "3s",
            4 => "4s",
            5 => "5s",
            6 => "6s",
            7 => "7s",
            8 => "8s",
            else => "9s",
        },
    };
}

/// Fisher–Yates 洗牌；同 `seed` 可复现。
fn shuffle(yama: *Yama, seed: u64) void {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var i: usize = WALL_LEN;
    while (i > 1) {
        i -= 1;
        const j = random.intRangeLessThan(usize, 0, i + 1);
        const tmp = yama.tiles[i];
        yama.tiles[i] = yama.tiles[j];
        yama.tiles[j] = tmp;
    }
}

/// 开局：填山、洗牌、重置游标。
pub fn prepare(ky: *Kyoku) void {
    fill(&ky.yama);
    shuffle(&ky.yama, ky.shuffle_seed);
    ky.yama.resetCursors();
}

/// 装入已定序的 136 张（与 `liveTileIndex` / 死山下标一致）。不洗牌。
pub fn loadWall(ky: *Kyoku, tiles: *const [WALL_LEN]Pai) void {
    ky.yama.tiles = tiles.*;
    ky.yama.resetCursors();
}

/// 从活牌山摸一张；山空返回 null。
pub fn drawLive(ky: *Kyoku) ?Pai {
    const y = &ky.yama;
    if (y.live_i >= y.live_end) return null;
    const pai = y.tiles[liveTileIndex(y.live_i)];
    y.live_i += 1;
    return pai;
}

/// 翻开下一张宝牌指示牌；已满则 null。
pub fn revealDora(ky: *Kyoku) ?Pai {
    const y = &ky.yama;
    if (y.dora_markers_len >= DORA_MARKER_CAP) return null;
    // 岭上占用死山局部 0..1（4 张）；表宝从局部 2 起，互不重叠
    const pai = y.tiles[doraTopIndex(y.dora_markers_len)];
    y.dora_markers[y.dora_markers_len] = pai;
    y.dora_markers_len += 1;
    return pai;
}

/// 岭上：按死山岭上侧垛序取牌，再 `live_end--`（海底并入死山）。
pub fn drawRinshan(ky: *Kyoku) ?Pai {
    const y = &ky.yama;
    if (y.live_end <= y.live_i) return null;
    if (y.rinshan_count >= 4) return null;

    const pai = y.tiles[rinshanTileIndex(y.rinshan_count)];
    y.rinshan_count += 1;
    y.live_end -= 1;
    return pai;
}

test "layout: live top-then-bottom" {
    try std.testing.expectEqual(@as(u8, 1), liveTileIndex(0));
    try std.testing.expectEqual(@as(u8, 0), liveTileIndex(1));
    try std.testing.expectEqual(@as(u8, 3), liveTileIndex(2));
    try std.testing.expectEqual(@as(u8, 2), liveTileIndex(3));
}

test "layout: dora top / ura bottom same stack" {
    try std.testing.expectEqual(@as(u8, 127), doraTopIndex(0));
    try std.testing.expectEqual(@as(u8, 126), uraBottomIndex(0));
    try std.testing.expectEqual(@as(u8, 129), doraTopIndex(1));
    try std.testing.expectEqual(@as(u8, 128), uraBottomIndex(1));
}

test "layout: rinshan from dead near side" {
    try std.testing.expectEqual(@as(u8, 123), rinshanTileIndex(0));
    try std.testing.expectEqual(@as(u8, 122), rinshanTileIndex(1));
    try std.testing.expectEqual(@as(u8, 125), rinshanTileIndex(2));
    try std.testing.expectEqual(@as(u8, 124), rinshanTileIndex(3));
}

test "rinshan shrinks live_end; dora markers independent" {
    var ky = Kyoku.init();
    prepare(&ky);
    try std.testing.expect(ky.yama.live_end == LIVE_WALL_LEN);
    try std.testing.expect(ky.yama.dora_markers_len == 0);
    try std.testing.expect(ky.yama.rinshan_count == 0);

    _ = revealDora(&ky) orelse unreachable;
    try std.testing.expect(ky.yama.dora_markers_len == 1);

    const before_live_end = ky.yama.live_end;
    const before_dora_n = ky.yama.dora_markers_len;
    _ = drawRinshan(&ky) orelse unreachable;
    try std.testing.expect(ky.yama.live_end == before_live_end - 1);
    try std.testing.expect(ky.yama.dora_markers_len == before_dora_n);
    try std.testing.expect(ky.yama.rinshan_count == 1);
}
