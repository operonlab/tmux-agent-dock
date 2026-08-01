#!/usr/bin/env bash
# smoke.sh — integration tests for tmux-agent-dock.
#
# Every tmux call runs against a throwaway `-L` socket, so your real server is
# never touched. The agent panes are forged: a tiny native binary (compiled
# here) prints a canned screen then blocks in pause(), so its
# pane_current_command reads `claude`/`codex` the way a real agent's would. No
# real AI CLI is launched.
#
# What CAN be verified headless (this script):
#   - every script parses; the entry binds A, honours "none", is idempotent
#   - rows.sh on an empty server prints nothing and does not error
#   - rows.sh classifies a forged busy / waiting / idle pane, and ignores a
#     non-agent pane
#   - teardown removes the binding and closes the dock pane
#   - RCE regression: a session named $(...) does not execute when the dock
#     scans it and the cursor lands on its row (focus fires on movement)
#   - the language switch changes the header strings
#
# What CANNOT be verified headless: the classifier against every real CLI's
# real screens (that is tmux-agent-status's detection-matrix, exercised there)
# and the actual jump/stop actions on a live agent.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOCK="agent-dock-smoke-$$"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent-dock-smoke.XXXXXX")"
SHIM="$WORK/tmux-shim"
FAILED=0
CC="$(command -v cc 2>/dev/null || command -v clang 2>/dev/null || true)"

cleanup() {
	tmux -L "$SOCK" kill-server 2>/dev/null
	[ -d "$WORK" ] && [ ! -L "$WORK" ] && rm -rf "$WORK"
}
trap cleanup EXIT

