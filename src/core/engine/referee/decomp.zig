//! 数牌单花色面子分解表：DecompTable / DecompTable_H。
//! 字牌不建表，见 `honorPureOk` / `honorPairIndex`。
const std = @import("std");

/// 状态编码空间大小：`5^9`（每位计数 0..4）。
pub const INDEX_SIZE: usize = 1_953_125;
/// 建表时单花色最大张数。
pub const MAX_TILES: u8 = 14;
/// 单方案最多面子数（14 张内纯面子至多 4）。
pub const MAX_MELDS: u8 = 4;

/// 面子类型。
pub const MeldKind = enum(u8) {
    /// 刻子（三同数字）。
    kotzu,
    /// 顺子（连续三张）。
    shuntsu,
};

/// 一个面子：类型 + 起始数字。
pub const Meld = struct {
    kind: MeldKind,
    /// 起始数字 1..9（刻子即该数字；顺子为最小数字）。
    start: u8,
};

/// 纯面子分解方案（无雀头）。`len == 0` 表示空方案（仅全零状态合法）。
pub const Plan = struct {
    melds: [MAX_MELDS]Meld = undefined,
    /// 有效面子个数。
    len: u8 = 0,
};

/// 含雀头分解方案：面子序列 + 雀头数字。
pub const PlanH = struct {
    melds: [MAX_MELDS]Meld = undefined,
    /// 有效面子个数。
    len: u8 = 0,
    /// 雀头数字 1..9。
    pair_tile: u8 = 0,
};

const empty_plans: [0]Plan = .{};
const empty_plans_h: [0]PlanH = .{};

var g_pure: std.AutoHashMap(u32, []const Plan) = undefined;
var g_pair: std.AutoHashMap(u32, []const PlanH) = undefined;
var g_ready: bool = false;

/// 将 9 位计数向量编码为表下标。
/// `counts[0]` 对应数字 1；`idx = Σ counts[i] · 5^i`。
pub fn encode(counts: *const [9]u8) u32 {
    var idx: u32 = 0;
    var base: u32 = 1;
    for (counts.*) |c| {
        std.debug.assert(c <= 4);
        idx += @as(u32, c) * base;
        base *= 5;
    }
    return idx;
}

/// 将表下标解码回 9 位计数向量，写入 `out`。
pub fn decode(idx: u32, out: *[9]u8) void {
    var x = idx;
    for (out) |*c| {
        c.* = @intCast(x % 5);
        x /= 5;
    }
}

/// 统计单花色总张数 `Σ counts[i]`。
pub fn sumCounts(counts: *const [9]u8) u8 {
    var s: u8 = 0;
    for (counts.*) |c| s += c;
    return s;
}

/// 懒建表：首次查询时用 `page_allocator` 填充 `g_pure` / `g_pair`。
fn ensureReady() void {
    if (g_ready) return;
    buildTables(std.heap.page_allocator) catch @panic("decomp table build failed");
    g_ready = true;
}

/// 查 DecompTable：返回该状态全部纯面子分解方案。
/// 空切片表示无法完整拆解；全零状态返回恰好一个空方案。
pub fn purePlans(counts: *const [9]u8) []const Plan {
    ensureReady();
    if (sumCounts(counts) > MAX_TILES) return &empty_plans;
    return g_pure.get(encode(counts)) orelse &empty_plans;
}

/// 查 DecompTable_H：返回该状态全部「雀头 + 纯面子」分解方案。
/// 空切片表示无法完整拆解。
pub fn pairPlans(counts: *const [9]u8) []const PlanH {
    ensureReady();
    if (sumCounts(counts) > MAX_TILES) return &empty_plans_h;
    return g_pair.get(encode(counts)) orelse &empty_plans_h;
}

/// 该状态是否存在至少一种纯面子分解（`purePlans` 非空）。
pub fn canPure(counts: *const [9]u8) bool {
    return purePlans(counts).len > 0;
}

/// 该状态是否存在至少一种含雀头分解（`pairPlans` 非空）。
pub fn canWithPair(counts: *const [9]u8) bool {
    return pairPlans(counts).len > 0;
}

/// 字牌非雀头是否可完整拆解：每种字牌张数必须为 0 或 3。
/// `honors` 顺序为东南西北中发白（下标 0..6）。
pub fn honorPureOk(honors: *const [7]u8) bool {
    for (honors.*) |c| {
        if (c != 0 and c != 3) return false;
    }
    return true;
}

