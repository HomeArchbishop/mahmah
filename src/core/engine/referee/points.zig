//! 得点：基本点、和了得失、罚符。不含役/符判定。
//!
//! 不满贯：基本点 = 符 × 2^(翻+2)（不先整百）；各家支付额再进位到 100。
//! 满贯以上用表定基本点。含切上满贯（3 翻 60 符 / 4 翻 30 符）。
const std = @import("std");
const types = @import("../../types.zig");

const Seat = types.Seat;
const CAPACITY = types.CAPACITY;

/// 一家和了的番符（供 `horaDeltas`）。
pub const HoraValue = struct {
    han: u8 = 0,
    fu: u16 = 0,
    yakuman: u8 = 0,
};

/// 听牌罚符：不听者合计支付 3000，由听牌者均分。0/4 家听则全 0。
pub fn notenDeltas(tenpai: [CAPACITY]bool) [CAPACITY]i32 {
    var n_ten: u8 = 0;
    for (tenpai) |t| {
        if (t) n_ten += 1;
    }
    if (n_ten == 0 or n_ten == 4) return .{ 0, 0, 0, 0 };

    const n_noten: u8 = @as(u8, CAPACITY) - n_ten;
    const pay: i32 = @divExact(3000, @as(i32, n_noten));
    const recv: i32 = @divExact(3000, @as(i32, n_ten));
    var d: [CAPACITY]i32 = .{ 0, 0, 0, 0 };
    var i: u8 = 0;
    while (i < CAPACITY) : (i += 1) {
        d[i] = if (tenpai[i]) recv else -pay;
    }
    return d;
}

/// 役满罚符点数差：亲家犯规 -12000/+4000×3；子家 -8000，亲家 +4000，另两家 +2000。
pub fn chomboDeltas(offender: Seat, oya: Seat) [CAPACITY]i32 {
    var d: [CAPACITY]i32 = .{ 0, 0, 0, 0 };
    if (offender == oya) {
        d[offender] = -12000;
        for (&d, 0..) |*x, i| {
            if (i != offender) x.* = 4000;
        }
    } else {
        d[offender] = -8000;
        d[oya] = 4000;
        for (&d, 0..) |*x, i| {
            if (i != offender and i != oya) x.* = 2000;
        }
    }
    return d;
}

/// 基本点。不满贯返回未整百的 raw（支付时再进位）；满贯以上为表定值。
pub fn basicPoints(han: u8, fu: u16, yakuman: u8) u32 {
    if (yakuman > 0) return 8000 * @as(u32, yakuman);
    if (han >= 13) return 8000;
    if (han >= 11) return 6000;
    if (han >= 8) return 4000;
    if (han >= 6) return 3000;
    if (han >= 5) return 2000;
    if (han == 0 or fu == 0) return 0;

    // 切上满贯：4 翻 30 符、3 翻 60 符
    if ((han >= 4 and fu >= 30) or (han == 3 and fu >= 60)) return 2000;

    const shift: u5 = @intCast(@min(han + 2, 31));
    const raw: u32 = @as(u32, fu) * (@as(u32, 1) << shift);
    if (raw >= 2000) return 2000;
    return raw;
}

/// 按番符计算一家和了的点数差（含本场；`kyotaku` 为供托棒数）。
pub fn horaDeltas(
    winner: Seat,
    from: Seat,
    oya: Seat,
    value: HoraValue,
    honba: u8,
    kyotaku: u8,
    tsumo: bool,
) [CAPACITY]i32 {
    var d: [CAPACITY]i32 = .{ 0, 0, 0, 0 };
    const bp = basicPoints(value.han, value.fu, value.yakuman);
    if (bp == 0) return d;

    const honba_all: i32 = 300 * @as(i32, honba);
    const honba_each: i32 = 100 * @as(i32, honba);
    const stick: i32 = 1000 * @as(i32, kyotaku);

    if (tsumo) {
        if (winner == oya) {
            const pay: i32 = @as(i32, @intCast(ceil100(2 * bp)));
            var i: u8 = 0;
            while (i < CAPACITY) : (i += 1) {
                if (i == winner) continue;
                d[i] -= pay + honba_each;
                d[winner] += pay + honba_each;
            }
        } else {
            const pay_oya: i32 = @as(i32, @intCast(ceil100(2 * bp)));
            const pay_ko: i32 = @as(i32, @intCast(ceil100(bp)));
            var i: u8 = 0;
            while (i < CAPACITY) : (i += 1) {
                if (i == winner) continue;
                const pay = if (i == oya) pay_oya else pay_ko;
                d[i] -= pay + honba_each;
                d[winner] += pay + honba_each;
            }
        }
        d[winner] += stick;
        return d;
    }

    const mult: u32 = if (winner == oya) 6 else 4;
    const pay: i32 = @as(i32, @intCast(ceil100(mult * bp))) + honba_all;
    d[from] -= pay;
    d[winner] += pay + stick;
    return d;
}

