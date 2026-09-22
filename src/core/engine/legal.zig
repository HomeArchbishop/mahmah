const std = @import("std");
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const pai_util = @import("pai.zig");
const referee = @import("referee/root.zig");
const round = @import("round.zig");
const kuikae = @import("kuikae.zig");
const Kyoku = kyoku_mod.Kyoku;
const Action = types.Action;
const Seat = types.Seat;
const Pai = types.Pai;
const CAPACITY = types.CAPACITY;

/// wait_act / wait_response 合法着写入 out。
pub fn fillLegal(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    return switch (ky.phase) {
        .wait_act => legalWaitAct(ky, seat, out),
        .wait_response => legalWaitResponse(ky, seat, out),
        .idle => out[0..0],
    };
}

fn legalWaitAct(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    if (seat != ky.turn) return out[0..0];
    var n: usize = 0;

    const p = &ky.players[seat];
    // 立直宣言后只能打牌
    if (ky.pending_riichi == seat) {
        return fillDahai(ky, seat, out);
    }

    // 自摸和
    if (ky.drawn != null and referee.canAgari(ky, seat, true)) {
        if (n < out.len) {
            out[n] = .{ .hora = .{ .target = seat, .pai = ky.drawn } };
            n += 1;
        }
    }

    // 九种九牌（过程规则：首巡未切、无副露）
    if (ky.is_first_turn and p.river_len == 0 and p.fuuro_len == 0 and ky.drawn != null) {
        // 配牌 13 张（不含当前摸牌）
        const closed13 = if (p.tehai_len > 0) p.tehai[0 .. p.tehai_len - 1] else p.tehai[0..0];
        if (kyushuKinds(closed13) >= 9) {
            if (n < out.len) {
                out[n] = .ryukyoku;
                n += 1;
            }
        }
    }

    // 立直：门前、有点棒、有摸牌，且存在切牌后听牌
    if (!p.riichi and ky.pending_riichi == null and p.isMenzen() and ky.scores[seat] >= 1000 and ky.drawn != null) {
        if (canDeclareRiichi(ky, seat)) {
            if (n < out.len) {
                out[n] = .reach;
                n += 1;
            }
        }
    }

    // 暗杠 / 加杠（立直中仅允许摸到的暗杠简化：有 4 张即可）
    n = appendKanActions(ky, seat, out, n);

    const dahai = fillDahai(ky, seat, out[n..]);
    return out[0 .. n + dahai.len];
}

fn fillDahai(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    const hand_slice = ky.handSlice(seat);
    const p = &ky.players[seat];
    var n: usize = 0;
    for (hand_slice, 0..) |pai, i| {
        if (n >= out.len) break;
        const tsumogiri = ky.drawn != null and i + 1 == hand_slice.len and types.paiEql(ky.drawn.?, pai);
        // 已立直：只能摸切
        if (p.riichi and !tsumogiri) continue;
        // 食替禁切
        if (kuikae.forbids(ky, pai)) continue;
        var dup = false;
        for (out[0..n]) |prev| {
            if (prev == .dahai and types.paiEql(prev.dahai.pai, pai) and prev.dahai.tsumogiri == tsumogiri) {
                dup = true;
                break;
            }
        }
        if (dup) continue;
        out[n] = .{ .dahai = .{ .pai = pai, .tsumogiri = tsumogiri } };
        n += 1;
    }
    return out[0..n];
}

