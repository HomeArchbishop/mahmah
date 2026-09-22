//! 合法着列表、应手探测、待行座位。
//!
//! 荣和形/役走 referee；本文件只做过程规则与着法枚举。
const std = @import("std");
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const pai_util = @import("pai.zig");
const referee = @import("referee/root.zig");
const round = @import("round.zig");
const kuikae = @import("kuikae.zig");
const ryuukyoku = @import("ryuukyoku.zig");

const Kyoku = kyoku_mod.Kyoku;
const Action = types.Action;
const Seat = types.Seat;
const Pai = types.Pai;
const CAPACITY = types.CAPACITY;

// ---------------------------------------------------------------------------
// 公开入口
// ---------------------------------------------------------------------------

/// 当前 phase 下该座位的合法着，写入 `out`。
pub fn fillLegal(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    return switch (ky.phase) {
        .wait_act => fillWaitAct(ky, seat, out),
        .wait_response => fillWaitResponse(ky, seat, out),
        .idle => out[0..0],
    };
}

/// 现在需要行动的座位。
pub fn seatsNeeding(ky: *const Kyoku, out: []Seat) []Seat {
    switch (ky.phase) {
        .wait_act => {
            if (out.len == 0) return out[0..0];
            out[0] = ky.turn;
            return out[0..1];
        },
        .wait_response => {
            var n: usize = 0;
            var s: u8 = 0;
            while (s < CAPACITY) : (s += 1) {
                if (!ky.response_open[s] or ky.response_done[s]) continue;
                if (n >= out.len) break;
                out[n] = @intCast(s);
                n += 1;
            }
            return out[0..n];
        },
        .idle => return out[0..0],
    }
}

/// 打牌后是否有人可应。进张须已写入 `response_pai`。
pub fn hasClaimOpportunity(ky: *const Kyoku, discarder: Seat) bool {
    var seat: u8 = 0;
    while (seat < CAPACITY) : (seat += 1) {
        if (seat == discarder) continue;
        if (seatHasClaim(ky, @intCast(seat), discarder, false)) return true;
    }
    return false;
}

/// 座位是否可应（荣 / 碰杠 / 吃）。进张为 `response_pai`。
/// 途中流局已成立时仅可荣（吃碰杠不打断四杠散了等）。
pub fn seatHasClaim(ky: *const Kyoku, seat: Seat, discarder: Seat, chankan: bool) bool {
    if (seat == discarder) return false;
    const pai = ky.response_pai orelse return false;
    if (canRon(ky, seat)) return true;
    if (chankan) return false;
    if (ryuukyoku.isTochuAbortPending(ky)) return false;
    if (!ky.yama.hasLive()) return false;
    if (ky.players[seat].riichi) return false;

    const hand = ky.handSlice(seat);
    if (pai_util.countKind(hand, pai) >= 2) {
        // 碰后须有非食替可切
        var cands: [4]Pai = undefined;
        const nc = collectKindTiles(hand, pai, &cands);
        var i: usize = 0;
        while (i < nc) : (i += 1) {
            var j: usize = i + 1;
            while (j < nc) : (j += 1) {
                if (canDiscardAfterPon(ky, hand, pai, cands[i], cands[j])) return true;
            }
        }
        // 无合法碰时仍可能大明杠（杠后摸岭上，不经食替禁切）；已四杠则不可再杠
        if (pai_util.countKind(hand, pai) >= 3 and ky.kan_count < 4) return true;
    }

    if (seat != round.nextSeat(discarder)) return false;
    return canChiWithLegalDiscard(ky, hand, pai);
}

