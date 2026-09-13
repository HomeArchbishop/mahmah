# Game / Kyoku 状态机 + Room 齐人开局 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「一盘 Game / 多局 Kyoku / 局内决策」状态机理清，Room 在四方都有 Sender（真人连上或 bot 已挂上）后分两步 `beginGame` → `beginKyoku`；bot 由 Room 创建并作为 `Sender` 接入现有 emit。

**Architecture:** Desk 持有 Game 相位；engine `State` 持有 Kyoku/局内相位。Room 管连接表；`init` 时对 bot 座位建 bot 实例并 `connections.put`，对齐真人 `onConnect`。齐四人后调用 `beginGame`（不发牌）再 `beginKyoku`（发牌+首摸）。bot 模块只被 room import；回包经 `Room.onMessage`，emit 末尾 `bot.drive` 消化队列以免重入。

**Tech Stack:** Zig 0.16；现有 `Desk` / `engine` / `Room` / `Sender` / `ids.isBot`。

## Global Constraints

- Room 可依赖 bot；**lobby / core 不 import bot**。
- Room 下行只认 `Sender`；bot 与真人同一 `connections`。
- 开局两步：`beginGame` 与 `beginKyoku` 分离；禁止再用含糊的 `Desk.start()` 包办。
- 注释只说明职责，禁止「不是…而是…」句式。
- 第一期局内仍以摸打骨架为主；鸣牌并行 pending 不在本计划。

---

## 综合后的目标时序

```text
openGame / Room.init(players)
  ├─ Desk.init（Game=AwaitingPlayers，未 beginKyoku）
  ├─ 对每个 isBot(players[i])：创建 bot.Sender，connections.put，视作已连接
  └─ 不 beginGame / 不 beginKyoku

真人 onConnect
  ├─ connections.put + start_game{id}
  └─ 若 connections 覆盖四座 → beginGame → beginKyoku → emit

bot（已在 init 挂上）
  └─ beginKyoku 的下行经 Sender.send 入队；emit/attach 结束后 bot.drive → onMessage
```

四人全 bot：`init` 结束时已齐 → `init` 末尾同样走 `tryStartIfReady()`。

---

## File map

| 文件 | 职责 |
|---|---|
| `src/core/state.zig` | 增加 `KyokuPhase`（或扩展 `Phase`）；牌山仅在局进行中有效 |
| `src/core/desk.zig` | `GamePhase`；`beginGame` / `beginKyoku`；删 `start`；`note` 连接由 Room 触发齐人逻辑 |
| `src/core/engine.zig` | `beginKyoku` 保持；可选 `afterKyoku` 桩（本计划可只留接口注释） |
| `src/core/root.zig` | 导出新符号（若需要） |
| `src/bot/root.zig` 等 | bot 实例、`Sender`、入队、`drive(room)` |
| `src/room/room.zig` | 不 init 时 start；bot 挂接；齐人两步开局；emit 后 drive |
| `src/net/player_conn.zig` | `onConnect`/`onMessage` 后 `room.afterTraffic()` 或等价 drive |
| `docs/engine.md` | 同步状态机与 API |
| Desk / Room 测试 | 齐人开局、bot 座位能自动打一手 |

---

## Task 1: Desk Game 相位 + 两步 API

**Files:** `src/core/desk.zig`, `src/core/state.zig`, `src/core/root.zig`, desk tests

- [ ] 在 `desk.zig` 增加：

```zig
pub const GamePhase = enum {
    awaiting_players,
    playing,
    finished,
};
```

- [ ] 删除 `started` / `start()`。
- [ ] 增加：

```zig
/// 盘开始：AwaitingPlayers → Playing。不发牌、不写 start_kyoku。
pub fn beginGame(self: *Desk) !Outcome

/// 开一局：须已 Playing；调用 engine.beginKyoku，再 pushRequest。
pub fn beginKyoku(self: *Desk) !Outcome
```

- [ ] `beginGame`：若非 `awaiting_players` 则 error；清事件缓冲；可推可选盘级事件（第一期可 Outcome 为空事件或仅内部切相位）；相位 → `playing`。
- [ ] `beginKyoku`：若非 `playing` 或 kyoku 已在进行则 error；`engine.beginKyoku` + `pushRequest`。
- [ ] `state.Phase`：保留局内 `wait_dahai` / `finished`；局未开时可用 `kyoku_idle` 或 `phase` 仅在 beginKyoku 后进入 `wait_dahai`。
- [ ] 改 desk 单测：先 `beginGame` 再 `beginKyoku`，再 `onAction`。
- [ ] `zig build test` 通过。

---

## Task 2: Room 齐人后再两步开局

