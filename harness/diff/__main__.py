"""差分入口：seed / scenario / all。"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("--exe", type=Path, default=None)
    p.add_argument("-v", "--verbose", action="store_true")
    p.add_argument("--no-coverage", action="store_true", help="不写本次覆盖报告")


def _cmd_seed(ns: argparse.Namespace) -> int:
    from .seed import main as seed_main

    argv = [
        "--seeds",
        str(ns.seeds),
        "--base-seed",
        str(ns.base_seed),
    ]
    if ns.exe is not None:
        argv += ["--exe", str(ns.exe)]
    if ns.verbose:
        argv.append("-v")
    if ns.no_coverage:
        argv.append("--no-coverage")
    return seed_main(argv)


def _cmd_scenario(ns: argparse.Namespace) -> int:
    from .scenario import (
        all_scenarios,
        get_scenario,
        list_scenario_ids,
        run_scenarios,
    )

    if ns.list:
        print("\n".join(list_scenario_ids()))
        return 0
    scs = [get_scenario(i) for i in ns.ids] if ns.ids else all_scenarios()
    return run_scenarios(
        scs, exe=ns.exe, verbose=ns.verbose, no_coverage=ns.no_coverage
    )


def _cmd_all(ns: argparse.Namespace) -> int:
    """先 scenario 门禁，再 seed 广度。"""
    sc = argparse.Namespace(
        list=False,
        ids=None,
        exe=ns.exe,
        verbose=ns.verbose,
        no_coverage=ns.no_coverage,
    )
    rc_sc = _cmd_scenario(sc)
    rc_seed = _cmd_seed(ns)
    return 1 if (rc_sc or rc_seed) else 0


def _dispatch(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)

    if args and args[0] == "coverage":
        from .coverage import main as coverage_main

        return coverage_main(args[1:])

    p = argparse.ArgumentParser(
        prog="diff",
        description="riichienv ↔ mahmah core 差分",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    seed_p = sub.add_parser("seed", help="随机牌山半庄差分")
    _add_common(seed_p)
    seed_p.add_argument("--seeds", type=int, default=1)
    seed_p.add_argument("--base-seed", type=int, default=0)
    seed_p.set_defaults(func=_cmd_seed)

    sc_p = sub.add_parser("scenario", help="构造场景差分（checklist 门禁）")
    _add_common(sc_p)
    sc_p.add_argument("--id", action="append", dest="ids", default=None)
    sc_p.add_argument("--list", action="store_true", help="列出场景 id")
    sc_p.set_defaults(func=_cmd_scenario)

    all_p = sub.add_parser("all", help="scenario + seed 全量")
    _add_common(all_p)
    all_p.add_argument("--seeds", type=int, default=1)
    all_p.add_argument("--base-seed", type=int, default=0)
    all_p.set_defaults(func=_cmd_all)

    ns = p.parse_args(args)
    return int(ns.func(ns))


raise SystemExit(_dispatch())