/// 下家能否吃，且吃后有非食替可切。
fn canChiWithLegalDiscard(ky: *const Kyoku, hand: []const Pai, pai: Pai) bool {
    const s = pai_util.suit(pai) orelse return false;
    const r = pai_util.rank(pai) orelse return false;
    const patterns = [_][2]i8{ .{ -2, -1 }, .{ -1, 1 }, .{ 1, 2 } };
    for (patterns) |pat| {
        const r1 = @as(i16, r) + pat[0];
        const r2 = @as(i16, r) + pat[1];
        if (r1 < 1 or r1 > 9 or r2 < 1 or r2 > 9) continue;
        const t1 = pai_util.suitedLiteral(@intCast(r1), s);
        const t2 = pai_util.suitedLiteral(@intCast(r2), s);

        var cand1: [4]Pai = undefined;
        var cand2: [4]Pai = undefined;
        const n1 = collectKindTiles(hand, t1, &cand1);
        const n2 = collectKindTiles(hand, t2, &cand2);
        if (n1 == 0 or n2 == 0) continue;

        if (pai_util.sameKind(t1, t2)) {
            var i: usize = 0;
            while (i < n1) : (i += 1) {
                var j: usize = i + 1;
                while (j < n1) : (j += 1) {
                    if (canDiscardAfterChi(ky, hand, pai, cand1[i], cand1[j])) return true;
                }
            }
        } else {
            var i: usize = 0;
            while (i < n1) : (i += 1) {
                var j: usize = 0;
                while (j < n2) : (j += 1) {
                    if (canDiscardAfterChi(ky, hand, pai, cand1[i], cand2[j])) return true;
                }
            }
        }
    }
    return false;
}

/// 国士抢暗杠：进张为 `response_pai`，含振听检查。
pub fn canKokushiChankan(ky: *const Kyoku, seat: Seat) bool {
    if (ky.response_pai == null) return false;
    return referee.canKokushiRon(ky, seat);
}

// ---------------------------------------------------------------------------
// wait_act
// ---------------------------------------------------------------------------

fn fillWaitAct(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    if (seat != ky.turn) return out[0..0];

    // 立直宣言后：只能切出使听牌的牌
    if (ky.pending_riichi == seat) {
        return appendDahai(ky, seat, out);
    }

    var n: usize = 0;
    const p = &ky.players[seat];

    if (ky.drawn != null and referee.canAgari(ky, seat, true)) {
        if (n < out.len) {
            out[n] = .{ .hora = .{ .target = seat, .pai = ky.drawn } };
            n += 1;
        }
    }

    // 九种九牌：首巡未切、无副露；14 张（含摸牌）中不同幺九种类 ≥ 9
    if (ky.rules.abort_kyushu and ky.is_first_turn and p.river_len == 0 and p.fuuro_len == 0 and ky.drawn != null) {
        if (kyushuKindCount(ky.handSlice(seat)) >= 9) {
            if (n < out.len) {
                out[n] = .ryukyoku;
                n += 1;
            }
        }
    }

    // 活山 < 4 不可立直（须至少再摸一轮）
    if (!p.riichi and ky.pending_riichi == null and p.isMenzen() and ky.scores[seat] >= 1000 and
        ky.drawn != null and ky.yama.liveRemaining() >= 4)
    {
        if (canDeclareRiichi(ky, seat)) {
            if (n < out.len) {
                out[n] = .reach;
                n += 1;
            }
        }
    }

    n = appendAnkanKakan(ky, seat, out, n);
    const dahai = appendDahai(ky, seat, out[n..]);
    return out[0 .. n + dahai.len];
}

fn appendDahai(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    const hand = ky.handSlice(seat);
    const p = &ky.players[seat];
    const pending_reach = ky.pending_riichi == seat;
    var n: usize = 0;
    for (hand, 0..) |pai, i| {
        if (n >= out.len) break;
        const tsumogiri = ky.drawn != null and i + 1 == hand.len and types.paiEql(ky.drawn.?, pai);
        // 已立直：只能摸切
        if (p.riichi and !tsumogiri) continue;
        if (kuikae.forbids(ky, pai)) continue;
        // 立直宣言打：必须切后听牌
        if (pending_reach and !discardLeavesTenpai(ky, seat, i)) continue;
        if (dahaiAlreadyListed(out[0..n], pai, tsumogiri)) continue;
        out[n] = .{ .dahai = .{ .pai = pai, .tsumogiri = tsumogiri } };
        n += 1;
    }
    return out[0..n];
}

