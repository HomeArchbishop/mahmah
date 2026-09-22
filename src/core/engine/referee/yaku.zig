//! 役种判定。
//! 对外只暴露 `Form` + `countYaku`；上层传入七对 / 国士无双形 / 标准型。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const standard = @import("standard.zig");
const pai_util = @import("../pai.zig");
const wall = @import("../wall.zig");
const closed_mod = @import("closed.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;
const Decomp = standard.StandardDecomp;

/// 役种计数结果。`yakuman>0` 时按役满计，忽略普通番。
pub const YakuCount = struct {
    han: u8 = 0,
    yakuman: u8 = 0,
};

/// 上层传入的牌形类别（国士十三面由内部对国士形再区分）。
pub const Form = enum {
    chiitoi,
    kokushi,
    standard,
};

/// 按牌形计役。标准型用 `decomp`；七对/国士可传 `.{}`。
pub fn countYaku(ky: *const Kyoku, seat: Seat, tsumo: bool, form: Form, decomp: Decomp) YakuCount {
    return switch (form) {
        .chiitoi => yakuChiitoi(ky, seat, tsumo),
        .kokushi => blk: {
            if (isKokushiJuusanmen(ky, seat, tsumo)) break :blk yakuKokushiJuusanmen(ky, seat, tsumo);
            break :blk yakuKokushi(ky, seat, tsumo);
        },
        .standard => yakuStandard(ky, seat, tsumo, decomp),
    };
}

/// 标准型某一拆解的役。各役函数自行互斥，此处只汇总。
fn yakuStandard(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) YakuCount {
    var total: YakuCount = .{};
    const add = struct {
        fn f(dst: *YakuCount, y: ?YakuCount) void {
            if (y) |v| {
                dst.han += v.han;
                dst.yakuman += v.yakuman;
            }
        }
    }.f;

    add(&total, tenhou(ky, seat, tsumo, decomp));
    add(&total, chiihou(ky, seat, tsumo, decomp));
    add(&total, daisangen(ky, seat, tsumo, decomp));
    add(&total, suuankoo(ky, seat, tsumo, decomp));
    add(&total, suuankootanki(ky, seat, tsumo, decomp));
    add(&total, tsuuiisoo(ky, seat, tsumo, decomp));
    add(&total, ryuuiisoo(ky, seat, tsumo, decomp));
    add(&total, shousuushii(ky, seat, tsumo, decomp));
    add(&total, daisuushii(ky, seat, tsumo, decomp));
    add(&total, chinroutou(ky, seat, tsumo, decomp));
    add(&total, chuurenpoutou(ky, seat, tsumo, decomp));
    add(&total, junseichuurenpoutou(ky, seat, tsumo, decomp));
    add(&total, suukantsu(ky, seat, tsumo, decomp));

    if (total.yakuman > 0) return .{ .yakuman = total.yakuman };

    add(&total, riichi(ky, seat, tsumo, decomp));
    add(&total, dabururiichi(ky, seat, tsumo, decomp));
    add(&total, ippatsu(ky, seat, tsumo, decomp));
    add(&total, menzenchintsumohou(ky, seat, tsumo, decomp));
    add(&total, danyao(ky, seat, tsumo, decomp));
    add(&total, pinfu(ky, seat, tsumo, decomp));
    add(&total, iipeekoo(ky, seat, tsumo, decomp));
    add(&total, ryanpeekoo(ky, seat, tsumo, decomp));
    add(&total, yakuhaiBakaze(ky, seat, tsumo, decomp));
    add(&total, yakuhaiJikaze(ky, seat, tsumo, decomp));
    add(&total, yakuhaiHaku(ky, seat, tsumo, decomp));
    add(&total, yakuhaiHatsu(ky, seat, tsumo, decomp));
    add(&total, yakuhaiChun(ky, seat, tsumo, decomp));
    add(&total, rinshankaihou(ky, seat, tsumo, decomp));
    add(&total, chankan(ky, seat, tsumo, decomp));
    add(&total, haiteiraoyue(ky, seat, tsumo, decomp));
    add(&total, houteiraoyui(ky, seat, tsumo, decomp));
    add(&total, sanshokudoujun(ky, seat, tsumo, decomp));
    add(&total, sanshokudookoo(ky, seat, tsumo, decomp));
    add(&total, ikkitsutokan(ky, seat, tsumo, decomp));
    add(&total, toitoihoo(ky, seat, tsumo, decomp));
    add(&total, sanankoo(ky, seat, tsumo, decomp));
    add(&total, honchantaiyaochuu(ky, seat, tsumo, decomp));
    add(&total, junchantaiyaochuu(ky, seat, tsumo, decomp));
    add(&total, honroutoo(ky, seat, tsumo, decomp));
    add(&total, shousangen(ky, seat, tsumo, decomp));
    add(&total, honiisoo(ky, seat, tsumo, decomp));
    add(&total, chiniisoo(ky, seat, tsumo, decomp));

    // 宝牌不是役：无役时即使有表/里/赤也不能和
    if (total.han == 0) return .{};

    add(&total, dora(ky, seat, tsumo, decomp));
    add(&total, uradora(ky, seat, tsumo, decomp));
    add(&total, akadora(ky, seat, tsumo, decomp));

    return total;
}

/// 七对役：2 番本体 + 可复合役。天和・地和・字一色按役满计。
fn yakuChiitoi(ky: *const Kyoku, seat: Seat, tsumo: bool) YakuCount {
    const empty: Decomp = .{};
    var closed_buf: [14]types.Pai = undefined;
    const closed = closed_mod.collectClosedFromKy(ky, seat, tsumo, &closed_buf) orelse return .{};

    if (tenhou(ky, seat, tsumo, empty)) |y| return y;
    if (chiihou(ky, seat, tsumo, empty)) |y| return y;
    if (tsuuiisooTiles(closed)) return .{ .yakuman = 1 };

    var total: YakuCount = .{ .han = 2 };

    if (dabururiichi(ky, seat, tsumo, empty)) |y| {
        total.han += y.han;
    } else if (riichi(ky, seat, tsumo, empty)) |y| {
        total.han += y.han;
    }
    if (ippatsu(ky, seat, tsumo, empty)) |y| total.han += y.han;
    if (menzenchintsumohou(ky, seat, tsumo, empty)) |y| total.han += y.han;

    if (danyaoTiles(closed)) |y| {
        if (ky.rules.kuitan or ky.players[seat].isMenzen()) total.han += y.han;
    } else if (honroutooTiles(closed)) |y| {
        total.han += y.han;
    }

    if (chiniisooTiles(closed, true)) |y| {
        total.han += y.han;
    } else if (honiisooTiles(closed, true)) |y| {
        total.han += y.han;
    }

    if (haiteiraoyue(ky, seat, tsumo, empty)) |y| total.han += y.han;
    if (houteiraoyui(ky, seat, tsumo, empty)) |y| total.han += y.han;
    if (chankan(ky, seat, tsumo, empty)) |y| total.han += y.han;

    if (doraHanTiles(closed, ky.doraMarkersSlice())) |y| total.han += y.han;
    if (ky.rules.ura and ky.players[seat].riichi) {
        var ura_buf: [kyoku_mod.DORA_MARKER_CAP]types.Pai = undefined;
        if (doraHanTiles(closed, wall.fillUraMarkers(ky, &ura_buf))) |y| total.han += y.han;
    }
    if (ky.rules.aka) {
        if (akadoraTiles(closed)) |y| total.han += y.han;
    }

    return total;
}

/// 国士无双（单倍）。可与天和/地和复合。
fn yakuKokushi(ky: *const Kyoku, seat: Seat, tsumo: bool) YakuCount {
    const empty: Decomp = .{};
    var y: YakuCount = .{ .yakuman = 1 };
    if (tenhou(ky, seat, tsumo, empty) != null or chiihou(ky, seat, tsumo, empty) != null) {
        y.yakuman += 1;
    }
    return y;
}

/// 国士十三面（juusanmen）。倍数额 `rules.kokushi_13_double`；可与天和/地和再复合。
fn yakuKokushiJuusanmen(ky: *const Kyoku, seat: Seat, tsumo: bool) YakuCount {
    const empty: Decomp = .{};
    var y: YakuCount = .{ .yakuman = if (ky.rules.kokushi_13_double) 2 else 1 };
    if (tenhou(ky, seat, tsumo, empty) != null or chiihou(ky, seat, tsumo, empty) != null) {
        y.yakuman += 1;
    }
    return y;
}

/// 国士是否十三面：和了后唯一对子种类 == 进张种类（单骑）。
fn isKokushiJuusanmen(ky: *const Kyoku, seat: Seat, tsumo: bool) bool {
    const winning = (if (tsumo) ky.drawn else ky.response_pai) orelse return false;
    const wk = pai_util.kindId(winning) orelse return false;
    var closed_buf: [14]types.Pai = undefined;
    const closed = closed_mod.collectClosedFromKy(ky, seat, tsumo, &closed_buf) orelse return false;

    var counts: [34]u8 = .{0} ** 34;
    for (closed) |p| {
        const id = pai_util.kindId(p) orelse return false;
        counts[id] += 1;
    }
    var pair_kind: ?u8 = null;
    for (counts, 0..) |c, i| {
        if (c == 2) {
            if (pair_kind != null) return false;
            pair_kind = @intCast(i);
        }
    }
    return pair_kind == wk;
}

fn riichi(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    _ = decomp;
    const p = &ky.players[seat];
    // 双立直由 dabururiichi 计 2 番，这里不重复
    if (!(p.isMenzen() and p.riichi and !p.double_riichi)) return null;
    return .{ .han = 1 };
}

fn ippatsu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    _ = decomp;
    if (!ky.rules.ippatsu) return null;
    if (!(ky.players[seat].isMenzen() and ky.players[seat].ippatsu)) return null;
    return .{ .han = 1 };
}

