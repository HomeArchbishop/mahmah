"""seed 入口：随机牌山半庄差分；比合法集 + 事件。"""
from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .adapters import CoreEngine, RiichiEngine, default_mjai_diff_path, make_wall, wall_to_mjai
from .compare import (
    events_equal,
    legal_key_sets_equal,
    strip_after_kyoku_end,
)
from .coverage import (
    tags_from_events,
    tags_from_yaku_ids,
    write_latest_report,
)

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


def meta_from_start_kyoku(ev: dict, scores: list[int] | None = None) -> Table:
    # 优先用事件自带 scores，避免 oracle ryukyoku 里「立直棒展示用 -1000」被 apply 后污染下一局
    ev_scores = ev.get("scores")
    use = list(ev_scores) if isinstance(ev_scores, list) and len(ev_scores) == 4 else list(scores or [25000] * 4)
    return Table(
        scores=use,
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
) -> tuple[Table | None, bool, set[str]]:
    """打一局。oracle 先整局录着，core 一次 replay；比合法键 + 事件。"""
    wall = make_wall(seed * 10007 + kyoku_i)
    paishan = wall_to_mjai(wall)

    o_start = filter_game_events(
        oracle.load_wall(
            wall,
            oya=table.oya,
            honba=table.honba,
            kyotaku=table.kyotaku,
            scores=table.scores,
            bakaze=table.bakaze,
        )
    )
    while o_start and o_start[0].get("type") == "start_game":
        o_start = o_start[1:]

    sk = next(e for e in o_start if e.get("type") == "start_kyoku")
    boot = meta_from_start_kyoku(sk, table.scores)
    table = boot
    # 开局场况快照：后面 apply_score_events 会改 table（与 boot 同对象）
    start_scores = list(boot.scores)
    start_kyotaku = boot.kyotaku
    start_honba = boot.honba

    steps: list[list[dict]] = []
    oracle_legals: list[dict[int, list[dict]]] = []
    oracle_step_events: list[list[dict]] = []
    cover_events: list[dict] = list(o_start)
    yaku_tags: set[str] = set()

    step = 0
    while not oracle.done():
        seats = oracle.seats_needing_action()
        if not seats:
            raise RuntimeError(f"seed={seed} no actors at step {step}")

        legals = {seat: oracle.legal_mjai(seat) for seat in seats}
        oracle_legals.append(legals)
        actions = {seat: oracle.pick_action(seat) for seat in seats}
        o_new = filter_game_events(oracle.step(actions))
        for ev in o_new:
            if ev.get("type") == "dahai" and ev.get("actor") in actions:
                actions[ev["actor"]]["tsumogiri"] = bool(ev.get("tsumogiri", False))

        payload = []
        for seat in sorted(actions.keys()):
            act = dict(actions[seat])
            act.setdefault("actor", seat)
            act.setdefault("request_id", 1)
            if act.get("type") == "dahai":
                act.setdefault("tsumogiri", False)
            payload.append({"seat": seat, "action": act})
        steps.append(payload)
        oracle_step_events.append(o_new)
        cover_events.extend(o_new)
        step += 1

        if any(e.get("type") == "hora" for e in o_new):
            for wr in oracle.env.win_results.values():
                yaku_tags |= tags_from_yaku_ids(wr.yaku)

        o_cmp = strip_after_kyoku_end(o_new)
        apply_score_events(table, o_cmp)
        if any(e.get("type") in ("end_kyoku", "end_game") for e in o_cmp):
            break

    kyoku_tags = tags_from_events(cover_events) | yaku_tags

    c_all, step_keys = core.replay_kyoku(
        paishan,
        oya=boot.oya,
        bakaze=boot.bakaze,
        kyoku=boot.kyoku,
        honba=start_honba,
        kyotaku=start_kyotaku,
        scores=start_scores,
        steps=steps,
    )
    c_all = filter_game_events(c_all)

    # 切开局事件与逐步事件：start_kyoku+tsumo … 直到第一着之前
    if not c_all or c_all[0].get("type") != "start_kyoku":
        raise AssertionError(f"seed={seed} core replay missing start_kyoku: {c_all[:3]!r}")
    # oracle start vs core start（到第一个非 start/tsumo 开局段）
    # 两边开局都是 [start_kyoku, tsumo]
    o_head = o_start
    c_head = c_all[:2]
    ok, msg = events_equal(o_head, c_head)
    if not ok:
        raise AssertionError(
            f"seed={seed} kyoku_i={kyoku_i} start mismatch: {msg}\noracle={o_head}\ncore={c_head}"
        )

    if len(step_keys) != len(steps):
        raise AssertionError(
            f"seed={seed} step_legal_keys len {len(step_keys)} != steps {len(steps)}"
        )

    # 按步切 core 事件：用 oracle 每步事件长度对齐不可靠；改为整段逐步比对
    # 从 c_all[2:] 按 oracle 每步 strip 后的事件序列顺序匹配
    c_rest = c_all[2:]
    c_i = 0
    for si, (legals, o_new) in enumerate(zip(oracle_legals, oracle_step_events)):
        for seat, o_legal in legals.items():
            keys = step_keys[si].get(seat)
            if keys is None:
                raise AssertionError(
                    f"seed={seed} kyoku_i={kyoku_i} step={si} seat={seat} missing legal_keys"
                )
            ok, msg = legal_key_sets_equal(o_legal, keys)
            if not ok:
                raise AssertionError(
                    f"seed={seed} kyoku_i={kyoku_i} step={si} seat={seat} legal mismatch: {msg}"
                )

        o_cmp = strip_after_kyoku_end(o_new)
        # 取 core 下一段等长事件（end_kyoku 后可能还有 start_kyoku）
        need = len(o_cmp)
        # 若本步含 end_kyoku，core 可能多吐下一局 start_kyoku：先取到 end_kyoku 为止，其余留到局终处理
        if any(e.get("type") == "end_kyoku" for e in o_cmp):
            c_seg: list[dict] = []
            while c_i < len(c_rest):
                c_seg.append(c_rest[c_i])
                c_i += 1
                if c_seg[-1].get("type") == "end_kyoku":
                    break
            # 吞掉紧随的 start_kyoku / end_game 供局终逻辑
            trailing = c_rest[c_i:]
            c_i = len(c_rest)
            c_cmp = c_seg
            ok, msg = events_equal(o_cmp, c_cmp)
            if not ok:
                raise AssertionError(
                    f"seed={seed} kyoku_i={kyoku_i} step={si} event mismatch: {msg}\n"
                    f"oracle={o_cmp}\ncore={c_cmp}"
                )
            if verbose:
                print(f"seed={seed} step={si} ok (kyoku end)", flush=True)

            if any(e.get("type") == "end_game" for e in o_cmp):
                return None, True, kyoku_tags

            renchan = False
            next_table: Table | None = None
            for ev in trailing:
                if ev.get("type") == "end_game":
                    return None, True, kyoku_tags
                if ev.get("type") == "start_kyoku":
                    renchan = (
                        int(ev["oya"]) == table.oya
                        and int(ev["kyoku"]) == table.kyoku
                        and str(ev["bakaze"]) == table.bakaze
                    )
                    next_table = meta_from_start_kyoku(ev, table.scores)
                    break
            if next_table is None:
                if should_end_hanchan(table, renchan=False):
                    return None, True, kyoku_tags
                raise AssertionError(
                    f"seed={seed} end_kyoku but no next start_kyoku: trailing={trailing!r}"
                )
            if should_end_hanchan(table, renchan=renchan):
                return None, True, kyoku_tags
            return next_table, False, kyoku_tags

        c_cmp = c_rest[c_i : c_i + need]
        c_i += need
        ok, msg = events_equal(o_cmp, c_cmp)
        if not ok:
            raise AssertionError(
                f"seed={seed} kyoku_i={kyoku_i} step={si} event mismatch: {msg}\n"
                f"oracle={o_cmp}\ncore={c_cmp}"
            )
        if verbose:
            print(f"seed={seed} step={si} ok", flush=True)

    if c_i != len(c_rest):
        raise AssertionError(
            f"seed={seed} leftover core events: {c_rest[c_i:]!r}"
        )
    return None, True, kyoku_tags


