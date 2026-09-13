# 对局引擎设计（room 适配器 + 一体引擎）

## 目标

- **好测**：引擎无 socket、无 JSON、无时钟副作用；单测只喂 Action、看 Event。
- **接口一一明确**：跨边界只有少量命名入口，禁止「大 Listener / 暴露 Kyoku」。
- **人类可维护**：目录少、依赖单向、词汇表短。

## 已拍板

1. **齐人后开盘**：`openGame` 只建 `Room`/`Desk`；四方都有 `Sender` 后 Room 只调 `Desk.beginGame`。局循环由 engine 在 `onStartGame` 后自行推进；`end_game` 时 Desk 置整盘 finished。
2. **Game / Kyoku 分离**：`Desk.game_phase` 管整盘（`finished` = 多局后整盘结束）；`Kyoku` / `KyokuPhase` 管局内；禁止用含糊的 `Desk.start()` 包办。
3. **bot 只挂在 room**：`room → bot`；lobby / core 不 import bot。bot 实现 `Sender`，与真人同一 `connections`；回包经 `Room.onMessage`，`deliverOutcome` 末尾 `flushBotReplies`。
4. **chombo 策略 A**：`apply` 失败 → `Desk` 合成 `action_resolved{rejected|unparseable}`，必要时再追加流局/罚符事件（与规则内正常流局可区分）。

## 模块与依赖

```text
lobby/     组队 Table（等候桌）
   ↓ openGame(players)
room/      通信适配：WS、MJAI、遮罩、定时器、ack；挂接 bot Sender
   ↓ Desk 入口
core/      一体引擎：状态 + 规则 + 牌桌编排（可单测）
bot/       进程内 stub（仅 room import）
```

```text
lobby → room（仅 openGame / 名单）
room → core
room → bot
core / lobby 不 import bot
core 不 import room / lobby / net
```

### 命名（避免宽泛词）

| 名字 | 层级 | 含义 |
|---|---|---|
| `Table` | lobby | 等候组队桌 |
| `Room` | room | 对局 WS 房间 / 连接与协议 |
| `Desk` | core | 一盘对局会话（`GamePhase` + pending + Outcome） |
| `Engine` | core/engine | 局状态机：`onStartGame` / `apply` / 局终连庄（不对 room 暴露） |
| `BotAgent` | bot | 进程内 `Sender`；入队回包由 Room 取出 |

不用 `game/`、`Session`：前者易与「一局游戏 / room」混称；后者过泛（HTTP session、登录态都会叫它）。

`core` 内部可分文件，**不**再拆独立 `rules` 包；对外只暴露 `Desk`。

建议文件（实现阶段）：

| 路径 | 职责 |
|---|---|
| `core/types.zig` | `Seat`、`Action`、`Event`、`Outcome`、错误集 |
| `core/kyoku.zig` | 一局牌桌真相 `Kyoku`（仅 core 内部） |
| `core/engine/root.zig` | Desk→engine：`onStartGame` / `legalActions` / `apply` / `chombo` |
| `core/engine/{apply,begin,wall,hand,score}.zig` | 着法子流程与工具 |
| `core/desk.zig` | `Desk`：`GamePhase`、座位映射、`request_id`、pending、入口 |
| `room/protocol.zig` | MJAI ↔ `Action`/`Event` |
| `room/room.zig` | 连接表 + bot 挂接 + 齐人两步开局 + 调 `Desk` |
| `bot/agent.zig` | stub bot：`Sender` + 待回包队列 |

## 词汇（全局只认这些）

### `Action`（上行意图）

与 MJAI bot→server / `possible_actions` 对齐；**不含** JSON、`observation`、`actor`（座位由 `Desk` 从 `player_id` 绑定）。

