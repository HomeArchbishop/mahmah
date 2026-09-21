# mahmah

四人立直麻将服务端（Zig 0.16）。

```text
lobby → room (WS / MJAI) → core (Desk → engine → referee)
```

```bash
zig build run    # :8080
zig build test
```

`/ws/lobby` 组队，`/ws/room/:id?player_id=` 对局。协议：`docs/lobby.md`、`docs/room.md`。