fn menzenchintsumohou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = decomp;
    if (!(ky.players[seat].isMenzen() and tsumo)) return null;
    return .{ .han = 1 };
}

fn danyao(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    if (!ky.rules.kuitan and !ky.players[seat].isMenzen()) return null;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            if (pai_util.isYaochuuhai(b.tiles[i])) return null;
        }
    }
    return .{ .han = 1 };
}

fn pinfu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    if (!ky.players[seat].isMenzen()) return null;
    for (decomp.blocks) |b| {
        if (b.kind == .kotsu or b.kind == .kantsu) return null;
        if (b.kind == .jantou) {
            // 役牌雀头不可：三元 / 场风 / 自风
            if (pai_util.isSangenpai(b.tiles[0])) return null;
            if (pai_util.sameKind(b.tiles[0], ky.bakaze)) return null;
            const winds = [_]types.Pai{ "E", "S", "W", "N" };
            const jk = winds[(@as(u8, seat) + 4 - @as(u8, ky.oya)) % 4];
            if (pai_util.sameKind(b.tiles[0], jk)) return null;
        }
        if (b.winning) |winning| {
            // 仅两面听；嵌张/边张/单骑等不可
            if (b.kind != .shuntsu) return null;
            if (pai_util.sameKind(winning, b.tiles[1])) return null; // 嵌张
            const low = pai_util.rank(b.tiles[0]) orelse return null;
            if (pai_util.sameKind(winning, b.tiles[0]) and low == 7) return null; // 789 边张
            if (pai_util.sameKind(winning, b.tiles[2]) and low == 1) return null; // 123 边张
        }
    }
    return .{ .han = 1 };
}

