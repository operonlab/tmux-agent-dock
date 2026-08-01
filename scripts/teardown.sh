#!/usr/bin/env bash
# teardown.sh — undo everything tmux-agent-dock installed into a running tmux
# server. Safe to run repeatedly.
#
# Removes: the prefix binding (whatever @agent-dock-bind resolved to) and the
# dock pane if it is open.
#
# Deliberately left alone:
#   * the @agent-dock-* lines in your tmux.conf — those are yours to edit
#   * the version cache under ~/.cache/tmux-agent-dock (see --purge-cache)
#   * every agent pane, which this plugin only ever reads, jumps to, or stops
#     when you explicitly ask it to
#
# No `set -e`: tmux reports a non-zero exit from run-shell as an error.

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${CURRENT_DIR}/helpers.sh"

KEY="$(get_tmux_option "@agent-dock-bind" "A")"
[ "$KEY" = "none" ] || tmux unbind-key -T prefix "$KEY" 2>/dev/null

# Close the dock pane if it is open (marked with @agent_dock on the pane).
dockid=$(tmux list-panes -a -F '#{pane_id} #{@agent_dock}' 2>/dev/null | awk '$2=="1"{print $1}')
for id in $dockid; do
	tmux kill-pane -t "$id" 2>/dev/null
done

if [ "${1:-}" = "--purge-cache" ]; then
	cache="${AGENT_DOCK_VCACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-dock}"
	cache="${cache%/versions.tsv}"
	case "$cache" in
		*/tmux-agent-dock)
			[ -d "$cache" ] && [ ! -L "$cache" ] && rm -rf "$cache"
			;;
	esac
fi

tmux display-message "tmux-agent-dock removed (binding + pane)" 2>/dev/null || true
exit 0
