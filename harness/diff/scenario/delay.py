"""延迟自摸脚本：避开天和吞役。"""
from __future__ import annotations

from riichienv import ActionType

from .runner import Script

_NO_CALL = {
    ActionType.RIICHI: 50,
    ActionType.CHI: 50,
    ActionType.PON: 50,
    ActionType.ANKAN: 50,
    ActionType.DAIMINKAN: 50,
    ActionType.KAKAN: 50,
}


def delay_tsumo(junk: str = "9s") -> Script:
    """亲家首摸 junk 切掉，三家过，随后第二巡自摸（live_draws[3]）。"""
    return Script(
        discard_queues={0: [junk]},
        force_pass_response=True,
        boost=dict(_NO_CALL),
    )


def live4(win: str, pad: str = "8m") -> list[str]:
    """seat1,2,3 摸 pad，亲家第二巡摸 win。"""
    return [pad, pad, pad, win]