fn iipeekoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    if (!(shuntsuPairCount(decomp) == 1 and ky.players[seat].isMenzen())) return null;
    return .{ .han = 1 };
}

fn yakuhaiBakaze(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = tsumo;
    if (!hasKotsuOrKantsu(decomp, ky.bakaze)) return null;
    return .{ .han = 1 };
}

fn yakuhaiJikaze(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    const winds = [_]types.Pai{ "E", "S", "W", "N" };
    const jikaze = winds[(@as(u8, seat) + 4 - @as(u8, ky.oya)) % 4];
    if (!hasKotsuOrKantsu(decomp, jikaze)) return null;
    return .{ .han = 1 };
}

fn yakuhaiHaku(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    if (!hasKotsuOrKantsu(decomp, "P")) return null;
    return .{ .han = 1 };
}

fn yakuhaiHatsu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    if (!hasKotsuOrKantsu(decomp, "F")) return null;
    return .{ .han = 1 };
}

fn yakuhaiChun(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    if (!hasKotsuOrKantsu(decomp, "C")) return null;
    return .{ .han = 1 };
}

fn rinshankaihou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = decomp;
    if (!(tsumo and ky.is_rinshan)) return null;
    return .{ .han = 1 };
}

fn chankan(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = decomp;
    if (!(!tsumo and ky.pending_kan != null)) return null;
    return .{ .han = 1 };
}

fn haiteiraoyue(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = decomp;
    if (!(tsumo and !ky.is_rinshan and !ky.yama.hasLive())) return null;
    return .{ .han = 1 };
}

fn houteiraoyui(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = decomp;
    if (!(!tsumo and ky.pending_kan == null and !ky.yama.hasLive())) return null;
    return .{ .han = 1 };
}

fn dora(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = tsumo;
    return doraHan(decomp, ky.doraMarkersSlice());
}

fn uradora(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    if (!ky.rules.ura) return null;
    if (!ky.players[seat].riichi) return null;
    var ura_buf: [kyoku_mod.DORA_MARKER_CAP]types.Pai = undefined;
    return doraHan(decomp, wall.fillUraMarkers(ky, &ura_buf));
}

