const types = @import("types.zig");
const Pai = types.Pai;
const CAPACITY = types.CAPACITY;
const TEHAI_LEN = types.TEHAI_LEN;

pub const WALL_LEN: usize = 136;
const DEAD_WALL_LEN: usize = 14;
/// 开局活山长度（常量切法）；运行时终点用 yama.live_end。
pub const LIVE_WALL_LEN: usize = WALL_LEN - DEAD_WALL_LEN;
pub const HAND_CAP: usize = 14;
pub const DORA_MARKER_CAP: usize = 5;
pub const FUURO_CAP: usize = 4;

/// 牌山真相：tiles + 绝对游标。
/// 不变量：0 ≤ live_i ≤ live_end ≤ dora_i ≤ rinshan_i+1 ≤ WALL_LEN
pub const Yama = struct {
    tiles: [WALL_LEN]Pai = undefined,
    /// 下一张活山摸牌下标
    live_i: u8 = 0,
    /// 活山右开终点（开局 = LIVE_WALL_LEN；每次岭上后 --）
    live_end: u8 = @intCast(LIVE_WALL_LEN),
    /// 下一张岭上下标（开局 = WALL_LEN-1；每摸一次 --）
    rinshan_i: u8 = @intCast(WALL_LEN - 1),
    /// 下一张宝牌指示下标（开局 = LIVE_WALL_LEN；每翻一次 ++）
    dora_i: u8 = @intCast(LIVE_WALL_LEN),
    dora_markers: [DORA_MARKER_CAP]Pai = undefined,
    dora_markers_len: u8 = 0,

    pub fn resetCursors(self: *Yama) void {
        self.live_i = 0;
        self.live_end = @intCast(LIVE_WALL_LEN);
        self.rinshan_i = @intCast(WALL_LEN - 1);
        self.dora_i = @intCast(LIVE_WALL_LEN);
        self.dora_markers_len = 0;
    }

    fn doraMarkersSlice(self: *const Yama) []const Pai {
        return self.dora_markers[0..self.dora_markers_len];
    }

    /// 活山是否还有牌可摸（空则河海底，不可杠）。
    pub fn hasLive(self: *const Yama) bool {
        return self.live_i < self.live_end;
    }
};

/// 局内相位（与引擎状态机一致）。
pub const Phase = enum {
    /// 未开局，或整盘已终
    idle,
    /// 行动座须出着（摸打，或吃碰后必须打牌）
    wait_act,
    /// 鸣牌 / 荣和 / 抢杠要约
    wait_response,
};

pub const FuuroKind = enum { chi, pon, daiminkan, ankan, kakan };

pub const Fuuro = struct {
    kind: FuuroKind,
    /// 吃碰杠所含牌（含叫牌）
    tiles: [4]Pai = undefined,
    tile_len: u8 = 0,
    /// 被鸣者；暗杠为 null
    from: ?types.Seat = null,
};

pub const Player = struct {
    tehai: [HAND_CAP]Pai = undefined,
    tehai_len: u8 = 0,
    river: [24]Pai = undefined,
    river_len: u8 = 0,
    fuuro: [FUURO_CAP]Fuuro = undefined,
    fuuro_len: u8 = 0,
    riichi: bool = false,
    ippatsu: bool = false,
};

/// 一局牌桌真相（仅 core 内部；由 engine 读写）。
pub const Kyoku = struct {
    phase: Phase = .idle,

    /// 摸打指针；wait_response 时仍为切牌（或加杠）者
    turn: types.Seat = 0,
    oya: types.Seat = 0,
    bakaze: Pai = "E",
    kyoku: u8 = 1,
    honba: u8 = 0,
    kyotaku: u8 = 0,

    shuffle_seed: u64 = 1,
    yama: Yama = .{},

    players: [CAPACITY]Player = .{ .{}, .{}, .{}, .{} },
    drawn: ?Pai = null,

    scores: [CAPACITY]i32 = .{ 25000, 25000, 25000, 25000 },

    is_first_turn: bool = true,
    is_rinshan: bool = false,
    /// 本巡已有人鸣过则清首巡
    claims_this_kyoku: u8 = 0,
    kan_count: u8 = 0,
    /// 四风连打：各家首打（仅首巡记录）
    first_discards: [CAPACITY]?Pai = .{ null, null, null, null },

    /// 抢杠窗进行中的加杠者；打牌应手时为 null
    pending_kan: ?types.Seat = null,
    /// 切完未承认的立直座
    pending_riichi: ?types.Seat = null,
    /// 明杠（大明/加）待打牌后翻的指示牌张数
    pending_minkan_dora: u8 = 0,

    /// wait_response：最后切出的牌 / 加杠牌
    last_discard: ?Pai = null,
    last_discarder: types.Seat = 0,
    response_open: [CAPACITY]bool = .{ false, false, false, false },
    response_done: [CAPACITY]bool = .{ false, false, false, false },
    response_choice: [CAPACITY]?types.Action = .{ null, null, null, null },

    pub fn init() Kyoku {
        return .{};
    }

    pub fn handSlice(self: *const Kyoku, seat: types.Seat) []const Pai {
        const p = &self.players[seat];
        return p.tehai[0..p.tehai_len];
    }

    pub fn doraMarkersSlice(self: *const Kyoku) []const Pai {
        return self.yama.doraMarkersSlice();
    }

    pub fn tehaisForEvent(self: *const Kyoku) types.Tehais {
        var out: types.Tehais = undefined;
        for (0..CAPACITY) |i| {
            const p = &self.players[i];
            const skip_last = self.drawn != null and i == self.turn;
            const take: usize = if (skip_last)
                @min(TEHAI_LEN, if (p.tehai_len > 0) p.tehai_len - 1 else 0)
            else
                @min(TEHAI_LEN, p.tehai_len);
            var n: usize = 0;
            while (n < take) : (n += 1) {
                out[i][n] = p.tehai[n];
            }
            while (n < TEHAI_LEN) : (n += 1) {
                out[i][n] = "?";
            }
        }
        return out;
    }
};
