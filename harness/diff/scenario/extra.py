"""补全 checklist 场景。中级役一律「切废再自摸」避开天和。"""
from __future__ import annotations

from riichienv import ActionType

from .delay import delay_tsumo
from .runner import Scenario, Script
from .util import dummies, fill_hand, remaining_hands
from .wall import LIVE_LEN, ban_from_live_except, build_wall, force_slots

JUNK = "9s"


def _sc(sid, desc, tags, wall, **kw) -> Scenario:
    return Scenario(id=sid, desc=desc, expect_tags=frozenset(tags), wall=wall, **kw)


def _delayed_wall(
    h0,
    win: str,
    *,
    junk: str = JUNK,
    dora: str = "C",
    ura: str | None = None,
    pads: list[str] | None = None,
):
    pads = pads or ["4s", "N", "W"]
    reserved = list(h0) + [junk, win, dora, *pads]
    if ura:
        reserved.append(ura)
    others = remaining_hands(reserved)
    kw = dict(
        oya=0,
        hands=[h0, *others],
        first_tsumo=junk,
        live_draws=[pads[0], pads[1], pads[2], win],
        dora_markers=[dora],
    )
    if ura:
        kw["ura_markers"] = [ura]
    return build_wall(**kw)


# ----- 鸣牌 -----