fn appendKanActions(ky: *const Kyoku, seat: Seat, out: []Action, start: usize) usize {
    // 吃碰后打牌前不可杠
    if (ky.drawn == null) return start;
    // 河海底不可杠
    if (!ky.yama.hasLive()) return start;
    var n = start;
    const hand = ky.handSlice(seat);
    const p = &ky.players[seat];

    // 暗杠：手中同种 4
    var seen: [34]bool = .{false} ** 34;
    for (hand) |tile| {
        const id = pai_util.kindId(tile) orelse continue;
        if (seen[id]) continue;
        seen[id] = true;
        if (pai_util.countKind(hand, tile) < 4) continue;
        var consumed: [4]Pai = undefined;
        const got = pai_util.takeKinds(hand, tile, 4, &consumed);
        if (got < 4) continue;
        if (n < out.len) {
            out[n] = .{ .ankan = .{ .consumed = consumed } };
            n += 1;
        }
    }

    // 加杠：有明碰且手中还有一张；consumed 为副露三张，pai 为手牌加杠张
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

fn legalWaitResponse(ky: *const Kyoku, seat: Seat, out: []Action) []Action {
    if (!ky.response_open[seat] or ky.response_done[seat]) return out[0..0];
    const pai = ky.response_pai orelse return out[0..0];
    const discarder = ky.response_from;
    if (seat == discarder) return out[0..0];

    var n: usize = 0;
    // 过
    if (n < out.len) {
        out[n] = .none;
        n += 1;
    }

    // 抢杠 / 荣和
    if (ky.pending_kan != null) {
        const ok = if (ky.pending_ankan)
            canKokushiChankan(ky, seat, pai)
        else
            canRon(ky, seat, pai);
        if (ok) {
            if (n < out.len) {
                out[n] = .{ .hora = .{ .target = discarder, .pai = pai } };
                n += 1;
            }
        }
        return out[0..n];
    }

    if (canRon(ky, seat, pai)) {
        if (n < out.len) {
            out[n] = .{ .hora = .{ .target = discarder, .pai = pai } };
            n += 1;
        }
    }

    // 河底：无牌可摸时不可吃碰明杠（仍可荣）
    if (ky.yama.hasLive()) {
        n = appendPonKan(ky, seat, pai, out, n);
        if (seat == round.nextSeat(discarder)) {
            n = appendChi(ky, seat, pai, out, n);
        }
    }

    return out[0..n];
}

fn canRon(ky: *const Kyoku, seat: Seat, pai: Pai) bool {
    const discard = ky.response_pai orelse return false;
    if (!types.paiEql(discard, pai)) return false;
    return referee.canAgari(ky, seat, false);
}

/// 国士抢暗杠：进张为 `response_pai`，仅国士形且非振听。
pub fn canKokushiChankan(ky: *const Kyoku, seat: Seat, pai: Pai) bool {
    const target = ky.response_pai orelse return false;
    if (!types.paiEql(target, pai)) return false;
    return referee.canKokushiRon(ky, seat);
}

fn appendPonKan(ky: *const Kyoku, seat: Seat, pai: Pai, out: []Action, start: usize) usize {
    var n = start;
    const hand = ky.handSlice(seat);
    const p = &ky.players[seat];
    if (p.riichi) return n;

    const cnt = pai_util.countKind(hand, pai);
    if (cnt >= 2) {
        var cands: [4]Pai = undefined;
        const nc = collectKindTiles(hand, pai, &cands);
        var i: usize = 0;
        while (i < nc) : (i += 1) {
            var j: usize = i + 1;
            while (j < nc) : (j += 1) {
                n = pushPonUnique(out, n, pai, cands[i], cands[j]);
            }
        }
    }
    if (cnt >= 3 and ky.yama.hasLive()) {
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
        // 多重集相等
        var want = [_]Pai{ a, b, c };
        var got = out[i].daiminkan.consumed;
        stdSortPai(&want);
        stdSortPai3(&got);
        if (types.paiEql(want[0], got[0]) and types.paiEql(want[1], got[1]) and types.paiEql(want[2], got[2]))
            return n;
    }
    if (n < out.len) {
        out[n] = .{ .daiminkan = .{ .pai = pai, .consumed = .{ a, b, c } } };
        n += 1;
    }
    return n;
}

fn stdSortPai(a: *[3]Pai) void {
    // 简单三元比较排序（按指针地址/内容）
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

fn stdSortPai3(a: *[3]Pai) void {
    stdSortPai(a);
}

fn paiLess(a: Pai, b: Pai) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn appendChi(ky: *const Kyoku, seat: Seat, pai: Pai, out: []Action, start: usize) usize {
    var n = start;
    const p = &ky.players[seat];
    if (p.riichi) return n;
    const s = pai_util.suit(pai) orelse return n;
    const r = pai_util.rank(pai) orelse return n;
    const hand = ky.handSlice(seat);

    const patterns = [_][2]i8{
        .{ -2, -1 },
        .{ -1, 1 },
        .{ 1, 2 },
    };
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
            // 两张同种：枚举有序对 i<j
            var i: usize = 0;
            while (i < n1) : (i += 1) {
                var j: usize = i + 1;
                while (j < n1) : (j += 1) {
                    n = pushChiUnique(out, n, pai, cand1[i], cand1[j]);
                }
            }
            continue;
        }

        var i: usize = 0;
        while (i < n1) : (i += 1) {
            var j: usize = 0;
            while (j < n2) : (j += 1) {
                n = pushChiUnique(out, n, pai, cand1[i], cand2[j]);
            }
        }
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

fn pushChiUnique(out: []Action, start: usize, pai: Pai, a: Pai, b: Pai) usize {
    var n = start;
    // 去重：consumed 同种多重集
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (out[i] != .chi) continue;
        const c = out[i].chi.consumed;
        if (!types.paiEql(out[i].chi.pai, pai)) continue;
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

/// 是否有人可应（打牌后）。
pub fn hasClaimOpportunity(ky: *const Kyoku, discarder: Seat, pai: Pai) bool {
    var seat: u8 = 0;
    while (seat < CAPACITY) : (seat += 1) {
        if (seat == discarder) continue;
        if (seatHasClaim(ky, @intCast(seat), discarder, pai, false)) return true;
    }
    return false;
}

pub fn seatHasClaim(ky: *const Kyoku, seat: Seat, discarder: Seat, pai: Pai, chankan: bool) bool {
    if (seat == discarder) return false;
    if (canRon(ky, seat, pai)) return true;
    if (chankan) return false;
    if (!ky.yama.hasLive()) return false;
    if (ky.players[seat].riichi) return false;
    const hand = ky.handSlice(seat);
    if (pai_util.countKind(hand, pai) >= 2) return true;
    if (seat == round.nextSeat(discarder) and pai_util.suit(pai) != null) {
        const s = pai_util.suit(pai).?;
        const r = pai_util.rank(pai).?;
        const patterns = [_][2]i8{ .{ -2, -1 }, .{ -1, 1 }, .{ 1, 2 } };
        for (patterns) |pat| {
            const r1 = @as(i16, r) + pat[0];
            const r2 = @as(i16, r) + pat[1];
            if (r1 < 1 or r1 > 9 or r2 < 1 or r2 > 9) continue;
            const t1 = pai_util.suitedLiteral(@intCast(r1), s);
            const t2 = pai_util.suitedLiteral(@intCast(r2), s);
            if (pai_util.sameKind(t1, t2)) {
                if (pai_util.countKind(hand, t1) >= 2) return true;
            } else if (pai_util.countKind(hand, t1) >= 1 and pai_util.countKind(hand, t2) >= 1) {
                return true;
            }
        }
    }
    return false;
}

/// 14 张手牌是否存在合法切牌使剩余听牌。
fn canDeclareRiichi(ky: *const Kyoku, seat: Seat) bool {
    const hand = ky.handSlice(seat);
    const fuuro_len = ky.players[seat].fuuro_len;
    var i: usize = 0;
    while (i < hand.len) : (i += 1) {
        const discard = hand[i];
        if (kuikae.forbids(ky, discard)) continue;
        var closed: [14]Pai = undefined;
        var n: usize = 0;
        for (hand, 0..) |p, j| {
            if (j == i) continue;
            closed[n] = p;
            n += 1;
        }
        if (referee.isTenpai(closed[0..n], fuuro_len)) return true;
    }
    return false;
}

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

/// 手牌中不同幺九种类数（九种九牌合法性用）。
fn kyushuKinds(hand: []const Pai) u8 {
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
