# Lobby WebSocket 协议

入口：`GET /ws/lobby` → 文本帧，UTF-8 JSON。每条消息必有 `type`。

## 约定

- id 用 JSON number
- 请求可带 `request_id`（u32）；对应响应带回同一 `request_id`
- 无 `request_id` 的是服务端推送

连上后服务端先推：

```json
{"type":"welcome","player_id":1001}
```

客户端保存 `player_id`。`start_game` 成功后断开 lobby，改连 `/ws/room/{room_id}?player_id={player_id}`。

机器人编排在**仍挂 lobby 连接时**完成（`create_room` / `join_room` 之后、`start_game` 之前）。

## 心跳

建议每 15s：

```json
{"type":"ping"}
```

```json
{"type":"pong"}
```

连续约 30s 无任何上行则服务端断开。

## 创建房间

```json
{"type":"create_room","request_id":1}
```

```json
{"type":"room_created","request_id":1,"room_id":42}
```

创建者成为房主并加入该房。

## 加入房间

```json
{"type":"join_room","request_id":2,"room_id":42}
```

```json
{"type":"room_joined","request_id":2,"room_id":42}
```

## 添加 / 删除机器人

仅房主。

```json
{"type":"add_bot","request_id":3,"room_id":42}
```

```json
{"type":"bot_added","request_id":3,"room_id":42,"player_id":9223372036854775809}
```

```json
{"type":"remove_bot","request_id":4,"room_id":42,"player_id":9223372036854775809}
```

```json
{"type":"bot_removed","request_id":4,"room_id":42,"player_id":9223372036854775809}
```

`player_id` 最高位为 1 表示机器人（`ids.isBot`）。

## 开始游戏

仅房主。

```json
{"type":"start_game","request_id":5,"room_id":42}
```

```json
{"type":"game_started","request_id":5,"room_id":42}
```

成功后向该房所有仍挂在 lobby 的成员推送（无 `request_id`）：

```json
{"type":"game_started","room_id":42}
```

收到后客户端断开 lobby，改连 room WS。人数不足 / 已开始 → `err`。

## 失败

任一带 `request_id` 的请求失败时，服务端回：

```json
{"type":"err","request_id":1,"code":"not_found","msg":"..."}
```

- 必带回原 `request_id`
- `code` 机器可读；`msg` 给人看，可省略

| code | 含义 |
|---|---|
| `bad_request` | 字段缺失或类型错 |
| `not_found` | 房间 / 目标不存在 |
| `forbidden` | 非房主或无权限 |
| `conflict` | 已在房间等冲突 |
| `full` | 房间已满 |
| `not_bot` | 目标不是机器人 |
| `not_ready` | 人数不足，无法开始 |
| `already_started` | 游戏已开始 |

## 最小顺序

```
welcome → ping/pong → create_room → add_bot* → start_game → 断 lobby
       → 连 /ws/room/{room_id}?player_id=...
```

加入已有房则把 `create_room` 换成 `join_room`；等房主 `start_game` 推送后再进 room。
