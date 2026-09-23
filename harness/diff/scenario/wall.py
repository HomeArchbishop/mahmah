"""从手牌/摸牌序列构造 riichienv 风格 136 tid 牌山（下标 0=首摸）。"""
from __future__ import annotations

from collections import Counter
from typing import Iterable

from riichienv import convert

LIVE_LEN = 122
WALL_LEN = 136
DEAL_LEN = 52  # 4×13
FIRST_TSUMO_I = 52


def _inventory() -> dict[str, list[int]]:
    inv: dict[str, list[int]] = {}
    for tid in range(WALL_LEN):
        inv.setdefault(convert.tid_to_mjai(tid), []).append(tid)
    return inv


def take(inv: dict[str, list[int]], pai: str) -> int:
    pile = inv.get(pai)
    if not pile:
        raise ValueError(f"tile exhausted: {pai}")
    return pile.pop()


def deal_positions(oya: int) -> list[list[int]]:
    """每位玩家 13 张发牌在 live 墙中的下标（按发牌顺序）。"""
    slots: list[list[int]] = [[] for _ in range(4)]
    pos = 0
    for _ in range(3):
        for i in range(4):
            seat = (oya + i) % 4
            for _k in range(4):
                slots[seat].append(pos)
                pos += 1
    for i in range(4):
        seat = (oya + i) % 4
        slots[seat].append(pos)
        pos += 1
    assert pos == DEAL_LEN
    return slots


def build_wall(
    *,
    oya: int = 0,
    hands: list[list[str]],
    first_tsumo: str,
    live_draws: Iterable[str] | None = None,
    dora_markers: list[str] | None = None,
    ura_markers: list[str] | None = None,
    rinshan: list[str] | None = None,
) -> list[int]:
    """hands: 4×13 mjai；first_tsumo 为亲家首摸；其余 live/死山可省略（用剩余牌填）。"""
    if len(hands) != 4:
        raise ValueError("need 4 hands")
    for s, h in enumerate(hands):
        if len(h) != 13:
            raise ValueError(f"seat {s} hand must be 13, got {len(h)}")

    inv = _inventory()
    wall: list[int | None] = [None] * WALL_LEN

    slots = deal_positions(oya)
    for seat in range(4):
        for pai, idx in zip(hands[seat], slots[seat]):
            wall[idx] = take(inv, pai)

    wall[FIRST_TSUMO_I] = take(inv, first_tsumo)

    next_i = FIRST_TSUMO_I + 1
    for pai in live_draws or ():
        if next_i >= LIVE_LEN:
            raise ValueError("too many live draws")
        wall[next_i] = take(inv, pai)
        next_i += 1

    doras = list(dora_markers or ["5m"])
    uras = list(ura_markers or [])
    rins = list(rinshan or [])
    if len(doras) > 5 or len(uras) > 5 or len(rins) > 4:
        raise ValueError("dead wall overflow")

    # Tenhou paishan 死山：宝指示 131,129,…；里 130,128,…；岭上 135..132
    for i, pai in enumerate(doras):
        wall[131 - 2 * i] = take(inv, pai)
    for i, pai in enumerate(uras):
        wall[130 - 2 * i] = take(inv, pai)
    for i, pai in enumerate(rins):
        wall[135 - i] = take(inv, pai)

    leftovers = [tid for pile in inv.values() for tid in pile]
    for i in range(WALL_LEN):
        if wall[i] is None:
            if not leftovers:
                raise RuntimeError("inventory underflow while padding")
            wall[i] = leftovers.pop()
    if leftovers:
        raise RuntimeError(f"inventory leftover {len(leftovers)}")

    out = [int(t) for t in wall]
    _assert_full_deck(out)
    return out


def _assert_full_deck(wall: list[int]) -> None:
    if len(wall) != WALL_LEN or len(set(wall)) != WALL_LEN:
        raise AssertionError("wall must be a permutation of 0..135")
    got = Counter(convert.tid_to_mjai(t) for t in wall)
    want = Counter(convert.tid_to_mjai(t) for t in range(WALL_LEN))
    if got != want:
        raise AssertionError(f"tile multiset mismatch: {got - want} / {want - got}")


def force_slots(
    wall: list[int],
    slots: dict[int, str],
    *,
    from_indices: Iterable[int] | None = None,
) -> list[int]:
    """通过交换，使 wall[i] 成为指定 mjai（用于海底末张等）。

    默认只从发牌区以外（≥52）取牌，避免抽走已构造的手牌。
    """
    out = list(wall)
    allowed = set(from_indices) if from_indices is not None else set(range(FIRST_TSUMO_I, WALL_LEN))
    for idx, pai in slots.items():
        if convert.tid_to_mjai(out[idx]) == pai:
            continue
        src = next(
            (
                i
                for i in allowed
                if i != idx and convert.tid_to_mjai(out[i]) == pai
            ),
            None,
        )
        if src is None:
            raise ValueError(f"no {pai} to place at {idx} (outside deal)")
        out[idx], out[src] = out[src], out[idx]
    _assert_full_deck(out)
    return out


def ban_from_live_except(wall: list[int], pai: str, keep: int) -> list[int]:
    """live 区（52..121）除 keep 外不得出现 pai；多余的与死山交换（不碰发牌区）。"""
    out = list(wall)
    for i in range(FIRST_TSUMO_I, LIVE_LEN):
        if i == keep:
            continue
        if convert.tid_to_mjai(out[i]) != pai:
            continue
        # 优先与死山中「非 pai」交换；避免把刚隔离的其他牌又换回活山
        src = next(
            (
                j
                for j in range(LIVE_LEN, WALL_LEN)
                if convert.tid_to_mjai(out[j]) != pai
            ),
            None,
        )
        if src is None:
            raise ValueError(f"cannot quarantine {pai} from live")
        out[i], out[src] = out[src], out[i]
    _assert_full_deck(out)
    return out


def quarantine_live(
    wall: list[int],
    banned: dict[str, int],
) -> list[int]:
    """一次性隔离多种牌：banned[pai]=keep 下标（-1 表示全禁）。

    多轮 ban_from_live_except 会把已隔离牌换回活山；此函数只把违例牌换到死山一次。
    """
    out = list(wall)
    offenders: list[int] = []
    for i in range(FIRST_TSUMO_I, LIVE_LEN):
        pai = convert.tid_to_mjai(out[i])
        if pai not in banned:
            continue
        keep = banned[pai]
        if i == keep:
            continue
        offenders.append(i)
    dead_free = [
        j
        for j in range(LIVE_LEN, WALL_LEN)
        if convert.tid_to_mjai(out[j]) not in banned
    ]
    if len(dead_free) < len(offenders):
        raise ValueError(
            f"cannot quarantine {len(offenders)} live tiles: only {len(dead_free)} dead slots"
        )
    for i, j in zip(offenders, dead_free):
        out[i], out[j] = out[j], out[i]
    _assert_full_deck(out)
    return out


def hands_mjai_from_wall(wall: list[int], oya: int) -> list[list[str]]:
    slots = deal_positions(oya)
    return [[convert.tid_to_mjai(wall[i]) for i in slots[s]] for s in range(4)]
