#!/usr/bin/env python3
"""Shared helpers for the Claude Code context-cost hooks.

Both hooks read the session transcript under ~/.claude/projects/. Claude Code
passes `session_id` and usually `transcript_path` on stdin; we honour the path
when given and fall back to a session-id search, then to the newest transcript.

Every helper fails soft: a hook must never block a turn.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

TAIL_BYTES = 3 * 1024 * 1024
MAX_AGE_SEC = 12 * 60 * 60
DEFAULT_AUTOCOMPACT = 220_000

SECRET_PATTERNS = [
    re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"),
    re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)\b(?:password|passwd|secret|api[_-]?key|token)\s*[:=]\s*\S+"),
    re.compile(r"(?i)\bauthorization\s*:\s*(?:bearer|basic)\s+\S+"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.\S+"),
]

SENSITIVE_PATH_PARTS = (
    "/.ssh", "/.secrets", "/.gnupg", "/.aws", "/.kube", "/.docker",
    "/.netrc", "/.pgpass", "/credentials", "/.config/gh", "/.npmrc",
    "/.claude/.credentials", "/.codex/auth",
)


def redact(text: str) -> str:
    for pattern in SECRET_PATTERNS:
        text = pattern.sub("[redacted]", text)
    return text


def sensitive_path(path: str) -> bool:
    lowered = path.lower()
    return any(part in lowered for part in SENSITIVE_PATH_PARTS)


def claude_home() -> Path:
    return Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))


def temp_root() -> Path:
    return Path(os.environ.get("TMPDIR", "/tmp"))


def read_payload() -> dict:
    try:
        raw = sys.stdin.read()
    except Exception:
        return {}
    try:
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def session_id(payload: dict) -> str | None:
    for key in ("session_id", "sessionId"):
        value = payload.get(key)
        if isinstance(value, str) and len(value) >= 8:
            return value
    return None


def transcript(payload: dict) -> Path | None:
    hinted = payload.get("transcript_path") or payload.get("transcriptPath")
    if isinstance(hinted, str):
        candidate = Path(hinted)
        if candidate.is_file():
            return candidate
    projects = claude_home() / "projects"
    if not projects.is_dir():
        return None
    sid = session_id(payload)
    if sid:
        matches = [p for p in projects.glob(f"*/{sid}.jsonl") if p.is_file()]
        if matches:
            return matches[0]
    everything = [p for p in projects.glob("*/*.jsonl") if p.is_file()]
    if not everything:
        return None
    newest = max(everything, key=lambda p: p.stat().st_mtime)
    if time.time() - newest.stat().st_mtime > MAX_AGE_SEC:
        return None
    return newest


def autocompact_window() -> int:
    """Effective auto-compact threshold: env, then settings.json, then default."""
    raw = os.environ.get("CLAUDE_AUTOCOMPACT_WINDOW")
    if raw:
        try:
            value = int(raw)
            if value > 0:
                return value
        except ValueError:
            pass
    model = ""
    for name in ("settings.json", "settings.local.json"):
        try:
            data = json.loads((claude_home() / name).read_text(encoding="utf-8"))
        except Exception:
            continue
        value = data.get("autoCompactWindow")
        if isinstance(value, int) and value > 0:
            return value
        model = model or str(data.get("model") or "")
    # No explicit window: fall back to the model's own context size, since a
    # 1M-context model does not compact anywhere near the default.
    if "1m" in model.lower():
        return 1_000_000
    return DEFAULT_AUTOCOMPACT


def tail_records(path: Path, limit: int = TAIL_BYTES):
    """Yield parsed JSON records from the tail of a transcript."""
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            if size > limit:
                handle.seek(size - limit)
                handle.readline()
            chunk = handle.read()
    except OSError:
        return
    for raw in chunk.splitlines():
        try:
            yield json.loads(raw)
        except Exception:
            continue


def context_tokens(record: dict) -> int | None:
    usage = (record.get("message") or {}).get("usage")
    if not isinstance(usage, dict):
        return None
    total = (
        (usage.get("input_tokens") or 0)
        + (usage.get("cache_read_input_tokens") or 0)
        + (usage.get("cache_creation_input_tokens") or 0)
    )
    return total or None


def pointer_path(sid: str) -> Path:
    return temp_root() / f"claude-handoff-{sid}.latest"


def write_private(path: Path, text: str) -> None:
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)


def emit(event: str, context: str | None) -> None:
    response: dict = {"continue": True}
    if context:
        response["hookSpecificOutput"] = {
            "hookEventName": event,
            "additionalContext": context,
        }
    json.dump(response, sys.stdout)
    sys.stdout.write("\n")
