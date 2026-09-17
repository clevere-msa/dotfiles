#!/usr/bin/env python3
"""PreToolUse hook: run this repository's CI gate set before a push or PR can leave.

WHY THIS BLOCKS, WHEN THE OTHER HOOKS IN THIS DIRECTORY DO NOT.

claude-hook-lib.py states that "a hook must never block a turn". That rule is about the
context-cost hooks: they are advisory, and an advisory hook that fails takes a turn with
it for no gain. This hook is the opposite kind. It exists to stop a push whose gates have
not passed, so refusing IS the product. Exit 2 is the only code Claude Code treats as a
block (0 and 2 are the documented PreToolUse verdicts; anything else is reported as a
non-blocking error and the call proceeds), so every refusal path here exits 2.

WHAT IT REPLACES.

Nothing in the repository runs the CI gate set locally. The agent runs it only when it
remembers to, which is exactly the failure this is for: a push, a red PR, a round trip
through CI to learn something `ruff check` knew in 200ms. The gate list is not invented
here -- it is declared per repository in .claude/gates.toml (or [tool.claude-gates] in
pyproject.toml), transcribed from that repository's own workflow, so the local run and CI
cannot drift apart silently.

PUSH DETECTION FAILS TOWARD RUNNING.

A false positive costs the seconds of a cached gate run. A miss costs a CI round trip. So
the matcher is a deliberately loose regex over the command string rather than a shell
parser: it catches `git -C dir push`, `cd x && git push --force-with-lease`, and
`gh pr create`. Commands whose push-ness only appears after expansion (`$CMD`, `eval`,
a script that pushes internally) are out of sight and out of scope -- this is a
convenience gate, not a security control. The security control is pretooluse-guard.sh.

ESCAPE HATCH.

CLAUDE_PR_GATE=off skips everything. A gate with no way out gets uninstalled instead of
bypassed, and a bypass that is visible in the environment is better than one that is not.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib.machinery import SourceFileLoader

_lib = SourceFileLoader(
    "claude_hook_lib", str(Path(__file__).resolve().parent / "claude-hook-lib.py")
).load_module()

# Commands that publish. Loose on purpose -- see the module docstring.
PUBLISH_PATTERNS = (
    re.compile(r"\bgit\b[^;&|\n]*\bpush\b"),
    re.compile(r"\bgh\s+pr\s+(?:create|merge|ready)\b"),
)

# A push does not have to happen in the session's directory. `git -C <path> push` and
# `cd <path> && git push` both target a tree the payload's `cwd` knows nothing about, and
# gating the wrong tree is worse than not gating at all -- it reports a pass for checks
# that never ran against the code being pushed. Both forms are read out of the command.
TARGET_DIR_PATTERNS = (
    re.compile(r"\bgit\s+(?:-[^\s-]\S*\s+)*-C\s+(?P<path>'[^']+'|\"[^\"]+\"|\S+)"),
    re.compile(r"(?:^|[;&|]\s*)cd\s+(?P<path>'[^']+'|\"[^\"]+\"|\S+)"),
)

# Interactive-shell variables that change how non-interactive scripts behave, and that CI
# does not have. Measured, not theoretical: ~/dotfiles/bash/sharedrc exports CDPATH, which
# makes `cd` echo its resolved path to stdout, so the extremely common
# `cd "$(dirname "$0")/../.."` captures two lines and the script dies. That broke five of
# aws-infra's CI guards locally while all five pass in CI. A gate that reports failures CI
# does not have is worse than no gate: it teaches the agent that the gate lies.
# IFS is belt-and-braces: it is a shell variable and is not normally exported, so popping
# it usually removes nothing. The others are real and do get exported by interactive rc files.
HOSTILE_ENV = ("CDPATH", "GREP_OPTIONS", "POSIXLY_CORRECT", "BASH_ENV", "IFS")

CACHE_TTL_SEC = 24 * 60 * 60
# Token budget for a refusal. The refusal text is fed to the agent and then re-sent on
# every following call, so it is the one part of this hook with a recurring cost. Full
# output goes to a log file; only a digest and the path enter the conversation.
DIGEST_LINES = 30
DIGEST_CHARS = 1400
DEFAULT_TIMEOUT_SEC = 900


def publishes(command: str) -> bool:
    return any(pattern.search(command) for pattern in PUBLISH_PATTERNS)


def target_dirs(command: str, cwd: str) -> list[str]:
    """Directories this command might act on, most specific first, then the session cwd."""
    found: list[str] = []
    for pattern in TARGET_DIR_PATTERNS:
        for match in pattern.finditer(command):
            raw = match.group("path").strip("'\"")
            if "$" in raw or raw.startswith("-"):
                continue  # Expansion-derived: not resolvable statically.
            candidate = Path(raw)
            if not candidate.is_absolute():
                candidate = Path(cwd) / candidate
            if candidate.is_dir():
                found.append(str(candidate))
    found.append(cwd)
    return found


def repo_root(start: str) -> Path | None:
    try:
        out = subprocess.run(
            ["git", "-C", start, "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
    except Exception:
        return None
    if out.returncode != 0:
        return None
    path = Path(out.stdout.strip())
    return path if path.is_dir() else None


def git(root: Path, *args: str) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(root), *args], capture_output=True, text=True, timeout=60
        )
    except Exception:
        return ""
    return out.stdout


def config_slug(root: Path) -> str:
    """Key a repository by its absolute path, the way ~/.claude/projects/ already does.

    `/home/clevere/aws-infra-md4260` becomes `-home-clevere-aws-infra-md4260`. Keying by
    basename alone would collide between two checkouts of the same repo.
    """
    return str(root.resolve()).replace("/", "-")


def local_manifest(root: Path) -> Path | None:
    """A manifest held in the user's Claude config rather than in the repository.

    These gate manifests are personal tooling: they describe someone's local pre-push
    checks, not the project's contract. Committing one into a shared repository puts
    agent configuration into ticket-scoped PRs and, in repositories that require change
    tickets and approver trailers, makes a local convenience into a compliance artifact.
    So the config directory is searched FIRST and a repository that ships its own
    manifest is still honoured.
    """
    gates_dir = _lib.claude_home() / "gates"
    for candidate in (gates_dir / f"{config_slug(root)}.toml", gates_dir / f"{root.name}.toml"):
        if candidate.is_file():
            return candidate
    return None


def load_manifest(root: Path) -> tuple[list[dict], str] | None:
    """Return (checks, raw manifest text).

    Resolution order: ~/.claude/gates/<repo>.toml, then the repo's own
    .claude/gates.toml, then [tool.claude-gates] in pyproject.toml.
    """
    gates_file = local_manifest(root) or root / ".claude" / "gates.toml"
    if gates_file.is_file():
        raw = gates_file.read_text(encoding="utf-8")
        data = tomllib.loads(raw)
        checks = data.get("check")
        if isinstance(checks, list) and checks:
            return checks, raw
        return None

    pyproject = root / "pyproject.toml"
    if pyproject.is_file():
        raw = pyproject.read_text(encoding="utf-8")
        try:
            data = tomllib.loads(raw)
        except Exception:
            return None
        section = (data.get("tool") or {}).get("claude-gates") or {}
        checks = section.get("check")
        if isinstance(checks, list) and checks:
            return checks, json.dumps(section, sort_keys=True)
    return None


def fingerprint(root: Path, manifest: str) -> str:
    """Identify the exact tree the gates would run against.

    HEAD, the tracked diff and the untracked file list are hashed directly. Untracked
    file CONTENT is represented by (size, mtime) rather than bytes: cheap, and wrong only
    in the case where an untracked file is rewritten to the same size within the same
    nanosecond. Tracked content -- everything the gates actually read in a normal edit
    cycle -- is covered exactly.
    """
    digest = hashlib.sha256()
    digest.update(manifest.encode("utf-8", "replace"))
    digest.update(git(root, "rev-parse", "HEAD").encode())
    digest.update(git(root, "diff", "HEAD").encode("utf-8", "replace"))
    status = git(root, "status", "--porcelain", "--untracked-files=all")
    digest.update(status.encode("utf-8", "replace"))
    for line in status.splitlines():
        if not line.startswith("?? "):
            continue
        candidate = root / line[3:].strip().strip('"')
        try:
            stat = candidate.stat()
            digest.update(f"{candidate}:{stat.st_size}:{stat.st_mtime_ns}".encode())
        except OSError:
            continue
    return digest.hexdigest()


def cache_path(root: Path) -> Path:
    key = hashlib.sha256(str(root).encode()).hexdigest()[:16]
    return _lib.temp_root() / f"claude-pr-gate-{key}.json"


def cached_pass(root: Path, mark: str) -> bool:
    path = cache_path(root)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False
    if data.get("fingerprint") != mark:
        return False
    return (time.time() - float(data.get("ts", 0))) < CACHE_TTL_SEC


def record_pass(root: Path, mark: str, names: list[str]) -> None:
    payload = json.dumps({"fingerprint": mark, "ts": time.time(), "gates": names})
    try:
        _lib.write_private(cache_path(root), payload)
    except OSError:
        pass


def run_checks(root: Path, checks: list[dict]) -> tuple[str, str, str] | None:
    """Run the checks in declaration order. Return (name, command, output) on the first
    failure, or None when every check passed. Fail fast: the agent needs one thing to fix,
    not every consequence of one thing."""
    for check in checks:
        name = str(check.get("name") or "unnamed")
        command = check.get("run")
        if not isinstance(command, str) or not command.strip():
            continue
        env = dict(os.environ)
        for hostile in HOSTILE_ENV:
            env.pop(hostile, None)
        extra = check.get("env")
        if isinstance(extra, dict):
            env.update({str(k): str(v) for k, v in extra.items()})
        try:
            timeout = float(check.get("timeout", DEFAULT_TIMEOUT_SEC))
        except (TypeError, ValueError):
            timeout = DEFAULT_TIMEOUT_SEC
        try:
            result = subprocess.run(
                ["bash", "-c", command], cwd=str(root), env=env,
                capture_output=True, text=True, timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            return name, command, f"timed out after {timeout:.0f}s"
        except Exception as error:
            return name, command, f"could not run: {error}"
        if result.returncode != 0:
            full = _lib.redact((result.stdout + result.stderr).strip())
            return name, command, digest(root, name, full, result.returncode)
    return None


def digest(root: Path, name: str, full: str, code: int) -> str:
    """Bound what a failure costs in context, and put the rest on disk.

    A gate's full output is unbounded -- a pytest suite or a Checkov scan can run to
    thousands of lines. That text is handed to the agent and then re-sent on every
    subsequent call for the rest of the session, so an unbounded refusal is the one way
    this hook could cost more tokens than the CI round trip it prevents. The tail carries
    the summary for every tool used here; the whole log stays one `sed -n` away.
    """
    if not full:
        return f"exited {code}"
    log = _lib.temp_root() / f"claude-pr-gate-{root.name}-{name}.log"
    try:
        _lib.write_private(log, full + "\n")
        pointer = f"\n\nFull output ({full.count(chr(10)) + 1} lines): {log}"
    except OSError:
        pointer = ""
    lines = full.splitlines()
    clipped = lines[-DIGEST_LINES:]
    text = "\n".join(clipped)
    if len(text) > DIGEST_CHARS:
        text = text[-DIGEST_CHARS:]
    if len(clipped) < len(lines) or len(text) < len(full):
        text = "[...]\n" + text
    return text + pointer


def refuse(message: str) -> None:
    sys.stderr.write(message.rstrip() + "\n")
    sys.exit(2)


def main() -> None:
    if os.environ.get("CLAUDE_PR_GATE", "").lower() in {"off", "0", "false"}:
        sys.exit(0)

    payload = _lib.read_payload()
    if payload.get("tool_name") not in (None, "Bash"):
        sys.exit(0)
    command = ((payload.get("tool_input") or {}).get("command") or "")
    if not isinstance(command, str) or not publishes(command):
        sys.exit(0)

    cwd = payload.get("cwd") or os.getcwd()
    root = None
    for candidate in target_dirs(command, cwd):
        root = repo_root(candidate)
        if root is not None:
            break
    if root is None:
        sys.exit(0)

    try:
        manifest = load_manifest(root)
    except Exception as error:
        # A manifest that exists but will not parse is a gate that silently stopped
        # applying. Say so rather than waving the push through.
        refuse(
            f"PR gate: {root}/.claude/gates.toml could not be parsed ({error}).\n"
            "Fix the manifest, or set CLAUDE_PR_GATE=off for this push."
        )
    if manifest is None:
        sys.exit(0)  # No declared gates for this repository. Not our business.

    checks, raw = manifest
    mark = fingerprint(root, raw)
    if cached_pass(root, mark):
        sys.exit(0)

    failure = run_checks(root, checks)
    if failure is None:
        record_pass(root, mark, [str(c.get("name") or "unnamed") for c in checks])
        sys.exit(0)

    name, failed_command, output = failure
    refuse(
        f"PR gate failed: {name}\n\n"
        f"    {failed_command}\n\n"
        f"{output}\n\n"
        "This gate runs in CI on this repository, so the push was refused rather than\n"
        "spent on a round trip. Fix it and retry -- the gate is cached, so the checks\n"
        "that already passed will not run again unless the tree changes."
    )


if __name__ == "__main__":
    main()