fn dahaiAlreadyListed(listed: []const Action, pai: Pai, tsumogiri: bool) bool {
    for (listed) |prev| {
        if (prev == .dahai and types.paiEql(prev.dahai.pai, pai) and prev.dahai.tsumogiri == tsumogiri)
            return true;
    }
    return false;
}

fn appendAnkanKakan(ky: *const Kyoku, seat: Seat, out: []Action, start: usize) usize {
    // 吃碰后打牌前、河海底、已四杠：不可再杠
    if (ky.drawn == null) return start;
    if (!ky.yama.hasLive()) return start;
    if (ky.kan_count >= 4) return start;

    var n = start;
    const hand = ky.handSlice(seat);
    const p = &ky.players[seat];

    // 暗杠
    var seen: [34]bool = .{false} ** 34;
    for (hand) |tile| {
        const id = pai_util.kindId(tile) orelse continue;
        if (seen[id]) continue;
        seen[id] = true;
        if (pai_util.countKind(hand, tile) < 4) continue;
        // 立直中：仅听口不变的暗杠
        if (p.riichi and ky.rules.riichi_ankan_must_preserve_wait and !ankanPreservesWaits(ky, seat, tile)) continue;
        var consumed: [4]Pai = undefined;
        if (pai_util.takeKinds(hand, tile, 4, &consumed) < 4) continue;
        if (n < out.len) {
            out[n] = .{ .ankan = .{ .consumed = consumed } };
            n += 1;
        }
    }

    // 加杠（立直后门清，不会走到）
    if (p.riichi) return n;
    var i: u8 = 0;
    while (i < p.fuuro_len) : (i += 1) {
        const f = p.fuuro[i];
        if (f.kind != .pon or f.tile_len < 3) continue;
        const base = f.tiles[0];
        if (pai_util.countKind(hand, base) < 1) continue;
        var one: [1]Pai = undefined;
        if (pai_util.takeKinds(hand, base, 1, &one) < 1) continue;
        if (n < out.len) {
            out[n] = .{ .kakan = .{
                .pai = one[0],
                .consumed = .{ f.tiles[0], f.tiles[1], f.tiles[2] },
            } };
            n += 1;
        }
    }
    return n;
}

/// 立直暗杠：去掉摸牌后的听口，须与杠掉 4 张并多一副暗杠后的听口一致。
pub fn ankanPreservesWaits(ky: *const Kyoku, seat: Seat, kan_tile: Pai) bool {
    const hand = ky.handSlice(seat);
    if (hand.len == 0 or ky.drawn == null) return false;
    const fuuro_len = ky.players[seat].fuuro_len;

    // 杠前听口：14 张去掉当前摸牌 → 13（或已有暗杠时的对应张数）
    var before: [14]Pai = undefined;
    var bn: usize = 0;
    for (hand[0 .. hand.len - 1]) |t| {
        before[bn] = t;
        bn += 1;
    }
    var waits_before: [34]bool = undefined;
    referee.fillWaitsClosed(before[0..bn], fuuro_len, &waits_before);

    // 杠后：14 张去掉同种 4 张，副露数 +1
    var after: [14]Pai = undefined;
    var an: usize = 0;
    var removed: u8 = 0;
    for (hand) |t| {
        if (removed < 4 and pai_util.sameKind(t, kan_tile)) {
            removed += 1;
            continue;
        }
        after[an] = t;
        an += 1;
    }
    if (removed != 4) return false;
    var waits_after: [34]bool = undefined;
    referee.fillWaitsClosed(after[0..an], fuuro_len + 1, &waits_after);

    return referee.waitsEqual(&waits_before, &waits_after);
}

fn canDeclareRiichi(ky: *const Kyoku, seat: Seat) bool {
    const hand = ky.handSlice(seat);
    var i: usize = 0;
    while (i < hand.len) : (i += 1) {
        if (kuikae.forbids(ky, hand[i])) continue;
        if (discardLeavesTenpai(ky, seat, i)) return true;
    }
    return false;
}

