//! 标准型面子分解：输入手牌计数，输出全部拆分方案。
//! 数牌查表、字牌刻/对拆分为内部实现。
const std = @import("std");

/// 闭张内最多面子数。
pub const MAX_MELDS: u8 = 4;
/// 单次 `decompose` 组合展开上限（防止极端牌姿写爆缓冲）。
const MAX_DECOMPS: usize = 64;

/// 面子类型。
pub const MeldKind = enum(u8) {
    kotzu,
    shuntsu,
};

/// 整手中的一个面子（牌种为 0..33）。
pub const Meld = struct {
    kind: MeldKind,
    /// 刻子：该牌种；顺子：起始牌种（同花色连续三张的最小）。
    tile: u8,
};

/// 一种完整标准型分解：雀头 + 闭张面子（不含副露）。
pub const Decomp = struct {
    /// 雀头牌种 0..33。
    pair: u8,
    melds: [MAX_MELDS]Meld = undefined,
    len: u8 = 0,
};

/// 对闭张 34 计数做标准型分解。
/// `need_mentsu` = `4 - fuuro_len`；要求 `Σ counts == 2 + 3 * need_mentsu`。
/// 写入 `out`，返回实际写出的子切片（可能被截断到 `out.len`）。
pub fn decompose(counts: *const [34]u8, need_mentsu: u8, out: []Decomp) []Decomp {
    if (need_mentsu > MAX_MELDS) return out[0..0];
    const expect: u8 = 2 + 3 * need_mentsu;
    if (sum34(counts) != expect) return out[0..0];

    var man: [9]u8 = undefined;
    var pin: [9]u8 = undefined;
    var sou: [9]u8 = undefined;
    var hon: [7]u8 = undefined;
    @memcpy(&man, counts[0..9]);
    @memcpy(&pin, counts[9..18]);
    @memcpy(&sou, counts[18..27]);
    @memcpy(&hon, counts[27..34]);

    var n: usize = 0;
    var pair_kind: u8 = 0;
    while (pair_kind < 34) : (pair_kind += 1) {
        if (counts[pair_kind] < 2) continue;
        n = emitWithPair(pair_kind, &man, &pin, &sou, &hon, need_mentsu, out, n);
        if (n >= out.len) break;
    }
    return out[0..n];
}

fn emitWithPair(
    pair_kind: u8,
    man: *const [9]u8,
    pin: *const [9]u8,
    sou: *const [9]u8,
    hon: *const [7]u8,
    need_mentsu: u8,
    out: []Decomp,
    start: usize,
) usize {
    // 各组方案：pair 组用含雀头，其余用纯面子
    var g0: GroupPlans = undefined;
    var g1: GroupPlans = undefined;
    var g2: GroupPlans = undefined;
    var g3: GroupPlans = undefined;
    var groups = [_]*GroupPlans{ &g0, &g1, &g2, &g3 };

    const pair_group: u8 = if (pair_kind < 9) 0 else if (pair_kind < 18) 1 else if (pair_kind < 27) 2 else 3;

    if (pair_group == 0) {
        if (!fillSuitedPair(&g0, man, pair_kind - 0, 0)) return start;
    } else {
        if (!fillSuitedPure(&g0, man, 0)) return start;
    }
    if (pair_group == 1) {
        if (!fillSuitedPair(&g1, pin, pair_kind - 9, 9)) return start;
    } else {
        if (!fillSuitedPure(&g1, pin, 9)) return start;
    }
    if (pair_group == 2) {
        if (!fillSuitedPair(&g2, sou, pair_kind - 18, 18)) return start;
    } else {
        if (!fillSuitedPure(&g2, sou, 18)) return start;
    }
    if (pair_group == 3) {
        if (!fillHonorPair(&g3, hon, pair_kind)) return start;
    } else {
        if (!fillHonorPure(&g3, hon)) return start;
    }

    return product(pair_kind, &groups, need_mentsu, out, start);
}

/// 一组花色/字牌的面子列表（中间结果，无雀头）。
const MeldBag = struct {
    melds: [MAX_MELDS]Meld = undefined,
    len: u8 = 0,
};

const GroupPlans = struct {
    plans: [16]MeldBag = undefined,
    len: u8 = 0,
};

fn fillSuitedPure(g: *GroupPlans, counts: *const [9]u8, base: u8) bool {
    const ps = suitedPurePlans(counts);
    if (ps.len == 0) return false;
    g.len = 0;
    for (ps) |sp| {
        if (g.len >= g.plans.len) break;
        g.plans[g.len] = suitPlanToMelds(sp, base);
        g.len += 1;
    }
    return g.len > 0;
}

