//! 役种判定：统一 `(ky, seat, tsumo, decomp)`。
const types = @import("../../types.zig");
const kyoku_mod = @import("../../kyoku.zig");
const standard = @import("standard.zig");
const pai_util = @import("../pai.zig");
const wall = @import("../wall.zig");

const Seat = types.Seat;
const Kyoku = kyoku_mod.Kyoku;
const Decomp = standard.StandardDecomp;

/// 役种计数结果。`yakuman>0` 时按役满计，忽略普通番。
pub const YakuCount = struct {
    han: u8 = 0,
    yakuman: u8 = 0,
};

/// 标准型某一拆解的役。TODO：逐役判定。
pub fn yakuStandard(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    _ = decomp;
    return .{ .han = 1 };
}

/// 七对役。TODO。`decomp` 保留接口一致，特殊形可传 `.{}`。
pub fn yakuChiitoi(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    _ = decomp;
    return .{ .han = 2 };
}

/// 国士役。TODO（双倍国士等）。`decomp` 保留接口一致，特殊形可传 `.{}`。
pub fn yakuKokushi(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    _ = decomp;
    return .{ .yakuman = 1 };
}

/// 标准型拆解是否有役（番缚）。
pub fn hasYaku(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) bool {
    const y = yakuStandard(ky, seat, tsumo, decomp);
    return y.yakuman > 0 or y.han > 0;
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
    if (!(ky.players[seat].isMenzen() and ky.players[seat].ippatsu)) return null;
    return .{ .han = 1 };
}

fn menzenchintsumohou(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = decomp;
    if (!(ky.players[seat].isMenzen() and tsumo)) return null;
    return .{ .han = 1 };
}

fn danyao(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            if (pai_util.isYaochuuhai(b.tiles[i])) return null;
        }
    }
    return .{ .han = 1 };
}

fn pinfu(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = tsumo;
    for (decomp.blocks) |b| {
        if (b.kind == .kotsu or b.kind == .kantsu) return null;
        if (b.kind == .jantou and pai_util.isJihai(b.tiles[0])) return null;
        if (b.winning) |winning| {
            if (pai_util.sameKind(winning, b.tiles[1])) return null;
        }
    }
    if (!ky.players[seat].isMenzen()) return null;
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
    if (!ky.players[seat].riichi) return null;
    var ura_buf: [kyoku_mod.DORA_MARKER_CAP]types.Pai = undefined;
    return doraHan(decomp, wall.fillUraMarkers(ky, &ura_buf));
}

fn akadora(ky: *const Kyoku, seat: Seat, tsumo: bool, decomp: Decomp) ?YakuCount {
    _ = ky;
    _ = seat;
    _ = tsumo;
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
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        if (b.kind != .kotsu and b.kind != .kantsu) continue;
        if (b.is_fuuro) continue;
        // 荣和完成的刻不算暗刻；自摸完成的算
        if (b.winning != null and !b.winning_tsumo) continue;
        n += 1;
    }
    if (n == 3) return .{ .han = 2 };
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
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        if (b.kind != .kotsu and b.kind != .kantsu) continue;
        if (b.is_fuuro) continue;
        if (b.winning != null and !b.winning_tsumo) continue;
        n += 1;
    }
    if (n == 4) return .{ .yakuman = 1 };
    return null;
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
    var is_dora: [34]bool = .{false} ** 34;
    for (markers) |m| {
        const k = pai_util.doraKindFromIndicator(m) orelse continue;
        is_dora[k] = true;
    }
    var n: u8 = 0;
    for (decomp.blocks) |b| {
        for (0..b.tile_len) |i| {
            const k = pai_util.kindId(b.tiles[i]) orelse continue;
            if (is_dora[k]) n += 1;
        }
    }
    if (n == 0) return null;
    return .{ .han = n };
}
