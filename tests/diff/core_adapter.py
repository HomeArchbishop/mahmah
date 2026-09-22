"""core（mjai_diff 子进程）侧。"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path


def default_mjai_diff_path() -> Path:
    root = Path(__file__).resolve().parents[2]
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

    def legal(self, seat: int) -> list[dict]:
        return self._rpc({"op": "legal", "seat": seat}).get("actions", [])
