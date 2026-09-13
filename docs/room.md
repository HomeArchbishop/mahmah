# Room WebSocket 协议（MJAI）

对局内 bot / 客户端与 gameserver 的消息约定。帧为文本，每条消息是单个 JSON 对象；二进制帧忽略。

## 连接

| Endpoint | Auth | 说明 |
|---|---|---|
| `/ws/ranked` | `Authorization: Bearer BOT_TOKEN` | 排位；需已激活 bot |
| `/ws/validate` | `Authorization: Bearer BOT_TOKEN` | 待审 bot 的校验局 |
| `/status` | 无 | 服务状态（HTTP GET，JSON） |

本仓库人类玩家经 lobby 开局后改连 `/ws/room/{room_id}?player_id={player_id}`；对局内事件格式与下表一致。

## 消息流

服务端驱动对局。Bot **只在**收到 `request_action` 后回复。

```
Server                         Bot
start_game  ----------------->  开局、座位
start_kyoku ----------------->  一局开始，时间银行回满
tsumo / dahai / ... --------->  摸打等事件
request_action -------------->  轮到你；在截止前回复
  request_id, time, possible_actions, observation
         <-------------------  dahai / ...（带回 request_id）
action_ack ------------------>  每条回复的回执
...
end_game -------------------->  终局；随后断开
```

`request_action` 带 `request_id` 与时间预算；回复须回声同一 `request_id`；服务端对每条已处理回复发 `action_ack`。

每条消息必有 `type`。服务端可能新增事件类型与字段——**须忽略未知 `type` 与未知字段**，不要因此报错。

---

## Server → Bot

### `start_game`

开局一次，告知座位。

```json
{"type":"start_game","id":0}
```

- `id` — 你的座位下标（0–3）

### `start_kyoku`

每局开始。

```json
{
  "type": "start_kyoku",
  "bakaze": "E",
  "dora_marker": ["2p"],
  "kyoku": 1,
  "honba": 0,
  "kyotaku": 0,
  "oya": 0,
  "tehais": [
    ["1m","3m","5m","7p","9s"],
    ["?","?","?","?","?"],
    ["?","?","?","?","?"],
    ["?","?","?","?","?"]
  ]
}
```

- `tehais` — 四人起手；仅自己的手牌可见，其余为 `"?"`

### `tsumo`

摸牌。他人摸牌时 `pai` 为 `"?"`。

```json
{"type":"tsumo","actor":0,"pai":"3m"}
```

### `dahai`

出牌。

```json
{"type":"dahai","actor":0,"pai":"3m","tsumogiri":true}
```

### `chi` / `pon` / `daiminkan` / `ankan` / `kakan`

鸣牌。

```json
{"type":"chi","actor":1,"target":0,"pai":"5m","consumed":["4m","6m"]}
{"type":"pon","actor":2,"target":0,"pai":"E","consumed":["E","E"]}
{"type":"daiminkan","actor":2,"target":0,"pai":"E","consumed":["E","E","E"]}
{"type":"ankan","actor":0,"consumed":["1s","1s","1s","1s"]}
{"type":"kakan","actor":0,"pai":"5m","consumed":["5m"]}
```

### `reach`

立直声明。切牌在后续 `dahai`。

```json
{"type":"reach","actor":0}
```

### `hora`

和牌。

```json
{"type":"hora","actor":0,"target":1,"pai":"5m"}
```

### `end_kyoku`

一局结束。

```json
{"type":"end_kyoku"}
```

局间细节（点数变动等）已体现在前置的 `hora` / `ryukyoku`；本消息仅作局界标记。

### `dora`

杠后追加宝牌指示牌。

```json
{"type":"dora","dora_marker":"3m"}
```

### `reach_accepted`

立直成立（宣言后未被荣和打断时）。可选；客户端可忽略。

```json
{"type":"reach_accepted","actor":0}
```

### `end_game`

终局；含最终点数。收到后应断开连接。

```json
{"type":"end_game","scores":[30000,25000,20000,25000]}
```

### `action_ack`

服务端处理（或代打）你对某次 `request_action` 的回复后发送。简单 bot 可忽略；用于调试与跟踪剩余时间银行。

```json
{
  "type": "action_ack",
  "request_id": 42,
  "status": "accepted",
  "elapsed_ms": 850,
  "bank_consumed_ms": 0,
  "bank_ms": 15000
}
```

| status | 含义 | 分数影响 |
|---|---|---|
| `accepted` | 动作已进入对局 | 无 |
| `rejected` | 可解析但不在 `possible_actions`（含 `reason` / `attempted` / `legal_types`） | 役满罚符（chombo） |
| `unparseable` | 无法解析（含 `reason`） | chombo |
| `stale` | 迟到或旧 `request_id`，丢弃 | 无 |
| `defaulted` | 超时；服务端代打，`action` 为代打内容 | 无（银行归 0） |

超时代打示例：

```json
{
  "type": "action_ack",
  "request_id": 42,
  "status": "defaulted",
  "action": {"type": "dahai", "pai": "7s", "tsumogiri": true},
  "elapsed_ms": 18001,
  "bank_consumed_ms": 15000,
  "bank_ms": 0
}
```

### `request_action`

轮到你行动时发送：请求 id、时间预算、合法动作、观测。

```json
{
  "type": "request_action",
  "request_id": 42,
  "time": {"grace_ms": 3000, "bank_ms": 15000, "deadline_ms": 18000},
  "possible_actions": [
    {"type": "dahai", "pai": "1m"},
    {"type": "dahai", "pai": "3m"},
    {"type": "reach"},
    {"type": "hora"},
    {"type": "none"}
  ],
  "observation": "eyJwbGF5ZXJfaWQiOjAs..."
}
```

