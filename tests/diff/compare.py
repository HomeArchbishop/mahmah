"""MJAI 事件 / 合法着规范化与比较。

仅对多重集字段排序（tehais / consumed），不抹平协议字段差。
"""
from __future__ import annotations

import copy
from typing import Any


def _sort_tehais(tehais: list[list[str]] | None) -> list[list[str]] | None:
    if tehais is None:
        return None
    return [sorted(hand) for hand in tehais]


def normalize_event(ev: dict[str, Any]) -> dict[str, Any]:
    e = copy.deepcopy(ev)
    e.pop("id", None)
    if "tehais" in e:
        e["tehais"] = _sort_tehais(e["tehais"])
    if "consumed" in e and isinstance(e["consumed"], list):
        e["consumed"] = sorted(e["consumed"])
    return e


def events_equal(
    oracle: list[dict[str, Any]],
    under_test: list[dict[str, Any]],
) -> tuple[bool, str]:
    a = [normalize_event(x) for x in oracle]
    b = [normalize_event(x) for x in under_test]
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
