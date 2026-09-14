const types = @import("../../types.zig");
const Seat = types.Seat;
const CAPACITY = types.CAPACITY;

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

/// 简化得点：荣和固定 2000+300*本场；自摸亲 2000/子各 1000，子家自摸亲 2000 子 1000。
pub fn applyHoraScores(
    scores: *[CAPACITY]i32,
    winners: []const Seat,
    from: Seat,
    oya: Seat,
    honba: u8,
    kyotaku: u8,
    tsumo: bool,
) void {
    const honba_bonus: i32 = 300 * @as(i32, honba);
    const stick: i32 = 1000 * @as(i32, kyotaku);

    if (tsumo) {
        const w = winners[0];
        if (w == oya) {
            var i: u8 = 0;
            while (i < CAPACITY) : (i += 1) {
                if (i == w) continue;
                scores[i] -= 2000 + honba_bonus;
                scores[w] += 2000 + honba_bonus;
            }
        } else {
            var i: u8 = 0;
            while (i < CAPACITY) : (i += 1) {
                if (i == w) continue;
                const pay: i32 = if (i == oya) 2000 + honba_bonus else 1000 + honba_bonus;
                scores[i] -= pay;
                scores[w] += pay;
            }
        }
        scores[w] += stick;
        return;
    }

    // 荣和（可多家）
    for (winners) |w| {
        const base: i32 = 2000 + honba_bonus;
        scores[from] -= base;
        scores[w] += base;
    }
    if (winners.len > 0) {
        scores[winners[0]] += stick;
    }
}
