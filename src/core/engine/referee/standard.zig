//! 标准型拆解（4 面子 + 雀头；不含七对/国士、不含役/振听）。
//!
//! # 术语
//! - **进张** `winning`：自摸为 `drawn`，荣和为 `response_pai`
//! - **闭张** `closed`：不含副露的手牌（荣和时含进张）
//! - **结构** `Shape`：雀头 + 若干闭张面子（尚无进张归属、无副露）
//! - **块** `Block`：`kind`（雀头/顺/刻/杠）+ 是否鸣牌副露 + 进张标记
//! - **拆解** `StandardDecomp`：恰 5 块（雀头 → 闭张面子 → 副露/暗杠）
//!
//! # 公开入口
//! - `standardDecomps`：枚举标准型拆解（含进张归属）
//! - `hasStandardShape`：指定进张是否成标准型（仅形，供听牌扫描）
//!
//! # 流程 `standardDecomps`
//! 1. 取进张；组闭张；`need_mentsu = 4 - fuuro_len`
//! 2. 枚举闭张结构
//! 3. 进张落入哪个闭张块 → 各物化成一条拆解
const std = @import("std");
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const pai_util = @import("../pai.zig");

const Pai = types.Pai;
const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;

/// 一条拆解的块数：雀头 + 4 面子（含副露）。
pub const BLOCKS: u8 = 5;
/// 闭张最多面子数。
const MAX_MENTSU: u8 = 4;
/// 单次结构枚举上限。
const MAX_SHAPES: usize = 64;

/// 一块的面子种类。
pub const BlockKind = enum {
    /// 雀头
    jantou,
    /// 顺子
    shuntsu,
    /// 刻子
    kotsu,
    /// 杠子（含暗杠）
    kantsu,
};

/// 一块：雀头 / 顺刻杠。
///
/// `is_fuuro`：仅吃碰大明杠/加杠为 true；暗杠与手内面子为 false。
/// 荣和进张所在块仍为闭张（`is_fuuro=false`），用 `winning` / `winning_tsumo` 区分暗刻。
pub const Block = struct {
    tiles: [4]Pai = undefined,
    tile_len: u8 = 0,
    kind: BlockKind = .jantou,
    is_fuuro: bool = false,
    /// 进张落入本块时为该牌，否则 null。
    winning: ?Pai = null,
    /// 仅 `winning != null` 时表示进张是否来自自摸。
    winning_tsumo: bool = false,
};

/// 一条完整拆解（恰 `BLOCKS` 块）。
pub const StandardDecomp = struct {
    /// 顺序：雀头、闭张面子…、副露…
    blocks: [BLOCKS]Block = [_]Block{.{}} ** BLOCKS,
};

/// 枚举座位标准型的全部拆解（含进张归属）。七对/国士返回空。
pub fn standardDecomps(ky: *const Kyoku, seat: Seat, tsumo: bool, out: []StandardDecomp) []StandardDecomp {
    if (out.len == 0) return out[0..0];

    const winning = (if (tsumo) ky.drawn else ky.response_pai) orelse return out[0..0];
    return standardDecompsWith(ky, seat, winning, tsumo, out);
}

/// 指定进张时闭张是否成标准型（仅形，不含役/振听）。
pub fn hasStandardShape(ky: *const Kyoku, seat: Seat, winning: Pai) bool {
    const winning_kind = pai_util.kindId(winning) orelse return false;
    const player = &ky.players[seat];
    if (player.fuuro_len > MAX_MENTSU) return false;
    const need_mentsu: u8 = MAX_MENTSU - player.fuuro_len;

    const hand = ky.handSlice(seat);
    const expect: usize = @as(usize, need_mentsu) * 3 + 2;
    if (hand.len + 1 != expect) return false;

    var counts: [34]u8 = .{0} ** 34;
    for (hand) |tile| {
        counts[pai_util.kindId(tile) orelse return false] += 1;
    }
    counts[winning_kind] += 1;

    var shapes_buf: [MAX_SHAPES]Shape = undefined;
    return enumerateShapes(&counts, need_mentsu, &shapes_buf).len > 0;
}