/// 切掉 `hand[discard_i]` 后闭张是否听牌。
fn discardLeavesTenpai(ky: *const Kyoku, seat: Seat, discard_i: usize) bool {
    const hand = ky.handSlice(seat);
    const fuuro_len = ky.players[seat].fuuro_len;
    var closed: [14]Pai = undefined;
    var n: usize = 0;
    for (hand, 0..) |p, j| {
        if (j == discard_i) continue;
        closed[n] = p;
        n += 1;
    }
    return referee.isTenpai(closed[0..n], fuuro_len);
}

fn kyushuKindCount(hand: []const Pai) u8 {
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

// ---------------------------------------------------------------------------
// wait_response
// ---------------------------------------------------------------------------

fn fillWaitResponse(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    if (!ky.response_open[seat] or ky.response_done[seat]) return out[0..0];
    const pai = ky.response_pai orelse return out[0..0];
    const discarder = ky.response_from;
    if (seat == discarder) return out[0..0];

    var n: usize = 0;
    if (n < out.len) {
        out[n] = .none;
        n += 1;
    }

    // 抢杠窗：仅荣（暗杠仅国士）
    if (ky.pending_kan != null) {
        const ok = if (ky.pending_ankan) canKokushiChankan(ky, seat) else canRon(ky, seat);
        if (ok and n < out.len) {
            out[n] = .{ .hora = .{ .target = discarder, .pai = pai } };
            n += 1;
        }
        return out[0..n];
    }

    if (canRon(ky, seat) and n < out.len) {
        out[n] = .{ .hora = .{ .target = discarder, .pai = pai } };
        n += 1;
    }

    // 途中流局待决 / 河底：不可吃碰明杠（仍可荣）
    if (!ryuukyoku.isTochuAbortPending(ky) and ky.yama.hasLive()) {
        n = appendPonDaiminkan(ky, seat, pai, out, n);
        if (seat == round.nextSeat(discarder)) {
            n = appendChi(ky, seat, pai, out, n);
        }
    }
    return out[0..n];
}

fn canRon(ky: *const Kyoku, seat: Seat) bool {
    if (ky.response_pai == null) return false;
    return referee.canAgari(ky, seat, false);
}

// ---------------------------------------------------------------------------
// 鸣牌着法枚举（具体 consumed）
// ---------------------------------------------------------------------------

fn appendPonDaiminkan(ky: *const Kyoku, seat: Seat, pai: Pai, out: []Action, start: usize) usize {
    var n = start;
    if (ky.players[seat].riichi) return n;

    const hand = ky.handSlice(seat);
    const cnt = pai_util.countKind(hand, pai);
    if (cnt >= 2) {
        var cands: [4]Pai = undefined;
        const nc = collectKindTiles(hand, pai, &cands);
        var i: usize = 0;
        while (i < nc) : (i += 1) {
            var j: usize = i + 1;
            while (j < nc) : (j += 1) {
                if (!canDiscardAfterPon(ky, hand, pai, cands[i], cands[j])) continue;
                n = pushPonUnique(out, n, pai, cands[i], cands[j]);
            }
        }
    }
    if (cnt >= 3 and ky.yama.hasLive() and ky.kan_count < 4) {
        var cands: [4]Pai = undefined;
        const nc = collectKindTiles(hand, pai, &cands);
        var i: usize = 0;
        while (i < nc) : (i += 1) {
            var j: usize = i + 1;
            while (j < nc) : (j += 1) {
                var k: usize = j + 1;
                while (k < nc) : (k += 1) {
                    n = pushDaiminkanUnique(out, n, pai, cands[i], cands[j], cands[k]);
                }
            }
        }
    }
    return n;
}

fn appendChi(ky: *const Kyoku, seat: Seat, pai: Pai, out: []Action, start: usize) usize {
    var n = start;
    if (ky.players[seat].riichi) return n;
    const s = pai_util.suit(pai) orelse return n;
    const r = pai_util.rank(pai) orelse return n;
    const hand = ky.handSlice(seat);

    const patterns = [_][2]i8{ .{ -2, -1 }, .{ -1, 1 }, .{ 1, 2 } };
    for (patterns) |pat| {
        const r1 = @as(i16, r) + pat[0];
        const r2 = @as(i16, r) + pat[1];
        if (r1 < 1 or r1 > 9 or r2 < 1 or r2 > 9) continue;
        const t1 = pai_util.suitedLiteral(@intCast(r1), s);
        const t2 = pai_util.suitedLiteral(@intCast(r2), s);

        var cand1: [4]Pai = undefined;
        var cand2: [4]Pai = undefined;
        const n1 = collectKindTiles(hand, t1, &cand1);
        const n2 = collectKindTiles(hand, t2, &cand2);
        if (n1 == 0 or n2 == 0) continue;

        if (pai_util.sameKind(t1, t2)) {
            var i: usize = 0;
            while (i < n1) : (i += 1) {
                var j: usize = i + 1;
                while (j < n1) : (j += 1) {
                    if (!canDiscardAfterChi(ky, hand, pai, cand1[i], cand1[j])) continue;
                    n = pushChiUnique(out, n, pai, cand1[i], cand1[j]);
                }
            }
            continue;
        }

        var i: usize = 0;
        while (i < n1) : (i += 1) {
            var j: usize = 0;
            while (j < n2) : (j += 1) {
                if (!canDiscardAfterChi(ky, hand, pai, cand1[i], cand2[j])) continue;
                n = pushChiUnique(out, n, pai, cand1[i], cand2[j]);
            }
        }
    }
    return n;
}

/// 吃/碰后须有非食替禁切可打。手牌去掉 `consumed` 后若全被禁则不可鸣。
fn canDiscardAfterChi(ky: *const Kyoku, hand: []const Pai, claimed: Pai, a: Pai, b: Pai) bool {
    if (!ky.rules.kuikae) return true;
    var forbid: [2]u8 = undefined;
    const fn_n = kuikae.chiForbidKinds(claimed, .{ a, b }, ky.rules.kuikae_suji, &forbid);
    return hasNonForbiddenRemain(hand, &.{ a, b }, forbid[0..fn_n]);
}

fn canDiscardAfterPon(ky: *const Kyoku, hand: []const Pai, claimed: Pai, a: Pai, b: Pai) bool {
    if (!ky.rules.kuikae) return true;
    var forbid: [1]u8 = undefined;
    const fn_n = kuikae.ponForbidKinds(claimed, &forbid);
    return hasNonForbiddenRemain(hand, &.{ a, b }, forbid[0..fn_n]);
}

fn hasNonForbiddenRemain(hand: []const Pai, consumed: []const Pai, forbid: []const u8) bool {
    var used: [14]bool = .{false} ** 14;
    for (consumed) |need| {
        var found = false;
        for (hand, 0..) |p, i| {
            if (used[i]) continue;
            if (!types.paiEql(p, need)) continue;
            used[i] = true;
            found = true;
            break;
        }
        if (!found) return false;
    }
    for (hand, 0..) |p, i| {
        if (used[i]) continue;
        if (!kuikae.kindForbidden(forbid, p)) return true;
    }
    return false;
}

fn pushPonUnique(out: []Action, start: usize, pai: Pai, a: Pai, b: Pai) usize {
    var n = start;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (out[i] != .pon) continue;
        if (!types.paiEql(out[i].pon.pai, pai)) continue;
        const c = out[i].pon.consumed;
        if ((types.paiEql(c[0], a) and types.paiEql(c[1], b)) or
            (types.paiEql(c[0], b) and types.paiEql(c[1], a)))
            return n;
    }
    if (n < out.len) {
        out[n] = .{ .pon = .{ .pai = pai, .consumed = .{ a, b } } };
        n += 1;
    }
    return n;
}

