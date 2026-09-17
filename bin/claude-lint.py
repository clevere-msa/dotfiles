#!/usr/bin/env python3
"""PostToolUse hook: format the file that was just edited, and report what formatting cannot fix.

WHY THIS FAILS SOFT, WHEN claude-pr-gate.py FAILS CLOSED.

The push gate refuses: a push is a discrete, rare, consequential act, and blocking one
costs seconds. This hook fires on EVERY edit. Anything it does badly, it does constantly.
So its posture is inverted -- a missing linter, an unreadable file, a tool that crashes,
a path outside a repository: all exit 0 in silence. It is a convenience, and a convenience
that interrupts is worse than one that is absent.

The two hooks are deliberately not consistent with each other, because the cost of a false
positive is not the same in both places.

OUTPUT CONTRACT (measured on this machine, not assumed).

A PostToolUse hook that exits 2 has its stderr delivered to the agent as a blocking error,
while the edit itself still lands. That is the behaviour this relies on: the file is
written, and the agent is told what is wrong with it. It cannot prevent the edit -- only
PreToolUse can -- and it does not try.

WHAT IT DOES.

Formatting is applied, never reported: `ruff format` and `terraform fmt` rewrite the file
in place and say nothing. Whitespace is not a decision, and a formatting complaint fed
back to the agent costs tokens and a follow-up edit to fix something the tool could have
fixed itself.

Everything else is reported and never applied: `ruff check` and `tflint` findings are real
decisions -- an undefined name, a missing variable type -- and are handed to the agent.
`ruff check --fix` is deliberately NOT used: deleting an "unused" import or reordering
code is a semantic change, and this hook fires too often to be trusted with those.

Auto-fixing is restricted to files inside a git working tree, so every rewrite this hook
performs is recoverable with `git diff` / `git checkout --`. Outside a repository it does
nothing at all.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from importlib.machinery import SourceFileLoader

_lib = SourceFileLoader(
    "claude_hook_lib", str(Path(__file__).resolve().parent / "claude-hook-lib.py")
).load_module()

# See claude-pr-gate.py: interactive rc files export variables that change how
# non-interactive tools behave. CDPATH in particular breaks `cd "$(dirname "$0")"`.
HOSTILE_ENV = ("CDPATH", "GREP_OPTIONS", "POSIXLY_CORRECT", "BASH_ENV", "IFS")

# This runs on every edit, and its output is re-sent on every following call. A linter that
# reports thirty findings on one file costs more than it saves, so it reports the first few
# and says how many it held back.
MAX_ISSUES = 8
MAX_CHARS = 900
TOOL_TIMEOUT = 45


def run(args: list[str], cwd: Path) -> subprocess.CompletedProcess | None:
    env = {k: v for k, v in os.environ.items() if k not in HOSTILE_ENV}
    try:
        return subprocess.run(
            args, cwd=str(cwd), env=env, capture_output=True, text=True, timeout=TOOL_TIMEOUT
        )
    except Exception:
        return None  # Missing binary, timeout, anything: this hook does not complain.


def which(name: str) -> str | None:
    from shutil import which as _which

    return _which(name)


def in_git_worktree(path: Path) -> bool:
    return git_root(path) is not None


def git_root(path: Path) -> Path | None:
    result = run(["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"], path.parent)
    if not result or result.returncode != 0:
        return None
    top = result.stdout.strip()
    return Path(top) if top else None


def ruff_configured(path: Path) -> bool:
    """True only if the project DECLARES a ruff style, walking up to the git root.

    Measured on this machine: `ruff format` would rewrite 59 of 98 Python files in
    aws-infra-md4260, which declares no ruff config and gates none of its 16 workflows
    on `ruff format --check`. Formatting a file to ruff's built-in defaults there would
    bury a one-line change in a whole-file diff that nothing upstream asked for.

    So the rewrite is opt-in by evidence: a `ruff.toml`, a `.ruff.toml`, or a
    `[tool.ruff]` table in a `pyproject.toml`. Reporting is not gated this way --
    `ruff check` only prints, and an undefined name is worth knowing about anywhere.
    """
    root = git_root(path)
    current = path.parent.resolve()
    stop = root.resolve() if root else current
    while True:
        if (current / "ruff.toml").is_file() or (current / ".ruff.toml").is_file():
            return True
        pyproject = current / "pyproject.toml"
        if pyproject.is_file():
            try:
                if "[tool.ruff" in pyproject.read_text(encoding="utf-8", errors="replace"):
                    return True
            except OSError:
                pass
        if current == stop or current == current.parent:
            return False
        current = current.parent


def digest_of(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def clip(issues: list[str]) -> str:
    held = len(issues) - MAX_ISSUES
    shown = issues[:MAX_ISSUES]
    text = "\n".join(shown)
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS] + " [...]"
    if held > 0:
        text += f"\n({held} more not shown)"
    return text


def lint_python(path: Path) -> tuple[bool, list[str]]:
    if not which("ruff"):
        return False, []
    configured = ruff_configured(path)
    before = digest_of(path)
    # --force-exclude is required: ruff ignores its own exclude lists when handed an
    # explicit path, so without it this reformats files the project deliberately pins.
    if configured:
        run(["ruff", "format", "--force-exclude", str(path)], path.parent)
    formatted = bool(before) and digest_of(path) != before

    command = ["ruff", "check", "--force-exclude", "--output-format=concise"]
    if not configured:
        # ruff 0.16's defaults include isort (I), so an unconfigured repo gets told its
        # import block is "un-sorted" against a style it never adopted -- the same
        # unasked-for churn as the formatting, just reported instead of written.
        # Verified on this machine: a bare directory with no config reports I001.
        # Where the project declares nothing, report only defects: E9 (syntax errors)
        # and F (pyflakes -- undefined names, unused imports).
        command.append("--select=E9,F")
    command.append(str(path))
    result = run(command, path.parent)
    if not result or result.returncode == 0:
        return formatted, []
    # Keep only the diagnostic lines. ruff's trailing summary ("Found 4 errors.",
    # "[*] 2 fixable with the --fix option") tells the agent nothing it cannot see from
    # the diagnostics themselves, and every line here is re-sent on each following call.
    prefix = f"{path.name}:"
    return formatted, [
        line for line in result.stdout.splitlines()
        if line.strip() and (prefix in line or line.startswith(str(path)))
    ]


def lint_terraform(path: Path) -> tuple[bool, list[str]]:
    # Unlike ruff, `terraform fmt` needs no opt-in: it is the one canonical HCL style,
    # and aws-infra's CI already gates on it (tests/ci/test_terraform_fmt.sh).
    before = digest_of(path)
    if which("terraform"):
        run(["terraform", "fmt", str(path.name)], path.parent)
    formatted = bool(before) and digest_of(path) != before
    tflint = which("tflint")
    if not tflint:
        return formatted, []
    # --filter scopes findings to THIS file. Without it, editing one file in a module
    # reports every pre-existing issue in its siblings -- noise the agent did not cause
    # and should not be asked to fix mid-task.
    # tflint reads `.tflint.hcl` from its working directory only -- it does NOT walk up.
    # Verified: with the terraform ruleset disabled in the repo-root config, a run from
    # applications/authsys still reported its 2 issues. Since this runs from the module
    # directory (so --filter matches), the root config has to be passed explicitly or the
    # repo's linting policy is silently ignored.
    command = [tflint, "--format=json", f"--filter={path.name}"]
    root = git_root(path)
    if root and not (path.parent.resolve() / ".tflint.hcl").is_file():
        # Same reasoning as the gate manifests: a personal ruleset belongs in the user's
        # config, not committed into a shared repository. Since --config is passed
        # explicitly anyway (tflint does not walk up), the file can live anywhere.
        slug = str(root.resolve()).replace("/", "-")
        tflint_dir = _lib.claude_home() / "tflint"
        for config in (
            tflint_dir / f"{slug}.hcl",
            tflint_dir / f"{root.name}.hcl",
            root / ".tflint.hcl",
        ):
            if config.is_file():
                command.append(f"--config={config}")
                break
    result = run(command, path.parent)
    if not result or not result.stdout.strip():
        return formatted, []
    try:
        payload = json.loads(result.stdout)
    except ValueError:
        return formatted, []
    issues = []
    for issue in payload.get("issues", []):
        line = (issue.get("range") or {}).get("start", {}).get("line", "?")
        rule = (issue.get("rule") or {}).get("name", "tflint")
        issues.append(f"{path.name}:{line} {rule}: {issue.get('message', '').strip()}")
    for error in payload.get("errors", []):
        message = str(error.get("message", "")).strip()
        if message:
            issues.append(f"{path.name}: {message}")
    return formatted, issues


def shellcheck_configured(path: Path) -> bool:
    """True if the project DECLARES shellcheck as its standard.

    Same reasoning as ruff_configured: severity is a policy, and imposing one the
    project never adopted is noise. The signals, cheapest first -- a `.shellcheckrc`
    walking up to the git root, shellcheck named in the repo's own gate manifest, or
    shellcheck in its workflows. The crawler qualifies (CI runs bare `shellcheck` on
    tools/, scripts/ and tests/shell/); aws-infra and dotfiles run it nowhere.
    """
    root = git_root(path)
    current = path.parent.resolve()
    stop = root.resolve() if root else current
    while True:
        if (current / ".shellcheckrc").is_file():
            return True
        if current == stop or current == current.parent:
            break
        current = current.parent
    if not root:
        return False
    manifest = root / ".claude" / "gates.toml"
    try:
        if manifest.is_file() and "shellcheck" in manifest.read_text(
            encoding="utf-8", errors="replace"
        ):
            return True
    except OSError:
        pass
    workflows = root / ".github" / "workflows"
    if workflows.is_dir():
        for wf in workflows.glob("*.y*ml"):
            try:
                if "shellcheck" in wf.read_text(encoding="utf-8", errors="replace"):
                    return True
            except OSError:
                continue
    return False


def lint_shell(path: Path) -> tuple[bool, list[str]]:
    """Report only -- shell is never rewritten.

    shfmt is not installed and no repository here declares a shell style
    (no .editorconfig, no .shellcheckrc), so there is nothing to format *to*.
    Reformatting 200+ scripts in dotfiles/bin to a tool's built-in defaults would be
    the ruff mistake again, with a bigger blast radius. If a shell style is ever
    adopted, add shfmt here behind the same declared-style check.
    """
    if not which("shellcheck"):
        return False, []
    command = ["shellcheck", "--format=gcc"]
    if not shellcheck_configured(path):
        # Errors and warnings are defects in any dialect; info and style are opinions.
        command.append("--severity=warning")
    command.append(path.name)
    result = run(command, path.parent)
    if not result or result.returncode == 0:
        return False, []
    prefix = f"{path.name}:"
    return False, [
        line.strip() for line in result.stdout.splitlines() if line.strip().startswith(prefix)
    ]


SHELL_SHEBANG = re.compile(r"^#!.*\b(?:bash|sh|dash|ksh)\b")


def is_shell_script(path: Path) -> bool:
    """Shell scripts frequently have no extension (`scripts/install-perl-toolchain`).

    The shebang is the only reliable signal, and it also keeps the many Perl scripts in
    dotfiles/bin out. Files with no shebang at all are skipped deliberately: bashrc,
    aliases and sharedrc are sourced fragments, not scripts, and shellcheck on them
    reports undefined-variable noise about things their caller defines.
    """
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            return bool(SHELL_SHEBANG.match(handle.readline()))
    except OSError:
        return False


DISPATCH = {
    ".py": lint_python,
    ".pyi": lint_python,
    ".tf": lint_terraform,
    ".tfvars": lint_terraform,
    ".sh": lint_shell,
    ".bash": lint_shell,
}


def main() -> None:
    if os.environ.get("CLAUDE_LINT", "").lower() in {"off", "0", "false"}:
        sys.exit(0)

    payload = _lib.read_payload()
    raw = (payload.get("tool_input") or {}).get("file_path")
    if not isinstance(raw, str) or not raw:
        sys.exit(0)

    path = Path(raw)
    if not path.is_file():
        sys.exit(0)
    handler = DISPATCH.get(path.suffix.lower())
    if handler is None and is_shell_script(path):
        handler = lint_shell
    if handler is None:
        sys.exit(0)
    if _lib.sensitive_path(str(path)) or not in_git_worktree(path):
        sys.exit(0)

    try:
        formatted, issues = handler(path)
    except Exception:
        sys.exit(0)

    if not issues:
        sys.exit(0)  # Nothing left to decide; any reformatting stays silent.

    lead = "reformatted; " if formatted else ""
    sys.stderr.write(
        f"{path.name}: {lead}these need a decision:\n\n"
        f"{_lib.redact(clip(issues))}\n"
    )
    sys.exit(2)


if __name__ == "__main__":
    main()
