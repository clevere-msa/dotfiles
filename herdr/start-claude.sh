#!/usr/bin/env bash
set -euo pipefail

# Usage: start-claude.sh [initial-prompt] [tab-label]
#
# Creates a new Herdr tab, starts Claude in it, and focuses it. With an initial
# prompt, Claude starts seeded with that prompt. Used by prefix+Shift+C (no
# arguments) and by the herdr-handoff skill (prompt pointing at a handoff doc).

herdr_bin="${HERDR_BIN_PATH:-/home/clevere/.local/bin/herdr}"
claude_bin="/home/clevere/.local/bin/claude"

initial_prompt="${1:-}"
tab_label="${2:-claude}"

# HERDR_ACTIVE_* are set for keybinding commands. A skill running inside an
# already-started Claude process has not inherited them, so fall back to asking
# Herdr which pane is current.
workspace_id="${HERDR_ACTIVE_WORKSPACE_ID:-}"
pane_cwd="${HERDR_ACTIVE_PANE_CWD:-}"
if [[ -z "$workspace_id" || -z "$pane_cwd" ]]; then
    current_json="$("$herdr_bin" pane current)"
    [[ -n "$workspace_id" ]] || workspace_id="$(jq -r '.result.pane.workspace_id // empty' <<<"$current_json")"
    [[ -n "$pane_cwd" ]] || pane_cwd="$(jq -r '.result.pane.cwd // empty' <<<"$current_json")"
fi
if [[ -z "$workspace_id" || -z "$pane_cwd" ]]; then
    printf 'Could not determine the active Herdr workspace and directory.\n' >&2
    exit 1
fi

tab_json="$("$herdr_bin" tab create \
    --workspace "$workspace_id" \
    --cwd "$pane_cwd" \
    --label "$tab_label" \
    --no-focus)"

pane_id="$(jq -r '.result.root_pane.pane_id // empty' <<<"$tab_json")"
tab_id="$(jq -r '.result.tab.tab_id // empty' <<<"$tab_json")"
if [[ -z "$pane_id" || -z "$tab_id" ]]; then
    printf 'Herdr did not return a pane id and tab id: %s\n' "$tab_json" >&2
    exit 1
fi

# pane run types this into the new pane's shell, so quote the prompt for the
# shell rather than interpolating it raw.
if [[ -n "$initial_prompt" ]]; then
    printf -v quoted_prompt '%q' "$initial_prompt"
    "$herdr_bin" pane run "$pane_id" "exec $claude_bin $quoted_prompt"
else
    "$herdr_bin" pane run "$pane_id" "exec $claude_bin"
fi

exec "$herdr_bin" tab focus "$tab_id"
