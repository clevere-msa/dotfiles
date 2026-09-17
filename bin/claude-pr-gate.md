# claude-pr-gate

A `PreToolUse` hook that runs a repository's CI gate set locally before a push or PR can
leave, and refuses the push when a gate fails.

## Why this exists

`~/.claude/skills/python-*` are prose. `python-testing-quality-gates` says "run quality
gates used by the repository" and "do not claim pass without command output" -- good
instructions that hold only as long as the model follows them. Nothing checks. The
failure mode is cheap to describe and expensive to live with: a push goes out, CI runs for
several minutes, and the answer is an import sort that `ruff check` knew about in 40ms.

This closes that loop deterministically. The model's compliance is no longer load-bearing.

## What it is not

It is not a security control, and it does not extend one. `pretooluse-guard.sh` (the
`ai_guardrails` submodule) refuses production-mutating commands and is fail-closed by
design. This hook is a convenience gate with a documented escape hatch. They are composed
as two separate `PreToolUse` entries; neither knows about the other.

## Layers

| Layer | Event | Stops a bad push? | Status |
|---|---|---|---|
| Push gate | `PreToolUse` / Bash | Yes -- the only event that can | **built** |
| Per-file lint | `PostToolUse` / Write\|Edit | No; feedback at introduction | proposed |
| Session sweep | `Stop` | No | proposed, most likely to become noise |

Only `PreToolUse` can prevent the tool call. `PostToolUse` fires after the edit lands, so
it can tell the agent a file is now unformatted but cannot stop it being written -- still
worth having, because catching it at introduction is cheaper than catching it at push.

## Configuration

Gates are declared per repository, never hardcoded in the hook: this hook is registered in
`~/.claude/settings.json` and therefore fires in every repository under this home
directory. A repository with no manifest is a silent no-op.

The manifest is `.claude/gates.toml`, or a `[tool.claude-gates]` table in `pyproject.toml`:

```toml
[[check]]
name = "ruff-lint"
run = "uv run --no-sync ruff check --force-exclude ."
env = { PYTHONPATH = "src" }   # optional
timeout = 900                  # optional, seconds, default 900
```

Checks run in declaration order from the repository root, stopping at the first failure --
the agent needs one thing to fix, not every downstream consequence of one thing. Order
them cheapest-first.

**Transcribe the list from the repository's own workflow.** A manifest that drifts from CI
is worse than no manifest: it teaches the agent that a green local run means nothing.

## Two things that will silently break a manifest

- **`ruff` ignores its own `exclude`/`extend-exclude` when given an explicit path.** Use
  `--force-exclude`. Without it the gate reports failures CI does not have, and a gate
  that cries wolf gets routed around.
- **`uv run` may sync on invocation.** Use `--no-sync`. A pre-push gate that can block on
  a package index is a gate people switch off.

## Behaviour

- **Push detection** is a loose regex over the command string (`git … push`,
  `cd x && git push --force-with-lease`, `git -C dir push`, `gh pr create|merge|ready`).
  It fails *toward* running: a false positive costs a cached run, a miss costs a CI round
  trip. Commands whose push-ness only appears after expansion (`$CMD`, `eval`, a script
  that pushes internally) are out of scope.
- **Pass cache** keyed on HEAD + tracked diff + untracked file list, in `$TMPDIR`, 24h TTL.
  Measured: 1044ms cold, 40ms warm. Without it the gate is too slow to survive.
- **Failure** exits 2 -- the only code Claude Code treats as a block -- with the gate name,
  its command and the tail of its output on stderr, redacted through `claude-hook-lib`'s
  secret patterns and capped at 3000 characters.
- **A manifest that will not parse refuses the push.** A gate that silently stops applying
  is the failure this is built to prevent.
- **`CLAUDE_PR_GATE=off`** skips everything. A gate with no way out gets uninstalled
  rather than bypassed.

## Token cost, which is the point as much as the time cost

