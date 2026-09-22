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
uv run python -m diff --seeds 5 -v
```

领导进程同牌山驱动标准（riichienv）与 `mjai_diff`：比合法集与 MJAI 事件，半庄多局，着法优先和/立直/鸣牌。每次跑完打印并覆盖写 `tests/diff/coverage-latest.md`（本次覆盖了哪些情况/役、对应 seed）。

细则：`src/core/rules.zig`。产品 `Rules.default()`（含切上）；`mjai_diff` 固定 `Rules.riichienv()`（关切上）。见 `docs/superpowers/specs/2026-09-22-rules-config-design.md`。

覆盖条目目录：`tests/diff/checklist.yaml`（只维护 id/group/desc；役种可 `uv run python -m diff coverage ensure` 补齐）。查看上次报告：

```bash
uv run python -m diff coverage report
```
