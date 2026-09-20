//! 特殊形：七对 / 国士 / 九种。只判形状，不含振听与役符。
const pai_util = @import("../pai.zig");
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");

const Pai = types.Pai;
const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

/// 门清特殊形。
pub const SpecialForm = enum { chiitoi, kokushi };

/// 起手 13 张中不同幺九种类数（九种九牌用）。
pub fn kyushuKinds(hand: []const Pai) u8 {
    var seen: [34]bool = .{false} ** 34;
    var n: u8 = 0;
    for (hand) |p| {
        if (!pai_util.isYaochuuhai(p)) continue;
        const id = pai_util.kindId(p) orelse continue;
        if (seen[id]) continue;
        seen[id] = true;
        n += 1;
    }
    return n;
}

/// 门清特殊形检测：是七对/国士则返回种类，否则 null。只判形状。
/// 七对/国士要求完全无副露（含暗杠）。
pub fn detectSpecialForm(ky: *const Kyoku, seat: Seat, tsumo: bool) ?SpecialForm {
    if (ky.players[seat].fuuro_len != 0) return null;
    var closed_buf: [14]Pai = undefined;
    const closed = collectClosed(ky, seat, tsumo, &closed_buf) orelse return null;
    if (isChiitoi(closed)) return .chiitoi;
    if (isKokushi(closed)) return .kokushi;
    return null;
}

fn collectClosed(ky: *const Kyoku, seat: Seat, tsumo: bool, buf: *[14]Pai) ?[]const Pai {
    const winning = (if (tsumo) ky.drawn else ky.response_pai) orelse return null;
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

/// 14 张闭张是否七对形。
pub fn isChiitoi(closed: []const Pai) bool {
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

/// 14 张闭张是否国士形。
pub fn isKokushi(closed: []const Pai) bool {
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