/// 字牌含雀头是否可完整拆解：恰好一种字牌为 2，其余为 0 或 3。
/// 成功返回雀头下标 0..6；不合法返回 `null`。
pub fn honorPairIndex(honors: *const [7]u8) ?u8 {
    var pair: ?u8 = null;
    for (honors.*, 0..) |c, i| {
        if (c == 2) {
            if (pair != null) return null;
            pair = @intCast(i);
        } else if (c != 0 and c != 3) {
            return null;
        }
    }
    return pair;
}

/// 在子方案前插入一个面子，生成新方案。
fn prepend(plan: Plan, meld: Meld) Plan {
    std.debug.assert(plan.len < MAX_MELDS);
    var out: Plan = .{ .len = plan.len + 1 };
    out.melds[0] = meld;
    @memcpy(out.melds[1..][0..plan.len], plan.melds[0..plan.len]);
    return out;
}

/// 按总张数 0..`MAX_TILES` 递推填充 DecompTable 与 DecompTable_H。
fn buildTables(gpa: std.mem.Allocator) !void {
    g_pure = .init(gpa);
    g_pair = .init(gpa);

    // DecompTable[(0..)] = { [] }
    const zero_plan = try gpa.dupe(Plan, &[_]Plan{.{}});
    try g_pure.put(0, zero_plan);

    var n: u8 = 1;
    while (n <= MAX_TILES) : (n += 1) {
        var counts: [9]u8 = .{0} ** 9;
        try forEachState(n, &counts, gpa);
    }
}

/// 枚举所有总张数恰为 `n` 的有效状态，并对每个调用 `processState`。
fn forEachState(n: u8, counts: *[9]u8, gpa: std.mem.Allocator) !void {
    try recState(0, n, counts, gpa);
}

/// 递归填充 `counts[pos..]`，使剩余张数恰好分完（每位 0..4）。
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