fn fillSuitedPair(g: *GroupPlans, counts: *const [9]u8, local_pair: u8, base: u8) bool {
    const want: u8 = local_pair + 1;
    const ps = suitedPairPlans(counts);
    g.len = 0;
    for (ps) |sp| {
        if (sp.pair_tile != want) continue;
        if (g.len >= g.plans.len) break;
        g.plans[g.len] = suitPlanHToMelds(sp, base);
        g.len += 1;
    }
    return g.len > 0;
}

fn fillHonorPure(g: *GroupPlans, honors: *const [7]u8) bool {
    const p = honorPurePlan(honors) orelse return false;
    g.plans[0] = honorPlanToMelds(p);
    g.len = 1;
    return true;
}

fn fillHonorPair(g: *GroupPlans, honors: *const [7]u8, pair_kind: u8) bool {
    const p = honorPairPlan(honors) orelse return false;
    if (p.pair_tile != pair_kind - 26) return false;
    g.plans[0] = honorPlanHToMelds(p);
    g.len = 1;
    return true;
}

fn suitPlanToMelds(sp: SuitPlan, base: u8) MeldBag {
    var bag: MeldBag = .{};
    var i: u8 = 0;
    while (i < sp.len) : (i += 1) {
        bag.melds[i] = .{
            .kind = sp.melds[i].kind,
            .tile = base + (sp.melds[i].start - 1),
        };
    }
    bag.len = sp.len;
    return bag;
}

fn suitPlanHToMelds(sp: SuitPlanH, base: u8) MeldBag {
    var bag: MeldBag = .{};
    var i: u8 = 0;
    while (i < sp.len) : (i += 1) {
        bag.melds[i] = .{
            .kind = sp.melds[i].kind,
            .tile = base + (sp.melds[i].start - 1),
        };
    }
    bag.len = sp.len;
    return bag;
}

fn honorPlanToMelds(sp: SuitPlan) MeldBag {
    var bag: MeldBag = .{};
    var i: u8 = 0;
    while (i < sp.len) : (i += 1) {
        bag.melds[i] = .{
            .kind = .kotzu,
            .tile = 26 + sp.melds[i].start,
        };
    }
    bag.len = sp.len;
    return bag;
}

fn honorPlanHToMelds(sp: SuitPlanH) MeldBag {
    var bag: MeldBag = .{};
    var i: u8 = 0;
    while (i < sp.len) : (i += 1) {
        bag.melds[i] = .{
            .kind = .kotzu,
            .tile = 26 + sp.melds[i].start,
        };
    }
    bag.len = sp.len;
    return bag;
}

fn product(pair: u8, groups: *const [4]*GroupPlans, need_mentsu: u8, out: []Decomp, start: usize) usize {
    var n = start;
    var idx: [4]u8 = .{ 0, 0, 0, 0 };
    while (true) {
        var total: u8 = 0;
        var i: u8 = 0;
        while (i < 4) : (i += 1) total += groups[i].plans[idx[i]].len;
        if (total == need_mentsu and n < out.len) {
            var d: Decomp = .{ .pair = pair };
            var m: u8 = 0;
            i = 0;
            while (i < 4) : (i += 1) {
                const gp = groups[i].plans[idx[i]];
                var j: u8 = 0;
                while (j < gp.len) : (j += 1) {
                    d.melds[m] = gp.melds[j];
                    m += 1;
                }
            }
            d.len = m;
            out[n] = d;
            n += 1;
        }

        var g: usize = 4;
        while (g > 0) {
            g -= 1;
            idx[g] += 1;
            if (idx[g] < groups[g].len) break;
            idx[g] = 0;
            if (g == 0) return n;
        }
    }
}

fn sum34(counts: *const [34]u8) u8 {
    var s: u8 = 0;
    for (counts.*) |c| s += c;
    return s;
}

// ---------------------------------------------------------------------------
// 内部：单花色 / 字牌方案
// ---------------------------------------------------------------------------

const SuitMeld = struct {
    kind: MeldKind,
    /// 数牌 1..9；字牌 1..7。
    start: u8,
};

const SuitPlan = struct {
    melds: [MAX_MELDS]SuitMeld = undefined,
    len: u8 = 0,
};

const SuitPlanH = struct {
    melds: [MAX_MELDS]SuitMeld = undefined,
    len: u8 = 0,
    pair_tile: u8 = 0,
};

const empty_pure: [0]SuitPlan = .{};
const empty_pair: [0]SuitPlanH = .{};

var g_pure: std.AutoHashMap(u32, []const SuitPlan) = undefined;
var g_pair: std.AutoHashMap(u32, []const SuitPlanH) = undefined;
var g_ready: bool = false;

const MAX_TILES: u8 = 14;