fn pushDaiminkanUnique(out: []Action, start: usize, pai: Pai, a: Pai, b: Pai, c: Pai) usize {
    var n = start;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (out[i] != .daiminkan) continue;
        if (!types.paiEql(out[i].daiminkan.pai, pai)) continue;
        var want = [_]Pai{ a, b, c };
        var got = out[i].daiminkan.consumed;
        sort3Pai(&want);
        sort3Pai(&got);
        if (types.paiEql(want[0], got[0]) and types.paiEql(want[1], got[1]) and types.paiEql(want[2], got[2]))
            return n;
    }
    if (n < out.len) {
        out[n] = .{ .daiminkan = .{ .pai = pai, .consumed = .{ a, b, c } } };
        n += 1;
    }
    return n;
}

fn pushChiUnique(out: []Action, start: usize, pai: Pai, a: Pai, b: Pai) usize {
    var n = start;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (out[i] != .chi) continue;
        if (!types.paiEql(out[i].chi.pai, pai)) continue;
        const c = out[i].chi.consumed;
        if ((types.paiEql(c[0], a) and types.paiEql(c[1], b)) or
            (types.paiEql(c[0], b) and types.paiEql(c[1], a)))
            return n;
    }
    if (n < out.len) {
        out[n] = .{ .chi = .{ .pai = pai, .consumed = .{ a, b } } };
        n += 1;
    }
    return n;
}

