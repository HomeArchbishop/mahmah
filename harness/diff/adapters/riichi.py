"""riichienv 标准侧。"""
from __future__ import annotations

import json
import random
from typing import Any

from riichienv import ActionType, GameType, RiichiEnv, convert

# 压鸣牌 / 立直 / 和了；PASS 垫底
_ACTION_PRIORITY = {
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


def make_wall(seed: int) -> list[int]:
    rng = random.Random(seed)
    wall = list(range(136))
    rng.shuffle(wall)
    return wall


def wall_to_mjai(wall: list[int]) -> list[str]:
    return [convert.tid_to_mjai(t) for t in wall]


def bakaze_to_round_wind(bakaze: str) -> int:
    return {"E": 0, "S": 1, "W": 2, "N": 3}.get(bakaze, 0)


class RiichiEngine:
    def __init__(self) -> None:
        self.env = RiichiEnv(game_mode=GameType.YON_IKKYOKU, seed=0)
        self._log_i = 0
        self._obs: dict[int, Any] = {}

    def load_wall(
        self,
        wall: list[int],
        *,
        oya: int = 0,
        honba: int = 0,
        kyotaku: int = 0,
        scores: list[int] | None = None,
        bakaze: str = "E",
    ) -> list[dict]:
        kw: dict[str, Any] = {
            "wall": wall,
            "oya": oya,
            "honba": honba,
            "kyotaku": kyotaku,
            "round_wind": bakaze_to_round_wind(bakaze),
        }
        if scores is not None:
            kw["scores"] = scores
        self._obs = self.env.reset(**kw)
        self._log_i = 0
        return self.drain_events()

    def drain_events(self) -> list[dict]:
        log = self.env.mjai_log
        evs = log[self._log_i :]
        self._log_i = len(log)
        return list(evs)

    def seats_needing_action(self) -> list[int]:
        return sorted(self._obs.keys())

    def legal_mjai(self, seat: int) -> list[dict]:
        obs = self._obs.get(seat)
        if obs is None:
            return []
        return [self._action_to_mjai(a) for a in obs.legal_actions()]

    def step(self, actions: dict[int, dict]) -> list[dict]:
        mapped: dict[int, Any] = {}
        for seat, mjai in actions.items():
            obs = self._obs[seat]
            payload = dict(mjai)
            payload.setdefault("actor", seat)
            probe = (
                {k: v for k, v in payload.items() if k != "tsumogiri"}
                if payload.get("type") == "dahai"
                else payload
            )
            act = obs.select_action_from_mjai(probe)
            if act is None:
                act = obs.select_action_from_mjai(payload)
            if act is None:
                raise RuntimeError(f"riichienv cannot select action for seat {seat}: {payload}")
            mapped[seat] = act
        self._obs = self.env.step(mapped)
        return self.drain_events()

    def done(self) -> bool:
        return self.env.done()

    def pick_action(self, seat: int, *, priority: dict | None = None) -> dict:
        """固定优先级：和 > 立直 > 碰/杠 > 吃 > 切 > 流 > 过。同级按 mjai 字典序。"""
        obs = self._obs[seat]
        acts = list(obs.legal_actions())
        if not acts:
            raise RuntimeError(f"no legal actions for seat {seat}")
        pri_map = priority or _ACTION_PRIORITY

        def sort_key(a) -> tuple:
            pri = pri_map.get(a.action_type, 15)
            mjai = self._action_to_mjai(a)
            # 去掉 actor 再序列化，保证稳定
            slim = {k: v for k, v in mjai.items() if k != "actor"}
            return (pri, json.dumps(slim, sort_keys=True, ensure_ascii=False))

        return self._action_to_mjai(min(acts, key=sort_key))

    def _action_to_mjai(self, action) -> dict:
        raw = action.to_mjai()
        mjai = json.loads(raw) if isinstance(raw, str) else dict(raw)
        if action.action_type == ActionType.DISCARD:
            drawn = self.env.drawn_tile
            mjai["tsumogiri"] = drawn is not None and action.tile == drawn
        return mjai