fn standardDecompsWith(ky: *const Kyoku, seat: Seat, winning: Pai, tsumo: bool, out: []StandardDecomp) []StandardDecomp {
    const winning_kind = pai_util.kindId(winning) orelse return out[0..0];

    const player = &ky.players[seat];
    if (player.fuuro_len > MAX_MENTSU) return out[0..0];
    const need_mentsu: u8 = MAX_MENTSU - player.fuuro_len;

    var closed_buf: [14]Pai = undefined;
    const closed = collectClosed(ky, seat, tsumo, winning, &closed_buf) orelse return out[0..0];

    var counts: [34]u8 = .{0} ** 34;
    for (closed) |tile| {
        counts[pai_util.kindId(tile) orelse return out[0..0]] += 1;
    }

    var shapes_buf: [MAX_SHAPES]Shape = undefined;
    const shapes = enumerateShapes(&counts, need_mentsu, &shapes_buf);

    var n: usize = 0;
    for (shapes) |shape| {
        // block_i：0 = 雀头，1.. = 闭张面子；副露不承担进张
        var block_i: u8 = 0;
        while (block_i < 1 + shape.mentsu_len) : (block_i += 1) {
            const accepts = if (block_i == 0)
                shape.pair_kind == winning_kind
            else
                mentsuContains(shape.mentsu[block_i - 1], winning_kind);
            if (!accepts) continue;
            if (n >= out.len) return out[0..n];
            out[n] = materialize(closed, player, shape, winning, tsumo, block_i);
            n += 1;
        }
    }
    return out[0..n];
}