| 变体 | 字段 | 说明 |
|---|---|---|
| `dahai` | `pai`, `tsumogiri` | 出牌；摸切时 `tsumogiri=true` |
| `chi` | `pai`, `consumed[2]` | 吃；`pai` 为他家切牌 |
| `pon` | `pai`, `consumed[2]` | 碰 |
| `daiminkan` | `pai`, `consumed[3]` | 大明杠 |
| `ankan` | `consumed[4]` | 暗杠 |
| `kakan` | `pai`, `consumed[1]` | 加杠 |
| `reach` | （无） | 立直宣言；切牌另发 `dahai` |
| `hora` | `target?`, `pai?` | 和；荣和填 target/pai，自摸可省略 |
| `ryukyoku` | （无） | 九种九牌等主动流局 |
| `none` | （无） | 鸣牌机会「过」 |

### `Event`（下行已发生事实）

| 变体 | 字段 | wire `type` |
|---|---|---|
| `start_game` | `players[4]` | `start_game`（room 另按座位发 `id`） |
| `start_kyoku` | `bakaze`, `dora_markers`, `kyoku`, `honba`, `kyotaku`, `oya`, `tehais[4][13]` | 同名；wire `dora_marker` 为数组 |
| `tsumo` | `actor`, `pai` | 同名（他人 `pai` 由 room 遮 `"?"`） |
| `dahai` | `actor`, `pai`, `tsumogiri` | 同名 |
| `chi` / `pon` / `daiminkan` | `actor`, `target`, `pai`, `consumed` | 同名 |
| `ankan` | `actor`, `consumed[4]` | 同名 |
| `kakan` | `actor`, `pai`, `consumed[1]` | 同名 |
| `dora` | `dora_marker` | 杠后宝牌 |
| `reach` | `actor` | 同名 |
| `reach_accepted` | `actor` | 同名（可选） |
| `hora` | `actor`, `target`, `pai` | 同名；自摸时 `target==actor` |
| `ryukyoku` | `reason`, `deltas[4]`, `tehais?` | 同名 |
| `end_kyoku` | （无） | 同名 |
| `end_game` | `scores[4]` | 同名 |
| `action_requested` | `seat`, `request_id`, `time`, `legal_actions`, `observation?` | wire=`request_action` |
| `action_resolved` | `request_id`, `status`, `action?`（仅 defaulted）, `attempted?`（rejected）, `reason?`, `legal_types?`, `elapsed_ms`, `bank_consumed_ms`, `bank_ms` | wire=`action_ack` |

约定：

- **`action_requested` 是普通 `Event` 变体**，下行只有 `[]Event`。
- 牌面真相在 Event 里；**遮罩在 room 编码时做**，core 不发半遮罩状态。
- `Pai` 为静态字符串切片（`1m`…`9s` / `E`…`C` / `5mr`… / `?`）。

### `Outcome`

```text
Outcome { events: []Event }
```

Desk 各入口统一返回它（或 `!Outcome`）。

### 谁看得见 `Kyoku`

只有 `core` 内部。对外测试断言 `Event` 序列。

---

## 跨模块接口（完整清单）

### 1. `lobby` → `room`

```text
RoomManager.openGame(room_id, players: [4]PlayerId) !void
```

建 `Room`（含 `Desk`），入 map 后 `attachBotsAndStartIfReady`：为 bot 座位挂 `Sender`，若已齐人则开局。**不**在 `openGame` 内发牌。

齐人条件：`players[0..4]` 均在 `connections`（真人 `onConnect` 或 bot 已 attach）。

### 2. `room` → `core.Desk`

```text
Desk.beginGame() !Outcome                 // Playing + engine.onStartGame + 首条 request
Desk.onAction(player_id, request_id, action) !Outcome
Desk.onTimeout(request_id) !Outcome
```

| 入口 | 何时调用 | 做什么 |
|---|---|---|
| `beginGame` | 四座 Sender 齐 | `game_phase=playing`；`engine.onStartGame`；首条 `action_requested` |
| `onAction` | 收到带 `request_id` 的意图 | pending → apply → resolved + 牌谱（局终连庄由 engine 写在 produced 里） |
| `onTimeout` | room 截止到期 | 默认着，`action_resolved{defaulted}` |