fn akadora(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = tsumo;
    if (!ky.rules.aka) return null;
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            if (pai_util.isRed(b.tiles[i])) n += 1;
        }
    }
    if (n == 0) return null;
    return .{ .han = n };
}

fn sanshokudoujun(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    // 起始点数 1..7 × 万饼索
    var has: [7][3]bool = .{.{false} ** 3} ** 7;
    for (decomp.blocks) |b| {
        if (b.kind != .shuntsu) continue;
        const r = pai_util.rank(b.tiles[0]) orelse continue;
        if (r < 1 or r > 7) continue;
        const si = pai_util.suitId(b.tiles[0]) orelse continue;
        has[r - 1][si] = true;
    }
    for (has) |suits| {
        if (suits[0] and suits[1] and suits[2]) {
            return .{ .han = if (ky.players[seat].isMenzen()) 2 else 1 };
        }
    }
    return null;
}

fn sanshokudookoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    // 点数 1..9 × 万饼索
    var has: [9][3]bool = .{.{false} ** 3} ** 9;
    for (decomp.blocks) |b| {
        if (b.kind != .kotsu and b.kind != .kantsu) continue;
        const r = pai_util.rank(b.tiles[0]) orelse continue;
        const si = pai_util.suitId(b.tiles[0]) orelse continue;
        has[r - 1][si] = true;
    }
    for (has) |suits| {
        if (suits[0] and suits[1] and suits[2]) return .{ .han = 2 };
    }
    return null;
}

fn ikkitsutokan(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    // 每色是否有 123 / 456 / 789
    var has: [3][3]bool = .{.{false} ** 3} ** 3;
    for (decomp.blocks) |b| {
        if (b.kind != .shuntsu) continue;
        const r = pai_util.rank(b.tiles[0]) orelse continue;
        const seg: u8 = switch (r) {
            1 => 0,
            4 => 1,
            7 => 2,
            else => continue,
        };
        const si = pai_util.suitId(b.tiles[0]) orelse continue;
        has[si][seg] = true;
    }
    for (has) |segs| {
        if (segs[0] and segs[1] and segs[2]) {
            return .{ .han = if (ky.players[seat].isMenzen()) 2 else 1 };
        }
    }
    return null;
}

fn toitoihoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    for (decomp.blocks) |b| {
        if (b.kind == .shuntsu) return null;
    }
    return .{ .han = 2 };
}

fn sanankoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    if (ankouCount(decomp) == 3) return .{ .han = 2 };
    return null;
}

fn honchantaiyaochuu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    var has_jihai = false;
    var has_shuntsu = false;
    for (decomp.blocks) |b| {
        if (b.kind == .shuntsu) has_shuntsu = true;
        var has_yaochuu = false;
        for (0..b.tile_len) |i| {
            const t = b.tiles[i];
            if (!pai_util.isYaochuuhai(t)) continue;
            has_yaochuu = true;
            if (pai_util.isJihai(t)) has_jihai = true;
        }
        if (!has_yaochuu) return null;
    }
    // 无字则归纯全；无顺则归混老头
    if (!has_jihai or !has_shuntsu) return null;
    return .{ .han = if (ky.players[seat].isMenzen()) 2 else 1 };
}

fn honroutoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    var has_jihai = false;
    for (decomp.blocks) |b| {
        if (b.kind == .shuntsu) return null;
        for (0..b.tile_len) |i| {
            const t = b.tiles[i];
            if (!pai_util.isYaochuuhai(t)) return null;
            if (pai_util.isJihai(t)) has_jihai = true;
        }
    }
    // 无字则归清老头
    if (!has_jihai) return null;
    return .{ .han = 2 };
}

fn shousangen(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    var sangen_kotsu: u8 = 0;
    var sangen_jantou = false;
    for (decomp.blocks) |b| {
        if (!pai_util.isSangenpai(b.tiles[0])) continue;
        switch (b.kind) {
            .jantou => sangen_jantou = true,
            .kotsu, .kantsu => sangen_kotsu += 1,
            else => {},
        }
    }
    if (sangen_kotsu == 2 and sangen_jantou) return .{ .han = 2 };
    return null;
}

fn dabururiichi(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    _ = decomp;
    const p = &ky.players[seat];
    if (!(p.isMenzen() and p.double_riichi)) return null;
    return .{ .han = 2 };
}

fn honiisoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    var suit_seen: ?u8 = null;
    var has_jihai = false;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            const t = b.tiles[i];
            if (pai_util.isJihai(t)) {
                has_jihai = true;
                continue;
            }
            const si = pai_util.suitId(t) orelse return null;
            if (suit_seen) |s| {
                if (s != si) return null;
            } else suit_seen = si;
        }
    }
    // 无字则归清一色；须有数牌
    if (!has_jihai or suit_seen == null) return null;
    return .{ .han = if (ky.players[seat].isMenzen()) 3 else 2 };
}

