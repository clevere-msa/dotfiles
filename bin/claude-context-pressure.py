#!/usr/bin/env python3
"""UserPromptSubmit hook: flag context pressure, and announce a handoff snapshot.

Silent unless it has something worth the tokens: below the pressure floor and
with no pending snapshot, it emits a bare `{"continue": true}`.

Measured basis on this machine: a ~45k floor per call and sessions over 100
calls settling at 207-281k average context, 99.3% of it input. Each tool result
is re-sent on every following call, so pressure is worth knowing about before
the window fills rather than after.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib.machinery import SourceFileLoader

_lib = SourceFileLoader(
    "claude_hook_lib", str(Path(__file__).resolve().parent / "claude-hook-lib.py")
).load_module()

PRESSURE_FLOOR = 0.60
EVENT = "UserPromptSubmit"

PRESSURE = (
    "Context pressure {pct:.0f}% ({used:,} of {limit:,} tokens). Every tool result "
    "you take now is re-sent on each following call. Project fields at the source, "
    "use counting queries before reads, write bulk output to a file and keep only a "
    "digest, and delegate broad searches to a subagent."
)

HANDOFF = (
    "Context was just compacted. A structured handoff snapshot for this session is at "
    "{path} - read it once instead of re-deriving prior state, and prefer the artifacts "
    "it references over reconstructing their contents."
)


def handoff_notice(sid: str | None) -> str | None:
    """Announce a PreCompact snapshot exactly once, then consume the pointer."""
    if not sid:
        return None
    pointer = _lib.pointer_path(sid)
    try:
        path = pointer.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None
    try:
        pointer.unlink()
    except OSError:
        pass
    if not path or not Path(path).is_file():
        return None
    return HANDOFF.format(path=path)


def pressure_notice(payload: dict) -> str | None:
    path = _lib.transcript(payload)
    if path is None:
        return None
    used = None
    for record in _lib.tail_records(path, limit=256 * 1024):
        value = _lib.context_tokens(record)
        if value:
            used = value
    if not used:
        return None
    limit = _lib.autocompact_window()
    if limit <= 0 or used < limit * PRESSURE_FLOOR:
        return None
    return PRESSURE.format(pct=min(100.0, 100.0 * used / limit), used=used, limit=limit)


def main() -> None:
    parts: list[str] = []
    try:
        payload = _lib.read_payload()
        for producer in (
            lambda: handoff_notice(_lib.session_id(payload)),
            lambda: pressure_notice(payload),
        ):
            try:
                text = producer()
            except Exception:
                text = None
            if text:
                parts.append(text)
    except Exception:
        pass
    _lib.emit(EVENT, "\n\n".join(parts) if parts else None)


if __name__ == "__main__":
    main()
    sys.exit(0)
