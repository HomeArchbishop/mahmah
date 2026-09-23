"""补齐 checklist 缺口的场景（默认套件启用）。"""
from __future__ import annotations

from riichienv import ActionType

from .delay import delay_tsumo
from .runner import Scenario, Script
from .util import fill_hand, remaining_hands
from .wall import LIVE_LEN, ban_from_live_except, build_wall, force_slots, quarantine_live

_NO_CALL = {
    ActionType.RIICHI: 50,
    ActionType.CHI: 50,
    ActionType.PON: 50,
    ActionType.ANKAN: 50,
    ActionType.DAIMINKAN: 50,
    ActionType.KAKAN: 50,
}


def _sc(sid, desc, tags, wall, **kw) -> Scenario:
    return Scenario(id=sid, desc=desc, expect_tags=frozenset(tags), wall=wall, **kw)


def _noten_hand(pool: list[str]) -> list[str]:
    return fill_hand([], 13, pool)


def _tsumogiri_keep(keep: set[str] | None = None, *, hora_seats: set[int] | None = None):
    """摸切；保留 keep 中的牌；仅 hora_seats 允许和。"""

    def pick(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if "hora" in types:
            if hora_seats is None or seat in hora_seats:
                return next(a for a in legals if a.get("type") == "hora")
            if "none" in types:
                return next(a for a in legals if a.get("type") == "none")
        for a in legals:
            if a.get("type") == "dahai" and a.get("tsumogiri"):
                if keep and a.get("pai") in keep:
                    continue
                return a
        for a in legals:
            if a.get("type") == "dahai" and (not keep or a.get("pai") not in keep):
                return a
        if "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        return None

    return pick


def scenario_kakan() -> Scenario:
    hand0 = ["5mr", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    hand1 = ["5m", "5m", "2m", "3m", "4m", "6m", "7m", "8m", "2s", "3s", "4s", "6s", "7s"]
    reserved = hand0 + hand1 + ["8m", "9s", "8s", "7s", "5m", "C", "9p"]
    h2, h3, _ = remaining_hands(reserved)
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, h2, h3],
        first_tsumo="8m",
        live_draws=["9s", "8s", "7s", "5m"],
        rinshan=["9p"],
        dora_markers=["C"],
    )
    return _sc(
        "kakan",
        "加杠",
        {"call.pon", "call.kakan", "meta.dora_flip"},
        wall,
        script=Script(
            discard_queues={0: ["5mr"]},
            prefer_types=["pon", "kakan"],
            force_pass_response=True,
            never_hora=True,
            boost={ActionType.CHI: 50, ActionType.RIICHI: 50},
        ),
    )


def scenario_riichi() -> Scenario:
    """南先摸切废牌，第二巡立直，西打 8p 放铳。"""
    hand0 = ["1m", "3m", "5m", "7m", "9m", "1p", "3p", "5p", "7p", "9p", "1s", "3s", "5s"]
    hand1 = ["2p", "2p", "3p", "3p", "4p", "4p", "5p", "5p", "6p", "6p", "7p", "7p", "8p"]
    hand2 = ["8p", "1s", "1s", "1s", "2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s"]
    h3 = ["9m", "9m", "9p", "9p", "9s", "9s", "E", "E", "S", "S", "W", "W", "N"]
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, h3],
        first_tsumo="6m",
        live_draws=["7m", "5s", "6s", "8s", "2m", "3m"],
        dora_markers=["C"],
        ura_markers=["1p"],
    )
    st = {"discarded": False, "reach": False}

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if "hora" in types:
            return next(a for a in legals if a.get("type") == "hora")
        if seat == 1:
            if not st["discarded"] and "dahai" in types:
                for a in legals:
                    if a.get("type") == "dahai" and a.get("pai") == "7m":
                        st["discarded"] = True
                        return a
            if st["discarded"] and not st["reach"] and "reach" in types:
                st["reach"] = True
                return next(a for a in legals if a.get("type") == "reach")
            if st["reach"] and "dahai" in types:
                for a in legals:
                    if a.get("type") == "dahai" and a.get("tsumogiri"):
                        return a
                for a in legals:
                    if a.get("type") == "dahai" and a.get("pai") != "8p":
                        return a
        if seat == 2 and "dahai" in types:
            if st["reach"]:
                for a in legals:
                    if a.get("type") == "dahai" and a.get("pai") == "8p":
                        return a
            for a in legals:
                if a.get("type") == "dahai" and a.get("pai") != "8p":
                    return a
        # 其他人一律过鸣/不立直，摸切
        if "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        for a in legals:
            if a.get("type") == "dahai" and a.get("tsumogiri"):
                return a
        return None

    return _sc(
        "riichi",
        "立直",
        {"yaku.riichi", "reach.declare", "reach.accepted", "hora.ron", "hora.with_ura", "yaku.ura"},
        wall,
        script=Script(
            discard_queues={0: ["6m"]},
            custom=custom,
            boost={ActionType.CHI: 50, ActionType.PON: 50, ActionType.RIICHI: 50},
        ),
    )