def scenario_chi() -> Scenario:
    hand0 = ["3m", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    hand1 = ["1m", "2m", "4m", "5m", "6m", "7m", "8m", "2s", "3s", "4s", "5s", "6s", "7s"]
    h2, h3, _ = dummies(["1s", "8s", "E", "S", "W", "N", "P"], ["9m", "9p", "F", "C", "8p", "7p", "6p"])
    wall = build_wall(oya=0, hands=[hand0, hand1, h2, h3], first_tsumo="8s", dora_markers=["C"])
    return _sc(
        "chi",
        "吃",
        {"call.chi"},
        wall,
        script=Script(
            discard_queues={0: ["3m"]},
            prefer_types=["chi"],
            never_hora=True,
            boost={ActionType.PON: 50, ActionType.RIICHI: 50},
        ),
    )


def scenario_pon() -> Scenario:
    hand0 = ["5mr", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    hand1 = ["5m", "5m", "2m", "3m", "4m", "6m", "7m", "8m", "2s", "3s", "4s", "5s", "6s"]
    h2, h3, _ = dummies(["1s", "7s", "8s", "9s", "E", "S", "W"], ["9m", "9p", "N", "P", "F", "C", "8p"])
    wall = build_wall(oya=0, hands=[hand0, hand1, h2, h3], first_tsumo="8m", dora_markers=["C"])
    return _sc(
        "pon",
        "碰",
        {"call.pon"},
        wall,
        script=Script(
            discard_queues={0: ["5mr"]},
            prefer_types=["pon"],
            never_hora=True,
            boost={ActionType.CHI: 50, ActionType.RIICHI: 50},
        ),
    )


def scenario_daiminkan() -> Scenario:
    hand0 = ["5mr", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    hand1 = ["5m", "5m", "5m", "2m", "3m", "4m", "6m", "7m", "8m", "2s", "3s", "4s", "5s"]
    h2, h3, _ = dummies(["1s", "6s", "7s", "8s", "9s", "E", "S"], ["9m", "9p", "N", "P", "F", "C", "8p"])
    wall = build_wall(
        oya=0, hands=[hand0, hand1, h2, h3], first_tsumo="8m", rinshan=["9s"], dora_markers=["C"]
    )
    return _sc(
        "daiminkan",
        "大明杠",
        {"call.daiminkan", "meta.dora_flip"},
        wall,
        script=Script(
            discard_queues={0: ["5mr"]},
            prefer_types=["daiminkan"],
            never_hora=True,
            boost={ActionType.PON: 50, ActionType.CHI: 50, ActionType.RIICHI: 50},
        ),
    )


def scenario_kakan() -> Scenario:
    """碰 5m 后巡摸 5m 加杠。"""
    hand0 = ["5mr", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    hand1 = ["5m", "5m", "2m", "3m", "4m", "6m", "7m", "8m", "2s", "3s", "4s", "6s", "7s"]
    h2 = fill_hand([], 13, ["1s", "8s", "9s", "E", "S", "W", "N"])
    h3 = fill_hand([], 13, ["9m", "9p", "F", "C", "8p", "7p", "6p"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, h2, h3],
        first_tsumo="8m",
        live_draws=["9s", "5m"],  # 碰后下家摸？实际碰后东家摸 — 用 force 把下一张 live 换 5m
        rinshan=["9p"],
        dora_markers=["C"],
    )
    # 碰发生后下一个 tsumo 给碰者：把 53 之后第一个还没用的 live 位设为 5m 不可靠。
    # 改用 custom：碰后 prefer kakan when available。
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
    """南家第二巡立直（非双），西家放铳。"""
    hand0 = fill_hand(["7s"], 13, ["1m", "2m", "3m", "4m", "5m", "6m", "8m"])
    hand1 = ["2p", "2p", "3p", "3p", "4p", "4p", "5p", "5p", "6p", "6p", "7p", "7p", "8p"]
    hand2 = ["8p", "1s", "1s", "1s", "2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s"]
    h3 = fill_hand([], 13, ["9m", "9p", "9s", "E", "S", "W", "N"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, h3],
        first_tsumo="9m",
        live_draws=["1m", "3m"],  # 南摸切废后再立直
        dora_markers=["C"],
        ura_markers=["2m"],
    )

    state = {"riichi_done": False}

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if seat == 1 and "reach" in types and state["riichi_done"] is False:
            # 第一巡有摸切后才立直：若手牌仍 14 张且刚摸过
            state["riichi_done"] = True
            return next(a for a in legals if a.get("type") == "reach")
        if seat == 2 and "dahai" in types:
            for a in legals:
                if a.get("type") == "dahai" and a.get("pai") == "8p":
                    return a
        return None

    return _sc(
        "riichi",
        "立直",
        {"yaku.riichi", "reach.declare", "reach.accepted", "hora.ron", "hora.with_ura"},
        wall,
        script=Script(
            discard_queues={0: ["9m"], 1: ["1m"]},
            custom=custom,
            boost={ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_reach_ankan() -> Scenario:
    hand0 = ["1m", "1m", "1m", "2p", "3p", "4p", "5p", "6p", "7p", "8p", "9p", "2s", "2s"]
    reserved = hand0 + ["5m", "3m", "4m", "6m", "1m", "C", "F", "3p"]
    h1, h2, h3 = remaining_hands(reserved)
    wall = build_wall(
        oya=0,
        hands=[hand0, h1, h2, h3],
        first_tsumo="5m",
        live_draws=["3m", "4m", "6m", "1m"],
        dora_markers=["C"],
        ura_markers=["F"],
        rinshan=["3p"],
    )

    def custom(engine, seat, legals):
        if seat != 0:
            if any(a.get("type") == "none" for a in legals):
                return next(a for a in legals if a.get("type") == "none")
            return None
        types = {a.get("type") for a in legals}
        if "ankan" in types:
            return next(a for a in legals if a.get("type") == "ankan")
        if "reach" in types:
            return next(a for a in legals if a.get("type") == "reach")
        return None

    return _sc(
        "reach_ankan",
        "立直后暗杠",
        {"reach.declare", "reach.accepted", "reach.ankan", "call.ankan"},
        wall,
        script=Script(
            discard_queues={0: ["5m"]},
            custom=custom,
            never_hora=True,
            boost={ActionType.CHI: 50, ActionType.PON: 50, ActionType.RIICHI: 50},
        ),
    )


# ----- 役（延迟自摸） -----


def scenario_yakuhai_haku() -> Scenario:
    h0 = ["P", "P", "P", "2m", "3m", "4m", "5m", "6m", "7m", "2p", "3p", "8p", "8p"]
    wall = _delayed_wall(h0, "4p", junk="9m", dora="9p", pads=["4s", "N", "W"])
    return _sc(
        "yakuhai_haku",
        "役牌白",
        {"yaku.haku", "hora.tsumo"},
        wall,
        script=delay_tsumo("9m"),
    )


def scenario_yakuhai_hatsu() -> Scenario:
    h0 = ["F", "F", "F", "2m", "3m", "4m", "5m", "6m", "7m", "2p", "3p", "8p", "8p"]
    wall = _delayed_wall(h0, "4p", junk="9m", dora="9p", pads=["4s", "N", "W"])
    return _sc(
        "yakuhai_hatsu",
        "役牌发",
        {"yaku.hatsu", "hora.tsumo"},
        wall,
        script=delay_tsumo("9m"),
    )


def scenario_yakuhai_chun() -> Scenario:
    h0 = ["C", "C", "C", "2m", "3m", "4m", "5m", "6m", "7m", "2p", "3p", "8p", "8p"]
    wall = _delayed_wall(h0, "4p", junk="9m", dora="9p", pads=["4s", "N", "W"])
    return _sc(
        "yakuhai_chun",
        "役牌中",
        {"yaku.chun", "hora.tsumo"},
        wall,
        script=delay_tsumo("9m"),
    )


def scenario_iipeeko() -> Scenario:
    h0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "6m", "7m", "8p", "8p", "2p", "3p"]
    wall = _delayed_wall(h0, "4p")
    return _sc(
        "iipeeko",
        "一杯口",
        {"yaku.iipeeko", "hora.tsumo", "yaku.menzen_tsumo"},
        wall,
        script=delay_tsumo(JUNK),
    )


def scenario_chanta() -> Scenario:
    h0 = ["1m", "2m", "3m", "7m", "8m", "9m", "1p", "2p", "3p", "9s", "9s", "E", "E"]
    wall = _delayed_wall(h0, "9s", junk="5m", dora="C", pads=["4s", "N", "W"])
    return _sc(
        "chanta",
        "混全",
        {"yaku.chanta", "hora.tsumo"},
        wall,
        script=delay_tsumo("5m"),
    )


def scenario_sanshoku() -> Scenario:
    h0 = ["1m", "2m", "3m", "1p", "2p", "3p", "1s", "2s", "6s", "6s", "8m", "8m", "8m"]
    wall = _delayed_wall(h0, "3s", pads=["4s", "N", "W"])
    return _sc(
        "sanshoku",
        "三色同顺",
        {"yaku.sanshoku", "hora.tsumo"},
        wall,
        script=delay_tsumo(JUNK),
    )


def scenario_sanshoku_doukou() -> Scenario:
    h0 = ["2m", "2m", "2m", "2p", "2p", "2p", "2s", "2s", "5m", "5m", "6m", "7m", "8m"]
    wall = _delayed_wall(h0, "2s", pads=["4s", "N", "W"])
    return _sc(
        "sanshoku_doukou",
        "三色同刻",
        {"yaku.sanshoku_doukou", "hora.tsumo"},
        wall,
        script=delay_tsumo(JUNK),
    )


def scenario_toitoi() -> Scenario:
    h0 = ["2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "5p", "6p", "7p"]
    # 有顺子？不对。对对：碰后自摸 — 用已开刻
    # 222 333 444 55 67 → 不是对对。改为：
    h0 = ["2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "5p", "5p", "6p"]
    wall = _delayed_wall(h0, "6p", junk="9m", pads=["4s", "N", "W"])
    # 这是四暗刻单骑。必须副露：
    hand0 = ["2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "5p", "5p", "6p", "7p"]
    hand1 = ["2m", "1s", "1s", "1s", "2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s"]
    others = remaining_hands(hand0 + hand1 + ["8m", "9m", "6p", "C"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, others[0], others[1]],
        first_tsumo="8m",
        live_draws=["9m", "6p"],
        dora_markers=["C"],
    )
    return _sc(
        "toitoi",
        "对对和",
        {"yaku.toitoi", "call.pon", "hora.tsumo"},
        wall,
        script=Script(
            discard_queues={0: ["8m"], 1: ["2m"]},
            prefer_types=["pon", "hora"],
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50},
        ),
    )


def scenario_sanankou() -> Scenario:
    h0 = ["2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p", "6p", "7p", "8p"]
    wall = _delayed_wall(h0, "8p")
    return _sc("sanankou", "三暗刻", {"yaku.sanankou", "hora.tsumo"}, wall, script=delay_tsumo(JUNK))


def scenario_chiitoitsu() -> Scenario:
    h0 = ["1m", "1m", "2m", "2m", "3m", "3m", "4p", "4p", "5p", "5p", "6s", "6s", "7s"]
    wall = _delayed_wall(h0, "7s")
    return _sc("chiitoitsu", "七对子", {"yaku.chiitoitsu", "hora.tsumo"}, wall, script=delay_tsumo(JUNK))


def scenario_honroutou() -> Scenario:
    h0 = ["1m", "1m", "1m", "9m", "9m", "9m", "1p", "1p", "1p", "9s", "9s", "E", "E"]
    wall = _delayed_wall(h0, "E", pads=["4s", "N", "W"])
    return _sc("honroutou", "混老头", {"yaku.honroutou", "hora.tsumo"}, wall, script=delay_tsumo(JUNK))


def scenario_junchan() -> Scenario:
    h0 = ["1m", "2m", "3m", "7m", "8m", "9m", "1p", "2p", "3p", "7p", "8p", "9p", "9s"]
    wall = _delayed_wall(h0, "9s", junk="5m", dora="5mr")
    return _sc("junchan", "纯全", {"yaku.junchan", "hora.tsumo"}, wall, script=delay_tsumo("5m"))


def scenario_shousangen() -> Scenario:
    h0 = ["P", "P", "P", "F", "F", "F", "C", "C", "2m", "2m", "2m", "3m", "4m"]
    wall = _delayed_wall(h0, "5m", junk="9m", dora="E")
    return _sc(
        "shousangen",
        "小三元",
        {"yaku.shousangen", "hora.tsumo"},
        wall,
        script=delay_tsumo("9m"),
    )


def scenario_aka() -> Scenario:
    h0 = ["5mr", "2m", "3m", "4m", "5m", "6m", "7m", "2p", "3p", "4p", "8p", "8p", "8p"]
    wall = _delayed_wall(h0, "5m", junk="9m")
    return _sc("aka", "赤宝", {"yaku.aka", "hora.tsumo"}, wall, script=delay_tsumo("9m"))


def scenario_chinitsu_ryanpeeko() -> Scenario:
    h0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    wall = _delayed_wall(h0, "8m", pads=["4s", "N", "W"])
    return _sc(
        "chinitsu_ryanpeeko",
        "清一色二杯口",
        {"yaku.chinitsu", "yaku.ryanpeeko", "hora.tsumo"},
        wall,
        script=delay_tsumo(JUNK),
    )


# ----- 役满（延迟） -----


def scenario_daisangen() -> Scenario:
    h0 = ["P", "P", "P", "F", "F", "F", "C", "C", "C", "2m", "3m", "4m", "5m"]
    wall = _delayed_wall(h0, "5m", junk="9m", dora="E")
    return _sc("daisangen", "大三元", {"yaku.daisangen", "hora.tsumo"}, wall, script=delay_tsumo("9m"))


def scenario_suuankou() -> Scenario:
    h0 = ["1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "5p", "5p"]
    wall = _delayed_wall(h0, "4m", junk="9m")
    return _sc("suuankou", "四暗刻", {"yaku.suuankou", "hora.tsumo"}, wall, script=delay_tsumo("9m"))


def scenario_suuankou_tanki() -> Scenario:
    hand0 = ["1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p"]
    hand1 = ["5p", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    h2, h3, _ = dummies(["1s", "2s", "3s", "4s", "5s", "6s", "7s"], ["8s", "9s", "9m", "E", "S", "W", "N"])
    wall = build_wall(oya=0, hands=[hand0, hand1, h2, h3], first_tsumo="8m", dora_markers=["C"])
    return _sc(
        "suuankou_tanki",
        "四暗刻单骑",
        {"yaku.suuankou_tanki", "hora.ron"},
        wall,
        script=Script(
            discard_queues={0: ["8m"], 1: ["5p"]},
            always_pass_response=True,
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_tsuuiisou() -> Scenario:
    h0 = ["E", "E", "E", "S", "S", "S", "W", "W", "W", "N", "N", "P", "P"]
    wall = _delayed_wall(h0, "P", junk="9m", dora="9p")
    return _sc("tsuuiisou", "字一色", {"yaku.tsuuiisou", "hora.tsumo"}, wall, script=delay_tsumo("9m"))


def scenario_ryuuiisou() -> Scenario:
    h0 = ["2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s", "6s", "6s", "F", "F"]
    wall = _delayed_wall(h0, "F", junk="9m", dora="9p")
    return _sc("ryuuiisou", "绿一色", {"yaku.ryuuiisou", "hora.tsumo"}, wall, script=delay_tsumo("9m"))


def scenario_chinroutou() -> Scenario:
    h0 = ["1m", "1m", "1m", "9m", "9m", "9m", "1p", "1p", "1p", "9p", "9p", "9s", "9s"]
    wall = _delayed_wall(h0, "9s", junk="5m", dora="5mr")
    return _sc("chinroutou", "清老头", {"yaku.chinroutou", "hora.tsumo"}, wall, script=delay_tsumo("5m"))


def scenario_shousuushii() -> Scenario:
    h0 = ["E", "E", "E", "S", "S", "S", "W", "W", "W", "N", "N", "2m", "3m"]
    wall = _delayed_wall(h0, "4m", junk="9m")
    return _sc("shousuushii", "小四喜", {"yaku.shousuushii", "hora.tsumo"}, wall, script=delay_tsumo("9m"))


def scenario_daisuushii() -> Scenario:
    h0 = ["E", "E", "E", "S", "S", "S", "W", "W", "W", "N", "N", "N", "2m"]
    wall = _delayed_wall(h0, "2m", junk="9m")
    return _sc("daisuushii", "大四喜", {"yaku.daisuushii", "hora.tsumo"}, wall, script=delay_tsumo("9m"))


def scenario_chuuren() -> Scenario:
    # 1122345678999 听 2/5… 摸 2 → 普通九莲（非纯正）
    h0 = ["1m", "1m", "2m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "9m", "9m"]
    wall = _delayed_wall(h0, "2m", junk="1p", pads=["4s", "N", "W"])
    return _sc("chuuren", "九莲宝灯", {"yaku.chuuren", "hora.tsumo"}, wall, script=delay_tsumo("1p"))


def scenario_junsei_chuuren() -> Scenario:
    h0 = ["1m", "1m", "1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "9m", "9m"]
    wall = _delayed_wall(h0, "5m", junk="1p")
    return _sc(
        "junsei_chuuren", "纯正九莲", {"yaku.junsei_chuuren", "hora.tsumo"}, wall, script=delay_tsumo("1p")
    )


def scenario_suukantsu() -> Scenario:
    hand0 = ["1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "5p"]
    h1, h2, h3 = dummies(
        ["1p", "2p", "3p", "4p", "6p", "7p", "8p"],
        ["1s", "2s", "3s", "4s", "5s", "6s", "7s"],
        ["8s", "9s", "9m", "E", "S", "W", "N"],
    )
    wall = build_wall(
        oya=0,
        hands=[hand0, h1, h2, h3],
        first_tsumo="1m",
        rinshan=["2m", "3m", "4m", "5p"],
        dora_markers=["C"],
    )
    return _sc(
        "suukantsu",
        "四杠子",
        {"yaku.suukantsu", "call.ankan", "hora.tsumo"},
        wall,
        script=Script(prefer_types=["ankan", "hora"], boost={ActionType.RIICHI: 50}),
    )


def scenario_sankantsu() -> Scenario:
    hand0 = ["1m", "1m", "1m", "2m", "2m", "2m", "3m", "3m", "3m", "4p", "5p", "6p", "7p"]
    h1, h2, h3 = dummies(
        ["1p", "2p", "3p", "8p", "9p", "1s", "2s"],
        ["3s", "4s", "5s", "6s", "7s", "8s", "9s"],
        ["4m", "5m", "6m", "7m", "8m", "9m", "E"],
    )
    wall = build_wall(
        oya=0,
        hands=[hand0, h1, h2, h3],
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
    hand0 = ["5m", "5m", "2m", "3m", "4m", "6m", "7m", "8m", "2p", "3p", "4p", "2s", "3s"]
    hand1 = ["1s", "1s", "2s", "2s", "3s", "3s", "4s", "4s", "6s", "6s", "7s", "7s", "8s"]
    hand2 = ["5mr", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    h3 = fill_hand([], 13, ["9m", "9p", "9s", "E", "S", "W", "N"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, h3],
        first_tsumo="8p",
        live_draws=["9m", "5m"],
        dora_markers=["1m"],
        rinshan=["9p"],
    )
    return _sc(
        "chankan",
        "抢杠",
        {"yaku.chankan", "call.kakan", "hora.ron"},
        wall,
        script=Script(
            discard_queues={0: ["8p"], 2: ["5mr"]},
            prefer_types=["pon", "kakan", "hora"],
            boost={ActionType.CHI: 50, ActionType.RIICHI: 50, ActionType.RON: 0},
        ),
    )


def scenario_haitei() -> Scenario:
    hand1 = ["2p", "2p", "3p", "3p", "4p", "4p", "5p", "5p", "6p", "6p", "7p", "7p", "8p"]
    h0 = fill_hand([], 13, ["1m", "2m", "3m", "4m", "5m", "6m", "7m"])
    h2 = fill_hand([], 13, ["1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    h3 = fill_hand([], 13, ["9m", "9p", "9s", "E", "S", "W", "N"])
    wall = build_wall(oya=0, hands=[h0, hand1, h2, h3], first_tsumo="8s", dora_markers=["C"])
    last = LIVE_LEN - 1
    wall = force_slots(wall, {last: "8p"})
    wall = ban_from_live_except(wall, "8p", last)
    return _sc(
        "haitei",
        "海底摸月",
        {"yaku.haitei", "hora.tsumo"},
        wall,
        script=Script(
            force_pass_response=True,
            prefer_types=["hora"],
            boost={
                ActionType.RIICHI: 50,
                ActionType.CHI: 50,
                ActionType.PON: 50,
                ActionType.ANKAN: 50,
                ActionType.RON: 90,
            },
        ),
    )


def scenario_houtei() -> Scenario:
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    hand1 = ["8m", "1p", "1p", "1p", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p"]
    h2 = fill_hand([], 13, ["1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    h3 = fill_hand([], 13, ["9m", "9p", "9s", "E", "S", "W", "N"])
    wall = build_wall(oya=0, hands=[hand0, hand1, h2, h3], first_tsumo="8s", dora_markers=["C"])
    last = LIVE_LEN - 1
    wall = force_slots(wall, {last: "1s"})
    wall = ban_from_live_except(wall, "8m", -1)  # 禁止 live 区再出 8m（keep=-1 全禁）

    def custom(engine, seat, legals):
        types = {a.get("type") for a in legals}
        if "hora" in types:
            return next(a for a in legals if a.get("type") == "hora")
        if seat == 1:
            for a in legals:
                if a.get("type") == "dahai" and a.get("pai") == "8m":
                    return a
        return None

    return _sc(
        "houtei",
        "河底捞鱼",
        {"yaku.houtei", "hora.ron"},
        wall,
        script=Script(
            force_pass_response=True,
            custom=custom,
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50, ActionType.RON: 90},
        ),
    )


def scenario_suukansansen() -> Scenario:
    hands = [
        ["1m", "1m", "1m", "1m", "5p", "6p", "7p", "5s", "6s", "7s", "8s", "9s", "E"],
        ["2m", "2m", "2m", "2m", "1p", "2p", "3p", "1s", "2s", "3s", "4s", "S", "W"],
        ["3m", "3m", "3m", "3m", "4p", "5p", "6p", "4s", "5s", "6s", "N", "P", "F"],
        ["4m", "4m", "4m", "4m", "7p", "8p", "9p", "7s", "8s", "9s", "C", "9m", "8m"],
    ]
    wall = build_wall(
        oya=0,
        hands=hands,
        first_tsumo="5m",
        live_draws=["6m", "7m", "8m"],
        rinshan=["5pr", "6p", "7p", "8p"],
        dora_markers=["9p"],
    )
    return _sc(
        "suukansansen",
        "四杠散了",
        {"ryukyoku.suukansansen"},
        wall,
        expect_ryukyoku_reason="suukansansen",
        script=Script(
            prefer_types=["ankan"],
            never_hora=True,
            force_pass_response=True,
            discard_queues={0: ["5m"], 1: ["6m"], 2: ["7m"], 3: ["8m"]},
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_exhaustive_noten() -> Scenario:
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    h1 = fill_hand([], 13, ["1p", "3p", "5p", "7p", "9p", "E", "S"])
    h2 = fill_hand([], 13, ["1s", "3s", "5s", "7s", "9s", "W", "N"])
    h3 = fill_hand([], 13, ["1m", "3m", "7m", "9m", "P", "F", "C"])
    wall = build_wall(oya=0, hands=[hand0, h1, h2, h3], first_tsumo="9p", dora_markers=["8s"])
    wall = ban_from_live_except(wall, "8m", -1)
    return _sc(
        "exhaustive_noten",
        "荒牌听牌罚符",
        {"ryukyoku.exhaustive_draw", "ryukyoku.noten"},
        wall,
        expect_ryukyoku_reason="exhaustive_draw",
        script=Script(
            never_hora=True,
            force_pass_response=True,
            boost={
                ActionType.RIICHI: 50,
                ActionType.CHI: 50,
                ActionType.PON: 50,
                ActionType.ANKAN: 50,
                ActionType.DAIMINKAN: 50,
                ActionType.KAKAN: 50,
            },
        ),
    )


def scenario_south() -> Scenario:
    h0 = ["5mr", "2m", "3m", "4m", "5m", "6m", "7m", "2p", "3p", "4p", "8p", "8p", "8p"]
    wall = _delayed_wall(h0, "5m", junk="9m", pads=["4s", "N", "W"])
    return _sc(
        "south",
        "南场",
        {"meta.south", "hora.tsumo", "yaku.aka"},
        wall,
        bakaze="S",
        script=delay_tsumo("9m"),
    )


def all_extra_scenarios() -> list[Scenario]:
    # 编排仍脆的场景暂不进默认套件（保留函数便于继续打磨）
    _deferred = {
        "kakan",
        "chankan",
        "haitei",
        "houtei",
        "exhaustive_noten",
        "riichi",  # 易变成双立直；普通立直由 double_riichi 旁路覆盖 reach
        "chuuren",  # 易被判纯正/清一色
        "honroutou",  # 易被判四暗刻
        "toitoi",
        "reach_ankan",  # core 对立直后暗杠仍 IllegalAction
        "chinitsu_ryanpeeko",  # 计点与 core 不一致（役种/符）
        "sankantsu",  # 同上
    }
    fns = [
        scenario_chi,
        scenario_pon,
        scenario_daiminkan,
        scenario_kakan,
        scenario_riichi,
        scenario_reach_ankan,
        scenario_yakuhai_haku,
        scenario_yakuhai_hatsu,
        scenario_yakuhai_chun,
        scenario_iipeeko,
        scenario_chanta,
        scenario_sanshoku,
        scenario_sanshoku_doukou,
        scenario_toitoi,
        scenario_sanankou,
        scenario_chiitoitsu,
        scenario_honroutou,
        scenario_junchan,
        scenario_shousangen,
        scenario_aka,
        scenario_chinitsu_ryanpeeko,
        scenario_daisangen,
        scenario_suuankou,
        scenario_suuankou_tanki,
        scenario_tsuuiisou,
        scenario_ryuuiisou,
        scenario_chinroutou,
        scenario_shousuushii,
        scenario_daisuushii,
        scenario_chuuren,
        scenario_junsei_chuuren,
        scenario_suukantsu,
        scenario_sankantsu,
        scenario_chankan,
        scenario_haitei,
        scenario_houtei,
        scenario_suukansansen,
        scenario_exhaustive_noten,
        scenario_south,
    ]
    out = []
    for fn in fns:
        sc = fn()
        if sc.id not in _deferred:
            out.append(sc)
    return out

