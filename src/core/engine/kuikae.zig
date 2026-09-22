//! 食替：吃碰后当巡禁切（现物；吃另禁筋另一头）。
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const pai_util = @import("pai.zig");

const Pai = types.Pai;
const Kyoku = kyoku_mod.Kyoku;

pub fn clear(ky: *Kyoku) void {
    ky.kuikae_len = 0;
}

pub fn forbids(ky: *const Kyoku, pai: Pai) bool {
    if (!ky.rules.kuikae) return false;
    return kindForbidden(ky.kuikae_kinds[0..ky.kuikae_len], pai);
}

pub fn kindForbidden(kinds: []const u8, pai: Pai) bool {
    const id = pai_util.kindId(pai) orelse return false;
    for (kinds) |k| {
        if (k == id) return true;
    }
    return false;
}

pub fn setPon(ky: *Kyoku, claimed: Pai) void {
    clear(ky);
    if (!ky.rules.kuikae) return;
    var buf: [1]u8 = undefined;
    const n = ponForbidKinds(claimed, &buf);
    @memcpy(ky.kuikae_kinds[0..n], buf[0..n]);
    ky.kuikae_len = n;
}

/// 吃：禁叫牌种；若吃边张且 `kuikae_suji`，另禁对侧筋。
pub fn setChi(ky: *Kyoku, claimed: Pai, consumed: [2]Pai) void {
    clear(ky);
    if (!ky.rules.kuikae) return;
    var buf: [2]u8 = undefined;
    const n = chiForbidKinds(claimed, consumed, ky.rules.kuikae_suji, &buf);
    @memcpy(ky.kuikae_kinds[0..n], buf[0..n]);
    ky.kuikae_len = n;
}

/// 碰后禁切 kinds（现物）。
pub fn ponForbidKinds(claimed: Pai, out: *[1]u8) u8 {
    const id = pai_util.kindId(claimed) orelse return 0;
    out[0] = id;
    return 1;
}

/// 吃后禁切 kinds。`suji=true` 时边张另禁对侧。
pub fn chiForbidKinds(claimed: Pai, consumed: [2]Pai, suji: bool, out: *[2]u8) u8 {
    const cid = pai_util.kindId(claimed) orelse return 0;
    var n: u8 = 0;
    out[n] = cid;
    n += 1;
    if (!suji) return n;

    const suit = pai_util.suit(claimed) orelse return n;
    var ranks: [3]u8 = .{
        pai_util.rank(claimed) orelse return n,
        pai_util.rank(consumed[0]) orelse return n,
        pai_util.rank(consumed[1]) orelse return n,
    };
    // 升序
    if (ranks[0] > ranks[1]) {
        const t = ranks[0];
        ranks[0] = ranks[1];
        ranks[1] = t;
    }
    if (ranks[1] > ranks[2]) {
        const t = ranks[1];
        ranks[1] = ranks[2];
        ranks[2] = t;
    }
    if (ranks[0] > ranks[1]) {
        const t = ranks[0];
        ranks[0] = ranks[1];
        ranks[1] = t;
    }

    const claimed_r = pai_util.rank(claimed).?;
    const extra: ?u8 = if (claimed_r == ranks[0] and ranks[2] < 9)
        kindFromSuitRank(suit, ranks[2] + 1)
    else if (claimed_r == ranks[2] and ranks[0] > 1)
        kindFromSuitRank(suit, ranks[0] - 1)
    else
        null;
    if (extra) |k| {
        if (k != cid) {
            out[n] = k;
            n += 1;
        }
    }
    return n;
}

fn kindFromSuitRank(suit_ch: u8, r: u8) ?u8 {
    const lit = pai_util.suitedLiteral(r, suit_ch);
    return pai_util.kindId(lit);
}

test "setChi: 23 chi 4 forbids 4 and 1" {
    const std = @import("std");
    var ky = Kyoku.init();
    setChi(&ky, "4m", .{ "2m", "3m" });
    try std.testing.expect(forbids(&ky, "4m"));
    try std.testing.expect(forbids(&ky, "1m"));
    try std.testing.expect(!forbids(&ky, "2m"));
    try std.testing.expect(!forbids(&ky, "7m"));
}

test "setChi: 56 chi 4 forbids 4 and 7" {
    const std = @import("std");
    var ky = Kyoku.init();
    setChi(&ky, "4p", .{ "5p", "6p" });
    try std.testing.expect(forbids(&ky, "4p"));
    try std.testing.expect(forbids(&ky, "7p"));
    try std.testing.expect(!forbids(&ky, "1p"));
}

test "setChi: kanchan only claimed" {
    const std = @import("std");
    var ky = Kyoku.init();
    setChi(&ky, "4s", .{ "3s", "5s" });
    try std.testing.expect(forbids(&ky, "4s"));
    try std.testing.expect(!forbids(&ky, "2s"));
    try std.testing.expect(!forbids(&ky, "6s"));
}

test "setPon: only claimed kind" {
    const std = @import("std");
    var ky = Kyoku.init();
    setPon(&ky, "E");
    try std.testing.expect(forbids(&ky, "E"));
    try std.testing.expect(!forbids(&ky, "S"));
}

test "chiForbidKinds: 78 chi 9 forbids 9 and 6" {
    const std = @import("std");
    var buf: [2]u8 = undefined;
    const n = chiForbidKinds("9s", .{ "7s", "8s" }, true, &buf);
    try std.testing.expectEqual(@as(u8, 2), n);
    try std.testing.expect(kindForbidden(buf[0..n], "9s"));
    try std.testing.expect(kindForbidden(buf[0..n], "6s"));
}