fn junchantaiyaochuu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    var has_shuntsu = false;
    for (decomp.blocks) |b| {
        if (b.kind == .shuntsu) has_shuntsu = true;
        var has_yaochuu = false;
        for (0..b.tile_len) |i| {
            const t = b.tiles[i];
            if (pai_util.isJihai(t)) return null;
            if (pai_util.isYaochuuhai(t)) has_yaochuu = true;
        }
        if (!has_yaochuu) return null;
    }
    // 无顺则归清老头
    if (!has_shuntsu) return null;
    return .{ .han = if (ky.players[seat].isMenzen()) 3 else 2 };
}

fn ryanpeekoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    if (!(shuntsuPairCount(decomp) == 2 and ky.players[seat].isMenzen())) return null;
    return .{ .han = 3 };
}

fn chiniisoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    var suit_seen: ?u8 = null;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            const si = pai_util.suitId(b.tiles[i]) orelse return null;
            if (suit_seen) |s| {
                if (s != si) return null;
            } else suit_seen = si;
        }
    }
    if (suit_seen == null) return null;
    return .{ .han = if (ky.players[seat].isMenzen()) 6 else 5 };
}

fn daisangen(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        if (b.kind != .kotsu and b.kind != .kantsu) continue;
        if (pai_util.isSangenpai(b.tiles[0])) n += 1;
    }
    if (n == 3) return .{ .yakuman = 1 };
    return null;
}

fn suuankoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    if (ankouCount(decomp) != 4) return null;
    // 单骑由 suuankootanki 计（单/双倍见 rules.suuankou_tanki_double）
    if (decomp.blocks[0].winning != null) return null;
    return .{ .yakuman = 1 };
}

fn tsuuiisoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            if (!pai_util.isJihai(b.tiles[i])) return null;
        }
    }
    return .{ .yakuman = 1 };
}

fn ryuuiisoo(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            if (!isGreen(b.tiles[i])) return null;
        }
    }
    return .{ .yakuman = 1 };
}

fn shousuushii(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    var kaze_kotsu: u8 = 0;
    var kaze_jantou = false;
    for (decomp.blocks) |b| {
        if (!pai_util.isKazehai(b.tiles[0])) continue;
        switch (b.kind) {
            .jantou => kaze_jantou = true,
            .kotsu, .kantsu => kaze_kotsu += 1,
            else => {},
        }
    }
    if (kaze_kotsu == 3 and kaze_jantou) return .{ .yakuman = 1 };
    return null;
}

fn chinroutou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    for (decomp.blocks) |b| {
        if (b.kind == .shuntsu) return null;
        for (0..b.tile_len) |i| {
            if (!pai_util.isRoutouhai(b.tiles[i])) return null;
        }
    }
    return .{ .yakuman = 1 };
}

fn chuurenpoutou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    if (!ky.players[seat].isMenzen()) return null;
    // 纯正由 junseichuurenpoutou 计（单/双倍见 rules.junsei_chuuren_double）
    if (chuurenKind(decomp) != false) return null;
    return .{ .yakuman = 1 };
}

fn suukantsu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        if (b.kind == .kantsu) n += 1;
    }
    if (n == 4) return .{ .yakuman = 1 };
    return null;
}

fn tenhou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = decomp;
    if (!(tsumo and seat == ky.oya and ky.is_first_turn)) return null;
    const p = &ky.players[seat];
    if (p.river_len != 0 or p.fuuro_len != 0) return null;
    return .{ .yakuman = 1 };
}

fn chiihou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = decomp;
    if (!(tsumo and seat != ky.oya and ky.is_first_turn)) return null;
    const p = &ky.players[seat];
    if (p.river_len != 0 or p.fuuro_len != 0) return null;
    return .{ .yakuman = 1 };
}

fn daisuushii(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = tsumo;
    var kaze_kotsu: u8 = 0;
    for (decomp.blocks) |b| {
        if (b.kind != .kotsu and b.kind != .kantsu) continue;
        if (pai_util.isKazehai(b.tiles[0])) kaze_kotsu += 1;
    }
    if (kaze_kotsu != 4) return null;
    return .{ .yakuman = if (ky.rules.daisuushii_double) 2 else 1 };
}

fn junseichuurenpoutou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    if (!ky.players[seat].isMenzen()) return null;
    if (chuurenKind(decomp) != true) return null;
    return .{ .yakuman = if (ky.rules.junsei_chuuren_double) 2 else 1 };
}

