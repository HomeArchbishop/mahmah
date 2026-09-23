"""场景构造小工具。"""
from __future__ import annotations

from collections import Counter

from riichienv import convert


def fill_hand(base: list[str], n: int, pool: list[str]) -> list[str]:
    """从 pool 循环补到 n 张，且单牌不超过牌山上限（5x 非赤最多 3）。"""
    out = list(base)
    used: dict[str, int] = {}
    for p in out:
        used[p] = used.get(p, 0) + 1

    def cap(pai: str) -> int:
        if pai in ("5m", "5p", "5s"):
            return 3
        if pai.endswith("r"):
            return 1
        return 4

    i = 0
    guard = 0
    while len(out) < n:
        pai = pool[i % len(pool)]
        i += 1
        guard += 1
        if used.get(pai, 0) >= cap(pai):
            if guard > n * len(pool) * 4:
                raise ValueError(f"cannot fill to {n} from {pool}")
            continue
        out.append(pai)
        used[pai] = used.get(pai, 0) + 1
    return out[:n]


def dummies(*pools: list[str]) -> list[list[str]]:
    out: list[list[str]] = []
    for i in range(3):
        pool = pools[i] if i < len(pools) else pools[-1]
        out.append(fill_hand([], 13, pool))
    return out


def remaining_hands(*reserved: list[str], n_hands: int = 3) -> list[list[str]]:
    """其余三家用「散幺九」模板，尽量不听牌、不撞 reserved。"""
    inv = Counter(convert.tid_to_mjai(t) for t in range(136))
    for group in reserved:
        for p in group:
            inv[p] -= 1
            if inv[p] < 0:
                raise ValueError(f"over-reserved {p}")

    templates = [
        ["1m", "3m", "5m", "7m", "9m", "1p", "3p", "5p", "7p", "9p", "1s", "3s", "5s"],
        ["2m", "4m", "6m", "8m", "2p", "4p", "6p", "8p", "2s", "4s", "6s", "8s", "E"],
        ["1m", "2m", "4m", "6m", "8m", "1p", "2p", "4p", "6p", "8p", "1s", "2s", "S"],
    ]
    out: list[list[str]] = []
    for tmpl in templates[:n_hands]:
        hand: list[str] = []
        for pai in tmpl:
            if inv[pai] > 0:
                hand.append(pai)
                inv[pai] -= 1
            else:
                # 找任意剩余
                alt = next((k for k, v in inv.items() if v > 0), None)
                if alt is None:
                    raise ValueError("inventory empty while filling dummies")
                hand.append(alt)
                inv[alt] -= 1
        out.append(hand)
    return out
