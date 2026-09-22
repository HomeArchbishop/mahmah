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

## 与 riichienv 差分

```bash
zig build mjai-diff
PYTHONPATH=. python -m tests.diff --seeds 5 -v
```

领导进程同牌山驱动标准（riichienv）与 `mjai_diff`：比合法集与 MJAI 事件，半庄多局，着法优先和/立直/鸣牌。
