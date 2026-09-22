"""领导进程：同一牌山驱动两边；比合法集 + 事件；半庄多局。"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .compare import (
    events_equal,
    legal_sets_equal,
    strip_after_kyoku_end,
)
from .core_adapter import CoreEngine, default_mjai_diff_path
from .riichi_adapter import RiichiEngine, make_wall, wall_to_mjai

RETURN_SCORE = 30000


@dataclass
class Table:
    scores: list[int] = field(default_factory=lambda: [25000, 25000, 25000, 25000])
    oya: int = 0
    honba: int = 0
    kyotaku: int = 0
    bakaze: str = "E"
    kyoku: int = 1


def filter_game_events(events: list[dict]) -> list[dict]:
    skip = {"start_game", "request_action", "action_ack", "action_resolved"}
    return [e for e in events if e.get("type") not in skip]


def apply_score_events(table: Table, events: list[dict]) -> None:
    for ev in events:
        t = ev.get("type")
        if t == "reach_accepted":
            actor = ev["actor"]
            table.scores[actor] -= 1000
            table.kyotaku += 1
        if t in ("hora", "ryukyoku") and "deltas" in ev:
            for i, d in enumerate(ev["deltas"]):
                table.scores[i] += int(d)
        if t == "hora":
            # 供托归和了者（若事件未把 kyotaku 写进 deltas）
            table.kyotaku = 0


def meta_from_start_kyoku(ev: dict, scores: list[int]) -> Table:
    return Table(
        scores=list(scores),
        oya=int(ev["oya"]),
        honba=int(ev["honba"]),
        kyotaku=int(ev["kyotaku"]),
        bakaze=str(ev["bakaze"]),
        kyoku=int(ev["kyoku"]),
    )


def should_end_hanchan(table: Table, *, renchan: bool) -> bool:
    if renchan:
        return False
    if table.bakaze == "E" and table.kyoku == 4:
        return max(table.scores) >= RETURN_SCORE
    if table.bakaze == "S" and table.kyoku == 4:
        return True
    return False


def run_kyoku(
    *,
    seed: int,
    kyoku_i: int,
    table: Table,
    oracle: RiichiEngine,
    core: CoreEngine,
    verbose: bool,
) -> tuple[Table | None, bool]:
    """打一局。返回 (下一局 table 或 None 若终战, 是否终战)。"""
    wall = make_wall(seed * 10007 + kyoku_i)
    paishan = wall_to_mjai(wall)

    o_ev = filter_game_events(
        oracle.load_wall(
            wall,
            oya=table.oya,
            honba=table.honba,
            kyotaku=table.kyotaku,
            scores=table.scores,
            bakaze=table.bakaze,
        )
    )
    while o_ev and o_ev[0].get("type") == "start_game":
        o_ev = o_ev[1:]

    sk = next(e for e in o_ev if e.get("type") == "start_kyoku")
    # 以标准 start_kyoku 元数据为准（oya/kyoku 推导）
    boot = meta_from_start_kyoku(sk, table.scores)

    c_ev = filter_game_events(
        core.load_wall(
            paishan,
            oya=boot.oya,
            bakaze=boot.bakaze,
            kyoku=boot.kyoku,
            honba=boot.honba,
            kyotaku=boot.kyotaku,
            scores=boot.scores,
        )
    )
    ok, msg = events_equal(o_ev, c_ev)
    if not ok:
        raise AssertionError(
            f"seed={seed} kyoku_i={kyoku_i} start mismatch: {msg}\noracle={o_ev}\ncore={c_ev}"
        )
    table = boot
    if verbose:
        print(
            f"seed={seed} {table.bakaze}{table.kyoku} oya={table.oya} "
            f"honba={table.honba} start ok",
            flush=True,
        )

    step = 0
    while not oracle.done():
        seats = oracle.seats_needing_action()
        if not seats:
            raise RuntimeError(f"seed={seed} no actors at step {step}")

        for seat in seats:
            o_legal = oracle.legal_mjai(seat)
            c_legal = core.legal(seat)
            ok, msg = legal_sets_equal(o_legal, c_legal)
            if not ok:
                raise AssertionError(
                    f"seed={seed} kyoku_i={kyoku_i} step={step} seat={seat} legal mismatch: {msg}"
                )

        actions = {seat: oracle.pick_action(seat) for seat in seats}
        o_new = filter_game_events(oracle.step(actions))
        for ev in o_new:
            if ev.get("type") == "dahai" and ev.get("actor") in actions:
                actions[ev["actor"]]["tsumogiri"] = bool(ev.get("tsumogiri", False))

        c_full: list[dict] = []
        for seat in sorted(actions.keys()):
            c_full.extend(filter_game_events(core.apply(seat, actions[seat])))

        o_cmp = strip_after_kyoku_end(o_new)
        c_cmp = strip_after_kyoku_end(c_full)
        ok, msg = events_equal(o_cmp, c_cmp)
        if not ok:
            raise AssertionError(
                f"seed={seed} kyoku_i={kyoku_i} step={step} seats={seats} actions={actions}\n"
                f"{msg}\noracle={o_cmp}\ncore={c_cmp}"
            )
        if verbose:
            print(
                f"seed={seed} step={step} ok "
                f"{ {s: a.get('type') for s, a in actions.items()} }",
                flush=True,
            )
        step += 1

        apply_score_events(table, o_cmp)

        if any(e.get("type") == "end_game" for e in o_cmp):
            return None, True
        if any(e.get("type") == "end_kyoku" for e in o_cmp):
            # 下一局元数据：看 core 局终后自动开的 start_kyoku（牌山作废，只取场况）
            renchan = False
            next_table: Table | None = None
            saw_end = False
            for ev in c_full:
                if ev.get("type") == "end_kyoku":
                    saw_end = True
                    continue
                if saw_end and ev.get("type") == "end_game":
                    return None, True
                if saw_end and ev.get("type") == "start_kyoku":
                    # 连庄：oya/kyoku/bakaze 未变
                    renchan = (
                        int(ev["oya"]) == table.oya
                        and int(ev["kyoku"]) == table.kyoku
                        and str(ev["bakaze"]) == table.bakaze
                    )
                    next_table = meta_from_start_kyoku(ev, table.scores)
                    break
            if next_table is None:
                # core 未衔接下局：按半庄规则在领导侧推进
                if should_end_hanchan(table, renchan=False):
                    return None, True
                raise AssertionError(
                    f"seed={seed} end_kyoku but no next start_kyoku in core events: {c_full}"
                )
            if should_end_hanchan(table, renchan=renchan):
                return None, True
            return next_table, False

    return None, True


def run_one(seed: int, exe: Path | None = None, verbose: bool = False) -> None:
    oracle = RiichiEngine()
    core = CoreEngine(exe)
    try:
        table: Table | None = Table()
        kyoku_i = 0
        while table is not None:
            table, ended = run_kyoku(
                seed=seed,
                kyoku_i=kyoku_i,
                table=table,
                oracle=oracle,
                core=core,
                verbose=verbose,
            )
            if ended or table is None:
                if verbose:
                    print(f"seed={seed} PASS kyokus={kyoku_i + 1}", flush=True)
                return
            kyoku_i += 1
            if kyoku_i > 16:
                raise RuntimeError(f"seed={seed} too many kyokus")
    finally:
        core.close()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Diff mahmah core vs riichienv")
    p.add_argument("--seeds", type=int, default=1)
    p.add_argument("--base-seed", type=int, default=0)
    p.add_argument("--exe", type=Path, default=None)
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)

    exe = args.exe or default_mjai_diff_path()
    failed = 0
    for i in range(args.seeds):
        seed = args.base_seed + i
        try:
            run_one(seed, exe=exe, verbose=args.verbose)
            print(f"OK seed={seed}")
        except Exception as e:
            failed += 1
            print(f"FAIL seed={seed}: {e}", file=sys.stderr)
            if args.seeds == 1:
                raise
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