fn suuankootanki(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = seat;
    _ = tsumo;
    if (ankouCount(decomp) != 4) return null;
    if (decomp.blocks[0].winning == null) return null;
    return .{ .yakuman = if (ky.rules.suuankou_tanki_double) 2 else 1 };
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

/// 绿一色允许的牌：2s 3s 4s 6s 8s 发。
fn isGreen(pai: types.Pai) bool {
    if (types.paiEql(pai, "F")) return true;
    if ((pai_util.suit(pai) orelse return false) != 's') return false;
    const r = pai_util.rank(pai) orelse return false;
    return r == 2 or r == 3 or r == 4 or r == 6 or r == 8;
}

/// 暗刻/暗杠数（荣和完成的刻不计）。
fn ankouCount(decomp: Decomp) u8 {
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        if (b.kind != .kotsu and b.kind != .kantsu) continue;
        if (b.is_fuuro) continue;
        if (b.winning != null and !b.winning_tsumo) continue;
        n += 1;
    }
    return n;
}

/// 九莲：`null` 非九莲；`false` 普通；`true` 纯正（听牌形恰为 1112345678999）。
fn chuurenKind(decomp: Decomp) ?bool {
    var counts: [9]u8 = .{0} ** 9;
    var suit_seen: ?u8 = null;
    var winning_rank: ?u8 = null;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            const t = b.tiles[i];
            const si = pai_util.suitId(t) orelse return null;
            const r = pai_util.rank(t) orelse return null;
            if (suit_seen) |s| {
                if (s != si) return null;
            } else suit_seen = si;
            counts[r - 1] += 1;
        }
        if (b.winning) |w| {
            winning_rank = pai_util.rank(w);
        }
    }
    const base = [_]u8{ 3, 1, 1, 1, 1, 1, 1, 1, 3 };
    var extras: u8 = 0;
    for (counts, 0..) |c, i| {
        if (c == base[i]) continue;
        if (c == base[i] + 1) {
            extras += 1;
            continue;
        }
        return null;
    }
    if (extras != 1) return null;
    const wr = winning_rank orelse return false;
    if (wr < 1 or wr > 9) return false;
    counts[wr - 1] -= 1;
    for (counts, 0..) |c, i| {
        if (c != base[i]) return false;
    }
    return true;
}

fn shuntsuPairCount(decomp: Decomp) u8 {
    var freq: [34]u8 = .{0} ** 34;
    for (decomp.blocks) |b| {
        if (b.kind != .shuntsu or b.is_fuuro) continue;
        freq[pai_util.kindId(b.tiles[0]) orelse continue] += 1;
    }
    var pairs: u8 = 0;
    for (freq) |c| pairs += c / 2;
    return pairs;
}

fn hasKotsuOrKantsu(decomp: Decomp, tile: types.Pai) bool {
    for (decomp.blocks) |b| {
        if (b.kind != .kotsu and b.kind != .kantsu) continue;
        if (pai_util.sameKind(b.tiles[0], tile)) return true;
    }
    return false;
}

fn doraHan(decomp: Decomp, markers: []const types.Pai) ?YakuCount {
    var mult: [34]u8 = undefined;
    fillDoraMult(markers, &mult);
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            const k = pai_util.kindId(b.tiles[i]) orelse continue;
            n += mult[k];
        }
    }
    if (n == 0) return null;
    return .{ .han = n };
}

/// 各牌种作为宝牌的倍数（同指示重复则累加，如两张 2p 指示 → 3p 算 2 翻）。
fn fillDoraMult(markers: []const types.Pai, mult: *[34]u8) void {
    mult.* = .{0} ** 34;
    for (markers) |m| {
        const k = pai_util.doraKindFromIndicator(m) orelse continue;
        mult[k] += 1;
    }
}

fn doraHanTiles(tiles: []const types.Pai, markers: []const types.Pai) ?YakuCount {
    var mult: [34]u8 = undefined;
    fillDoraMult(markers, &mult);
    var n: u8 = 0;
    for (tiles) |t| {
        const k = pai_util.kindId(t) orelse continue;
        n += mult[k];
    }
    if (n == 0) return null;
    return .{ .han = n };
}

fn akadoraTiles(tiles: []const types.Pai) ?YakuCount {
    var n: u8 = 0;
    for (tiles) |t| {
        if (pai_util.isRed(t)) n += 1;
    }
    if (n == 0) return null;
    return .{ .han = n };
}

fn danyaoTiles(tiles: []const types.Pai) ?YakuCount {
    for (tiles) |t| {
        if (pai_util.isYaochuuhai(t)) return null;
    }
    return .{ .han = 1 };
}

