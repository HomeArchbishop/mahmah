# mahmah

四人立直麻将服务端，用 Zig 0.16 写的。

## 怎么跑

```bash
zig build run    # 默认监听 :8080
zig build test
```

- 大厅通信端点 `/ws/lobby`，协议见 [docs/lobby.md](docs/lobby.md)
- 房间通信端点 `/ws/room/:id?player_id=`，协议见 [docs/room.md](docs/room.md)

## 和 riichienv 做差分

```bash
zig build mjai-diff
cd tests && uv sync
uv run python -m diff seed --seeds 5
uv run python -m diff scenario
uv run python -m diff all --seeds 5
```