/// 对单个状态建表：先由最小非零位做刻子/顺子转移写 DecompTable，
/// 再遍历所有可能雀头位置写 DecompTable_H。
fn processState(gpa: std.mem.Allocator, counts: *const [9]u8) !void {
    const idx = encode(counts);

    var p: usize = 0;
    while (p < 9 and counts[p] == 0) : (p += 1) {}
    std.debug.assert(p < 9);

    var plans: std.ArrayList(Plan) = .empty;
    defer plans.deinit(gpa);

    // 方式 A：刻子
    if (counts[p] >= 3) {
        var child = counts.*;
        child[p] -= 3;
        const child_plans = g_pure.get(encode(&child)) orelse &empty_plans;
        for (child_plans) |cp| {
            try plans.append(gpa, prepend(cp, .{ .kind = .kotzu, .start = @intCast(p + 1) }));
        }
    }

    // 方式 B：顺子
    if (p <= 6 and counts[p] >= 1 and counts[p + 1] >= 1 and counts[p + 2] >= 1) {
        var child = counts.*;
        child[p] -= 1;
        child[p + 1] -= 1;
        child[p + 2] -= 1;
        const child_plans = g_pure.get(encode(&child)) orelse &empty_plans;
        for (child_plans) |cp| {
            try plans.append(gpa, prepend(cp, .{ .kind = .shuntsu, .start = @intCast(p + 1) }));
        }
    }

    if (plans.items.len > 0) {
        const owned = try plans.toOwnedSlice(gpa);
        try g_pure.put(idx, owned);
    }

    // DecompTable_H：遍历所有可能雀头位置
    var plans_h: std.ArrayList(PlanH) = .empty;
    defer plans_h.deinit(gpa);

    var i: usize = 0;
    while (i < 9) : (i += 1) {
        if (counts[i] < 2) continue;
        var child = counts.*;
        child[i] -= 2;
        const child_plans = g_pure.get(encode(&child)) orelse &empty_plans;
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

test "encode decode roundtrip" {
    const c = [_]u8{ 0, 0, 1, 1, 1, 0, 0, 0, 0 };
    var out: [9]u8 = undefined;
    decode(encode(&c), &out);
    try std.testing.expectEqualSlices(u8, &c, &out);
}

test "empty state: one empty pure plan, no pair plan" {
    const z = [_]u8{0} ** 9;
    const ps = purePlans(&z);
    try std.testing.expectEqual(@as(usize, 1), ps.len);
    try std.testing.expectEqual(@as(u8, 0), ps[0].len);
    try std.testing.expect(!canWithPair(&z));
}

test "345 -> one shuntsu(3); no pair" {
    const c = [_]u8{ 0, 0, 1, 1, 1, 0, 0, 0, 0 };
    const ps = purePlans(&c);
    try std.testing.expectEqual(@as(usize, 1), ps.len);
    try std.testing.expectEqual(@as(u8, 1), ps[0].len);
    try std.testing.expect(ps[0].melds[0].kind == .shuntsu);
    try std.testing.expectEqual(@as(u8, 3), ps[0].melds[0].start);
    try std.testing.expect(!canWithPair(&c));
}

test "isolated 1+45 cannot pure-decompose" {
    const c = [_]u8{ 1, 0, 0, 1, 1, 0, 0, 0, 0 };
    try std.testing.expect(!canPure(&c));
    try std.testing.expectEqual(@as(usize, 0), purePlans(&c).len);
}

test "111 -> kotzu(1)" {
    const c = [_]u8{ 3, 0, 0, 0, 0, 0, 0, 0, 0 };
    const ps = purePlans(&c);
    try std.testing.expectEqual(@as(usize, 1), ps.len);
    try std.testing.expect(ps[0].melds[0].kind == .kotzu);
    try std.testing.expectEqual(@as(u8, 1), ps[0].melds[0].start);
}

test "11123 -> pair 1 + shuntsu 123" {
    const c = [_]u8{ 3, 1, 1, 0, 0, 0, 0, 0, 0 };
    try std.testing.expect(!canPure(&c));
    const hs = pairPlans(&c);
    try std.testing.expectEqual(@as(usize, 1), hs.len);
    try std.testing.expectEqual(@as(u8, 1), hs[0].pair_tile);
    try std.testing.expectEqual(@as(u8, 1), hs[0].len);
    try std.testing.expect(hs[0].melds[0].kind == .shuntsu);
    try std.testing.expectEqual(@as(u8, 1), hs[0].melds[0].start);
}

test "lone pair is valid PlanH with zero melds" {
    const c = [_]u8{ 2, 0, 0, 0, 0, 0, 0, 0, 0 };
    const hs = pairPlans(&c);
    try std.testing.expectEqual(@as(usize, 1), hs.len);
    try std.testing.expectEqual(@as(u8, 1), hs[0].pair_tile);
    try std.testing.expectEqual(@as(u8, 0), hs[0].len);
}

test "333444555 has both kotzu-path and shuntsu-path" {
    const c = [_]u8{ 0, 0, 3, 3, 3, 0, 0, 0, 0 };
    const ps = purePlans(&c);
    try std.testing.expect(ps.len >= 2);
    var saw_kotzu = false;
    var saw_shuntsu = false;
    for (ps) |plan| {
        try std.testing.expectEqual(@as(u8, 3), plan.len);
        if (plan.melds[0].kind == .kotzu) saw_kotzu = true;
        if (plan.melds[0].kind == .shuntsu) saw_shuntsu = true;
    }
    try std.testing.expect(saw_kotzu);
    try std.testing.expect(saw_shuntsu);
}

test "honor pure and pair rules" {
    try std.testing.expect(honorPureOk(&.{ 0, 3, 0, 0, 3, 0, 0 }));
    try std.testing.expect(!honorPureOk(&.{ 1, 0, 0, 0, 0, 0, 0 }));
    try std.testing.expect(!honorPureOk(&.{ 2, 0, 0, 0, 0, 0, 0 }));
    try std.testing.expect(!honorPureOk(&.{ 4, 0, 0, 0, 0, 0, 0 }));

    try std.testing.expectEqual(@as(?u8, 0), honorPairIndex(&.{ 2, 0, 3, 0, 0, 0, 0 }));
    try std.testing.expectEqual(@as(?u8, null), honorPairIndex(&.{ 2, 2, 0, 0, 0, 0, 0 }));
    try std.testing.expectEqual(@as(?u8, null), honorPairIndex(&.{ 3, 0, 0, 0, 0, 0, 0 }));
    try std.testing.expectEqual(@as(?u8, null), honorPairIndex(&.{ 1, 0, 0, 0, 0, 0, 0 }));
}
