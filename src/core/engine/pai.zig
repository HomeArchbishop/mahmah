const std = @import("std");
const types = @import("../types.zig");
const Pai = types.Pai;

/// 数牌花色；字牌为 null。
pub fn suit(pai: Pai) ?u8 {
    if (pai.len < 2) return null;
    const c = pai[pai.len - 1];
    if (c == 'r') {
        if (pai.len < 3) return null;
        return pai[pai.len - 2];
    }
    return switch (c) {
        'm', 'p', 's' => c,
        else => null,
    };
}

/// 数牌花色编号：m=0, p=1, s=2；字牌 / 非法为 null。
pub fn suitId(pai: Pai) ?u8 {
    return switch (suit(pai) orelse return null) {
        'm' => 0,
        'p' => 1,
        's' => 2,
        else => null,
    };
}

/// 数牌点数 1..9；字牌 / 非法为 null。赤宝作 5。
pub fn rank(pai: Pai) ?u8 {
    if (suit(pai) == null) return null;
    if (pai.len >= 3 and pai[pai.len - 1] == 'r') return 5;
    if (pai.len < 2) return null;
    const d = pai[0];
    if (d < '1' or d > '9') return null;
    return d - '0';
}

/// 字牌（东南西北白发中）。
pub fn isJihai(pai: Pai) bool {
    return suit(pai) == null and pai.len == 1 and switch (pai[0]) {
        'E', 'S', 'W', 'N', 'P', 'F', 'C' => true,
        else => false,
    };
}

/// 数牌（万饼索，含赤宝）。
pub fn isSuuhai(pai: Pai) bool {
    return suit(pai) != null;
}

/// 老头牌：数牌 1 / 9（不含字牌）。
pub fn isRoutouhai(pai: Pai) bool {
    const r = rank(pai) orelse return false;
    return r == 1 or r == 9;
}

/// 幺九牌：老头牌或字牌。
pub fn isYaochuuhai(pai: Pai) bool {
    return isJihai(pai) or isRoutouhai(pai);
}

/// 风牌（东南西北）。
pub fn isKazehai(pai: Pai) bool {
    return pai.len == 1 and switch (pai[0]) {
        'E', 'S', 'W', 'N' => true,
        else => false,
    };
}

/// 三元牌（白发中）。
pub fn isSangenpai(pai: Pai) bool {
    return pai.len == 1 and switch (pai[0]) {
        'P', 'F', 'C' => true,
        else => false,
    };
}

/// 中张牌：数牌 2..8。
pub fn isChunchanpai(pai: Pai) bool {
    const r = rank(pai) orelse return false;
    return r >= 2 and r <= 8;
}

/// 同种牌（5m 与 5mr 视为同种）。
pub fn sameKind(a: Pai, b: Pai) bool {
    if (types.paiEql(a, b)) return true;
    const sa = suit(a);
    const sb = suit(b);
    if (sa == null or sb == null) return false;
    if (sa.? != sb.?) return false;
    const ra = rank(a) orelse return false;
    const rb = rank(b) orelse return false;
    return ra == rb;
}

/// 牌种编号 0..33（m1-9,p1-9,s1-9,E S W N P F C）；非法为 null。
pub fn kindId(pai: Pai) ?u8 {
    if (isJihai(pai)) {
        return switch (pai[0]) {
            'E' => 27,
            'S' => 28,
            'W' => 29,
            'N' => 30,
            'P' => 31,
            'F' => 32,
            'C' => 33,
            else => null,
        };
    }
    const s = suit(pai) orelse return null;
    const r = rank(pai) orelse return null;
    const base: u8 = switch (s) {
        'm' => 0,
        'p' => 9,
        's' => 18,
        else => return null,
    };
    return base + (r - 1);
}

/// 牌种编号 0..33 → 代表牌（数牌非赤；字牌单字符）。
pub fn fromKindId(id: u8) ?Pai {
    if (id < 9) return suitedLiteral(id + 1, 'm');
    if (id < 18) return suitedLiteral(id - 9 + 1, 'p');
    if (id < 27) return suitedLiteral(id - 18 + 1, 's');
    return switch (id) {
        27 => "E",
        28 => "S",
        29 => "W",
        30 => "N",
        31 => "P",
        32 => "F",
        33 => "C",
        else => null,
    };
}

/// 静态字面量：数牌 rank+suit（非赤）。
pub fn suitedLiteral(r: u8, s: u8) Pai {
    return switch (s) {
        'm' => switch (r) {
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
        'p' => switch (r) {
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
        else => switch (r) {
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

/// 是否赤宝（`5mr` / `5pr` / `5sr`）。
pub fn isRed(pai: Pai) bool {
    return pai.len >= 3 and pai[pai.len - 1] == 'r';
}

/// 指示牌 → 宝牌种（数牌 9→1；风东南西北；三元白发中）。
pub fn doraKindFromIndicator(indicator: Pai) ?u8 {
    const id = kindId(indicator) orelse return null;
    if (id < 27) {
        const base = id / 9 * 9;
        return @intCast(base + (id - base + 1) % 9);
    }
    if (id < 31) return @intCast(27 + (id - 27 + 1) % 4);
    return @intCast(31 + (id - 31 + 1) % 3);
}

pub fn countKind(hand: []const Pai, target: Pai) u8 {
    var n: u8 = 0;
    for (hand) |p| {
        if (sameKind(p, target)) n += 1;
    }
    return n;
}

/// 手牌中取出与 target 同种的最多 `want` 张（优先非赤）。
pub fn takeKinds(hand: []const Pai, target: Pai, want: u8, out: []Pai) u8 {
    var n: u8 = 0;
    for (hand) |p| {
        if (n >= want) break;
        if (!sameKind(p, target)) continue;
        if (isRed(p)) continue;
        out[n] = p;
        n += 1;
    }
    for (hand) |p| {
        if (n >= want) break;
        if (!sameKind(p, target)) continue;
        if (!isRed(p)) continue;
        out[n] = p;
        n += 1;
    }
    return n;
}

test "sameKind red five" {
    try std.testing.expect(sameKind("5m", "5mr"));
    try std.testing.expect(kindId("5mr").? == 4);
}

test "tile class: routou yaochuu sangen chunchan" {
    try std.testing.expect(isRoutouhai("1m"));
    try std.testing.expect(isRoutouhai("9s"));
    try std.testing.expect(!isRoutouhai("E"));
    try std.testing.expect(!isRoutouhai("5m"));

    try std.testing.expect(isJihai("E"));
    try std.testing.expect(isJihai("P"));
    try std.testing.expect(!isJihai("1m"));

    try std.testing.expect(isYaochuuhai("1p"));
    try std.testing.expect(isYaochuuhai("N"));
    try std.testing.expect(!isYaochuuhai("5mr"));

    try std.testing.expect(isKazehai("S"));
    try std.testing.expect(!isKazehai("C"));

    try std.testing.expect(isSangenpai("P"));
    try std.testing.expect(isSangenpai("F"));
    try std.testing.expect(isSangenpai("C"));
    try std.testing.expect(!isSangenpai("E"));

    try std.testing.expect(isChunchanpai("2m"));
    try std.testing.expect(isChunchanpai("5mr"));
    try std.testing.expect(!isChunchanpai("1m"));
    try std.testing.expect(!isChunchanpai("E"));

    try std.testing.expect(isSuuhai("5mr"));
    try std.testing.expect(!isSuuhai("W"));
}