A gate caught locally costs one bounded refusal. The same failure caught in CI costs a
`gh run view --log-failed` -- routinely 20-50k tokens of log, re-sent on every following
call for the rest of the session -- plus a fix, a re-push and a second wait.

So the hook is built to spend as little context as it can:

- **A passing run is silent.** Exit 0, no output, nothing enters the conversation.
- **A failing run is bounded**: the last 30 lines / 1400 characters, with the full log
  written to `$TMPDIR/claude-pr-gate-<repo>-<gate>.log` and only its path in context.
  Measured: a 5000-line tool output becomes 1034 characters. A real `terraform fmt`
  failure costs 793 characters -- about 200 tokens.
- **Only the first failure is reported.** One thing to fix, not every consequence of it.
- **The agent should not run these gates by hand.** Doing so puts the full output in
  context; letting the hook run them keeps it in a subprocess.

## Installed

- `~/.claude/settings.json` -> `PreToolUse` / `Bash` (backup at `settings.json.bak-pr-gate`)
- `business-process-modeling-api-crawler/.claude/gates.toml` -- 12 checks transcribed from
  `full-test-suite.yml` and `ai-guardrails.yml`
- `aws-infra-md4260/.claude/gates.toml` -- 15 checks, the credential-free subset of the 16
  workflows that gate a PR there. ~28s cold, ~54ms cached.

The two policy checks at the front of that manifest are worth copying to any MSA
repository: they are pure string checks needing no toolchain, and they catch a class of PR
failure the test suite never will -- pushing from the integration branch itself, and a
missing `Change-Ticket:` trailer. Only the trailer is checkable locally; the workflow also
accepts the PR title and body, which do not exist yet at push time.

## Verified, not assumed

Checks run against this machine while building it, because each of these is a way the hook
could have looked correct and done nothing:

- The payload key is `cwd`, and `tool_name` / `tool_input.command` are as assumed
  (captured from a live `PreToolUse` invocation, not from documentation).
- `git -C /other/repo push` and `cd /other/repo && git push` gate **that** repository, not
  the session's. Gating the wrong tree is worse than not gating: it reports a pass for
  checks that never ran against the code being pushed.
- The gates *catch* a deliberately broken file, not merely pass on a clean one.
- `ruff format --check --force-exclude` still honours the three self-pinned
  `tidy_snapshot` exclusions when paths are passed explicitly.
- `uv run --no-sync` resolves to the existing `.venv` with no network access.
- A manifest that will not parse refuses; a repository with no manifest is silent.

Known gap: the `change-ticket-trailer` fallback range (`HEAD~1..HEAD`) errors rather than
explaining itself in a repository with no `origin`. Such a repository is not opening a PR,
so this is accepted rather than fixed.

## Terraform notes

Terraform splits cleanly into what can be gated locally and what cannot, and the split is
not where the skills suggest:

- **`terraform fmt -check -recursive` needs nothing** -- no init, no backend, no
  credentials. It is the cheapest real gate available (0.8s repo-wide) and the one most
  worth having.
- **`terraform validate` requires `terraform init`**, which reaches a provider registry and
  a backend. It is not a local gate. In `aws-infra` it only appears inside credentialed
  plan workflows, so gating it locally would add a network dependency for a check CI does
  not run on its own either.
- **Anything that plans** needs AWS credentials and is out of scope by definition.

