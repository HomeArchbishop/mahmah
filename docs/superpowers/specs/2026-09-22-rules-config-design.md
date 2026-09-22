# 细则规则配置（Rules）设计

**Date:** 2026-09-22  
**Status:** implemented（一期 1–5 已接线；6 `length` 占位）

## 决策（已拍板）

- **形态：** 扁平 `Rules` struct + named presets（`default` / `riichienv`）。不搞策略函数指针、不搞运行时 JSON/lobby 选规则。
- **生命周期：** 开局写入 `Kyoku`（`*const Rules` 或值拷贝），局中只读。
- **注入：** **仅代码配置**。`main`/Desk 用 `Rules.default()`；`mjai_diff` 用 `Rules.riichienv()`。编译进对应二进制后行为固定，无协议字段、无组桌选项。
- **一期范围：** 下列分组 **1–5 落地**；分组 **6 只占位**（可含 `length` 字段，暂不接线半庄逻辑分支）。
- **切上：** `default` **开**；`riichienv` **关**（对齐 seed 173 差分）。

## 非目标（一期）

- lobby / room 协议暴露 rules
- 热切换、局中改规则
- 终局细则（返点、流局听牌连庄变体、和了止め等）完整实现

## 结构

```text
src/core/rules.zig
  Rules
  Rules.default()      // mahmah 产品默认（含切上）
  Rules.riichienv()    // 差分 / mjai_diff

Kyoku.rules: Rules     // 或 *const Rules，实现时二选一：优先值拷贝免生命周期纠缠
Desk / engine 入口只读 ky.rules
```

各政策点：`if (ky.rules.kuikae)` / `basicPoints(..., ky.rules.kiriage_mangan)` 等；禁止再散落魔法布尔。

## 字段（一期）

### 1. 鸣牌 / 着法

| 字段 | 类型 | default | riichienv | 接线 |
|------|------|---------|-----------|------|
| `kuikae` | bool | true | true | `kuikae.zig` / `legal` / `discard` |
| `kuikae_suji` | bool | true | true | `kuikae.setChi`：false 时只禁现物 |
| `riichi_ankan_must_preserve_wait` | bool | true | true | `legal.ankanPreservesWaits` / `kan.applyAnkan` |

### 2. 得点

| 字段 | 类型 | default | riichienv | 接线 |
|------|------|---------|-----------|------|
| `kiriage_mangan` | bool | true | false | `points.basicPoints` |

符进十等两边一致的算法，一期不开关。

### 3. 役 / 宝牌

| 字段 | 类型 | default | riichienv | 接线 |
|------|------|---------|-----------|------|
| `kuitan` | bool | true | true | `yaku.danyao`：false 时要求门清 |
| `aka` | bool | true | true | `wall` 组牌；false 时无赤（全黑 5） |
| `ura` | bool | true | true | `yaku.uradora` |
| `ippatsu` | bool | true | true | `yaku.ippatsu` |
| `suuankou_tanki_double` | bool | true | false | `yaku.suuankootanki`：升级形双/单倍 |
| `kokushi_13_double` | bool | true | false | `yakuKokushiJuusanmen` |
| `junsei_chuuren_double` | bool | true | false | `yaku.junseichuurenpoutou` |
| `daisuushii_double` | bool | true | false | `yaku.daisuushii` |

### 4. 杠 / 指示牌时机

| 字段 | 类型 | default | riichienv | 接线 |
|------|------|---------|-----------|------|
| `minkan_dora_timing` | enum { immediate, after_discard } | after_discard | after_discard | `kan.resolveKan` 明杠/加杠 |
| `ankan_dora_timing` | enum { immediate, after_discard } | immediate | immediate | 暗杠 |
| `flush_pending_dora_on_renkan` | bool | true | true | `resolveKan` 开头 flush |

### 5. 途中流局

| 字段 | 类型 | default | riichienv | 接线 |
|------|------|---------|-----------|------|
| `abort_kyushu` | bool | true | true | `legal` / `ryuukyoku` |
| `abort_sufuurenta` | bool | true | true | `discard` 中途流局检查 |
| `abort_suukansansen` | bool | true | true | 同上 |
| `abort_suucha_riichi` | bool | true | true | 同上 |
| `abort_sanchaho` | bool | true | true | `response` 三家和 |

### 6. 占位（一期不接线业务）

| 字段 | 类型 | default | 说明 |
|------|------|---------|------|
| `length` | enum { tonpuu, hanchan } | hanchan | 仅存字段；`round.zig` 仍用现逻辑 |

## Preset

```zig
// 伪代码
pub fn default() Rules { ... kiriage_mangan = true, ... }
pub fn riichienv() Rules { ... kiriage_mangan = false, ... } // 其余与 default 相同，除非实测差分还需改
```

`mjai_diff` 在构造/reset `Kyoku` 时设 `rules = Rules.riichienv()`。  
产品 `Desk.init` / `beginGame` 路径设 `Rules.default()`。

## 测试与差分

- 单测：`kiriage_mangan` true/false 各测 4 翻 30 符亲荣点数。
- `zig build mjai-diff` + `uv run python -m diff`：期望 seed 173 等切上差消失（在 riichienv preset 下）。
- 默认 preset 行为与改前产品意图一致（切上仍开）。

## 实现顺序

1. 加 `rules.zig`、挂 `Kyoku`、两处入口注入；默认值使现有测试全绿（行为不变）。
2. 接线 `kiriage_mangan`、`kuikae`（+ suji）、`kuitan`、`aka`、`ura`、`ippatsu`。
3. 接线杠翻时机与连杠 flush。
4. 接线途中流局五开关。
5. 占位 `length`；README / `docs/engine.md` 补一行 Rules 说明。

## 验收

- [ ] `Rules.default()` 与改前产品规则一致（含切上）。
- [ ] `Rules.riichienv()` 下 diff 不再因切上与 oracle 得点分歧。
- [ ] 关 `kuikae` 时合法着可切食替牌；关 `aka` 时墙无赤且役不算赤。
- [ ] 无 lobby/协议改规则路径。