fn honroutooTiles(tiles: []const types.Pai) ?YakuCount {
    var has_jihai = false;
    for (tiles) |t| {
        if (!pai_util.isYaochuuhai(t)) return null;
        if (pai_util.isJihai(t)) has_jihai = true;
    }
    if (!has_jihai) return null;
    return .{ .han = 2 };
}

fn tsuuiisooTiles(tiles: []const types.Pai) bool {
    for (tiles) |t| {
        if (!pai_util.isJihai(t)) return false;
    }
    return tiles.len > 0;
}

fn honiisooTiles(tiles: []const types.Pai, menzen: bool) ?YakuCount {
    var suit_seen: ?u8 = null;
    var has_jihai = false;
    for (tiles) |t| {
        if (pai_util.isJihai(t)) {
            has_jihai = true;
            continue;
        }
        const si = pai_util.suitId(t) orelse return null;
        if (suit_seen) |s| {
            if (s != si) return null;
        } else suit_seen = si;
    }
    if (!has_jihai or suit_seen == null) return null;
    return .{ .han = if (menzen) 3 else 2 };
}

fn chiniisooTiles(tiles: []const types.Pai, menzen: bool) ?YakuCount {
    var suit_seen: ?u8 = null;
    for (tiles) |t| {
        const si = pai_util.suitId(t) orelse return null;
        if (suit_seen) |s| {
            if (s != si) return null;
        } else suit_seen = si;
    }
    if (suit_seen == null) return null;
    return .{ .han = if (menzen) 6 else 5 };
}

test "yakuChiitoi base 2 han" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");
    var ky = Kyoku.init();
    ky.is_first_turn = false;
    const tiles = [_]types.Pai{ "1m", "1m", "2m", "2m", "3m", "3m", "4p", "4p", "5p", "5p", "6s", "6s", "7s", "7s" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "7s";
    const y = countYaku(&ky, 0, true, .chiitoi, .{});
    try std.testing.expectEqual(@as(u8, 0), y.yakuman);
    try std.testing.expectEqual(@as(u8, 3), y.han); // 七对+门清自摸
}

test "yakuChiitoi chinitsu" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");
    var ky = Kyoku.init();
    ky.is_first_turn = false;
    const tiles = [_]types.Pai{ "1m", "1m", "2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "8m" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.response_pai = "8m";
    const y = countYaku(&ky, 0, false, .chiitoi, .{});
    try std.testing.expectEqual(@as(u8, 8), y.han); // 2+6 清一色
}

test "yakuChiitoi tsuuiisoo yakuman" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");
    var ky = Kyoku.init();
    ky.is_first_turn = false;
    const tiles = [_]types.Pai{ "E", "E", "S", "S", "W", "W", "N", "N", "P", "P", "F", "F", "C", "C" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "C";
    const y = countYaku(&ky, 0, true, .chiitoi, .{});
    try std.testing.expectEqual(@as(u8, 1), y.yakuman);
    try std.testing.expectEqual(@as(u8, 0), y.han);
}

test "yakuKokushi single; stacks with tenhou" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");
    const rules = @import("../../rules.zig");
    var ky = Kyoku.init();
    ky.oya = 0;
    ky.is_first_turn = true;
    // 对子在 C，进张 C → juusanmen
    const tiles = [_]types.Pai{ "1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C", "C" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "C";
    const y13 = countYaku(&ky, 0, true, .kokushi, .{});
    try std.testing.expectEqual(@as(u8, 3), y13.yakuman); // juusanmen2 + tenhou1

    ky.is_first_turn = false;
    const y13b = countYaku(&ky, 0, true, .kokushi, .{});
    try std.testing.expectEqual(@as(u8, 2), y13b.yakuman);

    ky.rules = rules.Rules.riichienv();
    try std.testing.expectEqual(@as(u8, 1), countYaku(&ky, 0, true, .kokushi, .{}).yakuman);

    // 对子在 1m，进张 C → 非 juusanmen
    var ky2 = Kyoku.init();
    ky2.oya = 0;
    ky2.is_first_turn = false;
    const tiles2 = [_]types.Pai{ "1m", "1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C" };
    for (tiles2) |t| seat_tiles.addToHand(&ky2, 0, t);
    ky2.drawn = "C";
    const y1 = countYaku(&ky2, 0, true, .kokushi, .{});
    try std.testing.expectEqual(@as(u8, 1), y1.yakuman);
}

