const std = @import("std");

/// 座位 0..3
pub const Seat = u2;
pub const CAPACITY: usize = 4;
pub const TEHAI_LEN: usize = 13;
/// 表/里宝指示牌上限（开局 1，杠后最多再翻 4）
pub const DORA_MARKER_CAP: usize = 5;

/// MJAI 牌面字符串，如 "1m" / "E" / "?"。只指向字面量或长期存活缓冲。
pub const Pai = []const u8;

/// 场风
pub const Kaze = Pai;

/// 四人各 13 张起手（可见性由 room 按观察者遮罩）
pub const Tehais = [CAPACITY][TEHAI_LEN]Pai;

/// 玩家意图（上行 / possible_actions）。不含 JSON、不含 actor（座位由 Desk 从 player_id 绑定）。
pub const Action = union(enum) {
    dahai: struct { pai: Pai, tsumogiri: bool = false },
    chi: struct { pai: Pai, consumed: [2]Pai },
    pon: struct { pai: Pai, consumed: [2]Pai },
    daiminkan: struct { pai: Pai, consumed: [3]Pai },
    ankan: struct { consumed: [4]Pai },
    kakan: struct { pai: Pai, consumed: [3]Pai },
    reach,
    /// target/pai 在荣和回复时填写；自摸可省略（由引擎根据状态判定）
    hora: struct { target: ?Seat = null, pai: ?Pai = null },
    /// 九种九牌等主动流局申报
    ryukyoku,
    none,
};

/// 一次 request 被处理后的结果状态（对应 action_ack.status）
pub const ResolveStatus = enum {
    accepted,
    rejected,
    unparseable,
    stale,
    defaulted,
};

/// 时限：grace 免费段 + bank 局内银行；deadline = grace + bank
pub const TimeBudget = struct {
    grace_ms: u32 = 3000,
    bank_ms: u32 = 15000,
    deadline_ms: u32 = 18000,
};

/// 「请你出招」——Room 据此发 request_action 并挂定时器
pub const ActionRequest = struct {
    seat: Seat,
    request_id: u32,
    time: TimeBudget = .{},
    /// 指向 Desk 内部缓冲，仅在下一次 Desk 调用前有效
    legal_actions: []const Action,
    /// 可选观测（通常由 room 附加；core 现为 null）
    observation: ?[]const u8 = null,
};

/// 「你的回复已处理」——Room 编成 action_ack
pub const ActionResolved = struct {
    request_id: u32,
    status: ResolveStatus,
    /// defaulted（及需要回声时）的实际着法 → JSON `action`
    action: ?Action = null,
    /// rejected 时的非法着 → JSON `attempted`
    attempted: ?Action = null,
    /// rejected / unparseable
    reason: ?[]const u8 = null,
    /// rejected 时当时合法 type 名
    legal_types: ?[]const []const u8 = null,
    /// 墙钟（room 可覆盖；编码时始终写出）
    elapsed_ms: u32 = 0,
    bank_consumed_ms: u32 = 0,
    bank_ms: u32 = 15000,
};

/// 已发生事实（下行）。Room 只消费 Event，不碰 Kyoku。
/// 遮罩（他人手牌 / 摸牌 "?"）在 room 编码时做。
pub const Event = union(enum) {
    /// wire `start_game` 由 Room 按连接单独发；core 不产出此变体。
    start_game,

    start_kyoku: struct {
        bakaze: Kaze,
        /// 开局表宝指示（wire 为单张字符串）
        dora_markers: []const Pai,
        kyoku: u8,
        honba: u8,
        kyotaku: u8,
        oya: Seat,
        scores: [CAPACITY]i32,
        tehais: Tehais,
    },

    tsumo: struct { actor: Seat, pai: Pai },
    dahai: struct { actor: Seat, pai: Pai, tsumogiri: bool },

    chi: struct { actor: Seat, target: Seat, pai: Pai, consumed: [2]Pai },
    pon: struct { actor: Seat, target: Seat, pai: Pai, consumed: [2]Pai },
    daiminkan: struct { actor: Seat, target: Seat, pai: Pai, consumed: [3]Pai },
    ankan: struct { actor: Seat, pai: Pai, consumed: [4]Pai },
    kakan: struct { actor: Seat, pai: Pai, consumed: [3]Pai },

    /// 杠后新翻开的一张宝牌指示牌
    dora: struct { dora_marker: Pai },

    reach: struct { actor: Seat },
    reach_accepted: struct { actor: Seat },

    hora: struct {
        actor: Seat,
        /// 自摸时 target == actor
        target: Seat,
        pai: Pai,
        deltas: [CAPACITY]i32,
        ura_markers: [DORA_MARKER_CAP]Pai = undefined,
        ura_markers_len: u8 = 0,
        tsumo: bool,
    },

    ryukyoku: struct {
        reason: []const u8,
        deltas: [CAPACITY]i32 = .{ 0, 0, 0, 0 },
        tehais: ?Tehais = null,
    },

    end_kyoku,
    end_game: struct { scores: [CAPACITY]i32 },

    action_requested: ActionRequest,
    action_resolved: ActionResolved,
};

/// Desk 入口的统一返回：本拍事件列表（切片指向 Desk 内部缓冲）。
pub const Outcome = struct {
    events: []const Event,
};

pub const ApplyError = error{
    IllegalAction,
};

pub fn paiEql(a: Pai, b: Pai) bool {
    return std.mem.eql(u8, a, b);
}

pub fn actionTypeName(action: Action) []const u8 {
    return switch (action) {
        .dahai => "dahai",
        .chi => "chi",
        .pon => "pon",
        .daiminkan => "daiminkan",
        .ankan => "ankan",
        .kakan => "kakan",
        .reach => "reach",
        .hora => "hora",
        .ryukyoku => "ryukyoku",
        .none => "none",
    };
}

fn consumedEql(comptime N: usize, a: [N]Pai, b: [N]Pai) bool {
    for (a, b) |x, y| {
        if (!paiEql(x, y)) return false;
    }
    return true;
}

pub fn actionEql(a: Action, b: Action) bool {
    return switch (a) {
        .none => b == .none,
        .reach => b == .reach,
        .ryukyoku => b == .ryukyoku,
        .dahai => |da| switch (b) {
            .dahai => |db| da.tsumogiri == db.tsumogiri and paiEql(da.pai, db.pai),
            else => false,
        },
        .chi => |da| switch (b) {
            .chi => |db| paiEql(da.pai, db.pai) and consumedEql(2, da.consumed, db.consumed),
            else => false,
        },
        .pon => |da| switch (b) {
            .pon => |db| paiEql(da.pai, db.pai) and consumedEql(2, da.consumed, db.consumed),
            else => false,
        },
        .daiminkan => |da| switch (b) {
            .daiminkan => |db| paiEql(da.pai, db.pai) and consumedEql(3, da.consumed, db.consumed),
            else => false,
        },
        .ankan => |da| switch (b) {
            .ankan => |db| consumedEql(4, da.consumed, db.consumed),
            else => false,
        },
        .kakan => |da| switch (b) {
            .kakan => |db| paiEql(da.pai, db.pai) and consumedEql(3, da.consumed, db.consumed),
            else => false,
        },
        .hora => |da| switch (b) {
            .hora => |db| blk: {
                const t_ok = if (da.target) |t|
                    db.target != null and t == db.target.?
                else
                    db.target == null;
                if (!t_ok) break :blk false;
                break :blk if (da.pai) |p|
                    db.pai != null and paiEql(p, db.pai.?)
                else
                    db.pai == null;
            },
            else => false,
        },
    };
}
