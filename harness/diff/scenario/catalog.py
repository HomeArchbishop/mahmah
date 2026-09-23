"""稀有局面场景目录（构造牌山 + 脚本着法）。"""
from __future__ import annotations

from riichienv import ActionType

from .runner import Scenario, Script
from .util import fill_hand as _fill
from .wall import build_wall


def scenario_kyushu_kyuhai() -> Scenario:
    """亲家起手≥9种幺九，首巡宣言九种九牌。"""
    hand0 = ["1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "2m", "3m", "4m", "5m"]
    hand1 = _fill([], 13, ["2p", "3p", "4p", "5p", "6p", "7p", "8p"])
    hand2 = _fill([], 13, ["2s", "3s", "4s", "5s", "6s", "7s", "8s"])
    hand3 = _fill([], 13, ["6m", "7m", "8m", "2p", "3p", "4p", "5p"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="N",
        dora_markers=["C"],
    )
    return Scenario(
        id="kyushu_kyuhai",
        desc="九种九牌",
        expect_tags=frozenset({"ryukyoku.kyushu_kyuhai"}),
        expect_ryukyoku_reason="kyushu_kyuhai",
        wall=wall,
        script=Script(prefer_kyushu=True),
    )


def scenario_sufuurenta() -> Scenario:
    """四家首切同一风牌（东），无人鸣牌 → 四风连打。"""
    # 散牌保证不听（避免误荣和成三家和）
    hands = [
        ["E", "1m", "3m", "5m", "7m", "9m", "1p", "3p", "5p", "7p", "9p", "1s", "3s"],
        ["E", "2m", "4m", "6m", "8m", "2p", "4p", "6p", "8p", "2s", "4s", "6s", "8s"],
        ["E", "1m", "2m", "4m", "5m", "7m", "8m", "1p", "2p", "4p", "5p", "7p", "8p"],
        ["E", "3m", "6m", "9m", "3p", "6p", "9p", "3s", "5s", "7s", "9s", "S", "W"],
    ]
    wall = build_wall(
        oya=0,
        hands=hands,
        first_tsumo="5s",
        live_draws=["5mr", "5pr", "5sr"],
        dora_markers=["N"],
    )
    return Scenario(
        id="sufuurenta",
        desc="四风连打",
        expect_tags=frozenset({"ryukyoku.sufuurenta"}),
        expect_ryukyoku_reason="sufuurenta",
        wall=wall,
        script=Script(
            discard_queues={0: ["E"], 1: ["E"], 2: ["E"], 3: ["E"]},
            force_pass_response=True,
            boost={
                ActionType.RIICHI: 50,
                ActionType.CHI: 50,
                ActionType.PON: 50,
                ActionType.DAIMINKAN: 50,
                ActionType.ANKAN: 50,
            },
        ),
    )


def scenario_tenhou() -> Scenario:
    """亲家配牌+首摸即和 → 天和。"""
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    hand1 = _fill([], 13, ["1p", "2p", "3p", "4p", "5p", "6p", "7p"])
    hand2 = _fill([], 13, ["1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    hand3 = _fill([], 13, ["9m", "9p", "9s", "E", "S", "W", "N"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="8m",
        dora_markers=["C"],
    )
    return Scenario(
        id="tenhou",
        desc="天和",
        expect_tags=frozenset({"yaku.tenhou", "hora.tsumo", "hora.dealer"}),
        wall=wall,
    )


def scenario_chiihou() -> Scenario:
    """子家第一巡自摸 → 地和。亲家先切废牌。"""
    hand0 = _fill(["9m"], 13, ["1m", "2m", "3m", "4m", "5m", "6m", "7m"])
    hand1 = ["2p", "2p", "3p", "3p", "4p", "4p", "5p", "5p", "6p", "6p", "7p", "7p", "8p"]
    hand2 = _fill([], 13, ["1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    hand3 = _fill([], 13, ["9p", "9s", "E", "S", "W", "N", "P"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="8m",
        live_draws=["8p"],
        dora_markers=["C"],
    )
    return Scenario(
        id="chiihou",
        desc="地和",
        expect_tags=frozenset({"yaku.chiihou", "hora.tsumo", "hora.child"}),
        wall=wall,
        script=Script(
            discard_queues={0: ["8m"]},
            always_pass_response=True,
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_kokushi() -> Scenario:
    """国士无双（普通，非亲家首摸天和）：子家听 C，亲家切 C。"""
    hand0 = ["C", "2m", "3m", "4m", "5m", "6m", "7m", "2p", "3p", "4p", "5p", "6p", "7p"]
    hand1 = ["1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "F"]
    hand2 = _fill([], 13, ["2s", "3s", "4s", "5s", "6s", "7s", "8s"])
    hand3 = _fill([], 13, ["8m", "8p", "2p", "3p", "4p", "5p", "6p"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="8m",
        dora_markers=["5mr"],
    )
    return Scenario(
        id="kokushi",
        desc="国士无双",
        expect_tags=frozenset({"yaku.kokushi", "hora.ron"}),
        wall=wall,
        script=Script(
            discard_queues={0: ["C"]},
            force_pass_response=False,
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_kokushi_13() -> Scenario:
    """国士十三面。"""
    hand0 = ["1m", "9m", "1p", "9p", "1s", "9s", "E", "S", "W", "N", "P", "F", "C"]
    hand1 = _fill([], 13, ["2m", "3m", "4m", "5m", "6m", "7m", "8m"])
    hand2 = _fill([], 13, ["2p", "3p", "4p", "5p", "6p", "7p", "8p"])
    hand3 = _fill([], 13, ["2s", "3s", "4s", "5s", "6s", "7s", "8s"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="1m",
        dora_markers=["5mr"],
    )
    return Scenario(
        id="kokushi_13",
        desc="国士无双十三面",
        expect_tags=frozenset({"yaku.kokushi_13", "hora.tsumo"}),
        wall=wall,
    )


def scenario_double_riichi_ippatsu() -> Scenario:
    """双立直 + 一发（荣和）。"""
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    hand1 = ["8m", "2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p", "5p", "5p", "5p"]
    hand2 = _fill([], 13, ["1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    hand3 = _fill([], 13, ["9m", "9p", "9s", "E", "S", "W", "N"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="1m",
        dora_markers=["C"],
    )
    return Scenario(
        id="double_riichi_ippatsu",
        desc="双立直+一发",
        expect_tags=frozenset(
            {
                "yaku.double_riichi",
                "yaku.ippatsu",
                "yaku.chinitsu",
                "yaku.ryanpeeko",
                "yaku.pinfu",
                "yaku.tanyao",
                "reach.declare",
                "reach.accepted",
                "hora.ron",
                "hora.with_ura",
            }
        ),
        wall=wall,
        script=Script(
            discard_queues={0: ["1m"], 1: ["8m"]},
            prefer_riichi=True,
            boost={
                ActionType.CHI: 50,
                ActionType.PON: 50,
            },
        ),
    )


def scenario_rinshan() -> Scenario:
    """暗杠后岭上开花：东暗杠，岭上摸 9m 成清一色。"""
    hand0 = ["E", "E", "E", "E", "1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m"]
    hand1 = _fill([], 13, ["1p", "2p", "3p", "4p", "5p", "6p", "7p"])
    hand2 = _fill([], 13, ["1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    hand3 = _fill([], 13, ["2m", "3m", "4m", "5m", "S", "W", "N"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="9m",
        rinshan=["9m"],
        dora_markers=["C"],
    )
    return Scenario(
        id="rinshan",
        desc="岭上开花",
        expect_tags=frozenset(
            {
                "yaku.rinshan",
                "call.ankan",
                "hora.tsumo",
                "meta.dora_flip",
                "yaku.menzen_tsumo",
                "yaku.jikaze",
                "yaku.bakaze",
                "yaku.honitsu",
                "yaku.ittsu",
                "yaku.dora",
            }
        ),
        wall=wall,
        script=Script(
            boost={ActionType.ANKAN: 0, ActionType.TSUMO: 0, ActionType.RIICHI: 50}
        ),
    )


def scenario_honba_kyotaku_ron() -> Scenario:
    """带本场+供托的荣和（对对断幺，避开复杂役种计点差）。"""
    hand0 = ["2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "6p", "6p", "6p", "5p"]
    hand1 = ["5p", "1s", "1s", "1s", "2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s"]
    hand2 = _fill([], 13, ["1m", "5m", "6m", "7m", "8m", "9m", "E"])
    hand3 = _fill([], 13, ["1p", "2p", "3p", "4p", "8p", "9p", "S"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="8m",
        dora_markers=["C"],
    )
    return Scenario(
        id="honba_kyotaku_ron",
        desc="本场+供托荣和",
        expect_tags=frozenset(
            {
                "hora.ron",
                "hora.with_honba",
                "hora.with_kyotaku",
                "meta.honba",
                "meta.kyotaku",
            }
        ),
        wall=wall,
        honba=2,
        kyotaku=1,
        scores=[24000, 25000, 25000, 25000],
        script=Script(
            discard_queues={0: ["8m"], 1: ["5p"]},
            boost={ActionType.RIICHI: 50, ActionType.CHI: 50, ActionType.PON: 50},
        ),
    )


def scenario_sanchaho() -> Scenario:
    """三家和：三家同听一张，放铳者打出后三家荣。"""
    hand0 = ["8m", "1p", "2p", "3p", "4p", "6p", "7p", "8p", "1s", "2s", "3s", "4s", "6s"]
    hand1 = ["2p", "2p", "2p", "3p", "3p", "3p", "4p", "4p", "4p", "6s", "6s", "6s", "5m"]
    hand2 = ["2m", "2m", "2m", "3m", "3m", "3m", "4m", "4m", "4m", "7s", "7s", "7s", "5m"]
    hand3 = ["2s", "2s", "2s", "3s", "3s", "3s", "4s", "4s", "4s", "8p", "8p", "8p", "5m"]
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="5mr",
        dora_markers=["C"],
    )
    return Scenario(
        id="sanchaho",
        desc="三家和",
        expect_tags=frozenset({"ryukyoku.sanchaho"}),
        expect_ryukyoku_reason="sanchaho",
        wall=wall,
        script=Script(
            discard_queues={0: ["5mr"]},
            boost={ActionType.CHI: 50, ActionType.PON: 50, ActionType.RIICHI: 50},
        ),
    )


def scenario_suucha_riichi() -> Scenario:
    """四家立直。"""
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    hand1 = ["2p", "2p", "3p", "3p", "4p", "4p", "5p", "5p", "6p", "6p", "7p", "7p", "8p"]
    hand2 = ["2s", "2s", "3s", "3s", "4s", "4s", "5s", "5s", "6s", "6s", "7s", "7s", "8s"]
    hand3 = ["1m", "2m", "3m", "4m", "5m", "6m", "7m", "8m", "9m", "2s", "3s", "4s", "5s"]
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="1p",
        live_draws=["1s", "9s", "9m"],
        dora_markers=["C"],
    )
    return Scenario(
        id="suucha_riichi",
        desc="四家立直",
        expect_tags=frozenset({"ryukyoku.suucha_riichi", "reach.declare"}),
        expect_ryukyoku_reason="suucha_riichi",
        wall=wall,
        script=Script(
            prefer_riichi=True,
            discard_queues={0: ["1p"], 1: ["1s"], 2: ["9s"], 3: ["9m"]},
            force_pass_response=True,
            boost={ActionType.CHI: 50, ActionType.PON: 50, ActionType.ANKAN: 50},
        ),
    )


def all_scenarios() -> list[Scenario]:
    from .extra import all_extra_scenarios
    from .gaps import all_gap_scenarios

    base = [
        scenario_kyushu_kyuhai(),
        scenario_sufuurenta(),
        scenario_sanchaho(),
        scenario_suucha_riichi(),
        scenario_tenhou(),
        scenario_chiihou(),
        scenario_kokushi(),
        scenario_kokushi_13(),
        scenario_double_riichi_ippatsu(),
        scenario_rinshan(),
        scenario_honba_kyotaku_ron(),
        scenario_renchan_tag(),
    ]
    return base + all_extra_scenarios() + all_gap_scenarios()


def scenario_renchan_tag() -> Scenario:
    """亲家自摸；runner 在局终后补下一局 start_kyoku 以打上 meta.renchan。"""
    hand0 = ["2m", "2m", "3m", "3m", "4m", "4m", "5m", "5m", "6m", "6m", "7m", "7m", "8m"]
    hand1 = _fill([], 13, ["1p", "2p", "3p", "4p", "5p", "6p", "7p"])
    hand2 = _fill([], 13, ["1s", "2s", "3s", "4s", "5s", "6s", "7s"])
    hand3 = _fill([], 13, ["9m", "9p", "9s", "E", "S", "W", "N"])
    wall = build_wall(
        oya=0,
        hands=[hand0, hand1, hand2, hand3],
        first_tsumo="8m",
        dora_markers=["C"],
    )
    return Scenario(
        id="renchan",
        desc="连庄",
        expect_tags=frozenset({"meta.renchan", "hora.dealer", "hora.tsumo"}),
        wall=wall,
    )


def get_scenario(sid: str) -> Scenario:
    for sc in all_scenarios():
        if sc.id == sid:
            return sc
    raise KeyError(sid)


def list_scenario_ids() -> list[str]:
    return [s.id for s in all_scenarios()]