**Files:** `src/room/room.zig`, `docs/engine.md`

- [ ] `Room.init`：只 `Desk.init` + 空 connections；**不**调用开局；catch_up 初始为空。
- [ ] 抽取 `attachSender(player_id, sender) !void`：`connections.put`；若 Game 仍在 awaiting，只发 `start_game{id}`（不要冲刷不存在的开局 catch_up）。
- [ ] `onConnect` 改为调 `attachSender`；然后 `tryBeginWhenReady()`.
- [ ] `tryBeginWhenReady`：

```text
若 desk.game_phase != awaiting_players → return
若 connections 未覆盖 players[0..4] → return
outcome1 = desk.beginGame()
emit(outcome1)           // 可能为空
outcome2 = desk.beginKyoku()
recordCatchUp(outcome2)  // 供极晚连接；齐人场景已在线为主
emit(outcome2)
```

- [ ] 真人晚于齐人之后才连（不应发生若齐人=4 才开；若未来观战另议）：`attachSender` 在 `playing` 时发 `start_game` + 现有 catch_up。
- [ ] 更新 `docs/engine.md`：删除「openGame 后立刻 start」；写明 Game/Kyoku 两步与齐人条件。
- [ ] `zig build test`；手测或单测 Room 逻辑尽量覆盖「未齐人不 beginKyoku」。

---

## Task 3: bot 模块骨架（Room 依赖 bot）

**Files:** create `src/bot/agent.zig`, `src/bot/root.zig`；改 `src/room/room.zig`, `build.zig`（若需 module）

- [ ] `BotAgent`：持有 `player_id`、入站队列或「pending request」；实现 `Sender`（`send` 只解析/入队，不同步回包）。
- [ ] stub 策略：见 `request_action` → 选 `possible_actions` 第一项（优先 `dahai`）→ 组 JSON。
- [ ] `pub fn drive(room: *Room) !void`：对房间内 bot 刷新队列，对每个待回包调用 `room.onMessage(bot_id, 0, bytes)`（conn_id 可用 0）。
- [ ] 重入：`onMessage`→`emit`→`bot.send` 只入队；`emit` 末尾与 `tryBeginWhenReady` 末尾调用 `bot.drive(self)`。
- [ ] `Room` 增加 `bots:` 容器（如 `AutoHashMap(PlayerId, *BotAgent)` 或定长可选数组）；`deinit` 释放。
- [ ] `Room.init` 末尾：对 `ids.isBot(players[i])` 建 `BotAgent`，`attachSender`，再 `tryBeginWhenReady()`（全 bot 局可立刻开局）。
- [ ] **lobby 不 import bot**；无需改 lobby 占座逻辑。
- [ ] `zig build test`；增加测试或脚本路径：1 真人 id + 3 bot id 的 Desk/Room 在 attach 齐后能 `beginKyoku` 且 bot 能回应至少一次 `request_action`。

---

## Task 4: net 路径补 drive

**Files:** `src/net/player_conn.zig`, `src/room/room.zig`

- [ ] `Room.afterWire() !void`：内部 `bot.drive(self)`（无 bot 则为空操作）。
- [ ] `PlayerConn.afterInit` / `clientMessage` 在成功调 room 之后调用 `room.afterWire()`。
- [ ] 确认 `onMessage` 内 emit 已 drive 时，`afterWire` 可做成幂等（多次 drive 安全）。

---

## Task 5: 文档与验收

**Files:** `docs/engine.md`, optional `docs/superpowers/specs/2026-09-09-game-kyoku-bot-design.md` 短摘要

- [ ] 文档写清：

```text
Game: AwaitingPlayers → Playing → Finished
Kyoku: （在 Playing 下）Idle → InProgress → Ended
齐人（四 Sender）→ beginGame → beginKyoku
bot: Room.init 挂 Sender；emit 链路不变
```

- [ ] 验收清单：
  - 未齐人：无 `start_kyoku`。
  - 第四人连上（或第四 bot attach）：出现 `start_kyoku` + `request_action`。
  - bot 座位能自动打牌，真人 UI 能看到他家牌背与河。
  - core / lobby 无 `@import("bot")`。

---

## 刻意不做（本计划外）

- 外置 bot 进程 / ranked WS。
- 局中断线重连完整协议。
- 多局连庄 / `beginKyoku` 第二次（可留 API，规则后补）。
- 完整 timeout 挂表（可后续接 `onTimeout`）。

---

## 执行顺序

1 → 2 → 3 → 4 → 5  

先保证无 bot 时「齐人两步开局」正确，再挂 bot，避免两团逻辑缠在一起调试。