def run_one(
    seed: int,
    exe: Path | None = None,
    verbose: bool = False,
    *,
    core: CoreEngine | None = None,
) -> set[str]:
    oracle = RiichiEngine()
    own_core = core is None
    eng = core or CoreEngine(exe)
    tags: set[str] = set()
    try:
        table: Table | None = Table()
        kyoku_i = 0
        while table is not None:
            table, ended, kyoku_tags = run_kyoku(
                seed=seed,
                kyoku_i=kyoku_i,
                table=table,
                oracle=oracle,
                core=eng,
                verbose=verbose,
            )
            tags |= kyoku_tags
            if ended or table is None:
                if verbose:
                    print(f"seed={seed} PASS kyokus={kyoku_i + 1}", flush=True)
                return tags
            kyoku_i += 1
            if kyoku_i > 16:
                raise RuntimeError(f"seed={seed} too many kyokus")
        return tags
    finally:
        if own_core:
            eng.close()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Diff mahmah core vs riichienv")
    p.add_argument("--seeds", type=int, default=1)
    p.add_argument("--base-seed", type=int, default=0)
    p.add_argument("--exe", type=Path, default=None)
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument(
        "--no-coverage",
        action="store_true",
        help="不写本次覆盖报告",
    )
    args = p.parse_args(argv)

    exe = args.exe or default_mjai_diff_path()
    failed = 0
    seed_tags: dict[int, set[str]] = {}
    core = CoreEngine(exe)
    try:
        for i in range(args.seeds):
            seed = args.base_seed + i
            try:
                seed_tags[seed] = run_one(seed, exe=exe, verbose=args.verbose, core=core)
                print(f"OK seed={seed}")
            except Exception as e:
                failed += 1
                print(f"FAIL seed={seed}: {e}", file=sys.stderr)
                if args.seeds == 1:
                    raise
    finally:
        core.close()

    if not args.no_coverage and seed_tags:
        path = write_latest_report(
            seed_tags,
            base_seed=args.base_seed,
            n_seeds=args.seeds,
            failed=failed,
        )
        print(f"coverage → {path}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
