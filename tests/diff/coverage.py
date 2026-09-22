"""覆盖报告：checklist 是条目目录；每次 diff 跑完写最新报告。

- `checklist.yaml`：人工维护 id/group/desc（役种可由 YAKU_CATALOG 补齐）
- `coverage-latest.md`：本次 diff 覆盖了什么、哪个 seed（每次覆盖写）
"""
from __future__ import annotations

import argparse
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

import yaml

from riichienv import ActionType

from .riichi_adapter import RiichiEngine, make_wall

CHECKLIST_PATH = Path(__file__).with_name("checklist.yaml")
LATEST_PATH = Path(__file__).with_name("coverage-latest.md")

# 覆盖扫描：优先打出九种九牌，便于扫到途中流局。
_COVER_PRIORITY = {
    ActionType.RON: 0,
    ActionType.TSUMO: 0,
    ActionType.KYUSHU_KYUHAI: 1,
    ActionType.RIICHI: 2,
    ActionType.PON: 3,
    ActionType.DAIMINKAN: 3,
    ActionType.KAKAN: 3,
    ActionType.ANKAN: 3,
    ActionType.CHI: 4,
    ActionType.DISCARD: 10,
    ActionType.PASS: 20,
}

# riichienv Yaku.id → checklist (id, group, desc)。缺省项由 ensure_yaku_items 自动写入 yaml。
# 跳过 34 抜きドラ（三人麻将）。
YAKU_CATALOG: dict[int, tuple[str, str, str]] = {
    1: ("yaku.menzen_tsumo", "役", "门前清自摸和"),
    2: ("yaku.riichi", "役", "立直"),
    3: ("yaku.chankan", "役", "抢杠"),
    4: ("yaku.rinshan", "役", "岭上开花"),
    5: ("yaku.haitei", "役", "海底摸月"),
    6: ("yaku.houtei", "役", "河底捞鱼"),
    7: ("yaku.haku", "役", "役牌·白"),
    8: ("yaku.hatsu", "役", "役牌·发"),
    9: ("yaku.chun", "役", "役牌·中"),
    10: ("yaku.jikaze", "役", "自风"),
    11: ("yaku.bakaze", "役", "场风"),
    12: ("yaku.tanyao", "役", "断幺九"),
    13: ("yaku.iipeeko", "役", "一杯口"),
    14: ("yaku.pinfu", "役", "平和"),
    15: ("yaku.chanta", "役", "混全带幺九"),
    16: ("yaku.ittsu", "役", "一气通贯"),
    17: ("yaku.sanshoku", "役", "三色同顺"),
    18: ("yaku.double_riichi", "役", "双立直"),
    19: ("yaku.sanshoku_doukou", "役", "三色同刻"),
    20: ("yaku.sankantsu", "役", "三杠子"),
    21: ("yaku.toitoi", "役", "对对和"),
    22: ("yaku.sanankou", "役", "三暗刻"),
    23: ("yaku.shousangen", "役", "小三元"),
    24: ("yaku.honroutou", "役", "混老头"),
    25: ("yaku.chiitoitsu", "役", "七对子"),
    26: ("yaku.junchan", "役", "纯全带幺九"),
    27: ("yaku.honitsu", "役", "混一色"),
    28: ("yaku.ryanpeeko", "役", "二杯口"),
    29: ("yaku.chinitsu", "役", "清一色"),
    30: ("yaku.ippatsu", "役", "一发"),
    31: ("yaku.dora", "宝牌", "宝牌"),
    32: ("yaku.aka", "宝牌", "赤宝牌"),
    33: ("yaku.ura", "宝牌", "里宝牌"),
    35: ("yaku.tenhou", "役满", "天和"),
    36: ("yaku.chiihou", "役满", "地和"),
    37: ("yaku.daisangen", "役满", "大三元"),
    38: ("yaku.suuankou", "役满", "四暗刻"),
    39: ("yaku.tsuuiisou", "役满", "字一色"),
    40: ("yaku.ryuuiisou", "役满", "绿一色"),
    41: ("yaku.chinroutou", "役满", "清老头"),
    42: ("yaku.kokushi", "役满", "国士无双"),
    43: ("yaku.shousuushii", "役满", "小四喜"),
    44: ("yaku.suukantsu", "役满", "四杠子"),
    45: ("yaku.chuuren", "役满", "九莲宝灯"),
    47: ("yaku.junsei_chuuren", "役满", "纯正九莲宝灯"),
    48: ("yaku.suuankou_tanki", "役满", "四暗刻单骑"),
    49: ("yaku.kokushi_13", "役满", "国士无双十三面"),
    50: ("yaku.daisuushii", "役满", "大四喜"),
}


