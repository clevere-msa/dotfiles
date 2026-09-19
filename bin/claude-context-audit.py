#!/usr/bin/env python3
"""Report what is actually occupying a Claude Code session's context.

Every turn re-sends the whole input, so the cost of a block is its size times the
number of calls that follow it. This reads a session transcript and reports the
composition: totals by role and block type, the largest individual blocks, and the
tool-result distribution. Use it to get a before/after number rather than an
impression.

Usage:
    claude-context-audit.py                 # newest transcript
    claude-context-audit.py <session-id>    # by id, full or prefix
    claude-context-audit.py <path.jsonl>    # explicit path
    claude-context-audit.py --top 40        # show more large blocks
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from importlib.machinery import SourceFileLoader
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
_lib = SourceFileLoader(
    "claude_hook_lib", str(Path(__file__).resolve().parent / "claude-hook-lib.py")
).load_module()

# Rough conversion. Good enough for comparing runs against each other, which is all
# this is for; treat the absolute figures as indicative, not billing-accurate.
CHARS_PER_TOKEN = 4
BIG_BLOCK_CHARS = 8000


def find_transcript(target: str | None) -> Path | None:
    """Resolve a session id, a path, or nothing (newest) to a transcript."""
    if target:
        direct = Path(target).expanduser()
        if direct.is_file():
            return direct
        matches = sorted(
            (_lib.claude_home() / "projects").glob(f"*/{target}*.jsonl"),
            key=lambda p: p.stat().st_mtime,
        )
        return matches[-1] if matches else None
    # No argument: reuse the library's own newest-transcript logic.
    return _lib.transcript({})


def block_text(block: dict) -> str:
    """Extract the context-occupying text from one content block."""
    kind = block.get("type")
    if kind == "tool_result":
        value = block.get("content")
        if isinstance(value, list):
            return "".join(
                part.get("text", "") for part in value if isinstance(part, dict)
            )
        return value or ""
    if kind == "tool_use":
        return json.dumps(block.get("input", {}))
    if kind == "thinking":
        return block.get("thinking", "")
    return block.get("text") or ""


def classify(role: str, kind: str, text: str) -> str:
    """Label a block, separating injected content from genuine conversation."""
    if kind == "text" and role == "user":
        if "<command-name>" in text:
            return "user/slash-command"
        if "Base directory for this skill:" in text:
            return "user/skill-body-injection"
        if "<system-reminder>" in text:
            return "user/text+system-reminder"
    return f"{role}/{kind}"


def tokens(chars: int) -> int:
    return chars // CHARS_PER_TOKEN


def audit(path: Path, top: int) -> int:
    by_kind: Counter[str] = Counter()
    tool_results: list[int] = []
    big: list[tuple[int, str, str]] = []
    peak_context = 0

    for record in _lib.tail_records(path):
        message = record.get("message") or {}
        role = message.get("role") or record.get("type") or "?"
        content = message.get("content")
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        if not isinstance(content, list):
            continue

        seen = _lib.context_tokens(record)
        if seen:
            peak_context = max(peak_context, seen)

        for block in content:
            if not isinstance(block, dict):
                continue
            kind = block.get("type") or "?"
            text = block_text(block)
            size = len(text)
            if not size:
                continue
            label = classify(role, kind, text)
            by_kind[label] += size
            if kind == "tool_result":
                tool_results.append(size)
            if size >= BIG_BLOCK_CHARS:
                head = " ".join(text[:110].split())
                big.append((size, label, head))

    total = sum(by_kind.values())
    if not total:
        print(f"No content found in {path}", file=sys.stderr)
        return 1

    print(f"Transcript: {path}")
    if peak_context:
        print(f"Peak reported context: {peak_context:,} tokens")
    print(f"Transcript content: {total:,} chars  ~{tokens(total):,} tokens\n")

    print("By role and block type:")
    for label, size in by_kind.most_common():
        share = 100 * size / total
        print(f"  {size:>10,} chars  ~{tokens(size):>8,} tok  {share:>5.1f}%  {label}")

    if tool_results:
        tool_results.sort(reverse=True)
        run = sum(tool_results)
        print(
            f"\nTool results: {len(tool_results)} blocks, {run:,} chars "
            f"(~{tokens(run):,} tok), largest {tool_results[0]:,}, "
            f"median {tool_results[len(tool_results) // 2]:,}"
        )

    if big:
        print(f"\nBlocks over {BIG_BLOCK_CHARS:,} chars:")
        for size, label, head in sorted(big, reverse=True)[:top]:
            print(f"  {size:>10,} chars  ~{tokens(size):>8,} tok  {label}")
            print(f"      {_lib.redact(head)}")

    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", nargs="?", help="session id, id prefix, or path")
    parser.add_argument("--top", type=int, default=15, help="large blocks to list")
    args = parser.parse_args()

    path = find_transcript(args.session)
    if path is None:
        print("No transcript found.", file=sys.stderr)
        raise SystemExit(1)
    raise SystemExit(audit(path, args.top))


if __name__ == "__main__":
    main()
