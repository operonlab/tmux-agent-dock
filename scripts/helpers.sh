#!/usr/bin/env bash
# helpers.sh — shared option helper for tmux-agent-dock.
#
# Sourced, not executed. It intentionally does NOT use `set -e`: it is pulled
# into scripts tmux calls from a binding via run-shell, where a non-zero exit is
# treated as an error.

# get_tmux_option <option-name> <default-value>
# Read a global tmux user option, falling back to a default when unset/empty.
get_tmux_option() {
	option_name="$1"
	default_value="$2"
	option_value=$(tmux show-option -gqv "$option_name" 2>/dev/null)
	if [ -z "$option_value" ]; then
		printf '%s' "$default_value"
	else
		printf '%s' "$option_value"
	fi
}
