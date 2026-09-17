#!/usr/bin/env bash
set -euo pipefail

herdr_bin="${HERDR_BIN_PATH:-/home/clevere/.local/bin/herdr}"
workspace_id="${HERDR_ACTIVE_WORKSPACE_ID:?missing active Herdr workspace}"
pane_cwd="${HERDR_ACTIVE_PANE_CWD:?missing active Herdr pane directory}"

# Snapshot shared settings so each new tab starts with its own profile.
codex_dir="${CODEX_HOME:-$HOME/.codex}"
profile_file="$(mktemp "$codex_dir/herdr-tab-XXXXXXXXXX.config.toml")"
trap 'rm -f -- "$profile_file"' EXIT
cat "$codex_dir/config.toml" > "$profile_file"
profile_name="${profile_file##*/}"
profile_name="${profile_name%.config.toml}"

tab_json="$("$herdr_bin" tab create \
    --workspace "$workspace_id" \
    --cwd "$pane_cwd" \
    --label codex \
    --focus)"

pane_id="$(jq -r '.result.root_pane.pane_id // empty' <<<"$tab_json")"
if [[ -z "$pane_id" ]]; then
    printf 'Herdr did not return a pane id: %s\n' "$tab_json" >&2
    exit 1
fi

"$herdr_bin" pane run "$pane_id" \
    "exec /home/clevere/bin/codex --yolo --dangerously-bypass-hook-trust --model gpt-6-astra --config 'model_reasoning_effort=\"low\"' --profile $profile_name"
# Keep the profile for the running session and subsequent resume commands.
trap - EXIT
