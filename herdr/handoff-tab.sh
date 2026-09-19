#!/usr/bin/env bash
set -euo pipefail

# Bound to prefix+Shift+O.
#
# A Herdr keybinding runs as a plain shell command and has no access to the
# conversation in the pane, so it cannot write the handoff itself. Instead it
# types /herdr-handoff into the live Claude pane and lets that session -- which
# does have the context -- write the doc and open the seeded tab.

herdr_bin="${HERDR_BIN_PATH:-/home/clevere/.local/bin/herdr}"

pane_id="${HERDR_ACTIVE_PANE_ID:-}"
if [[ -z "$pane_id" ]]; then
    pane_id="$("$herdr_bin" pane current | jq -r '.result.pane.pane_id // empty')"
fi
if [[ -z "$pane_id" ]]; then
    printf 'Could not determine the current Herdr pane.\n' >&2
    exit 1
fi

agent="$("$herdr_bin" pane get "$pane_id" | jq -r '.result.pane.agent // empty')"
if [[ "$agent" != "claude" ]]; then
    printf 'prefix+Shift+O needs a Claude pane; this pane is running: %s\n' "${agent:-nothing}" >&2
    exit 1
fi

"$herdr_bin" pane send-text "$pane_id" "/herdr-handoff"
exec "$herdr_bin" pane send-keys "$pane_id" enter
