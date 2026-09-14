//! 牌形检测：和形、九种九牌等。
const pai_util = @import("../pai.zig");
const types = @import("../../types.zig");
const Pai = types.Pai;

/// 标准型 / 七对 / 国士：闭张手牌能否和了（已含所和之牌）。
/// `fuuro_len`：副露面子数，标准型需再凑 `4 - fuuro_len` 面子 + 雀头。
pub fn canAgari(closed: []const Pai, fuuro_len: u8) bool {
    if (fuuro_len > 4) return false;
    if (fuuro_len == 0) {
        if (isChiitoi(closed)) return true;
        if (isKokushi(closed)) return true;
    }
    const need_mentsu: u8 = 4 - fuuro_len;
    const expect_len: usize = 2 + 3 * @as(usize, need_mentsu);
    if (closed.len != expect_len) return false;

    var counts: [34]u8 = .{0} ** 34;
    for (closed) |p| {
        const id = pai_util.kindId(p) orelse return false;
        counts[id] += 1;
    }
    return canStandard(&counts, need_mentsu);
}

fn isChiitoi(closed: []const Pai) bool {
    if (closed.len != 14) return false;
    var counts: [34]u8 = .{0} ** 34;
    for (closed) |p| {
        const id = pai_util.kindId(p) orelse return false;
        counts[id] += 1;
    }
    var pairs: u8 = 0;
    for (counts) |c| {
        if (c == 0) continue;
        if (c != 2) return false;
        pairs += 1;
    }
    return pairs == 7;
}

fn isKokushi(closed: []const Pai) bool {
    if (closed.len != 14) return false;
    const terminals = [_]u8{ 0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33 };
    var counts: [34]u8 = .{0} ** 34;
    for (closed) |p| {
        const id = pai_util.kindId(p) orelse return false;
        counts[id] += 1;
    }
    var pair = false;
    for (terminals) |t| {
        const c = counts[t];
        if (c == 0) return false;
        if (c == 1) continue;
        if (c == 2) {
            if (pair) return false;
            pair = true;
            continue;
        }
        return false;
    }
    for (counts, 0..) |c, i| {
        var is_t = false;
        for (terminals) |t| {
            if (t == i) {
                is_t = true;
                break;
            }
        }
        if (!is_t and c != 0) return false;
    }
    return pair;
}

fn canStandard(counts: *[34]u8, need_mentsu: u8) bool {
    var id: u8 = 0;
    while (id < 34) : (id += 1) {
        if (counts[id] < 2) continue;
        counts[id] -= 2;
        if (mentsuOk(counts, need_mentsu)) {
            counts[id] += 2;
            return true;
        }
        counts[id] += 2;
    }
    return false;
}

fn mentsuOk(counts: *[34]u8, left: u8) bool {
    if (left == 0) {
        for (counts.*) |c| {
            if (c != 0) return false;
        }
        return true;
    }
    var id: u8 = 0;
    while (id < 34) : (id += 1) {
        if (counts[id] == 0) continue;

        if (counts[id] >= 3) {
            counts[id] -= 3;
            if (mentsuOk(counts, left - 1)) {
                counts[id] += 3;
                return true;
            }
            counts[id] += 3;
        }

        if (id < 27) {
            const r = id % 9;
            if (r <= 6 and counts[id] > 0 and counts[id + 1] > 0 and counts[id + 2] > 0) {
                counts[id] -= 1;
                counts[id + 1] -= 1;
                counts[id + 2] -= 1;
                if (mentsuOk(counts, left - 1)) {
                    counts[id] += 1;
                    counts[id + 1] += 1;
                    counts[id + 2] += 1;
                    return true;
                }
                counts[id] += 1;
                counts[id + 1] += 1;
                counts[id + 2] += 1;
            }
        }
        return false;
    }
    return false;
}

/// 闭张 + 所和之牌拼临时手，判断能否和。
pub fn canWinWith(closed: []const Pai, winning: Pai, fuuro_len: u8) bool {
    var buf: [14]Pai = undefined;
    if (closed.len >= buf.len) return false;
    @memcpy(buf[0..closed.len], closed);
    buf[closed.len] = winning;
    return canAgari(buf[0 .. closed.len + 1], fuuro_len);
}

/// 九种九牌：起手（13 张）不同幺九种类 ≥ 9。
pub fn kyushuKinds(hand: []const Pai) u8 {
    var seen: [34]bool = .{false} ** 34;
    var n: u8 = 0;
    for (hand) |p| {
        if (!pai_util.isTerminalOrHonor(p)) continue;
        const id = pai_util.kindId(p) orelse continue;
        if (seen[id]) continue;
        seen[id] = true;
        n += 1;
    }
    return n;
}
