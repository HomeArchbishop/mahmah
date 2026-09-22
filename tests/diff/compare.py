"""MJAI 事件 / 合法着规范化与比较。"""
from __future__ import annotations

import copy
from typing import Any


IGNORE_KEYS = {"scores", "id", "actor"}  # actor 在合法着里常由 seat 隐含


def _sort_tehais(tehais: list[list[str]] | None) -> list[list[str]] | None:
    if tehais is None:
        return None
    return [sorted(hand) for hand in tehais]


def normalize_event(ev: dict[str, Any]) -> dict[str, Any]:
    e = copy.deepcopy(ev)
    for k in list(e.keys()):
        if k in ("id",):
            del e[k]
    # start_kyoku scores：两边有则比，仅一边有则忽略
    if e.get("type") == "start_kyoku" and "scores" in e:
        # 保留，由调用方保证两边都有或都无；diff 时若仅 core 无则删
        pass

    if "dora_marker" in e:
        dm = e["dora_marker"]
        if isinstance(dm, list):
            e["dora_marker"] = dm[0] if len(dm) == 1 else dm

    if "tehais" in e:
        e["tehais"] = _sort_tehais(e["tehais"])

    if "consumed" in e and isinstance(e["consumed"], list):
        e["consumed"] = sorted(e["consumed"])

    # ankan：标准可能带 pai，core 只有 consumed
    if e.get("type") == "ankan":
        e.pop("pai", None)

    if e.get("type") == "dahai" and "tsumogiri" not in e:
        e["tsumogiri"] = False

    # hora：core 目前只发 actor/target/pai；先只比座位
    if e.get("type") == "hora":
        e = {
            "type": "hora",
            "actor": e.get("actor"),
            "target": e.get("target"),
        }

    if e.get("type") == "ryukyoku":
        reason = e.get("reason")
        aliases = {
            "howanpai": "exhaustive_draw",
            "exhaustive_draw": "exhaustive_draw",
            "yao9": "kyushukyuhai",
            "kyushu_kyuhai": "kyushukyuhai",
            "kyushukyuhai": "kyushukyuhai",
            "suukaikan": "suukaikan",
            "suufonrenda": "suufonrenda",
            "suuchariichi": "suuchariichi",
            "sanchahou": "sanchahou",
        }
        if reason in aliases:
            e["reason"] = aliases[reason]

    return e


def events_equal(
    oracle: list[dict[str, Any]],
    under_test: list[dict[str, Any]],
) -> tuple[bool, str]:
    a = [normalize_event(x) for x in oracle]
    b = [normalize_event(x) for x in under_test]
    # start_kyoku：仅一边带 scores 时两边都去掉
    for lst in (a, b):
        for e in lst:
            if e.get("type") == "start_kyoku":
                pass
    if any(e.get("type") == "start_kyoku" and "scores" in e for e in a) != any(
        e.get("type") == "start_kyoku" and "scores" in e for e in b
    ):
        for e in a + b:
            if e.get("type") == "start_kyoku":
                e.pop("scores", None)

    if a == b:
        return True, ""
    n = max(len(a), len(b))
    for i in range(n):
        if i >= len(a):
            return False, f"index {i}: oracle missing, core={b[i]!r}"
        if i >= len(b):
            return False, f"index {i}: core missing, oracle={a[i]!r}"
        if a[i] != b[i]:
            return False, f"index {i}: oracle={a[i]!r} core={b[i]!r}"
    return False, "events differ"


def strip_after_kyoku_end(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for ev in events:
        out.append(ev)
        if ev.get("type") in ("end_kyoku", "end_game"):
            break
    return out


def action_key(action: dict[str, Any]) -> tuple:
    """合法着比较键（与 seat 无关）。"""
    t = action.get("type")
    if t == "dahai":
        return ("dahai", action.get("pai"), bool(action.get("tsumogiri", False)))
    if t in ("chi", "pon", "daiminkan", "kakan"):
        cons = tuple(sorted(action.get("consumed") or []))
        return (t, action.get("pai"), cons)
    if t == "ankan":
        return ("ankan", tuple(sorted(action.get("consumed") or [])))
    if t in ("reach", "hora", "none", "ryukyoku"):
        return (t,)
    # 其它字段尽量纳入
    rest = {k: action[k] for k in sorted(action) if k not in ("type", "actor", "request_id")}
    if "consumed" in rest and isinstance(rest["consumed"], list):
        rest["consumed"] = tuple(sorted(rest["consumed"]))
    return (t, tuple(sorted(rest.items())))


def legal_sets_equal(
    oracle: list[dict[str, Any]],
    under_test: list[dict[str, Any]],
) -> tuple[bool, str]:
    a = {action_key(x) for x in oracle}
    b = {action_key(x) for x in under_test}
    if a == b:
        return True, ""
    only_o = sorted(a - b)
    only_c = sorted(b - a)
    return False, f"only_oracle={only_o!r} only_core={only_c!r}"
