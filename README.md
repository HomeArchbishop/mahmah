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
cd tests && uv sync
uv run python -m diff seed --seeds 5 -v      # 随机半庄
uv run python -m diff scenario               # 构造场景（checklist）
uv run python -m diff all --seeds 5          # scenario + seed
```

同牌山驱动 riichienv 与 `mjai_diff`：比合法集与 MJAI 事件。代码在 `tests/diff/`（`seed` / `scenario/` / `adapters/`）。每次跑完覆盖写 `coverage-latest.md`。

细则：`src/core/rules.zig`。产品 `Rules.default()`（含切上）；`mjai_diff` 固定 `Rules.riichienv()`（关切上）。见 `docs/superpowers/specs/2026-09-22-rules-config-design.md`。

覆盖目录：`tests/diff/checklist.yaml`。查看上次报告：`uv run python -m diff coverage report`。