fn collectKindTiles(hand: []const Pai, target: Pai, out: []Pai) usize {
    var n: usize = 0;
    for (hand) |h| {
        if (n >= out.len) break;
        if (pai_util.sameKind(h, target)) {
            out[n] = h;
            n += 1;
        }
    }
    return n;
}

fn sort3Pai(a: *[3]Pai) void {
    inline for (0..2) |_| {
        if (paiLess(a[1], a[0])) {
            const t = a[0];
            a[0] = a[1];
            a[1] = t;
        }
        if (paiLess(a[2], a[1])) {
            const t = a[1];
            a[1] = a[2];
            a[2] = t;
        }
        if (paiLess(a[1], a[0])) {
            const t = a[0];
            a[0] = a[1];
            a[1] = t;
        }
    }
}

fn paiLess(a: Pai, b: Pai) bool {
    return std.mem.order(u8, a, b) == .lt;
}

test "chi blocked when kuikae leaves no discard (78 chi 9, remain 99)" {
    const seat_tiles = @import("seat_tiles.zig");

    var ky = Kyoku.init();
    ky.rules.kuikae = true;
    ky.rules.kuikae_suji = true;
    // 三副露占位 → 手牌 4 张应手
    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = 0 };
        f.tiles = .{ "1m", "1m", "1m", undefined };
        seat_tiles.addFuuro(&ky, 1, f);
    }
    for ([_]Pai{ "7s", "8s", "9s", "9s" }) |t| seat_tiles.addToHand(&ky, 1, t);

    ky.phase = .wait_response;
    ky.response_pai = "9s";
    ky.response_from = 0;
    ky.response_open = .{ false, true, false, false };

    var buf: [32]Action = undefined;
    const legal = fillLegal(&ky, 1, &buf);
    var has_chi = false;
    var has_pon = false;
    for (legal) |a| {
        switch (a) {
            .chi => |c| {
                if (types.paiEql(c.pai, "9s")) has_chi = true;
            },
            .pon => has_pon = true,
            else => {},
        }
    }
    try std.testing.expect(has_pon);
    try std.testing.expect(!has_chi);
}

test "no 5th kan when kan_count >= 4" {
    const seat_tiles = @import("seat_tiles.zig");

    var ky = Kyoku.init();
    ky.phase = .wait_act;
    ky.turn = 0;
    ky.kan_count = 4;
    ky.drawn = "6m";
    // 碰 6m + 摸 6m → 否则可加杠
    var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = 1 };
    f.tiles = .{ "6m", "6m", "6m", undefined };
    seat_tiles.addFuuro(&ky, 0, f);
    for ([_]Pai{ "1p", "2p", "3p", "4p", "5p", "7p", "8p", "9p", "1s", "2s", "6m" }) |t| {
        seat_tiles.addToHand(&ky, 0, t);
    }

    var buf: [32]Action = undefined;
    const legal = fillLegal(&ky, 0, &buf);
    for (legal) |a| {
        try std.testing.expect(a != .kakan);
        try std.testing.expect(a != .ankan);
    }
}

