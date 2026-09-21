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
    const id = pai_util.kindId(pai) orelse return false;
    var i: u8 = 0;
    while (i < ky.kuikae_len) : (i += 1) {
        if (ky.kuikae_kinds[i] == id) return true;
    }
    return false;
}

pub fn setPon(ky: *Kyoku, claimed: Pai) void {
    clear(ky);
    const id = pai_util.kindId(claimed) orelse return;
    ky.kuikae_kinds[0] = id;
    ky.kuikae_len = 1;
}

/// 吃：禁叫牌种；若吃边张，另禁对侧筋（123 吃 3 → 禁 1；456 吃 4 → 禁 7）。
pub fn setChi(ky: *Kyoku, claimed: Pai, consumed: [2]Pai) void {
    clear(ky);
    const cid = pai_util.kindId(claimed) orelse return;
    add(ky, cid);

    const suit = pai_util.suit(claimed) orelse return;
    var ranks: [3]u8 = .{
        pai_util.rank(claimed) orelse return,
        pai_util.rank(consumed[0]) orelse return,
        pai_util.rank(consumed[1]) orelse return,
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
    if (claimed_r == ranks[0] and ranks[2] < 9) {
        // 吃低边 → 禁高+1
        if (kindFromSuitRank(suit, ranks[2] + 1)) |k| add(ky, k);
    } else if (claimed_r == ranks[2] and ranks[0] > 1) {
        // 吃高边 → 禁低-1
        if (kindFromSuitRank(suit, ranks[0] - 1)) |k| add(ky, k);
    }
}

fn add(ky: *Kyoku, kind: u8) void {
    var i: u8 = 0;
    while (i < ky.kuikae_len) : (i += 1) {
        if (ky.kuikae_kinds[i] == kind) return;
    }
    if (ky.kuikae_len >= ky.kuikae_kinds.len) return;
    ky.kuikae_kinds[ky.kuikae_len] = kind;
    ky.kuikae_len += 1;
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