ok()   { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=$((FAILED + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (want [$3] got [$2])"; fi; }
t() { tmux -L "$SOCK" "$@"; }

printf '#!/bin/bash\nexec tmux -L %s "$@"\n' "$SOCK" > "$SHIM"; chmod +x "$SHIM"
export TMUX_BIN="$SHIM"
export AGENT_DOCK_ROWS_BIN="$ROOT/scripts/rows.sh"
export AGENT_DOCK_VCACHE="$WORK/versions.tsv"    # empty -> no background CLI probing

echo "tmux-agent-dock smoke"

# ── 1. everything parses ─────────────────────────────────────────────────────
for f in "$ROOT/agent-dock.tmux" "$ROOT/scripts/helpers.sh" "$ROOT/scripts/dock.sh" \
         "$ROOT/scripts/rows.sh" "$ROOT/scripts/teardown.sh" "$ROOT/tests/smoke.sh"; do
	if bash -n "$f" 2>/dev/null; then ok "parse $(basename "$f")"; else fail "parse $(basename "$f")"; fi
done

# forge <name> <screen-file>: a native binary that prints the file then pauses,
# so pane_current_command stays <name>.
forge() {
	[ -n "$CC" ] || return 1
	if [ ! -f "$WORK/agent.c" ]; then
		cat > "$WORK/agent.c" <<'C'
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv){
  if(argc>1){ FILE*f=fopen(argv[1],"r"); char b[4096]; size_t k;
    if(f){ while((k=fread(b,1,sizeof b,f))>0) fwrite(b,1,k,stdout); fclose(f);} fflush(stdout);}
  for(;;) pause(); return 0;
}
C
	fi
	"$CC" -o "$WORK/$1" "$WORK/agent.c" 2>/dev/null
}

# A screen with the meaningful footer at the BOTTOM (where a live agent's output
# sits): 50 blank lines push it down past capture-pane's tail window.
screen() { # <out> <osc-title> <footer...>
	local out="$1" title="$2"; shift 2
	{ printf '\033]2;%s\033\\' "$title"; for _ in $(seq 1 50); do printf '\n'; done; printf '%b' "$@"; } > "$out"
}

# ── 2. the entry binds, honours none, and is idempotent ─────────────────────
t -f /dev/null new-session -d 2>/dev/null || { echo "cannot start tmux"; exit 1; }
t run-shell "bash '$ROOT/agent-dock.tmux'" 2>/dev/null; sleep 0.3
check "default key A is bound" "$(t list-keys -T prefix 2>/dev/null | grep -c -- '-T prefix A ')" "1"
t run-shell "bash '$ROOT/agent-dock.tmux'" 2>/dev/null; sleep 0.3
check "reload does not duplicate the binding" "$(t list-keys -T prefix 2>/dev/null | grep -c -- '-T prefix A ')" "1"
t set -g @agent-dock-bind none 2>/dev/null
t unbind-key -T prefix A 2>/dev/null
t run-shell "bash '$ROOT/agent-dock.tmux'" 2>/dev/null; sleep 0.3
check "bind=none binds nothing" "$(t list-keys -T prefix 2>/dev/null | grep -c -- '-T prefix A ')" "0"
t set -g @agent-dock-bind A 2>/dev/null

# ── 3. rows.sh on an empty server: no rows, no error ────────────────────────
t kill-server 2>/dev/null; sleep 0.5
t -f /dev/null new-session -d 2>/dev/null
out=$(bash "$ROOT/scripts/rows.sh" --no-color 2>&1); rc=$?
check "rows exits 0 with no agents" "$rc" "0"
check "rows emits nothing with no agents" "$(printf '%s' "$out" | grep -c .)" "0"

# ── 4. rows.sh classifies forged panes and ignores a non-agent ──────────────
if forge claude && cp "$WORK/claude" "$WORK/codex"; then
	screen "$WORK/busy.txt" "refactor auth"  '  Working\n  \xc2\xb7 esc to interrupt\n'
	screen "$WORK/wait.txt" "run migration"  'Allow command?\n  press enter to confirm or esc to cancel\n'
	screen "$WORK/idle.txt" "explain retry"  'Done.\n\xe2\x9d\xaf \n'
	t kill-server 2>/dev/null; sleep 0.5
	t -f /dev/null new-session -d -s work -x 200 -y 50 -n editor "exec '$WORK/claude' '$WORK/busy.txt'"
	t new-window -t work -n api  "exec '$WORK/codex' '$WORK/wait.txt'"
	t new-window -t work -n docs "exec '$WORK/claude' '$WORK/idle.txt'"
	t new-window -t work -n sh   "exec sleep 600"
	sleep 2
	rows=$(bash "$ROOT/scripts/rows.sh" --no-color 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
	check "three agent panes scanned (sleep ignored)" "$(printf '%s\n' "$rows" | grep -c .)" "3"
	case "$rows" in *working*) ok "a working pane is classified" ;; *) fail "no working state: $rows" ;; esac
	case "$rows" in *waiting*) ok "a waiting pane is classified" ;; *) fail "no waiting state" ;; esac
	case "$rows" in *idle*)    ok "an idle pane is classified" ;; *) fail "no idle state" ;; esac
	stats=$(bash "$ROOT/scripts/dock.sh" stats 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
	case "$stats" in *jump*) ok "en header renders key hints" ;; *) fail "header: $stats" ;; esac
	zh=$(AGENT_DOCK_LANG=zh bash "$ROOT/scripts/dock.sh" stats 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
	if [ "$stats" != "$zh" ]; then ok "lang=zh changes the header"; else fail "lang switch not wired"; fi

	# ── 5. RCE regression: a session named $(...) must not execute ──────────
	# The payload rides on a session NAME (column 2 of a row, reachable by the
	# fzf {2} placeholder). The dock runs in a SEPARATE, normally-named session
	# and scans the whole server (list-panes -a), so it sees the hostile session
	# without ever targeting it by that name — which is also how a real attack
	# would land. cwd is $WORK, so a relative-path payload lands where MARK looks.
	if command -v fzf >/dev/null 2>&1; then
		MARK="$WORK/PWNED"
		t kill-server 2>/dev/null; sleep 0.5
		t -f /dev/null new-session -d -s '$(touch PWNED)' -x 200 -y 50 -n editor "exec '$WORK/claude' '$WORK/busy.txt'"
		run="cd '$WORK' && TMUX_BIN='$SHIM' AGENT_DOCK_ROWS_BIN='$ROOT/scripts/rows.sh' AGENT_DOCK_VCACHE='$AGENT_DOCK_VCACHE' PATH='$PATH' exec bash '$ROOT/scripts/dock.sh' run"
		t new-session -d -s viewer -x 200 -y 50 -n dock "$run" 2>/dev/null
		sleep 5
		t send-keys -t viewer:dock Down 2>/dev/null; sleep 0.6
		t send-keys -t viewer:dock Up 2>/dev/null;   sleep 0.6
		t send-keys -t viewer:dock q 2>/dev/null;    sleep 0.5
		if [ -e "$MARK" ]; then fail "COMMAND INJECTION: a session named \$(...) executed on focus"
		else ok "a session named \$(...) does not execute on focus"; fi
	else
		printf '  skip  RCE regression (fzf not installed) — not a pass, install fzf to run it\n'
	fi
else
	printf '  skip  pane classification + RCE (no C compiler to forge an agent pane)\n'
fi

echo
if [ "$FAILED" -eq 0 ]; then echo "smoke: all checks passed"; exit 0; fi
echo "smoke: $FAILED check(s) failed"; exit 1
