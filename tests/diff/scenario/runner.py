"""构造场景：固定牌山 + 可选脚本着法，仍走 riichienv↔core 差分。"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable

from riichienv import ActionType

from ..adapters import CoreEngine, RiichiEngine, default_mjai_diff_path, wall_to_mjai
from ..compare import (
    events_equal,
    legal_key_sets_equal,
    strip_after_kyoku_end,
)
from ..coverage import tags_from_events, tags_from_yaku_ids
from ..seed import apply_score_events, filter_game_events, meta_from_start_kyoku

PickFn = Callable[["RiichiEngine", int, list[dict]], dict | None]


@dataclass
class Script:
    """着法覆盖：队列切牌 / 强制流局宣言 / 应手一律过；其余回退默认 priority。"""

    discard_queues: dict[int, list[str]] = field(default_factory=dict)
    prefer_kyushu: bool = False
    always_pass_response: bool = False
    force_pass_response: bool = False
    prefer_riichi: bool = False
    never_hora: bool = False
    # 按顺序尝试匹配的 mjai type（如 "chi","pon","daiminkan","kakan","ankan","hora"）
    prefer_types: list[str] = field(default_factory=list)
    boost: dict[ActionType, int] = field(default_factory=dict)
    custom: PickFn | None = None

    def pick(self, engine: RiichiEngine, seat: int) -> dict:
        legals = engine.legal_mjai(seat)
        if self.custom is not None:
            chosen = self.custom(engine, seat, legals)
            if chosen is not None:
                return chosen

        types = {a.get("type") for a in legals}

        if self.prefer_kyushu and "ryukyoku" in types:
            return next(a for a in legals if a.get("type") == "ryukyoku")

        for want in self.prefer_types:
            hits = [a for a in legals if a.get("type") == want]
            if hits:
                return hits[0]

        if self.force_pass_response and "none" in types:
            return next(a for a in legals if a.get("type") == "none")

        if self.always_pass_response and "none" in types and "hora" not in types:
            return next(a for a in legals if a.get("type") == "none")

        if self.prefer_riichi and "reach" in types:
            return next(a for a in legals if a.get("type") == "reach")

        q = self.discard_queues.get(seat)
        if q and "dahai" in types:
            want = q[0]
            for a in legals:
                if a.get("type") == "dahai" and a.get("pai") == want:
                    q.pop(0)
                    return a

        pri = dict(_DEFAULT_PRIORITY)
        pri.update(self.boost)
        if self.never_hora:
            pri[ActionType.RON] = 90
            pri[ActionType.TSUMO] = 90
        return engine.pick_action(seat, priority=pri)


_DEFAULT_PRIORITY = {
    ActionType.RON: 0,
    ActionType.TSUMO: 0,
    ActionType.RIICHI: 1,
    ActionType.PON: 2,
    ActionType.DAIMINKAN: 2,
    ActionType.KAKAN: 2,
    ActionType.ANKAN: 2,
    ActionType.CHI: 3,
    ActionType.DISCARD: 10,
    ActionType.KYUSHU_KYUHAI: 11,
    ActionType.PASS: 20,
}


@dataclass
class Scenario:
    id: str
    desc: str
    expect_tags: frozenset[str]
    wall: list[int]
    oya: int = 0
    bakaze: str = "E"
    kyoku: int = 1
    honba: int = 0
    kyotaku: int = 0
    scores: list[int] = field(default_factory=lambda: [25000, 25000, 25000, 25000])
    script: Script | None = None
    expect_ryukyoku_reason: str | None = None


def run_scenario(
    sc: Scenario,
    *,
    core: CoreEngine,
    verbose: bool = False,
) -> set[str]:
    """单局差分；返回覆盖 tags。缺 expect_tags / reason 则 AssertionError。"""
    oracle = RiichiEngine()
    script = sc.script or Script()
    wall = sc.wall
    paishan = wall_to_mjai(wall)

    o_start = filter_game_events(
        oracle.load_wall(
            wall,
            oya=sc.oya,
            honba=sc.honba,
            kyotaku=sc.kyotaku,
            scores=list(sc.scores),
            bakaze=sc.bakaze,
        )
    )
    while o_start and o_start[0].get("type") == "start_game":
        o_start = o_start[1:]

    sk = next(e for e in o_start if e.get("type") == "start_kyoku")
    boot = meta_from_start_kyoku(sk, sc.scores)
    table = boot
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
            raise RuntimeError(f"scenario={sc.id} no actors at step {step}")

        legals = {seat: oracle.legal_mjai(seat) for seat in seats}
        oracle_legals.append(legals)
        actions = {seat: script.pick(oracle, seat) for seat in seats}
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

    # 单局模式下补连庄标签：亲家和了后再挂一局同场 start_kyoku
    if "meta.renchan" in sc.expect_tags and "hora.dealer" in kyoku_tags:
        cover_events.append(
            {
                "type": "start_kyoku",
                "oya": sc.oya,
                "kyoku": sc.kyoku,
                "bakaze": sc.bakaze,
                "honba": sc.honba + 1,
                "kyotaku": 0,
                "scores": list(sc.scores),
            }
        )
        kyoku_tags = tags_from_events(cover_events) | yaku_tags

    missing = set(sc.expect_tags) - kyoku_tags
    if missing:
        raise AssertionError(
            f"scenario={sc.id} missing tags {sorted(missing)}; got {sorted(kyoku_tags)}"
        )
    if sc.expect_ryukyoku_reason is not None:
        ryu = next((e for e in cover_events if e.get("type") == "ryukyoku"), None)
        if ryu is None:
            raise AssertionError(f"scenario={sc.id} expected ryukyoku, none found")
        reason = str(ryu.get("reason") or "exhaustive_draw")
        if reason != sc.expect_ryukyoku_reason:
            raise AssertionError(
                f"scenario={sc.id} ryukyoku reason={reason!r} "
                f"want={sc.expect_ryukyoku_reason!r}"
            )

    c_all, step_keys = core.replay_kyoku(
        paishan,
        oya=boot.oya,
        bakaze=boot.bakaze,
        kyoku=sc.kyoku,
        honba=start_honba,
        kyotaku=start_kyotaku,
        scores=start_scores,
        steps=steps,
    )
    c_all = filter_game_events(c_all)

    if not c_all or c_all[0].get("type") != "start_kyoku":
        raise AssertionError(f"scenario={sc.id} core missing start_kyoku: {c_all[:3]!r}")

    o_head = o_start
    c_head = c_all[:2]
    ok, msg = events_equal(o_head, c_head)
    if not ok:
        raise AssertionError(
            f"scenario={sc.id} start mismatch: {msg}\noracle={o_head}\ncore={c_head}"
        )

    if len(step_keys) != len(steps):
        raise AssertionError(
            f"scenario={sc.id} step_legal_keys len {len(step_keys)} != steps {len(steps)}"
        )

    c_rest = c_all[2:]
    c_i = 0
    for si, (legals, o_new) in enumerate(zip(oracle_legals, oracle_step_events)):
        for seat, o_legal in legals.items():
            keys = step_keys[si].get(seat)
            if keys is None:
                raise AssertionError(
                    f"scenario={sc.id} step={si} seat={seat} missing legal_keys"
                )
            ok, msg = legal_key_sets_equal(o_legal, keys)
            if not ok:
                raise AssertionError(
                    f"scenario={sc.id} step={si} seat={seat} legal mismatch: {msg}"
                )

        o_cmp = strip_after_kyoku_end(o_new)
        need = len(o_cmp)
        if any(e.get("type") == "end_kyoku" for e in o_cmp):
            c_seg: list[dict] = []
            while c_i < len(c_rest):
                c_seg.append(c_rest[c_i])
                c_i += 1
                if c_seg[-1].get("type") == "end_kyoku":
                    break
            c_cmp = c_seg
            ok, msg = events_equal(o_cmp, c_cmp)
            if not ok:
                raise AssertionError(
                    f"scenario={sc.id} step={si} event mismatch: {msg}\n"
                    f"oracle={o_cmp}\ncore={c_cmp}"
                )
            if verbose:
                print(f"scenario={sc.id} step={si} ok (kyoku end)", flush=True)
            break

        c_cmp = c_rest[c_i : c_i + need]
        c_i += need
        ok, msg = events_equal(o_cmp, c_cmp)
        if not ok:
            raise AssertionError(
                f"scenario={sc.id} step={si} event mismatch: {msg}\n"
                f"oracle={o_cmp}\ncore={c_cmp}"
            )
        if verbose:
            print(f"scenario={sc.id} step={si} ok", flush=True)

    return kyoku_tags


def run_scenarios(
    scenarios: Iterable[Scenario],
    *,
    exe: Path | None = None,
    verbose: bool = False,
    no_coverage: bool = False,
) -> int:
    exe = exe or default_mjai_diff_path()
    core = CoreEngine(exe)
    failed = 0
    tag_map: dict[str, set[str]] = {}
    try:
        for sc in scenarios:
            try:
                tag_map[sc.id] = run_scenario(sc, core=core, verbose=verbose)
                print(f"OK scenario={sc.id}")
            except Exception as e:
                failed += 1
                print(f"FAIL scenario={sc.id}: {e}", file=__import__("sys").stderr)
    finally:
        core.close()

    if not no_coverage and tag_map:
        # 复用报告：把 scenario id 当作「seed」标签来源键
        # write_latest_report 期望 dict[int,set]；另写 scenario 版
        from ..coverage import LATEST_PATH, load_checklist
        from collections import defaultdict
        from datetime import datetime, timezone

        catalog = load_checklist()
        hits: dict[str, list[str]] = {it["id"]: [] for it in catalog["items"]}
        for sid, tags in tag_map.items():
            for t in tags:
                if t in hits:
                    hits[t].append(sid)
        groups: dict[str, list] = defaultdict(list)
        for it in catalog["items"]:
            groups[it["group"]].append(it)
        covered = sum(1 for v in hits.values() if v)
        total = len(catalog["items"])
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        lines = [
            "# Diff coverage（本次·scenarios）",
            "",
            f"- time: {now}",
            f"- scenarios: n={len(tag_map)} ok={len(tag_map) - failed} fail={failed}",
            f"- covered: {covered}/{total}",
            "",
        ]
        for group, items in groups.items():
            lines.append(f"## {group}")
            for it in items:
                ids = hits[it["id"]]
                mark = "x" if ids else " "
                part = f" → {', '.join(ids)}" if ids else ""
                lines.append(f"- [{mark}] `{it['id']}` {it['desc']}{part}")
            lines.append("")
        text = "\n".join(lines).rstrip() + "\n"
        LATEST_PATH.write_text(text, encoding="utf-8")
        print(text, end="")
        print(f"coverage → {LATEST_PATH}")

    return 1 if failed else 0
