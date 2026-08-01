#!/usr/bin/env bash
# agent-dock.tmux — TPM entry point for tmux-agent-dock.
#
# TPM sources this file once at tmux start. It installs a single prefix-table
# binding that toggles the dock — a full-height sidebar on the right edge of the
# current window listing every live AI-CLI pane.
#
# The binding is @agent-dock-bind; set it to "none" to skip it and call
# scripts/dock.sh toggle from your own binding instead. The default key is A,
# which tmux does not bind itself (verified against tmux next-3.8 defaults).

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${CURRENT_DIR}/scripts/helpers.sh"

DOCK_SCRIPT="${CURRENT_DIR}/scripts/dock.sh"

KEY="$(get_tmux_option "@agent-dock-bind" "A")"
if [ "$KEY" != "none" ]; then
	tmux bind-key -T prefix "$KEY" run-shell "bash '${DOCK_SCRIPT}' toggle"
fi

# A matched-case guard can leave a non-zero $? on a clean run; do not let that
# surface as a scary "returned 1" on every config reload.
exit 0