def load_checklist(path: Path = CHECKLIST_PATH) -> dict[str, Any]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or "items" not in data:
        raise ValueError(f"bad checklist: {path}")
    ensure_yaku_items(data)
    return data


def ensure_yaku_items(data: dict[str, Any]) -> int:
    """把 YAKU_CATALOG 缺的条目追加进 checklist（不改已有 desc/seeds）。"""
    have = {it["id"] for it in data["items"]}
    added = 0
    for _yid, (cid, group, desc) in sorted(YAKU_CATALOG.items(), key=lambda x: x[0]):
        if cid in have:
            continue
        data["items"].append(
            {"id": cid, "group": group, "desc": desc, "count": 0, "seeds": []}
        )
        have.add(cid)
        added += 1
    return added


def tags_from_yaku_ids(yaku_ids: Iterable[int]) -> set[str]:
    tags: set[str] = set()
    for yi in yaku_ids:
        entry = YAKU_CATALOG.get(int(yi))
        if entry is not None:
            tags.add(entry[0])
    return tags


def save_checklist(data: dict[str, Any], path: Path = CHECKLIST_PATH) -> None:
    """只写目录条目（id/group/desc），不存 count/seeds。"""
    lines = [
        "# Diff 覆盖条目目录。",
        "# 人工维护：id / group / desc。",
        "# 役种缺项可由 `python -m diff coverage ensure` 从 YAKU_CATALOG 补齐。",
        "# 每次 diff 的命中报告见 coverage-latest.md（单次最新，不累积）。",
        f"version: {int(data.get('version', 1))}",
        "items:",
    ]
    for it in data["items"]:
        lines.append(f"  - id: {it['id']}")
        lines.append(f"    group: {it['group']}")
        lines.append(f"    desc: {it['desc']}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def known_ids(data: dict[str, Any]) -> set[str]:
    return {it["id"] for it in data["items"]}


def tags_from_events(events: Iterable[dict[str, Any]]) -> set[str]:
    """从半庄（或多局）事件流提取 checklist id。"""
    tags: set[str] = set()
    oya: int | None = None
    honba = 0
    kyotaku = 0
    bakaze = "E"
    prev_oya: int | None = None
    prev_kyoku: int | None = None
    prev_bakaze: str | None = None
    riichi_seats: set[int] = set()

    for ev in events:
        t = ev.get("type")
        if t == "start_kyoku":
            oya = int(ev["oya"])
            honba = int(ev.get("honba", 0))
            kyotaku = int(ev.get("kyotaku", 0))
            bakaze = str(ev.get("bakaze", "E"))
            kyoku = int(ev.get("kyoku", 1))
            riichi_seats = set()
            if honba >= 1:
                tags.add("meta.honba")
            if kyotaku >= 1:
                tags.add("meta.kyotaku")
            if bakaze == "S":
                tags.add("meta.south")
            if (
                prev_oya is not None
                and prev_oya == oya
                and prev_kyoku == kyoku
                and prev_bakaze == bakaze
            ):
                tags.add("meta.renchan")
            prev_oya, prev_kyoku, prev_bakaze = oya, kyoku, bakaze
            continue

        if t == "chi":
            tags.add("call.chi")
        elif t == "pon":
            tags.add("call.pon")
        elif t == "daiminkan":
            tags.add("call.daiminkan")
        elif t == "ankan":
            tags.add("call.ankan")
            actor = int(ev["actor"])
            if actor in riichi_seats:
                tags.add("reach.ankan")
        elif t == "kakan":
            tags.add("call.kakan")
        elif t == "reach":
            tags.add("reach.declare")
        elif t == "reach_accepted":
            tags.add("reach.accepted")
            riichi_seats.add(int(ev["actor"]))
        elif t == "dora":
            tags.add("meta.dora_flip")
        elif t == "hora":
            actor = int(ev["actor"])
            target = int(ev["target"])
            if actor == target:
                tags.add("hora.tsumo")
            else:
                tags.add("hora.ron")
            if oya is not None:
                if actor == oya:
                    tags.add("hora.dealer")
                else:
                    tags.add("hora.child")
            if honba >= 1:
                tags.add("hora.with_honba")
            if kyotaku >= 1:
                tags.add("hora.with_kyotaku")
            ura = ev.get("ura_markers") or []
            if ura:
                tags.add("hora.with_ura")
        elif t == "ryukyoku":
            reason = str(ev.get("reason") or "exhaustive_draw")
            tags.add(f"ryukyoku.{reason}")
            if reason == "exhaustive_draw":
                deltas = ev.get("deltas") or [0, 0, 0, 0]
                if any(int(d) != 0 for d in deltas):
                    tags.add("ryukyoku.noten")

    return tags


def _renchan_after(table, events: list[dict[str, Any]]) -> bool:
    """局终是否连庄（覆盖扫描用启发式，与裁判细则可略有出入）。"""
    hora = next((e for e in events if e.get("type") == "hora"), None)
    if hora is not None:
        return int(hora["actor"]) == table.oya
    ryu = next((e for e in events if e.get("type") == "ryukyoku"), None)
    if ryu is None:
        return False
    reason = str(ryu.get("reason") or "")
    if reason == "exhaustive_draw":
        deltas = ryu.get("deltas") or [0, 0, 0, 0]
        return int(deltas[table.oya]) >= 0
    return True


def _advance_table(table, *, renchan: bool):
    from .leader import Table, should_end_hanchan

    if should_end_hanchan(table, renchan=renchan):
        return None
    if renchan:
        return Table(
            scores=list(table.scores),
            oya=table.oya,
            honba=table.honba + 1,
            kyotaku=table.kyotaku,
            bakaze=table.bakaze,
            kyoku=table.kyoku,
        )
    next_oya = (table.oya + 1) % 4
    if table.bakaze == "E" and table.kyoku == 4:
        bakaze, kyoku = "S", 1
    elif table.bakaze == "S" and table.kyoku == 4:
        return None
    else:
        bakaze = table.bakaze
        kyoku = table.kyoku + 1
    return Table(
        scores=list(table.scores),
        oya=next_oya,
        honba=0,
        kyotaku=table.kyotaku,
        bakaze=bakaze,
        kyoku=kyoku,
    )


def collect_seed_tags(seed: int) -> set[str]:
    """跑 oracle 半庄，返回事件标签 + 役种标签（不差分，供 scan）。"""
    from .leader import (
        Table,
        apply_score_events,
        filter_game_events,
        meta_from_start_kyoku,
    )

    oracle = RiichiEngine()
    table = Table()
    kyoku_i = 0
    all_ev: list[dict[str, Any]] = []
    yaku_tags: set[str] = set()

    while table is not None:
        wall = make_wall(seed * 10007 + kyoku_i)
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
        table = meta_from_start_kyoku(sk, table.scores)
        all_ev.extend(o_ev)

        kyoku_events: list[dict[str, Any]] = list(o_ev)
        while not oracle.done():
            seats = oracle.seats_needing_action()
            if not seats:
                break
            actions = {
                seat: oracle.pick_action(seat, priority=_COVER_PRIORITY) for seat in seats
            }
            o_new = filter_game_events(oracle.step(actions))
            all_ev.extend(o_new)
            kyoku_events.extend(o_new)
            apply_score_events(table, o_new)

            if any(e.get("type") == "hora" for e in o_new):
                for wr in oracle.env.win_results.values():
                    yaku_tags |= tags_from_yaku_ids(wr.yaku)

            if any(e.get("type") == "end_kyoku" for e in o_new):
                renchan = _renchan_after(table, kyoku_events)
                table = _advance_table(table, renchan=renchan)
                break

        kyoku_i += 1
        if kyoku_i > 16:
            break

    return tags_from_events(all_ev) | yaku_tags


def report_from_run(
    seed_tags: dict[int, set[str]],
    catalog: dict[str, Any],
    *,
    base_seed: int,
    n_seeds: int,
    failed: int = 0,
    max_seeds: int = 16,
) -> str:
    """根据本次 diff 的 seed→tags 生成报告（相对 checklist 目录）。"""
    hits: dict[str, list[int]] = {it["id"]: [] for it in catalog["items"]}
    for seed in sorted(seed_tags):
        for tag in seed_tags[seed]:
            if tag in hits:
                hits[tag].append(seed)

    groups: dict[str, list[dict]] = defaultdict(list)
    for it in catalog["items"]:
        groups[it["group"]].append(it)

    covered = sum(1 for sid, seeds in hits.items() if seeds)
    total = len(catalog["items"])
    ok = n_seeds - failed
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    lines = [
        "# Diff coverage（本次）",
        "",
        f"- time: {now}",
        f"- seeds: base={base_seed} n={n_seeds} ok={ok} fail={failed}",
        f"- covered: {covered}/{total}",
        "",
    ]
    for group, items in groups.items():
        lines.append(f"## {group}")
        for it in items:
            seeds = hits[it["id"]]
            mark = "x" if seeds else " "
            if seeds:
                shown = ", ".join(str(s) for s in seeds[:max_seeds])
                more = f" … +{len(seeds) - max_seeds}" if len(seeds) > max_seeds else ""
                seed_part = f" → seed {shown}{more} (n={len(seeds)})"
            else:
                seed_part = ""
            lines.append(f"- [{mark}] `{it['id']}` {it['desc']}{seed_part}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def write_latest_report(
    seed_tags: dict[int, set[str]],
    *,
    base_seed: int,
    n_seeds: int,
    failed: int = 0,
    catalog_path: Path = CHECKLIST_PATH,
    out_path: Path = LATEST_PATH,
) -> Path:
    catalog = load_checklist(catalog_path)
    text = report_from_run(
        seed_tags,
        catalog,
        base_seed=base_seed,
        n_seeds=n_seeds,
        failed=failed,
    )
    out_path.write_text(text, encoding="utf-8")
    sys.stdout.write(text)
    return out_path


def format_report(data: dict[str, Any], *, max_seeds: int = 12) -> str:
    """打印上次 diff 的 coverage-latest.md。"""
    if LATEST_PATH.is_file():
        return LATEST_PATH.read_text(encoding="utf-8")
    return report_from_run({}, data, base_seed=0, n_seeds=0, max_seeds=max_seeds)


def scan_seeds(base: int, n: int) -> dict[int, set[str]]:
    out: dict[int, set[str]] = {}
    for i in range(n):
        seed = base + i
        out[seed] = collect_seed_tags(seed)
    return out


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Diff coverage")
    p.add_argument("--checklist", type=Path, default=CHECKLIST_PATH)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("report", help="打印 coverage-latest.md（上次 diff）")
    sub.add_parser("ensure", help="把缺的役种条目写入 checklist.yaml")

    scan_p = sub.add_parser(
        "scan",
        help="只跑 oracle 扫覆盖（不差分）；写 coverage-latest.md",
    )
    scan_p.add_argument("--seeds", type=int, default=50)
    scan_p.add_argument("--base-seed", type=int, default=0)

    args = p.parse_args(argv)
    data = load_checklist(args.checklist)

    if args.cmd == "report":
        sys.stdout.write(format_report(data))
        return 0

    if args.cmd == "ensure":
        n = ensure_yaku_items(data)
        save_checklist(data, args.checklist)
        print(f"ensure: added {n} yaku items → {args.checklist}")
        return 0

    if args.cmd == "scan":
        seed_tags = scan_seeds(args.base_seed, args.seeds)
        path = write_latest_report(
            seed_tags,
            base_seed=args.base_seed,
            n_seeds=args.seeds,
            catalog_path=args.checklist,
        )
        print(f"scan coverage → {path}", flush=True)
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
