#!/usr/bin/env bash
set -euo pipefail

herdr_bin="${HERDR_BIN_PATH:-/home/clevere/.local/bin/herdr}"
workspace_id="${HERDR_ACTIVE_WORKSPACE_ID:?missing active Herdr workspace}"
pane_cwd="${HERDR_ACTIVE_PANE_CWD:?missing active Herdr pane directory}"

tab_json="$("$herdr_bin" tab create \
    --workspace "$workspace_id" \
    --cwd "$pane_cwd" \
    --label claude \
    --no-focus)"

pane_id="$(jq -r '.result.root_pane.pane_id // empty' <<<"$tab_json")"
tab_id="$(jq -r '.result.tab.tab_id // empty' <<<"$tab_json")"
if [[ -z "$pane_id" || -z "$tab_id" ]]; then
    printf 'Herdr did not return a pane id and tab id: %s\n' "$tab_json" >&2
    exit 1
fi

"$herdr_bin" pane run "$pane_id" "exec /home/clevere/.local/bin/claude"
exec "$herdr_bin" tab focus "$tab_id"
