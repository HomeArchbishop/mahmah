"""引擎适配：riichienv oracle / mahmah core。"""
from .core import CoreEngine, default_mjai_diff_path
from .riichi import RiichiEngine, make_wall, wall_to_mjai

__all__ = [
    "CoreEngine",
    "RiichiEngine",
    "default_mjai_diff_path",
    "make_wall",
    "wall_to_mjai",
]