test "yakuStandard: menzen tsumo pinfu danyao" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    ky.is_first_turn = false;
    // 门清：123m 456m 789p 22s + 摸 3s → 需完整拆解
    // 用 standardDecomps 生成
    const tiles = [_]types.Pai{ "1m", "2m", "3m", "4m", "5m", "6m", "7p", "8p", "9p", "2s", "2s", "3s", "4s", "5s" };
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "5s";

    var buf: [64]standard.StandardDecomp = undefined;
    const decomps = standard.standardDecomps(&ky, 0, true, &buf);
    try std.testing.expect(decomps.len >= 1);

    const y = countYaku(&ky, 0, true, .standard, decomps[0]);
    try std.testing.expectEqual(@as(u8, 0), y.yakuman);
    // 门清自摸 + 断幺 + 可能平和
    try std.testing.expect(y.han >= 2);
}

test "suuankootanki: double vs riichienv single" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");
    const rules = @import("../../rules.zig");

    // 111m 222p 333s CCC WW + 摸 W：四暗刻单骑
    const tiles = [_]types.Pai{ "1m", "1m", "1m", "2p", "2p", "2p", "3s", "3s", "3s", "C", "C", "C", "W", "W" };
    var ky = Kyoku.init();
    ky.is_first_turn = false;
    for (tiles) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "W";

    var buf: [64]standard.StandardDecomp = undefined;
    const decomps = standard.standardDecomps(&ky, 0, true, &buf);
    try std.testing.expect(decomps.len >= 1);
    // 取雀头进张的拆解
    var tanki_decomp: ?standard.StandardDecomp = null;
    for (decomps) |d| {
        if (d.blocks[0].winning != null) {
            tanki_decomp = d;
            break;
        }
    }
    try std.testing.expect(tanki_decomp != null);

    ky.rules = rules.Rules.default();
    try std.testing.expectEqual(@as(u8, 2), countYaku(&ky, 0, true, .standard, tanki_decomp.?).yakuman);

    ky.rules = rules.Rules.riichienv();
    try std.testing.expectEqual(@as(u8, 1), countYaku(&ky, 0, true, .standard, tanki_decomp.?).yakuman);
}

test "daisuushii: double vs riichienv single" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");
    const rules = @import("../../rules.zig");

    // 大四喜副露三风刻，避免叠四暗刻：碰 E/S/W + 手牌 NNN 11m 摸 1m
    var ky = Kyoku.init();
    ky.is_first_turn = false;
    for ([_]types.Pai{ "E", "S", "W" }) |w| {
        var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = 1 };
        f.tiles = .{ w, w, w, undefined };
        seat_tiles.addFuuro(&ky, 0, f);
    }
    for ([_]types.Pai{ "N", "N", "N", "1m", "1m" }) |t| seat_tiles.addToHand(&ky, 0, t);
    ky.drawn = "1m";

    var buf: [64]standard.StandardDecomp = undefined;
    const decomps = standard.standardDecomps(&ky, 0, true, &buf);
    try std.testing.expect(decomps.len >= 1);

    ky.rules = rules.Rules.default();
    try std.testing.expectEqual(@as(u8, 2), countYaku(&ky, 0, true, .standard, decomps[0]).yakuman);

    ky.rules = rules.Rules.riichienv();
    try std.testing.expectEqual(@as(u8, 1), countYaku(&ky, 0, true, .standard, decomps[0]).yakuman);
}

test "doraHan: duplicate markers stack" {
    const std = @import("std");
    const seat_tiles = @import("../seat_tiles.zig");

    var ky = Kyoku.init();
    ky.is_first_turn = false;
    // 吃 345p（含一张 3p）+ 三碰占位；雀头自摸 2m
    var f0: kyoku_mod.Fuuro = .{ .kind = .chi, .tile_len = 3, .from = 1 };
    f0.tiles = .{ "3p", "4p", "5p", undefined };
    seat_tiles.addFuuro(&ky, 0, f0);
    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        var f: kyoku_mod.Fuuro = .{ .kind = .pon, .tile_len = 3, .from = 1 };
        f.tiles = .{ "9s", "9s", "9s", undefined };
        seat_tiles.addFuuro(&ky, 0, f);
    }
    seat_tiles.addToHand(&ky, 0, "2m");
    seat_tiles.addToHand(&ky, 0, "2m");
    ky.drawn = "2m";
    ky.yama.dora_markers = .{ "2p", "2p", undefined, undefined, undefined };
    ky.yama.dora_markers_len = 2;

    var buf: [64]standard.StandardDecomp = undefined;
    const decomps = standard.standardDecomps(&ky, 0, true, &buf);
    try std.testing.expect(decomps.len >= 1);
    const d = doraHan(decomps[0], ky.doraMarkersSlice());
    try std.testing.expect(d != null);
    try std.testing.expectEqual(@as(u8, 2), d.?.han);
}