def scenario_reach_ankan() -> Scenario:
    # 三暗刻形听 2s；立直后摸第 4 张 1m 暗杠（听口不变）
    hand0 = ["1m", "1m", "1m", "3p", "3p", "3p", "5p", "5p", "5p", "7p", "7p", "7p", "2s"]
    reserved = hand0 + ["8s", "3m", "4m", "6m", "1m", "C", "F", "3s", "2s", "2s", "2s"]
    h1, h2, h3 = remaining_hands(reserved)
    wall = build_wall(
        oya=0,
        hands=[hand0, h1, h2, h3],
        first_tsumo="8s",
        live_draws=["3m", "4m", "6m", "1m"],
        dora_markers=["C"],
        ura_markers=["F"],
        rinshan=["3s"],
    )
    # 禁活山 2s，避免立直后被人打入听牌张导致 furiten/应手分歧
    wall = ban_from_live_except(wall, "2s", -1)
    return _sc(
        "reach_ankan",
        "立直后暗杠",
        {"reach.declare", "reach.accepted", "reach.ankan", "call.ankan"},
        wall,
        script=Script(
            discard_queues={0: ["8s"]},
            prefer_types=["ankan", "reach"],
            never_hora=True,
            force_pass_response=True,
            boost={ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_toitoi() -> Scenario:
    """南切 2m → 东碰 → 东再摸 6p 自摸对对。"""
    hand0 = ["2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "5p", "5p", "6p", "7p"]
    hand1 = ["2m", "1s", "1s", "1s", "2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s"]
    h2, h3, _ = remaining_hands(hand0 + hand1 + ["8m", "9m", "7s", "8s", "1p", "6p", "C"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, h2, h3],
        first_tsumo="8m",
        live_draws=["9m", "7s", "8s", "1p", "6p"],
        dora_markers=["C"],
    )
    st = {"ponned": False}

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if seat == 0 and "pon" in types and not st["ponned"]:
            st["ponned"] = True
            return next(a for a in legals if a.get("type") == "pon")
        if seat == 0 and "hora" in types:
            return next(a for a in legals if a.get("type") == "hora")
        if seat == 1 and "dahai" in types and not st["ponned"]:
            for a in legals:
                if a.get("type") == "dahai" and a.get("pai") == "2m":
                    return a
        if "hora" in types and "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        if "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        return _tsumogiri_keep({"3m", "4m", "5p", "6p"})(engine, seat, legals)

    return _sc(
        "toitoi",
        "对对和",
        {"yaku.toitoi", "call.pon", "hora.tsumo"},
        wall,
        script=Script(
            discard_queues={0: ["8m", "7p"]},
            custom=custom,
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_honroutou() -> Scenario:
    # 碰 1m 后切 E，单骑听 S
    hand0 = ["1m", "1m", "9m", "9m", "9m", "1p", "1p", "1p", "9s", "9s", "9s", "S", "E"]
    hand1 = ["1m", "2p", "3p", "4p", "5p", "6p", "7p", "2s", "3s", "4s", "5s", "6s", "7s"]
    h2, h3, _ = remaining_hands(hand0 + hand1 + ["8m", "7m", "8p", "2p", "4p", "S", "C"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, h2, h3],
        first_tsumo="8m",
        live_draws=["7m", "8p", "2p", "4p", "S"],
        dora_markers=["C"],
    )
    st = {"ponned": False}

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if seat == 0 and "pon" in types and not st["ponned"]:
            st["ponned"] = True
            return next(a for a in legals if a.get("type") == "pon")
        if seat == 0 and "hora" in types:
            return next(a for a in legals if a.get("type") == "hora")
        if seat == 1 and "dahai" in types and not st["ponned"]:
            for a in legals:
                if a.get("type") == "dahai" and a.get("pai") == "1m":
                    return a
        if "hora" in types and "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        if "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        return _tsumogiri_keep({"9m", "1p", "9s", "S"})(engine, seat, legals)

    return _sc(
        "honroutou",
        "混老头",
        {"yaku.honroutou", "call.pon", "hora.tsumo"},
        wall,
        script=Script(
            discard_queues={0: ["8m", "E"]},
            custom=custom,
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_chuuren() -> Scenario:
    # 1112234567899 听 9，摸 9 → 普通九莲（非九面听）
    h0 = ["1m", "1m", "1m", "2m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "9m"]
    wall = build_wall(
        oya=0,
        hands=[h0, *remaining_hands(h0 + ["1p", "4s", "N", "W", "9m", "C"])],
        first_tsumo="1p",
        live_draws=["4s", "N", "W", "9m"],
        dora_markers=["C"],
    )
    return _sc(
        "chuuren",
        "九莲宝灯",
        {"yaku.chuuren", "hora.tsumo"},
        wall,
        script=delay_tsumo("1p"),
    )


def scenario_sankantsu() -> Scenario:
    hand0 = ["1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4p", "5p", "6p", "7p"]
    others = remaining_hands(hand0 + ["1m", "2m", "3m", "7p", "C"])
    wall = build_wall(
        oya=0,
        hands=[hand0, *others],
        first_tsumo="1m",
        rinshan=["2m", "3m", "7p"],
        dora_markers=["C"],
    )
    return _sc(
        "sankantsu",
        "三杠子",
        {"yaku.sankantsu", "call.ankan", "hora.tsumo"},
        wall,
        script=Script(prefer_types=["ankan", "hora"], boost={ActionType.RIICHI: 50}),
    )


def scenario_chankan() -> Scenario:
    """西切 5mr → 东碰 → 东摸 5m 加杠 → 南两面听 5 抢杠。"""
    hand0 = ["5m", "5m", "1p", "2p", "3p", "4p", "6p", "7p", "8p", "1s", "2s", "3s", "4s"]
    hand1 = ["3m", "4m", "6s", "6s", "6s", "7s", "7s", "7s", "8s", "8s", "8s", "9s", "9s"]
    hand2 = ["5mr", "9m", "9m", "9m", "9p", "9p", "9p", "E", "E", "E", "S", "S", "S"]
    h3, _, __ = remaining_hands(hand0 + hand1 + hand2 + ["8p", "N", "F", "W", "P", "C", "5m", "1m", "2p"])
    # 碰后：南/西/北/东摸 5m
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, h3],
        first_tsumo="8p",
        live_draws=["N", "F", "W", "P", "C", "5m"],
        dora_markers=["1m"],
        rinshan=["2p"],
    )

    st = {"kakan": False}

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if seat == 0 and "kakan" in types:
            st["kakan"] = True
            return next(a for a in legals if a.get("type") == "kakan")
        if "hora" in types:
            if seat == 1 and st["kakan"]:
                return next(a for a in legals if a.get("type") == "hora")
            if "none" in types:
                return next(a for a in legals if a.get("type") == "none")
        if seat == 0 and "pon" in types:
            hits = [a for a in legals if a.get("type") == "pon" and a.get("pai") == "5mr"]
            if hits:
                return hits[0]
        if seat == 2 and "dahai" in types:
            for a in legals:
                if a.get("type") == "dahai" and a.get("pai") == "5mr":
                    return a
        if "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        return _tsumogiri_keep({"3m", "4m"})(engine, seat, legals)

    return _sc(
        "chankan",
        "抢杠",
        {"yaku.chankan", "call.kakan", "hora.ron"},
        wall,
        script=Script(
            discard_queues={0: ["8p"]},
            custom=custom,
            boost={ActionType.CHI: 50, ActionType.RIICHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_haitei() -> Scenario:
    # 七对听 8p（单听），末张自摸 → 避免两面形误听其它牌
    hand1 = ["1p", "1p", "2p", "2p", "3p", "3p", "4p", "4p", "5p", "5p", "6p", "6p", "8p"]
    h0, h2, h3 = remaining_hands(hand1 + ["8s", "8p", "C"])
    wall = build_wall(oya=0, hands=[h0, hand1, h2, h3], first_tsumo="8s", dora_markers=["C"])
    last = LIVE_LEN - 1
    wall = force_slots(wall, {last: "8p"})
    wall = ban_from_live_except(wall, "8p", last)

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        live_left = max(0, len(engine.env.wall) - 14)
        if "hora" in types:
            if seat == 1 and live_left == 0:
                return next(a for a in legals if a.get("type") == "hora")
            if "none" in types:
                return next(a for a in legals if a.get("type") == "none")
        keep = {"1p", "2p", "3p", "4p", "5p", "6p", "8p"}
        return _tsumogiri_keep(keep, hora_seats=set())(engine, seat, legals)

    return _sc(
        "haitei",
        "海底摸月",
        {"yaku.haitei", "hora.tsumo"},
        wall,
        script=Script(
            force_pass_response=True,
            custom=custom,
            boost={**_NO_CALL, ActionType.RON: 90},
        ),
    )


def scenario_houtei() -> Scenario:
    # 东两面听 5/8：同上万子；南末巡切 8m
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "5m", "6m", "6m", "7m", "7m"]
    hand1 = ["8m", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    h2, h3, _ = remaining_hands(hand0 + hand1 + ["8s", "1s", "C"])
    wall = build_wall(oya=0, hands=[hand0, hand1, h2, h3], first_tsumo="8s", dora_markers=["C"])
    last = LIVE_LEN - 1
    wall = ban_from_live_except(wall, "5m", -1)
    wall = ban_from_live_except(wall, "5mr", -1)
    wall = ban_from_live_except(wall, "8m", -1)
    wall = force_slots(wall, {last: "1s"})
    wall = ban_from_live_except(wall, "1s", last)

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if "hora" in types:
            if seat == 0:
                return next(a for a in legals if a.get("type") == "hora")
            if "none" in types:
                return next(a for a in legals if a.get("type") == "none")
        if seat == 1 and "dahai" in types:
            if any(a.get("type") == "dahai" and a.get("tsumogiri") and a.get("pai") == "1s" for a in legals):
                for a in legals:
                    if a.get("type") == "dahai" and a.get("pai") == "8m":
                        return a
        keep = {"2m", "3m", "4m", "5m", "6m", "7m"} if seat == 0 else ({"8m"} if seat == 1 else None)
        return _tsumogiri_keep(keep, hora_seats={0})(engine, seat, legals)

    return _sc(
        "houtei",
        "河底捞鱼",
        {"yaku.houtei", "hora.ron"},
        wall,
        script=Script(
            force_pass_response=True,
            custom=custom,
            boost={**_NO_CALL},
        ),
    )


def scenario_exhaustive_noten() -> Scenario:
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    h1, h2, h3 = remaining_hands(hand0 + ["9p", "8s"])
    wall = build_wall(oya=0, hands=[hand0, h1, h2, h3], first_tsumo="9p", dora_markers=["8s"])
    wall = ban_from_live_except(wall, "8m", -1)

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        # 绝不和；应手一律过
        if "none" in types:
            return next(a for a in legals if a.get("type") == "none")
        for a in legals:
            if a.get("type") == "dahai" and a.get("tsumogiri"):
                if seat == 0 and a.get("pai") == "8m":
                    continue
                return a
        for a in legals:
            if a.get("type") == "dahai" and not (seat == 0 and a.get("pai") == "8m"):
                return a
        return None

    return _sc(
        "exhaustive_noten",
        "荒牌听牌罚符",
        {"ryukyoku.exhaustive_draw", "ryukyoku.noten"},
        wall,
        expect_ryukyoku_reason="exhaustive_draw",
        script=Script(
            never_hora=True,
            force_pass_response=True,
            custom=custom,
            boost={**_NO_CALL, ActionType.KAKAN: 50},
        ),
    )


def all_gap_scenarios() -> list[Scenario]:
    return [
        scenario_kakan(),
        scenario_riichi(),
        scenario_reach_ankan(),
        scenario_toitoi(),
        scenario_honroutou(),
        scenario_chuuren(),
        scenario_sankantsu(),
        scenario_chankan(),
        scenario_haitei(),
        scenario_houtei(),
        scenario_exhaustive_noten(),
    ]
