# mahmah <img src="https://img.shields.io/badge/Zig-0.16-F7A41D?style=flat-square&logo=zig" alt="Zig 0.16" />

四人立直麻将服务器。

## Development

```bash
zig build run    # 默认监听 :8080
zig build test
```

- 大厅通信端点 `/ws/lobby`，协议见 [docs/lobby.md](docs/lobby.md)
- 房间通信端点 `/ws/room/:id?player_id=`，协议见 [docs/room.md](docs/room.md)

## Test

使用 riichienv 做差分测试。

```bash
zig build mjai-diff
cd harness && uv sync
uv run python -m diff seed --seeds 5
uv run python -m diff scenario
uv run python -m diff all --seeds 5
```

使用 webui 试打。

```bash
cd webui
bun i
bunx vite .
```

## License

[Apache License 2.0](LICENSE)