/// 组装闭张牌列：自摸用手牌；荣和为手牌 + 进张。
fn collectClosed(
    ky: *const Kyoku,
    seat: Seat,
    tsumo: bool,
    winning: Pai,
    buf: *[14]Pai,
) ?[]const Pai {
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

// ---------------------------------------------------------------------------
// 物化：结构 + 进张归属 → StandardDecomp
// ---------------------------------------------------------------------------

/// 将一种结构写成 5 块，并把进张标在 `winning_block`（0=雀头，其余为闭张面子下标+1）。
fn materialize(
    closed: []const Pai,
    player: *const kyoku_mod.Player,
    shape: Shape,
    winning: Pai,
    tsumo: bool,
    winning_block: u8,
) StandardDecomp {
    var used: [14]bool = .{false} ** 14;
    var result: StandardDecomp = .{};
    var bi: u8 = 0;

    result.blocks[bi] = fillClosedBlock(
        &used,
        closed,
        pairKindList(shape.pair_kind),
        .jantou,
        winning,
        tsumo,
        winning_block == 0,
    );
    bi += 1;

    var mi: u8 = 0;
    while (mi < shape.mentsu_len) : (mi += 1) {
        const mk: BlockKind = switch (shape.mentsu[mi].kind) {
            .kotzu => .kotsu,
            .shuntsu => .shuntsu,
        };
        result.blocks[bi] = fillClosedBlock(
            &used,
            closed,
            mentsuKindList(shape.mentsu[mi]),
            mk,
            winning,
            tsumo,
            winning_block == 1 + mi,
        );
        bi += 1;
    }

    var fi: u8 = 0;
    while (fi < player.fuuro_len) : (fi += 1) {
        const f = player.fuuro[fi];
        const bk: BlockKind = switch (f.kind) {
            .chi => .shuntsu,
            .pon => .kotsu,
            .daiminkan, .ankan, .kakan => .kantsu,
        };
        // 暗杠在 kyoku.fuuro 中，拆解上不算副露（门前暗杠）
        result.blocks[bi] = .{
            .kind = bk,
            .is_fuuro = f.kind != .ankan,
            .tile_len = f.tile_len,
        };
        @memcpy(result.blocks[bi].tiles[0..f.tile_len], f.tiles[0..f.tile_len]);
        sortBlockTiles(&result.blocks[bi]);
        bi += 1;
    }

    std.debug.assert(bi == BLOCKS);
    return result;
}

/// 一块所需的牌种列表（至多 3 个）。
const KindList = struct {
    kinds: [3]u8 = undefined,
    len: u8 = 0,
};

/// 雀头对应的两张同种牌。
fn pairKindList(pair_kind: u8) KindList {
    return .{ .kinds = .{ pair_kind, pair_kind, 0 }, .len = 2 };
}

/// 面子对应的三张牌种（刻子三同；顺子连续）。
fn mentsuKindList(m: Mentsu) KindList {
    return switch (m.kind) {
        .kotzu => .{ .kinds = .{ m.tile, m.tile, m.tile }, .len = 3 },
        .shuntsu => .{ .kinds = .{ m.tile, m.tile + 1, m.tile + 2 }, .len = 3 },
    };
}

/// 从闭张池抽出一块的具体牌。
/// 承担进张的块：进张牌面精确抽入（故进张为 `5mr` 时赤宝钉在该块），由 `winning` 标记。
/// 其余张按牌种抽取，与 `pai.takeKinds` 一样优先非赤。
/// 填完后按牌种升序排列（同种保持相对顺序）。
fn fillClosedBlock(
    used: *[14]bool,
    closed: []const Pai,
    kind_list: KindList,
    kind: BlockKind,
    winning: Pai,
    tsumo: bool,
    takes_winning: bool,
) Block {
    var kinds = kind_list.kinds;
    var klen = kind_list.len;
    var block: Block = .{
        .kind = kind,
        .is_fuuro = false,
        .winning = if (takes_winning) winning else null,
        .winning_tsumo = takes_winning and tsumo,
    };

    if (takes_winning) {
        const wk = pai_util.kindId(winning).?;
        removeOneKind(&kinds, &klen, wk);
        block.tiles[0] = winning;
        block.tile_len = 1;
        if (!takeExact(used, closed, winning)) {
            _ = takeByKind(used, closed, wk);
        }
    }

    var i: u8 = 0;
    while (i < klen) : (i += 1) {
        block.tiles[block.tile_len] = takeByKind(used, closed, kinds[i]) orelse "?";
        block.tile_len += 1;
    }
    sortBlockTiles(&block);
    return block;
}

/// 块内牌按 `kindId` 升序（稳定：同种不交换）。
fn sortBlockTiles(block: *Block) void {
    var i: u8 = 1;
    while (i < block.tile_len) : (i += 1) {
        const t = block.tiles[i];
        const tk = pai_util.kindId(t) orelse 255;
        var j = i;
        while (j > 0) {
            const pk = pai_util.kindId(block.tiles[j - 1]) orelse 255;
            if (pk <= tk) break;
            block.tiles[j] = block.tiles[j - 1];
            j -= 1;
        }
        block.tiles[j] = t;
    }
}

/// 从 `kinds[0..len]` 去掉一个等于 `kind` 的项。
fn removeOneKind(kinds: *[3]u8, len: *u8, kind: u8) void {
    var i: u8 = 0;
    while (i < len.*) : (i += 1) {
        if (kinds[i] == kind) {
            var j = i;
            while (j + 1 < len.*) : (j += 1) kinds[j] = kinds[j + 1];
            len.* -= 1;
            return;
        }
    }
}

/// 从未使用闭张中取走与 `want` 牌面完全相同的一张。
fn takeExact(used: *[14]bool, closed: []const Pai, want: Pai) bool {
    for (closed, 0..) |tile, i| {
        if (used[i]) continue;
        if (types.paiEql(tile, want)) {
            used[i] = true;
            return true;
        }
    }
    return false;
}

/// 从未使用闭张中取走一张指定牌种（优先非赤，与 `pai.takeKinds` 一致）。
fn takeByKind(used: *[14]bool, closed: []const Pai, kind: u8) ?Pai {
    for (closed, 0..) |tile, i| {
        if (used[i]) continue;
        if (pai_util.kindId(tile) != kind) continue;
        if (pai_util.isRed(tile)) continue;
        used[i] = true;
        return tile;
    }
    for (closed, 0..) |tile, i| {
        if (used[i]) continue;
        if (pai_util.kindId(tile) != kind) continue;
        used[i] = true;
        return tile;
    }
    return null;
}

/// 面子是否包含该牌种。
fn mentsuContains(m: Mentsu, kind: u8) bool {
    return switch (m.kind) {
        .kotzu => m.tile == kind,
        .shuntsu => kind >= m.tile and kind <= m.tile + 2 and kind / 9 == m.tile / 9,
    };
}

// ---------------------------------------------------------------------------
// 结构枚举：34 计数 → Shape 列表
// ---------------------------------------------------------------------------

/// 面子类型。
const MentsuKind = enum(u8) {
    kotzu,
    shuntsu,
};

/// 一个闭张面子（牌种 0..33）。
const Mentsu = struct {
    kind: MentsuKind,
    /// 刻子：该牌种；顺子：起始牌种。
    tile: u8,
};

/// 一种闭张结构：雀头 + 闭张面子（不含副露、不含进张归属）。
const Shape = struct {
    pair_kind: u8,
    mentsu: [MAX_MENTSU]Mentsu = undefined,
    mentsu_len: u8 = 0,
};

/// 枚举所有「雀头 + need_mentsu 个面子」的标准型结构。
fn enumerateShapes(counts: *const [34]u8, need_mentsu: u8, out: []Shape) []Shape {
    if (need_mentsu > MAX_MENTSU) return out[0..0];
    var sum: u8 = 0;
    for (counts.*) |c| sum += c;
    if (sum != 2 + 3 * need_mentsu) return out[0..0];

    var n: usize = 0;
    var pair_kind: u8 = 0;
    while (pair_kind < 34) : (pair_kind += 1) {
        if (counts[pair_kind] < 2) continue;
        n = appendShapesWithPair(pair_kind, counts, need_mentsu, out, n);
        if (n >= out.len) break;
    }
    return out[0..n];
}

/// 固定雀头后，对四组（万/筒/索/字）方案做笛卡尔积，写入 `out`。
fn appendShapesWithPair(
    pair_kind: u8,
    counts: *const [34]u8,
    need_mentsu: u8,
    out: []Shape,
    start: usize,
) usize {
    // 四组：万0 / 筒9 / 索18 / 字27
    const groups_meta = [_]struct { base: u8, width: u8 }{
        .{ .base = 0, .width = 9 },
        .{ .base = 9, .width = 9 },
        .{ .base = 18, .width = 9 },
        .{ .base = 27, .width = 7 },
    };
    var groups: [4]Group = .{ .{}, .{}, .{}, .{} };
    const pair_group: u8 = if (pair_kind < 9) 0 else if (pair_kind < 18) 1 else if (pair_kind < 27) 2 else 3;

    for (groups_meta, 0..) |meta, gi| {
        const g: u8 = @intCast(gi);
        const local_pair: ?u8 = if (g == pair_group) pair_kind - meta.base else null;
        if (meta.width == 9) {
            var c9: [9]u8 = undefined;
            @memcpy(&c9, counts[meta.base..][0..9]);
            if (!fillSuitedGroup(&groups[g], &c9, meta.base, local_pair)) return start;
        } else {
            var c7: [7]u8 = undefined;
            @memcpy(&c7, counts[27..34]);
            if (!fillHonorGroup(&groups[g], &c7, if (local_pair != null) pair_kind else null)) return start;
        }
    }
    return cartesianProduct(pair_kind, &groups, need_mentsu, out, start);
}

/// 一组花色/字牌内的一种面子组合（无雀头）。
const GroupPlan = struct {
    mentsu: [MAX_MENTSU]Mentsu = undefined,
    mentsu_len: u8 = 0,
};

/// 一组花色/字牌的全部候选面子组合。
const Group = struct {
    plans: [16]GroupPlan = undefined,
    plan_len: u8 = 0,
};

/// 填入数牌组方案：`local_pair` 非空则该组含雀头（1..9 局部数字）。
fn fillSuitedGroup(group: *Group, counts: *const [9]u8, base: u8, local_pair: ?u8) bool {
    group.plan_len = 0;
    if (local_pair) |lp| {
        for (lookupSuitedWithPair(counts)) |entry| {
            if (entry.pair_digit != lp + 1) continue;
            if (group.plan_len >= group.plans.len) break;
            group.plans[group.plan_len] = suitedEntryToPlan(entry.mentsu[0..entry.mentsu_len], base);
            group.plan_len += 1;
        }
    } else {
        const entries = lookupSuitedPure(counts);
        if (entries.len == 0) return false;
        for (entries) |entry| {
            if (group.plan_len >= group.plans.len) break;
            group.plans[group.plan_len] = suitedEntryToPlan(entry.mentsu[0..entry.mentsu_len], base);
            group.plan_len += 1;
        }
    }
    return group.plan_len > 0;
}

/// 填入字牌组方案：`pair_kind` 非空则该种为雀头（全局 27..33）。
fn fillHonorGroup(group: *Group, counts: *const [7]u8, pair_kind: ?u8) bool {
    group.plan_len = 0;
    var mentsu: [MAX_MENTSU]Mentsu = undefined;
    var mentsu_len: u8 = 0;
    var found_pair = false;

    for (counts.*, 0..) |c, i| {
        const kind: u8 = @intCast(27 + i);
        if (c == 0) continue;
        if (pair_kind) |pk| {
            if (c == 2) {
                if (found_pair or kind != pk) return false;
                found_pair = true;
                continue;
            }
        }
        if (c != 3) return false;
        if (mentsu_len >= MAX_MENTSU) return false;
        mentsu[mentsu_len] = .{ .kind = .kotzu, .tile = kind };
        mentsu_len += 1;
    }

    if (pair_kind != null and !found_pair) return false;
    group.plans[0] = .{ .mentsu = mentsu, .mentsu_len = mentsu_len };
    group.plan_len = 1;
    return true;
}

/// 表内数牌面子（局部数字）转为全局牌种面子方案。
fn suitedEntryToPlan(mentsu: []const SuitMentsu, base: u8) GroupPlan {
    var plan: GroupPlan = .{};
    for (mentsu, 0..) |m, i| {
        plan.mentsu[i] = .{ .kind = m.kind, .tile = base + (m.digit - 1) };
    }
    plan.mentsu_len = @intCast(mentsu.len);
    return plan;
}

/// 四组方案笛卡尔积；面子总数等于 `need_mentsu` 时写入一条 Shape。
fn cartesianProduct(
    pair_kind: u8,
    groups: *const [4]Group,
    need_mentsu: u8,
    out: []Shape,
    start: usize,
) usize {
    var n = start;
    var idx: [4]u8 = .{0} ** 4;
    while (true) {
        var total: u8 = 0;
        for (groups, idx) |group, i| total += group.plans[i].mentsu_len;

        if (total == need_mentsu and n < out.len) {
            var shape: Shape = .{ .pair_kind = pair_kind };
            var m: u8 = 0;
            for (groups, idx) |group, i| {
                const plan = group.plans[i];
                var j: u8 = 0;
                while (j < plan.mentsu_len) : (j += 1) {
                    shape.mentsu[m] = plan.mentsu[j];
                    m += 1;
                }
            }
            shape.mentsu_len = m;
            out[n] = shape;
            n += 1;
        }

        var g: usize = 4;
        while (g > 0) {
            g -= 1;
            idx[g] += 1;
            if (idx[g] < groups[g].plan_len) break;
            idx[g] = 0;
            if (g == 0) return n;
        }
    }
}

// ---------------------------------------------------------------------------
// 数牌查表（单花色 9 位计数 → 纯面子 / 含雀头方案）
// ---------------------------------------------------------------------------

/// 表内面子：数字 1..9。
const SuitMentsu = struct {
    kind: MentsuKind,
    digit: u8,
};

/// 表项：纯面子分解。
const SuitPureEntry = struct {
    mentsu: [MAX_MENTSU]SuitMentsu = undefined,
    mentsu_len: u8 = 0,
};

/// 表项：含雀头分解。
const SuitPairEntry = struct {
    mentsu: [MAX_MENTSU]SuitMentsu = undefined,
    mentsu_len: u8 = 0,
    /// 雀头数字 1..9。
    pair_digit: u8 = 0,
};

const empty_pure: [0]SuitPureEntry = .{};
const empty_pair: [0]SuitPairEntry = .{};

var table_pure: std.AutoHashMap(u32, []const SuitPureEntry) = undefined;
var table_pair: std.AutoHashMap(u32, []const SuitPairEntry) = undefined;
var table_ready: bool = false;

/// 查纯面子表；无法完全拆解则空切片。
fn lookupSuitedPure(counts: *const [9]u8) []const SuitPureEntry {
    ensureSuitTable();
    if (sumDigits(counts) > 14) return &empty_pure;
    return table_pure.get(encodeSuit(counts)) orelse &empty_pure;
}

/// 查含雀头表；无法完全拆解则空切片。
fn lookupSuitedWithPair(counts: *const [9]u8) []const SuitPairEntry {
    ensureSuitTable();
    if (sumDigits(counts) > 14) return &empty_pair;
    return table_pair.get(encodeSuit(counts)) orelse &empty_pair;
}

/// 数牌状态编码：`Σ counts[i] · 5^i`。
fn encodeSuit(counts: *const [9]u8) u32 {
    var idx: u32 = 0;
    var place: u32 = 1;
    for (counts.*) |c| {
        idx += c * place;
        place *= 5;
    }
    return idx;
}

/// 单花色总张数。
fn sumDigits(counts: *const [9]u8) u8 {
    var s: u8 = 0;
    for (counts.*) |c| s += c;
    return s;
}

/// 懒建数牌分解表。
fn ensureSuitTable() void {
    if (table_ready) return;
    buildSuitTable(std.heap.page_allocator) catch @panic("standard suit table");
    table_ready = true;
}

/// 按总张数 0..14 递推填充纯面子表与含雀头表。
fn buildSuitTable(gpa: std.mem.Allocator) !void {
    table_pure = .init(gpa);
    table_pair = .init(gpa);
    try table_pure.put(0, try gpa.dupe(SuitPureEntry, &[_]SuitPureEntry{.{}}));

    var n: u8 = 1;
    while (n <= 14) : (n += 1) {
        var counts: [9]u8 = .{0} ** 9;
        try forEachSuitState(0, n, &counts, gpa);
    }
}

/// 递归枚举总张数恰为 `remaining` 的数牌状态。
fn forEachSuitState(pos: usize, remaining: u8, counts: *[9]u8, gpa: std.mem.Allocator) !void {
    if (pos == 9) {
        if (remaining == 0) try computeSuitState(counts, gpa);
        return;
    }
    var c: u8 = 0;
    while (c <= @min(4, remaining)) : (c += 1) {
        counts[pos] = c;
        try forEachSuitState(pos + 1, remaining - c, counts, gpa);
    }
    counts[pos] = 0;
}

/// 对单个数牌状态：由最小非零位做刻/顺转移写纯表，再枚举雀头写含雀头表。
fn computeSuitState(counts: *const [9]u8, gpa: std.mem.Allocator) !void {
    const idx = encodeSuit(counts);
    var p: usize = 0;
    while (p < 9 and counts[p] == 0) : (p += 1) {}
    std.debug.assert(p < 9);

    var pure: std.ArrayList(SuitPureEntry) = .empty;
    defer pure.deinit(gpa);

    if (counts[p] >= 3) {
        var child = counts.*;
        child[p] -= 3;
        for (table_pure.get(encodeSuit(&child)) orelse &empty_pure) |child_plan| {
            try pure.append(gpa, prependSuitMentsu(child_plan, .{ .kind = .kotzu, .digit = @intCast(p + 1) }));
        }
    }
    if (p <= 6 and counts[p] > 0 and counts[p + 1] > 0 and counts[p + 2] > 0) {
        var child = counts.*;
        child[p] -= 1;
        child[p + 1] -= 1;
        child[p + 2] -= 1;
        for (table_pure.get(encodeSuit(&child)) orelse &empty_pure) |child_plan| {
            try pure.append(gpa, prependSuitMentsu(child_plan, .{ .kind = .shuntsu, .digit = @intCast(p + 1) }));
        }
    }
    if (pure.items.len > 0) try table_pure.put(idx, try pure.toOwnedSlice(gpa));

    var with_pair: std.ArrayList(SuitPairEntry) = .empty;
    defer with_pair.deinit(gpa);
    var i: usize = 0;
    while (i < 9) : (i += 1) {
        if (counts[i] < 2) continue;
        var child = counts.*;
        child[i] -= 2;
        for (table_pure.get(encodeSuit(&child)) orelse &empty_pure) |child_plan| {
            try with_pair.append(gpa, .{
                .mentsu = child_plan.mentsu,
                .mentsu_len = child_plan.mentsu_len,
                .pair_digit = @intCast(i + 1),
            });
        }
    }
    if (with_pair.items.len > 0) try table_pair.put(idx, try with_pair.toOwnedSlice(gpa));
}

/// 在子方案前插入一个面子。
fn prependSuitMentsu(plan: SuitPureEntry, mentsu: SuitMentsu) SuitPureEntry {
    var out: SuitPureEntry = .{ .mentsu_len = plan.mentsu_len + 1 };
    out.mentsu[0] = mentsu;
    @memcpy(out.mentsu[1..][0..plan.mentsu_len], plan.mentsu[0..plan.mentsu_len]);
    return out;
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

test "standardDecomps: tsumo winning on pair or shuntsu" {
    const seat_tiles = @import("../seat_tiles.zig");
    var ky = Kyoku.init();
    ky.phase = .wait_act;
    ky.turn = 0;
    ky.drawn = "1m";
    for ([_]Pai{ "1m", "1m", "2m", "3m", "1m" }) |t| seat_tiles.addToHand(&ky, 0, t);
    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = 1 };
        f.tiles = .{ "9s", "9s", "9s", "9s" };
        seat_tiles.addFuuro(&ky, 0, f);
    }

    var buf: [8]StandardDecomp = undefined;
    const decomps = standardDecomps(&ky, 0, true, &buf);
    try std.testing.expectEqual(@as(usize, 2), decomps.len);

    var saw_pair = false;
    var saw_mentsu = false;
    for (decomps) |decomp| {
        try std.testing.expect(decomp.blocks[0].kind == .jantou);
        var wins: u8 = 0;
        for (decomp.blocks) |b| {
            if (b.winning) |w| {
                wins += 1;
                try std.testing.expect(types.paiEql(w, "1m"));
                try std.testing.expect(b.winning_tsumo);
                if (b.kind == .jantou) saw_pair = true else saw_mentsu = true;
            } else try std.testing.expect(!b.winning_tsumo);
            if (b.is_fuuro) try std.testing.expect(b.winning == null);
        }
        try std.testing.expectEqual(@as(u8, 1), wins);
    }
    try std.testing.expect(saw_pair and saw_mentsu);
}

