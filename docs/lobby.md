# Lobby WebSocket 协议

大厅链接端点是 `GET /ws/lobby`。连上之后用文本 JSON 传递消息，编码 UTF-8。

## 基本约定

- id 用 JSON 数字
- 客户端请求可以带 `request_id`（无符号 32 位整数）；服务端对应的回复会使用同一个整数作标记
- 没有 `request_id` 的，是服务端主动推给你的

一连上，服务端会先给你发：

```json
{"type":"welcome","player_id":1001}
```

把这个 `player_id` 记下来。等 `start_game` 成功之后，连接房间频道需要 `/ws/room/{room_id}?player_id={player_id}`。

加机器人、摆座位这些事，由lobby负责。

## 心跳

建议大概每 15 秒发一次：

```json
{"type":"ping"}
```

服务端回：

```json
{"type":"pong"}
```

如果连续大约 30 秒都没有任何上行消息，服务端会把你踢掉。

## 创建房间

```json
{"type":"create_room","request_id":1}
```

```json
{"type":"room_created","request_id":1,"room_id":42}
```

创建的人自动当房主，并且已经在这个房间里了。

## 加入房间

```json
{"type":"join_room","request_id":2,"room_id":42}
```

```json
{"type":"room_joined","request_id":2,"room_id":42}
```

## 添加 / 删除机器人

只有房主能做。

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

`player_id` 最高位是 1 的是机器人。

## 开始游戏

只有房主能开。

```json
{"type":"start_game","request_id":5,"room_id":42}
```

房主自己会收到带 `request_id` 的回复：

```json
{"type":"game_started","request_id":5,"room_id":42}
```

同时，这个房里其他还挂在 lobby 上的真人，会收到一条没有 `request_id` 的推送：

```json
{"type":"game_started","room_id":42}
```

看到这条之后，连对局用的 room WebSocket。如果人数不够，或者游戏已经开过了，会返回 `err`。

## 出错时

凡是带了 `request_id` 的请求失败，服务端都会返回：

```json
{"type":"err","request_id":1,"code":"not_found","msg":"..."}
```

- `code` 供程序使用；`msg` 是人类可读信息，可能缺失。

| code | 意思 |
|---|---|
| `bad_request` | 字段缺失，或类型不对 |
| `not_found` | 房间或目标找不到 |
| `forbidden` | 你不是房主，或者没权限 |
| `conflict` | 比如你已经在别的房间里了 |
| `full` | 房间满了 |
| `not_bot` | 你要删的那个不是机器人 |
| `not_ready` | 人数不够，开不了 |
| `already_started` | 这局已经开过了 |

## 最短流程

```
welcome → ping/pong → create_room → add_bot* → start_game
      → 连 /ws/room/{room_id}?player_id=... → 游戏结束
```

如果是进别人的房，把 `create_room` 换成 `join_room`，等房主开了、你收到 `game_started` 推送之后，再进 room。
