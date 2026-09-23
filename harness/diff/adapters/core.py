"""core（mjai_diff 子进程）侧。"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any


def default_mjai_diff_path() -> Path:
    # harness/diff/adapters/core.py → repo root
    root = Path(__file__).resolve().parents[3]
    exe = "mjai_diff.exe" if os.name == "nt" else "mjai_diff"
    return root / "zig-out" / "bin" / exe


class CoreEngine:
    def __init__(self, exe: Path | None = None) -> None:
        path = exe or default_mjai_diff_path()
        if not path.is_file():
            raise FileNotFoundError(f"mjai_diff not found at {path}; run `zig build mjai-diff`")
        self.proc = subprocess.Popen(
            [str(path)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        # seat -> compact legal key strings（start/act/acts 回包）
        self._legal_keys: dict[int, list[str]] = {}

    def close(self) -> None:
        if self.proc.poll() is None:
            try:
                self._rpc({"op": "quit"})
            except Exception:
                pass
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def _rpc(self, msg: dict) -> dict:
        assert self.proc.stdin and self.proc.stdout
        self.proc.stdin.write((json.dumps(msg, ensure_ascii=False) + "\n").encode("utf-8"))
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            err = self.proc.stderr.read() if self.proc.stderr else b""
            raise RuntimeError(f"mjai_diff died: {err!r}")
        reply = json.loads(line.decode("utf-8"))
        if not reply.get("ok", False):
            raise RuntimeError(f"mjai_diff error: {reply}")
        if "legal_keys" in reply:
            self._legal_keys = {int(k): list(v) for k, v in reply["legal_keys"].items()}
        return reply

    def load_wall(
        self,
        paishan_mjai: list[str],
        *,
        oya: int = 0,
        bakaze: str = "E",
        kyoku: int = 1,
        honba: int = 0,
        kyotaku: int = 0,
        scores: list[int] | None = None,
    ) -> list[dict]:
        msg: dict = {
            "op": "start",
            "paishan": paishan_mjai,
            "oya": oya,
            "bakaze": bakaze,
            "kyoku": kyoku,
            "honba": honba,
            "kyotaku": kyotaku,
        }
        if scores is not None:
            msg["scores"] = scores
        return self._rpc(msg)["events"]

    def apply(self, seat: int, action: dict) -> list[dict]:
        act = dict(action)
        act.setdefault("request_id", 1)
        act.setdefault("actor", seat)
        if act.get("type") == "dahai":
            act.setdefault("tsumogiri", False)
        return self._rpc({"op": "act", "seat": seat, "action": act})["events"]

    def apply_many(self, actions: dict[int, dict]) -> list[dict]:
        """多座位一次提交（应手窗）；回包含下一步 legals。"""
        payload = []
        for seat in sorted(actions.keys()):
            act = dict(actions[seat])
            act.setdefault("request_id", 1)
            act.setdefault("actor", seat)
            if act.get("type") == "dahai":
                act.setdefault("tsumogiri", False)
            payload.append({"seat": seat, "action": act})
        return self._rpc({"op": "acts", "actions": payload})["events"]

    def replay_kyoku(
        self,
        paishan_mjai: list[str],
        *,
        oya: int,
        bakaze: str,
        kyoku: int,
        honba: int,
        kyotaku: int,
        scores: list[int],
        steps: list[list[dict]],
    ) -> tuple[list[dict], list[dict[int, list[str]]]]:
        """整局回放。steps[i] = [{\"seat\", \"action\"}, ...]。"""
        reply = self._rpc(
            {
                "op": "replay_kyoku",
                "paishan": paishan_mjai,
                "oya": oya,
                "bakaze": bakaze,
                "kyoku": kyoku,
                "honba": honba,
                "kyotaku": kyotaku,
                "scores": scores,
                "steps": steps,
            }
        )
        raw_keys = reply.get("step_legal_keys") or []
        step_keys: list[dict[int, list[str]]] = []
        for m in raw_keys:
            step_keys.append({int(k): list(v) for k, v in m.items()})
        return reply["events"], step_keys