fn ceil100(x: u32) u32 {
    if (x == 0) return 0;
    return ((x + 99) / 100) * 100;
}

test "basicPoints 1han 30fu raw" {
    try std.testing.expectEqual(@as(u32, 240), basicPoints(1, 30, 0));
}

test "basicPoints kiriage mangan 4han 30fu" {
    try std.testing.expectEqual(@as(u32, 2000), basicPoints(4, 30, 0));
}

test "basicPoints kiriage mangan 3han 60fu" {
    try std.testing.expectEqual(@as(u32, 2000), basicPoints(3, 60, 0));
}

test "horaDeltas child ron 1han 30fu" {
    const v: HoraValue = .{ .han = 1, .fu = 30 };
    const d = horaDeltas(1, 0, 0, v, 0, 0, false);
    try std.testing.expectEqual(@as(i32, -1000), d[0]);
    try std.testing.expectEqual(@as(i32, 1000), d[1]);
}

test "horaDeltas child ron 1han 30fu 1honba" {
    const v: HoraValue = .{ .han = 1, .fu = 30 };
    const d = horaDeltas(1, 0, 0, v, 1, 0, false);
    try std.testing.expectEqual(@as(i32, -1300), d[0]);
    try std.testing.expectEqual(@as(i32, 1300), d[1]);
}

test "horaDeltas dealer ron 1han 30fu" {
    const v: HoraValue = .{ .han = 1, .fu = 30 };
    const d = horaDeltas(0, 1, 0, v, 0, 0, false);
    try std.testing.expectEqual(@as(i32, 1500), d[0]);
    try std.testing.expectEqual(@as(i32, -1500), d[1]);
}

test "horaDeltas dealer ron 4han 30fu 2honba kiriage" {
    // 切上满贯 12000 + 600 = 12600
    const v: HoraValue = .{ .han = 4, .fu = 30 };
    const d = horaDeltas(2, 3, 2, v, 2, 0, false);
    try std.testing.expectEqual(@as(i32, 12600), d[2]);
    try std.testing.expectEqual(@as(i32, -12600), d[3]);
}

test "horaDeltas child tsumo 1han 30fu" {
    const v: HoraValue = .{ .han = 1, .fu = 30 };
    const d = horaDeltas(1, 1, 0, v, 0, 0, true);
    try std.testing.expectEqual(@as(i32, -500), d[0]);
    try std.testing.expectEqual(@as(i32, 1100), d[1]);
    try std.testing.expectEqual(@as(i32, -300), d[2]);
    try std.testing.expectEqual(@as(i32, -300), d[3]);
}

test "horaDeltas mangan child ron" {
    const v: HoraValue = .{ .han = 5, .fu = 30 };
    const d = horaDeltas(1, 0, 0, v, 0, 0, false);
    try std.testing.expectEqual(@as(i32, -8000), d[0]);
    try std.testing.expectEqual(@as(i32, 8000), d[1]);
}

test "horaDeltas yakuman child ron" {
    const v: HoraValue = .{ .yakuman = 1 };
    const d = horaDeltas(1, 0, 0, v, 0, 0, false);
    try std.testing.expectEqual(@as(i32, -32000), d[0]);
    try std.testing.expectEqual(@as(i32, 32000), d[1]);
}

test "notenDeltas 1 tenpai" {
    const d = notenDeltas(.{ true, false, false, false });
    try std.testing.expectEqual(@as(i32, 3000), d[0]);
    try std.testing.expectEqual(@as(i32, -1000), d[1]);
    try std.testing.expectEqual(@as(i32, -1000), d[2]);
    try std.testing.expectEqual(@as(i32, -1000), d[3]);
}

test "notenDeltas 2 tenpai" {
    const d = notenDeltas(.{ true, true, false, false });
    try std.testing.expectEqual(@as(i32, 1500), d[0]);
    try std.testing.expectEqual(@as(i32, 1500), d[1]);
    try std.testing.expectEqual(@as(i32, -1500), d[2]);
    try std.testing.expectEqual(@as(i32, -1500), d[3]);
}