fn suitedPurePlans(counts: *const [9]u8) []const SuitPlan {
    ensureReady();
    if (sum9(counts) > MAX_TILES) return &empty_pure;
    return g_pure.get(encode(counts)) orelse &empty_pure;
}

fn suitedPairPlans(counts: *const [9]u8) []const SuitPlanH {
    ensureReady();
    if (sum9(counts) > MAX_TILES) return &empty_pair;
    return g_pair.get(encode(counts)) orelse &empty_pair;
}

fn honorPurePlan(honors: *const [7]u8) ?SuitPlan {
    var plan: SuitPlan = .{};
    for (honors.*, 0..) |c, i| {
        if (c == 0) continue;
        if (c != 3) return null;
        if (plan.len >= MAX_MELDS) return null;
        plan.melds[plan.len] = .{ .kind = .kotzu, .start = @intCast(i + 1) };
        plan.len += 1;
    }
    return plan;
}

fn honorPairPlan(honors: *const [7]u8) ?SuitPlanH {
    var plan: SuitPlanH = .{};
    var pair: ?u8 = null;
    for (honors.*, 0..) |c, i| {
        if (c == 2) {
            if (pair != null) return null;
            pair = @intCast(i + 1);
        } else if (c == 3) {
            if (plan.len >= MAX_MELDS) return null;
            plan.melds[plan.len] = .{ .kind = .kotzu, .start = @intCast(i + 1) };
            plan.len += 1;
        } else if (c != 0) {
            return null;
        }
    }
    plan.pair_tile = pair orelse return null;
    return plan;
}

fn encode(counts: *const [9]u8) u32 {
    var idx: u32 = 0;
    var base: u32 = 1;
    for (counts.*) |c| {
        std.debug.assert(c <= 4);
        idx += @as(u32, c) * base;
        base *= 5;
    }
    return idx;
}

fn decode(idx: u32, out: *[9]u8) void {
    var x = idx;
    for (out) |*c| {
        c.* = @intCast(x % 5);
        x /= 5;
    }
}

fn sum9(counts: *const [9]u8) u8 {
    var s: u8 = 0;
    for (counts.*) |c| s += c;
    return s;
}

fn ensureReady() void {
    if (g_ready) return;
    buildTables(std.heap.page_allocator) catch @panic("decomp table build failed");
    g_ready = true;
}

fn prepend(plan: SuitPlan, meld: SuitMeld) SuitPlan {
    std.debug.assert(plan.len < MAX_MELDS);
    var out: SuitPlan = .{ .len = plan.len + 1 };
    out.melds[0] = meld;
    @memcpy(out.melds[1..][0..plan.len], plan.melds[0..plan.len]);
    return out;
}

fn buildTables(gpa: std.mem.Allocator) !void {
    g_pure = .init(gpa);
    g_pair = .init(gpa);

    const zero_plan = try gpa.dupe(SuitPlan, &[_]SuitPlan{.{}});
    try g_pure.put(0, zero_plan);

    var n: u8 = 1;
    while (n <= MAX_TILES) : (n += 1) {
        var counts: [9]u8 = .{0} ** 9;
        try recState(0, n, &counts, gpa);
    }
}

fn recState(pos: usize, remaining: u8, counts: *[9]u8, gpa: std.mem.Allocator) !void {
    if (pos == 9) {
        if (remaining == 0) try processState(gpa, counts);
        return;
    }
    const max_c: u8 = @min(4, remaining);
    var c: u8 = 0;
    while (c <= max_c) : (c += 1) {
        counts[pos] = c;
        try recState(pos + 1, remaining - c, counts, gpa);
    }
    counts[pos] = 0;
}