test "standardDecomps: ron winning on pair" {
    const seat_tiles = @import("../seat_tiles.zig");
    var ky = Kyoku.init();
    ky.phase = .wait_response;
    ky.response_pai = "S";
    for ([_]Pai{ "1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "E", "E", "E", "S" }) |t| {
        seat_tiles.addToHand(&ky, 0, t);
    }

    var buf: [8]StandardDecomp = undefined;
    const decomps = standardDecomps(&ky, 0, false, &buf);
    try std.testing.expectEqual(@as(usize, 1), decomps.len);
    try std.testing.expect(decomps[0].blocks[0].kind == .jantou);
    try std.testing.expect(types.paiEql(decomps[0].blocks[0].winning.?, "S"));
    try std.testing.expect(!decomps[0].blocks[0].winning_tsumo);
}

test "standardDecomps: multi structure 333444555m" {
    const seat_tiles = @import("../seat_tiles.zig");
    var ky = Kyoku.init();
    ky.phase = .wait_act;
    ky.turn = 0;
    ky.drawn = "5m";
    for ([_]Pai{ "3m", "3m", "3m", "4m", "4m", "4m", "5m", "5m", "1p", "1p", "5m" }) |t| {
        seat_tiles.addToHand(&ky, 0, t);
    }
    var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = 1 };
    f.tiles = .{ "9s", "9s", "9s", "9s" };
    seat_tiles.addFuuro(&ky, 0, f);

    var buf: [16]StandardDecomp = undefined;
    const decomps = standardDecomps(&ky, 0, true, &buf);
    try std.testing.expect(decomps.len >= 2);
}