`terraform-style-guide` and `terrashark` are worth reading for what they imply about
enforcement rather than what they say: nearly every rule they state ("require `type` and
`description` on variables", "prefer `for_each` over `count`") is a `tflint` rule. tflint
is **not installed on this machine** and `aws-infra` has no `.tflint.hcl`, so those rules
are currently advisory everywhere. Installing tflint and adding a ruleset would convert the
largest block of that skill's prose into gates; that is the obvious next step and is not
done here.

### The environment trap

`~/dotfiles/bash/sharedrc` exports `CDPATH`. With `CDPATH` set, `cd` echoes its resolved
path to stdout, so the very common `cd "$(dirname "$0")/../.."` captures two lines and the
script dies. Five of `aws-infra`'s CI guards fail locally for this reason alone while
passing in CI.

This is the single most dangerous class of bug for a gate like this, because it produces
failures CI does not have -- and a gate that cries wolf gets routed around within a day.
The runner therefore strips `CDPATH`, `GREP_OPTIONS`, `POSIXLY_CORRECT`, `BASH_ENV` and
`IFS` from the environment it hands each check. If a gate ever fails locally and passes in
CI, suspect the environment before the code.

### Known gap in this manifest

`validate-approval-controls.yml` runs `pytest tests/controls/` (330 files) on every PR.
pytest is not installed on this machine; CI installs it per run. The check is left
commented out in the manifest with the enabling command (`uv tool install pytest`) rather
than silently omitted or made to block every push on a missing tool.

---

# claude-lint (PostToolUse)

The second layer, added after the push gate. `~/dotfiles/bin/claude-lint.py` runs on every
`Write`/`Edit`/`MultiEdit`/`NotebookEdit` and handles the file that was just touched.

**Formatting is applied, never reported.** `ruff format` and `terraform fmt` rewrite the
file in place and say nothing. Whitespace is not a decision, and a formatting complaint
costs tokens plus a follow-up edit to fix something the tool could have fixed itself.

**But only against a style the project actually declares.** `ruff format` runs only if a
`ruff.toml`, `.ruff.toml`, or `[tool.ruff]` table is found walking up to the git root.
Measured: `ruff format` would rewrite **59 of 98** Python files in `aws-infra-md4260`,
which declares no ruff config and gates none of its 16 workflows on `ruff format --check`.
Formatting there would bury a one-line change in a whole-file diff nothing upstream asked
for -- the same mistake as inventing a gate, made in the editor instead of the manifest.

The same logic applies to reporting. ruff 0.16 includes isort in its defaults, so an
unconfigured repository gets told its import block is "un-sorted" against a style it never
adopted. Verified in a bare directory with no config: `I001` is reported. So where nothing
is declared, the hook passes `--select=E9,F` and reports only defects -- syntax errors,
undefined names, unused imports -- never style.

`terraform fmt` needs no such opt-in: it is the one canonical HCL style, and `aws-infra`
CI already gates on it (`tests/ci/test_terraform_fmt.sh`).

**Everything else is reported, never applied.** `ruff check` and `tflint` findings are real
decisions -- an undefined name, an untyped variable -- so they go to the agent.
`ruff check --fix` is deliberately not used: removing an "unused" import or reordering code
is a semantic change, and this hook fires far too often to be trusted with those.

## Posture: this one fails soft, the push gate fails closed

The inversion is deliberate. A push is rare and consequential, so blocking one costs
seconds. This fires on every edit, so anything it does badly it does constantly. A missing
linter, an unreadable file, a crashing tool, a path outside a repository -- all exit 0 in
silence.

Auto-fixing is restricted to files inside a git working tree, so every rewrite is
recoverable with `git diff` / `git checkout --`. Outside a repository it does nothing.

## Output contract, measured

A `PostToolUse` hook that exits 2 has its stderr delivered to the agent as a blocking
error, **while the edit still lands**. Verified on this machine with a probe hook, not
assumed. It cannot prevent an edit -- only `PreToolUse` can -- and does not try.

Output is capped at 8 findings / 900 characters, and ruff's trailing summary lines
("Found 4 errors.", "[*] 2 fixable...") are stripped: they repeat what the diagnostics
already say, and every line is re-sent on each following call.

Escape hatch: `CLAUDE_LINT=off`.

## Coverage

| Extension | Applied silently | Reported |
|---|---|---|
| `.py`, `.pyi` | `ruff format --force-exclude` *(only if ruff is configured)* | `ruff check --force-exclude` *(`--select=E9,F` if not configured)* |
| `.tf`, `.tfvars` | `terraform fmt` | `tflint --filter=<file> --config=<git root>/.tflint.hcl` |
| `.sh`, `.bash`, or any shebang file | *(nothing)* | `shellcheck --format=gcc` (`--severity=warning` if not declared) |

The header says "reformatted; these need a decision" only when the file actually changed
on disk -- compared by hash before and after, not assumed from the tool having run.

`--force-exclude` on both ruff calls is required, not decoration -- ruff ignores its own
exclude lists when handed an explicit path, so without it the hook reformats files a
project deliberately pins.

`--filter` on tflint scopes findings to the edited file. Without it, editing one file in a
module reports every pre-existing issue in its siblings: noise the agent did not cause and
should not be asked to fix mid-task.

`--config` is passed explicitly because **tflint reads `.tflint.hcl` from its working
directory only -- it does not walk up to the repository root.** The hook runs from the
module directory so `--filter` matches, which would otherwise mean the repo's ruleset is
silently ignored. Verified by disabling the terraform ruleset in the root config: before
the fix a run from `applications/authsys/` still reported its 2 findings; after, it is
silent, and re-enabling brings both findings back.

## tflint

Installed 2026-09-17 at `~/.local/bin/tflint` (v0.64.0, bundled terraform ruleset), with
`aws-infra-md4260/.tflint.hcl` set to the `recommended` preset. Measured blast radius on
one module: 2 findings, both legitimate.

This converts the bulk of the `terraform-style-guide` skill from prose into checks --
typed variables, required descriptions, unused declarations, required_version and
required_providers. It is **not** a PR gate and is deliberately absent from
`.claude/gates.toml`: no workflow runs tflint, and gating on it would block pushes over
pre-existing findings until the repository has been swept.

## Shell

**Report only -- shell is never rewritten.** shfmt is not installed and no repository
here declares a shell style (no `.editorconfig`, no `.shellcheckrc`), so there is nothing
to format *to*. Reformatting the 200+ scripts in `bin/` and `sbin/` to a tool's built-in
defaults would be the `ruff format` mistake again with a larger blast radius. If a shell
style is ever adopted, add shfmt behind the same declared-style check.

**Severity follows the project, as with ruff.** Where shellcheck is declared -- a
`.shellcheckrc`, or shellcheck named in the repo's `.claude/gates.toml` or workflows --
it runs at full severity, matching CI exactly. The crawler qualifies: CI runs bare
`shellcheck` on `tools/`, `scripts/` and `tests/shell/`. Everywhere else it runs
`--severity=warning`, reporting defects and dropping opinions.

Measured: the three crawler scripts CI already passes are **silent** through the hook, as
they must be. In `dotfiles`, 15 of 40 shell scripts report at warning level -- mostly one
finding each, and all genuine rather than stylistic: `SC2068` (unquoted array expansion,
an error), `SC2076` (quoted right-hand side of `=~`, which matches literally instead of as
a regex), `SC2164` (`cd` without `|| exit`), `SC2034`, `SC2155`. This repository has not
been swept, so opening an old script may surface findings that predate the edit.

**Which files count as shell.** Extension `.sh` or `.bash`, or any file whose first line is
a `bash`/`sh`/`dash`/`ksh` shebang -- shell scripts often have no extension
(`scripts/install-perl-toolchain`). The shebang is also what keeps the many Perl scripts in
`bin/` out. Files with **no** shebang are skipped deliberately: `bashrc`, `aliases` and
`sharedrc` are sourced fragments, not scripts, and shellcheck reports undefined-variable
noise about things their caller defines.

**Nothing was added to the gate layer for shell.** The crawler's manifest already
transcribes CI's `shell-syntax` (`bash -n`) and `shellcheck` checks. `aws-infra` runs
neither, and `dotfiles` has no CI at all -- so shell is gated exactly where CI gates it,
and inventing a gate for the others is the thing this whole design exists to avoid.