fn processState(gpa: std.mem.Allocator, counts: *const [9]u8) !void {
    const idx = encode(counts);

    var p: usize = 0;
    while (p < 9 and counts[p] == 0) : (p += 1) {}
    std.debug.assert(p < 9);

    var plans: std.ArrayList(SuitPlan) = .empty;
    defer plans.deinit(gpa);

    if (counts[p] >= 3) {
        var child = counts.*;
        child[p] -= 3;
        const child_plans = g_pure.get(encode(&child)) orelse &empty_pure;
        for (child_plans) |cp| {
            try plans.append(gpa, prepend(cp, .{ .kind = .kotzu, .start = @intCast(p + 1) }));
        }
    }

    if (p <= 6 and counts[p] >= 1 and counts[p + 1] >= 1 and counts[p + 2] >= 1) {
        var child = counts.*;
        child[p] -= 1;
        child[p + 1] -= 1;
        child[p + 2] -= 1;
        const child_plans = g_pure.get(encode(&child)) orelse &empty_pure;
        for (child_plans) |cp| {
            try plans.append(gpa, prepend(cp, .{ .kind = .shuntsu, .start = @intCast(p + 1) }));
        }
    }

    if (plans.items.len > 0) {
        const owned = try plans.toOwnedSlice(gpa);
        try g_pure.put(idx, owned);
    }

    var plans_h: std.ArrayList(SuitPlanH) = .empty;
    defer plans_h.deinit(gpa);

    var i: usize = 0;
    while (i < 9) : (i += 1) {
        if (counts[i] < 2) continue;
        var child = counts.*;
        child[i] -= 2;
        const child_plans = g_pure.get(encode(&child)) orelse &empty_pure;
        for (child_plans) |cp| {
            try plans_h.append(gpa, .{
                .melds = cp.melds,
                .len = cp.len,
                .pair_tile = @intCast(i + 1),
            });
        }
    }

    if (plans_h.items.len > 0) {
        const owned = try plans_h.toOwnedSlice(gpa);
        try g_pair.put(idx, owned);
    }
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

fn countsFromKinds(kinds: []const u8) [34]u8 {
    var c: [34]u8 = .{0} ** 34;
    for (kinds) |k| c[k] += 1;
    return c;
}

test "encode decode roundtrip" {
    const c = [_]u8{ 0, 0, 1, 1, 1, 0, 0, 0, 0 };
    var out: [9]u8 = undefined;
    decode(encode(&c), &out);
    try std.testing.expectEqualSlices(u8, &c, &out);
}

test "decompose: 123m456m789m EEE SS" {
    // 0,1,2 + 3,4,5 + 6,7,8 + 27,27,27 + 28,28
    const kinds = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 27, 27, 27, 28, 28 };
    const c = countsFromKinds(&kinds);
    var buf: [MAX_DECOMPS]Decomp = undefined;
    const plans = decompose(&c, 4, &buf);
    try std.testing.expect(plans.len >= 1);
    try std.testing.expectEqual(@as(u8, 28), plans[0].pair);
    try std.testing.expectEqual(@as(u8, 4), plans[0].len);
}

test "decompose: 11123m cannot (need pair+1shuntsu only covers 5 tiles)" {
    const kinds = [_]u8{ 0, 0, 0, 1, 2 };
    const c = countsFromKinds(&kinds);
    var buf: [8]Decomp = undefined;
    // 5 tiles → need_mentsu=1 → expect 5 ok
    const plans = decompose(&c, 1, &buf);
    try std.testing.expectEqual(@as(usize, 1), plans.len);
    try std.testing.expectEqual(@as(u8, 0), plans[0].pair);
    try std.testing.expectEqual(@as(u8, 1), plans[0].len);
    try std.testing.expect(plans[0].melds[0].kind == .shuntsu);
    try std.testing.expectEqual(@as(u8, 0), plans[0].melds[0].tile);
}

test "decompose: isolated tiles fail" {
    const kinds = [_]u8{ 0, 3, 4 }; // 1m 4m 5m
    const c = countsFromKinds(&kinds);
    var buf: [4]Decomp = undefined;
    try std.testing.expectEqual(@as(usize, 0), decompose(&c, 1, &buf).len);
}

test "decompose: 333444555m + 11p → multi plans" {
    // man 333444555 (kinds 2,3,4 x3) + pin 11 (kind 9 x2)
    var kinds_buf: [11]u8 = undefined;
    var n: usize = 0;
    for (0..3) |_| {
        kinds_buf[n] = 2;
        n += 1;
        kinds_buf[n] = 3;
        n += 1;
        kinds_buf[n] = 4;
        n += 1;
    }
    kinds_buf[n] = 9;
    n += 1;
    kinds_buf[n] = 9;
    n += 1;
    const c = countsFromKinds(kinds_buf[0..n]);
    var buf: [MAX_DECOMPS]Decomp = undefined;
    const plans = decompose(&c, 3, &buf);
    try std.testing.expect(plans.len >= 2);
    try std.testing.expectEqual(@as(u8, 9), plans[0].pair);
    for (plans) |hp| {
        try std.testing.expectEqual(@as(u8, 3), hp.len);
    }
}

test "honor-only: EEE SSS WW" {
    const kinds = [_]u8{ 27, 27, 27, 28, 28, 28, 29, 29 };
    const c = countsFromKinds(&kinds);
    var buf: [8]Decomp = undefined;
    const plans = decompose(&c, 2, &buf);
    try std.testing.expectEqual(@as(usize, 1), plans.len);
    try std.testing.expectEqual(@as(u8, 29), plans[0].pair);
    try std.testing.expectEqual(@as(u8, 2), plans[0].len);
}
