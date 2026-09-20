//! 座位牌位（手牌 / 河 / 副露）增删。
const std = @import("std");
const types = @import("../types.zig");
const kyoku_mod = @import("../kyoku.zig");
const pai_util = @import("pai.zig");
const Kyoku = kyoku_mod.Kyoku;
const Seat = types.Seat;
const Pai = types.Pai;
const HAND_CAP = kyoku_mod.HAND_CAP;

/// 手牌末尾加入一张（发牌/摸牌）；摸入时清除同巡振听。
pub fn addToHand(ky: *Kyoku, seat: Seat, pai: Pai) void {
    const p = &ky.players[seat];
    std.debug.assert(p.tehai_len < HAND_CAP);
    p.tehai[p.tehai_len] = pai;
    p.tehai_len += 1;
    clearDoujunFuriten(ky, seat);
}

/// 河牌末尾加入一张。
pub fn addToRiver(ky: *Kyoku, seat: Seat, pai: Pai) void {
    const p = &ky.players[seat];
    std.debug.assert(p.river_len < p.river.len);
    p.river[p.river_len] = pai;
    p.river_len += 1;
}

/// 舍张日志末尾加入一张（鸣走不删）。
pub fn addToSutehai(ky: *Kyoku, seat: Seat, pai: Pai) void {
    const p = &ky.players[seat];
    std.debug.assert(p.sutehai_len < p.sutehai.len);
    p.sutehai[p.sutehai_len] = pai;
    p.sutehai_len += 1;
}

pub fn clearDoujunFuriten(ky: *Kyoku, seat: Seat) void {
    ky.players[seat].doujun_furiten = false;
}

/// 从河末移除（被鸣走）。
pub fn popRiver(ky: *Kyoku, seat: Seat) ?Pai {
    const p = &ky.players[seat];
    if (p.river_len == 0) return null;
    p.river_len -= 1;
    return p.river[p.river_len];
}

/// 从手牌移除指定牌。摸切只摘末张摸牌；非摸切在非摸牌区查找。
pub fn removeFromHand(ky: *Kyoku, seat: Seat, pai: Pai, tsumogiri: bool) bool {
    const p = &ky.players[seat];
    if (p.tehai_len == 0) return false;

    if (tsumogiri) {
        if (ky.drawn == null or !types.paiEql(ky.drawn.?, pai)) return false;
        if (!types.paiEql(p.tehai[p.tehai_len - 1], pai)) return false;
        p.tehai_len -= 1;
        return true;
    }

    const last_is_drawn = ky.drawn != null and types.paiEql(p.tehai[p.tehai_len - 1], ky.drawn.?);
    const search_end: usize = if (last_is_drawn) p.tehai_len - 1 else p.tehai_len;
    var i: usize = 0;
    while (i < search_end) : (i += 1) {
        if (types.paiEql(p.tehai[i], pai)) {
            removeAt(p, i);
            return true;
        }
    }
    if (last_is_drawn and types.paiEql(ky.drawn.?, pai)) {
        p.tehai_len -= 1;
        return true;
    }
    return false;
}

/// 按精确牌面依次移除（用于吃碰杠 consumed）。
pub fn removeExactTiles(ky: *Kyoku, seat: Seat, tiles: []const Pai) bool {
    const p = &ky.players[seat];
    for (tiles) |need| {
        var found = false;
        var i: usize = 0;
        while (i < p.tehai_len) : (i += 1) {
            if (types.paiEql(p.tehai[i], need)) {
                removeAt(p, i);
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn removeAt(p: *kyoku_mod.Player, i: usize) void {
    var j = i;
    while (j + 1 < p.tehai_len) : (j += 1) {
        p.tehai[j] = p.tehai[j + 1];
    }
    p.tehai_len -= 1;
}

pub fn addFuuro(ky: *Kyoku, seat: Seat, f: kyoku_mod.Fuuro) void {
    const p = &ky.players[seat];
    std.debug.assert(p.fuuro_len < kyoku_mod.FUURO_CAP);
    p.fuuro[p.fuuro_len] = f;
    p.fuuro_len += 1;
}

/// 将指定明碰升级为加杠；consumed 为副露三张，pai 为手牌第四张。
pub fn upgradePonToKakan(ky: *Kyoku, seat: Seat, pai: Pai, consumed: [3]Pai) bool {
    for (consumed) |c| {
        if (!pai_util.sameKind(c, pai)) return false;
    }
    const p = &ky.players[seat];
    var i: u8 = 0;
    while (i < p.fuuro_len) : (i += 1) {
        const f = &p.fuuro[i];
        if (f.kind != .pon or f.tile_len < 3) continue;
        if (!pai_util.sameKind(f.tiles[0], pai)) continue;
        f.kind = .kakan;
        f.tiles[3] = pai;
        f.tile_len = 4;
        return true;
    }
    return false;
}

pub fn clearIppatsuAll(ky: *Kyoku) void {
    for (&ky.players) |*p| {
        p.ippatsu = false;
    }
}
