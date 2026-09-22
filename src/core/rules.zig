//! 细则规则：开局写入 Kyoku，局中只读。仅代码 preset，无协议配置。
pub const Rules = struct {
    pub const DoraTiming = enum {
        immediate,
        after_discard,
    };

    pub const Length = enum {
        tonpuu,
        hanchan,
    };

    kuikae: bool = true,
    kuikae_suji: bool = true,
    riichi_ankan_must_preserve_wait: bool = true,

    kiriage_mangan: bool = true,

    kuitan: bool = true,
    aka: bool = true,
    ura: bool = true,
    ippatsu: bool = true,

    minkan_dora_timing: DoraTiming = .after_discard,
    ankan_dora_timing: DoraTiming = .immediate,
    flush_pending_dora_on_renkan: bool = true,

    abort_kyushu: bool = true,
    abort_sufuurenta: bool = true,
    abort_suukansansen: bool = true,
    abort_suucha_riichi: bool = true,
    abort_sanchaho: bool = true,

    /// 双倍役满升级形（false 时按单倍，对齐 riichienv / 天凤系）。
    suuankou_tanki_double: bool = true,
    kokushi_13_double: bool = true,
    junsei_chuuren_double: bool = true,
    daisuushii_double: bool = true,

    /// 占位：一期不接线半庄分支。
    length: Length = .hanchan,

    /// 产品默认（含切上满贯、双倍役满升级）。
    pub fn default() Rules {
        return .{};
    }

    /// 对齐 riichienv / mjai_diff（关切上；升级形役满单倍）。
    pub fn riichienv() Rules {
        var r: Rules = .{};
        r.kiriage_mangan = false;
        r.suuankou_tanki_double = false;
        r.kokushi_13_double = false;
        r.junsei_chuuren_double = false;
        r.daisuushii_double = false;
        return r;
    }
};
