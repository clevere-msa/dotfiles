#!/usr/bin/env python3
"""PreToolUse hook: bound Bash commands that would return unprojected output.

WHY THIS EXISTS, AND WHY IT IS A *Pre*ToolUse HOOK.

Every tool result stays in context until compaction, so a result's real cost is its size
times the number of calls that follow it. ~/CLAUDE.md already prescribes the discipline -
project at the source, locate before reading, spill bulk to a file - but discipline is
remembered unevenly. The obvious place to enforce it mechanically would be PostToolUse.
That does not work: PostToolUse fires after the result is final and can only *append*
(`hookSpecificOutput.additionalContext`), which makes a size problem worse. PreToolUse is
the last point at which the command is still editable, so this is where the enforcement
has to live.

It is a second line, not the first. `bashOutputMaxChars` in settings.json is the blunt
byte cap and catches everything. This hook exists for what a byte cap handles badly: it
rewrites the command so the *bound is visible in the output*, with an exact count of what
was suppressed, rather than leaving the model to guess whether it saw the whole thing.

CONSERVATIVE BY CONSTRUCTION.

A false rewrite that hides something needed costs a retry, and a retry costs more context
than the rewrite saved. So the bar for touching a command is deliberately high:

- The command must be a single, simple invocation. Any `;`, `&&`, `||`, `|`, redirection,
  command substitution or backtick and the command is left alone - composition means the
  author already had an output shape in mind.
- `cat` is bounded only when a named argument is verifiably large on disk. Small files are
  not touched, so the appended "N more lines suppressed" note is never a lie.
- `sed -n 'A,Bp'` is clamped only when the requested span is itself huge, and the clamp
  says exactly which lines were dropped and how to get them.
- Anything unparsed, unresolvable or ambiguous falls through untouched.

EVERY REWRITE ANNOUNCES ITSELF, SO THE HOOK STAYS SILENT.

No `systemMessage` is emitted. It would be redundant and, on a common command like a bare
`find`, pure noise: the awk stage prints nothing at all when the output was under the
limit, and prints an exact suppressed-line count when it was not. The `sed` clamp says
which lines it dropped. A rewrite is therefore never invisible to whoever reads the
output, and a rewrite that changed nothing is never announced.

ESCAPE HATCH.

CLAUDE_OUTPUT_PROJECT=off skips everything, the way CLAUDE_LINT=off does for the linter.
A hook with no way out gets uninstalled rather than bypassed.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
_lib = SourceFileLoader(
    "claude_hook_lib", str(Path(__file__).resolve().parent / "claude-hook-lib.py")
).load_module()

# A file smaller than this is cheap enough to read whole; bounding it would only add
# noise. Set above the median tool result measured in this environment (~1k chars).
LARGE_FILE_BYTES = 32_000

CAT_LINES = 300  # Lines kept from an unbounded `cat` of a large file.
FIND_LINES = 200  # Lines kept from a bare `find`.
SED_SPAN_LINES = 400  # Largest `sed -n 'A,Bp'` span left unclamped.

# Shell metacharacters that mean the author already composed an output shape. Their
# presence disqualifies the command outright -- see the module docstring.
COMPOSITION = re.compile(r"[;|&<>`]|\$\(|\n")

SED_RANGE = re.compile(r"^(?P<a>\d+),(?P<b>\d+)p$")


def bounder(limit: int) -> str:
    """A pipeline stage that keeps `limit` lines and reports the exact remainder.

    awk rather than `head`: head over-reads a pipe in blocks, so anything counting the
    leftovers behind it undercounts. awk sees every line, so the suppressed count is
    exact -- which is the whole point of preferring this to a silent byte cap.
    """
    return (
        f"awk 'NR<={limit}; NR>{limit}{{s++}} END{{if(s) printf "
        f'"\\n[claude-output-project: %d more line(s) suppressed; '
        f"re-run with an explicit bound to see them]\\n\", s}}'"
    )


def words(command: str) -> list[str] | None:
    """Split a command, or None when it is not a single simple invocation."""
    if COMPOSITION.search(command):
        return None
    try:
        parts = shlex.split(command)
    except ValueError:
        return None  # Unbalanced quoting: not ours to interpret.
    return parts or None


def file_size(token: str, cwd: str) -> int | None:
    if token.startswith("-") or "*" in token or "?" in token or "$" in token:
        return None
    path = Path(token).expanduser()
    if not path.is_absolute():
        path = Path(cwd) / path
    try:
        return path.stat().st_size if path.is_file() else None
    except OSError:
        return None


def project_cat(parts: list[str], command: str, cwd: str) -> str | None:
    """Bound `cat <large file>`. Flags other than `--` disqualify: `cat -n` is already a
    deliberate choice, and `cat -A` on a binary is a different problem than this one."""
    args = [p for p in parts[1:] if p != "--"]
    if not args or any(p.startswith("-") for p in args):
        return None
    sizes = [file_size(p, cwd) for p in args]
    if any(size is None for size in sizes):
        return None  # An argument we cannot verify: leave it alone.
    if sum(sizes) <= LARGE_FILE_BYTES:
        return None
    return f"{command} | {bounder(CAT_LINES)}"


def project_find(parts: list[str], command: str) -> str | None:
    """Bound a bare `find`. `-quit`, `-delete` and `-exec` mean the caller is not reading
    the listing as output, so those are left alone."""
    if any(p in ("-quit", "-delete", "-exec", "-execdir", "-ok", "-okdir") for p in parts):
        return None
    return f"{command} | {bounder(FIND_LINES)}"


def project_sed(parts: list[str]) -> str | None:
    """Clamp an oversized `sed -n 'A,Bp'` window and say exactly what was dropped."""
    if "-n" not in parts:
        return None
    at = None
    for index, part in enumerate(parts[1:], start=1):
        if SED_RANGE.match(part):
            if at is not None:
                return None  # More than one range: not a shape we model.
            at = index
    if at is None:
        return None
    script = SED_RANGE.match(parts[at])
    start, end = int(script.group("a")), int(script.group("b"))
    if end - start + 1 <= SED_SPAN_LINES:
        return None
    clamped = start + SED_SPAN_LINES - 1
    rebuilt = list(parts)
    rebuilt[at] = f"{start},{clamped}p"
    note = (
        f"printf '\\n[claude-output-project: clamped to lines {start}-{clamped}; "
        f"lines {clamped + 1}-{end} were not read]\\n'"
    )
    return " ".join(shlex.quote(p) for p in rebuilt) + "; " + note


def project(command: str, cwd: str) -> str | None:
    """The rewritten command, or None to leave it exactly as written."""
    parts = words(command)
    if not parts:
        return None
    name = Path(parts[0]).name
    if name == "cat":
        return project_cat(parts, command, cwd)
    if name == "find":
        return project_find(parts, command)
    if name == "sed":
        return project_sed(parts)
    return None


def main() -> None:
    if os.environ.get("CLAUDE_OUTPUT_PROJECT", "").lower() in {"off", "0", "false"}:
        sys.exit(0)

    payload = _lib.read_payload()
    if payload.get("tool_name") not in (None, "Bash"):
        sys.exit(0)
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip():
        sys.exit(0)

    try:
        rewritten = project(command.strip(), payload.get("cwd") or os.getcwd())
    except Exception:
        sys.exit(0)  # Advisory hook: a bug here must never cost a turn.
    if not rewritten or rewritten == command.strip():
        sys.exit(0)

    updated = dict(tool_input)
    updated["command"] = rewritten
    json.dump(
        {
            "continue": True,
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "updatedInput": updated,
            },
        },
        sys.stdout,
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
