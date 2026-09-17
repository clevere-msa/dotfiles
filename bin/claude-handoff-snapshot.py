#!/usr/bin/env python3
"""PreCompact hook: write a deterministic handoff snapshot before context is lost.

Costs no model tokens - every fact is read from the session transcript. Leaves a
pointer file that the UserPromptSubmit hook announces on the next prompt, since
PreCompact has no way to inject context itself.

Writes only under the OS temporary directory with mode 0600, skips credential
paths, redacts credential-shaped strings, and always exits 0.

Runnable by hand:  claude-handoff-snapshot.py --session-id <id> [--print]
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from collections import Counter
from importlib.machinery import SourceFileLoader
from pathlib import Path

_lib = SourceFileLoader(
    "claude_hook_lib", str(Path(__file__).resolve().parent / "claude-hook-lib.py")
).load_module()

TOP_PATHS = 12
MAX_REQUESTS = 5
# Operator prompts above this length are injected skill/system text, not a request.
MAX_REQUEST_CHARS = 600

PATH_RE = re.compile(r"(/(?:home|project|opt|etc)/[A-Za-z0-9_./-]{4,120})")
PR_RE = re.compile(r"\b([a-z][a-z0-9_-]{3,40})#(\d{1,5})\b")
BARE_PR_RE = re.compile(r"\bPR #(\d{1,5})\b")


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        out = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                out.append(item.get("text", ""))
        return " ".join(out)
    return ""


def scan(path: Path) -> dict:
    out: dict = {
        "cwd": None, "branch": None, "version": None, "session": None,
        "requests": [], "last_agent": None, "tools": Counter(),
        "paths": Counter(), "prs": Counter(), "calls": 0, "context": None,
    }
    for record in _lib.tail_records(path):
        kind = record.get("type")
        out["cwd"] = record.get("cwd") or out["cwd"]
        out["branch"] = record.get("gitBranch") or out["branch"]
        out["version"] = record.get("version") or out["version"]
        out["session"] = record.get("sessionId") or out["session"]

        used = _lib.context_tokens(record)
        if used:
            out["context"] = used
            out["calls"] += 1

        message = record.get("message") or {}
        content = message.get("content")

        if kind == "assistant" and isinstance(content, list):
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "tool_use":
                    out["tools"][item.get("name", "?")] += 1
                    blob = str(item.get("input", ""))
                    for match in PATH_RE.finditer(blob):
                        if not _lib.sensitive_path(match.group(1)):
                            out["paths"][match.group(1)] += 1
            body = " ".join(text_of(content).split())
            if body:
                out["last_agent"] = body[:1600]
                for match in PR_RE.finditer(body):
                    out["prs"][f"{match.group(1)}#{match.group(2)}"] += 1
                for match in BARE_PR_RE.finditer(body):
                    out["prs"][f"PR #{match.group(1)}"] += 1

        elif kind == "user":
            body = " ".join(text_of(content).split())
            # Skill bodies and system injections arrive as user records too. Real
            # operator prompts are short; anything book-length is injected text.
            if body and not body.startswith("<") and len(body) <= MAX_REQUEST_CHARS:
                out["requests"].append(body[:400])
    return out


def render(data: dict) -> str:
    now = time.strftime("%Y-%m-%d %H:%M:%S %Z")
    lines = [
        f"# Handoff snapshot - session `{(data.get('session') or '?')[:8]}`",
        "",
        f"Generated {now} by claude-handoff-snapshot.py at a compaction boundary.",
        "Structured facts only, no model summary. Read the referenced artifacts rather",
        "than trusting this file for detail.",
        "",
        "## Session",
        "",
        f"- Session: `{data.get('session') or 'unknown'}`",
        f"- Working directory: `{data.get('cwd') or 'unknown'}`",
        f"- Git branch: `{data.get('branch') or 'unknown'}`",
        f"- Claude Code version: `{data.get('version') or 'unknown'}`",
        f"- API calls in the scanned tail: {data.get('calls', 0)}",
    ]
    if data.get("context"):
        lines.append(f"- Context at snapshot: {data['context']:,} tokens")

    requests = data.get("requests") or []
    if requests:
        lines += ["", "## Recent operator requests (oldest first in the scanned tail)", ""]
        lines += [f"- {_lib.redact(r)}" for r in requests[-MAX_REQUESTS:]]

    if data.get("last_agent"):
        lines += ["", "## State as last reported", "", _lib.redact(data["last_agent"])]

    prs = data.get("prs") or Counter()
    if prs:
        lines += ["", "## Pull requests referenced", ""]
        lines += [f"- `{name}` ({n} mentions)" for name, n in prs.most_common(TOP_PATHS)]

    paths = data.get("paths") or Counter()
    if paths:
        lines += ["", "## Files and paths in play", ""]
        lines += [f"- `{p}` ({n} touches)" for p, n in paths.most_common(TOP_PATHS)]

    tools = data.get("tools") or Counter()
    if tools:
        lines += ["", "## Tool mix", ""]
        lines += [f"- `{name}` x{n}" for name, n in tools.most_common(8)]

    lines += [
        "",
        "## Continuation guidance",
        "",
        "- Re-read the artifacts above rather than reconstructing their contents.",
        "- Confirm live state (PR review status, CI, ticket status) before acting on",
        "  anything here; this is a point-in-time record and external state moves on.",
        "- If work was blocked on an external review or authorization gate, it still is",
        "  until verified otherwise. Do not re-derive evidence to rediscover the blocker.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-id")
    parser.add_argument("--out")
    parser.add_argument("--print", action="store_true", dest="show")
    args = parser.parse_args()

    payload = {} if args.session_id else _lib.read_payload()
    if args.session_id:
        payload = {"session_id": args.session_id}

    path = _lib.transcript(payload)
    if path is None:
        return 0
    data = scan(path)
    sid = data.get("session") or _lib.session_id(payload) or "unknown"
    document = render(data)

    stamp = time.strftime("%Y%m%dT%H%M%S")
    out = Path(args.out) if args.out else _lib.temp_root() / f"claude-handoff-{sid[:8]}-{stamp}.md"
    _lib.write_private(out, document)
    try:
        _lib.write_private(_lib.pointer_path(sid), str(out) + "\n")
    except OSError:
        pass

    if args.show:
        sys.stdout.write(document)
    else:
        sys.stderr.write(f"handoff snapshot: {out}\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