禁止：`getKyoku`、`subscribe`、把 `onConnect` 塞进 core、业务 `tick`、对 Room 暴露 `beginKyoku`。  
WS / bot 进出只在 room 记账；core 只认构造时固定的 `player_id`→`seat`。
wire `start_game` 仍由 Room 在 attach 时发，**不**驱动 engine。

### 3. `room` 本地（不对 core 暴露成接口）

- MJAI 编解码与按座位遮罩
- `Sender` / 广播单播；bot 与真人同一 `connections`
- `deliverOutcome` 末尾 `flushBotReplies`：取出 bot 待回包 → `onMessage`（防嵌套二次 drain）
- `action_requested` → 挂定时器 → `onTimeout`（墙钟可后补）
- 晚连真人：`bindSender` 时发 `start_game` + catch-up（若已过 `awaiting_players`）

### 4. `core` 内部（不对 room 暴露）

```text
legalActions(state, seat) -> []Action
defaultAction(state, seat) -> ?Action
beginKyoku(state) -> []Event          // 洗牌发牌 + start_kyoku + 首摸
apply / legalActions / defaultAction   // 摸打骨架；鸣牌/和了未实现
chomboReason / chombo                  // 罚符结束本局（不出 end_game）
```

`Kyoku` 持有牌山、手牌、河、`drawn`、局内 `KyokuPhase`。`shuffle_seed` 控制洗牌复现。

`Desk` 做：`GamePhase`、pending / `request_id` 门禁、拼 `action_resolved` / `action_requested`、调用上述函数。见到 `end_game` 才把 `game_phase` 置 `finished`；单局 `KyokuPhase.finished` 不等于整盘结束。非法着时 Desk 写 ack，罚则事件由 `chombo` 产出。

---

## 开局与一回合时序

```text
openGame → Room.init → put map → attachBotsAndStartIfReady
  ├─ isBot → BotAgent + bindSender
  └─ 若四座齐 → beginGame → deliverOutcome → flushBotReplies

真人 onConnect → bindSender → beginIfAllSeatsConnected（同上）

room                           Desk                          engine
 |-- beginGame() ------------->|  playing                      |
 |                             |-- onStartGame --------------->|
 |<------ Outcome -------------|  kyoku events + request        |
 |  deliverOutcome + flush bots |                               |
 |                             |                               |
 |-- onAction(pid,rid,act) --->|  check pending                |
 |                             |-- apply --------------------->|
 |<------ Outcome -------------|  resolved + 牌谱 (+ 下局?)    |
 |  deliverOutcome + flush bots |                               |
 |                             |                               |
 |-- onTimeout(rid) ---------->|  default action               |
 |<------ Outcome -------------|                               |
```

## 测试策略

| 层级 | 测什么 | 不测什么 |
|---|---|---|
| `core` / `Desk` | `beginGame`/`onAction`/`onTimeout` 的 `Event` 序列、拒绝非法着、超时默认着、chombo | JSON、WS |
| `core` / engine | 吃碰杠荣合法集、和了、流局罚符 | 连接 |
| `room/protocol` | 编解码、遮罩 | 规则 |
| 少量集成 | 齐人两步开局、bot 回至少一手 | 全牌谱可后补 |

## 明确不做

- 不把 `Kyoku` 借给 `room`
- 不为每种牌谱事件设回调接口
- `core` 不 import `Sender` / `httpz` / `websocket`
- Lobby 不认识 `Action` / `Event`
- 第一期不做中途重连进引擎（断线由 room 记，引擎吃 `onTimeout` 代打）

## 验收标准

- 一页纸能画清：`openGame` → 齐人 → `beginGame`，之后只有 `onAction` / `onTimeout`；局循环在 engine；下行只有 `Outcome.events`
- 未齐人不 `beginGame`；全 bot 或 1 人+3 bot 在 Sender 齐后能自动打至少一手
- Room / Desk 不暴露 `beginKyoku`；仅 `end_game` 时整盘 finished
- 不接网络能跑脚本测完一局关键路径
- 改 MJAI 只动 `room/protocol`；改能否碰只动 `core` 内部；lobby/core 无 `@import("bot")`
