const std = @import("std");
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const Kyoku = kyoku_mod.Kyoku;
const Yama = kyoku_mod.Yama;
const Pai = types.Pai;
const WALL_LEN = kyoku_mod.WALL_LEN;
const LIVE_WALL_LEN = kyoku_mod.LIVE_WALL_LEN;
const DORA_MARKER_CAP = kyoku_mod.DORA_MARKER_CAP;

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

/// 从活牌山摸一张；山空返回 null。
pub fn drawLive(ky: *Kyoku) ?Pai {
    const y = &ky.yama;
    if (y.live_i >= y.live_end) return null;
    const pai = y.tiles[y.live_i];
    y.live_i += 1;
    return pai;
}

/// 翻开下一张宝牌指示牌；已满则 null。下标走开局死山起点，不跟 live_end。
pub fn revealDora(ky: *Kyoku) ?Pai {
    const y = &ky.yama;
    if (y.dora_markers_len >= DORA_MARKER_CAP) return null;
    if (y.dora_i > y.rinshan_i) return null;
    const pai = y.tiles[y.dora_i];
    y.dora_markers[y.dora_markers_len] = pai;
    y.dora_markers_len += 1;
    y.dora_i += 1;
    return pai;
}

/// 岭上：取 rinshan_i，再 live_end--（海底并入死山）。
pub fn drawRinshan(ky: *Kyoku) ?Pai {
    const y = &ky.yama;
    if (y.live_end <= y.live_i) return null;
    // 最多 4 次岭上（开局死山 14，指示+岭上共用）
    const drawn: u8 = @intCast((WALL_LEN - 1) - @as(usize, y.rinshan_i));
    if (drawn >= 4) return null;
    if (y.rinshan_i < y.dora_i) return null;

    const pai = y.tiles[y.rinshan_i];
    y.rinshan_i -= 1;
    y.live_end -= 1;
    return pai;
}

test "rinshan shrinks live_end; dora_i stays on opening dead start" {
    var ky = Kyoku.init();
    prepare(&ky);
    try std.testing.expect(ky.yama.live_end == LIVE_WALL_LEN);
    try std.testing.expect(ky.yama.dora_i == LIVE_WALL_LEN);

    _ = revealDora(&ky) orelse unreachable;
    try std.testing.expect(ky.yama.dora_i == LIVE_WALL_LEN + 1);

    const before_live_end = ky.yama.live_end;
    const before_dora_i = ky.yama.dora_i;
    _ = drawRinshan(&ky) orelse unreachable;
    try std.testing.expect(ky.yama.live_end == before_live_end - 1);
    try std.testing.expect(ky.yama.dora_i == before_dora_i);
}
