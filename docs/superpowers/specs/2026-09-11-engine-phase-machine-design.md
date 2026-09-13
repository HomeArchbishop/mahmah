# 引擎局内状态机设计

**Date:** 2026-09-11  
**Status:** approved for implementation

## 决策

- 局终：先写 `end_kyoku`，再在**同一** `out` 内调用 `initializeRound` 开下一局（或按规则写 `end_game` 且不再开局）。
- `turn`：摸打指针；`wait_response` 时仍为切牌/加杠者。
- 命名：方法 camelCase，字段 snake_case；无 lodash 前缀。
- Desk 对外仍只认 `onStartGame` / `legalActions` / `defaultAction` / `apply` / `chombo*`。

## 相位

`idle` | `wait_act` | `wait_response`

- 吃碰后仍为 `wait_act`，`drawn == null`（必须打牌）。
- 和了/流局为瞬时结算，不长期占 `finished`。

## 主路径（与流程图同构）

`wait_act` → 匹配动作 →（打牌）`resolveDiscard` → 有应手则 `wait_response`，否则 `acceptRiichi` → 中途流局检查 → `dealNext` → `wait_act`。

`wait_response` → Ron / Call / Pass → 和了、流局、`resolveKan`、吃碰回 `wait_act`、或全过走 `acceptRiichi` 路径。

## Desk

按 engine 给出的「需要出着的座位」挂 request（可多人）；不再写死只问 `turn`。