test "standardDecomps: ron 5mr on 5567m — red in pair vs shuntsu" {
    const seat_tiles = @import("../seat_tiles.zig");
    var ky = Kyoku.init();
    ky.phase = .wait_response;
    ky.response_pai = "5mr";
    // 闭张 5567 + 5mr → 雀头55 + 顺567；进张赤5可落雀头或顺子
    for ([_]Pai{ "5m", "5m", "6m", "7m" }) |t| seat_tiles.addToHand(&ky, 0, t);
    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = 1 };
        f.tiles = .{ "9s", "9s", "9s", "9s" };
        seat_tiles.addFuuro(&ky, 0, f);
    }

    var buf: [8]StandardDecomp = undefined;
    const decomps = standardDecomps(&ky, 0, false, &buf);
    try std.testing.expectEqual(@as(usize, 2), decomps.len);

    var red_in_pair = false;
    var red_in_shuntsu = false;
    for (decomps) |decomp| {
        var win_on_pair = false;
        for (decomp.blocks) |b| {
            if (b.winning) |w| {
                try std.testing.expect(types.paiEql(w, "5mr"));
                try std.testing.expect(!b.winning_tsumo);
                var has_red = false;
                for (0..b.tile_len) |ti| {
                    if (types.paiEql(b.tiles[ti], "5mr")) has_red = true;
                }
                try std.testing.expect(has_red);
                win_on_pair = b.kind == .jantou;
            }
        }
        if (win_on_pair) {
            red_in_pair = true;
            try std.testing.expect(!pai_util.isRed(decomp.blocks[1].tiles[0]));
            try std.testing.expect(!pai_util.isRed(decomp.blocks[1].tiles[1]));
            try std.testing.expect(!pai_util.isRed(decomp.blocks[1].tiles[2]));
        } else {
            red_in_shuntsu = true;
            try std.testing.expect(decomp.blocks[0].winning == null);
            try std.testing.expect(!pai_util.isRed(decomp.blocks[0].tiles[0]));
            try std.testing.expect(!pai_util.isRed(decomp.blocks[0].tiles[1]));
        }
    }
    try std.testing.expect(red_in_pair and red_in_shuntsu);
}