#### `request_id`

对局内单调递增、每次请求唯一。回复须回声；迟到回复不会被绑到更新的请求上。

#### `time`

以消息内数值为准（服务端可改配置）。

| 字段 | 含义 |
|---|---|
| `grace_ms` | 每次请求的免费时间；在此内回复不扣银行 |
| `bank_ms` | 当前局剩余时间银行 |
| `deadline_ms` | `grace_ms + bank_ms`；超时则代打 |

#### `possible_actions`

当前合法动作（MJAI 形状）。回复必须对应其中之一。

| type | 字段 | 含义 |
|---|---|---|
| `dahai` | `pai` | 出牌 |
| `chi` | `pai`, `consumed` | 吃 |
| `pon` | `pai`, `consumed` | 碰 |
| `daiminkan` | `pai`, `consumed` | 大明杠 |
| `ankan` | `consumed` | 暗杠 |
| `kakan` | `pai`, `consumed` | 加杠 |
| `reach` | | 立直 |
| `hora` | | 和（自摸/荣；回复时可带 `target`/`pai`） |
| `ryukyoku` | | 九种九牌等流局 |
| `none` | | 过 / 鸣牌放弃 |

#### `observation`

Base64 编码的 RiichiEnv 观测。4 人用 `Observation`，3 人用 `Observation3P` 解码，得到己方视角的完整状态与合法动作。

```python
from riichienv import Observation
obs = Observation.deserialize_from_base64(msg["observation"])
actions = obs.legal_actions()
state = obs.to_dict()
```

---

## Bot → Server

单条 MJAI JSON，回声对应 `request_id`。未知多余字段服务端忽略。

| type | 必填字段 | 备注 |
|---|---|---|
| `dahai` | `pai`（建议带 `actor`） | `tsumogiri` 默认 `false`；座位以连接身份为准 |
| `chi` | `pai`, `consumed` | `consumed`：手牌 2 张；建议带 `actor`/`target` |
| `pon` | `pai`, `consumed` | 同上 |
| `daiminkan` | `pai`, `consumed` | `consumed`：3 张 |
| `ankan` | `consumed` | 四张 |
| `kakan` | `pai`, `consumed` | 在已有碰上加杠 |
| `reach` | | 切牌另发 `dahai` |
| `hora` | | 自摸/荣由服务端判定；可带 `target`/`pai` |
| `ryukyoku` | | 九种九牌等 |
| `none` | | 放弃鸣牌机会 |

```json
{"type":"dahai","actor":0,"pai":"3m","tsumogiri":true,"request_id":42}
{"type":"chi","actor":1,"target":0,"pai":"5m","consumed":["4m","6m"],"request_id":42}
{"type":"reach","actor":0,"request_id":42}
{"type":"hora","actor":0,"target":2,"pai":"5m","request_id":42}
{"type":"none","request_id":42}
```

### `request_id` 回声

强烈建议始终带回（日后排位可能强制）。

| 回复 | 服务端行为 |
|---|---|
| 回声当前 `request_id` | 绑定该请求并处理 |
| 回声更旧的 `request_id` | `action_ack` `stale`，丢弃，无罚 |
| 回声未知 / 未来的 `request_id` | 协议违规，按 `unparseable`（chombo） |
| 无 `request_id`（旧客户端） | 按到达顺序绑定，服务端做 stale 记账 |

---

## 牌面记号

| 花色 | 牌 |
|---|---|
| 万 | `1m` … `9m` |
| 筒 | `1p` … `9p` |
| 索 | `1s` … `9s` |
| 风 | `E` `S` `W` `N` |
| 箭 | `P`（白）`F`（发）`C`（中） |
| 赤宝 | `5mr` `5pr` `5sr` |

他人不可见牌为 `"?"`。

---

## 时限、代打与惩罚

### 时限：grace + 每局银行（默认 3s + 15s）

- **Grace**：每次请求免费时间；超时部分扣银行。
- **Bank**：每局开始回满，不跨局结转；摸牌回合与鸣牌机会共用。
- **Deadline**：`grace + 剩余 bank`。超时则银行归 0，服务端代打并继续：
  - 己方摸牌回合（WaitAct）→ 摸切（`dahai` + `tsumogiri`）
  - 鸣牌机会（WaitResponse）→ `{"type":"none"}`

单纯超时不罚分。时钟从发出 `request_action` 起算（含 RTT）。常规推理宜 &lt; 500ms；银行是偶发慢回合的余量，不是每手该花光的额度。

### 迟到回复

带回 `request_id` 时：旧 id 一律 `stale`，绝不绑到新请求；最坏是代打，不会因“慢手绑错题”吃 chombo。

无 `request_id` 时：每次请求期望恰好一条回复；超时后下一条入站消息结算欠账并丢弃（记账最多保留约 30s）。应对每个 `request_action` 按序各回一次。

### 非法动作 → chombo（满贯罚符）

可解析但不在 `possible_actions`，或完全无法解析时：

```json
{"type":"ryukyoku","reason":"Error: Illegal Action by Player 0","deltas":[-12000,4000,4000,4000]}
```

四人分差（示意）：

- 亲家犯规：−12000；每家闲家 +4000
- 闲家犯规：−8000；亲家 +4000；其余闲家各 +2000

该局立即结束，连庄（renchan）。发送前务必对照 `possible_actions` 校验。

### 断线

连接断开后本局视为断线；后续行动一律代打、不额外罚分（同超时）。不支持中途重连。
