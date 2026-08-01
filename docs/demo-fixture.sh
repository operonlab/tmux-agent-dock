#!/usr/bin/env bash
# demo-fixture.sh — stage a set of forged AI-agent panes on an isolated tmux
# server, for docs/demo.tape and docs/screenshot.tape.
#
# The dock puts agent titles and screens on the recording, so a recording made
# against a real machine would publish whatever you were actually working on.
# Everything here is invented: fictional projects, fictional prompts, and forged
# panes whose pane_current_command reads `claude`/`codex`/… via a tiny native
# binary (compiled here) that prints a canned screen then blocks in pause().
#
# Usage: demo-fixture.sh <socket> <workdir>
#   creates windows on `tmux -L <socket>`; scratch files live under <workdir>.

set -u

SOCK="${1:?usage: demo-fixture.sh <socket> <workdir>}"
WORK="${2:?usage: demo-fixture.sh <socket> <workdir>}"
TMUX_BIN="${TMUX_BIN:-tmux}"
CC="$(command -v cc 2>/dev/null || command -v clang 2>/dev/null || true)"
[ -n "$CC" ] || { echo "demo-fixture: need a C compiler to forge agent panes" >&2; exit 1; }

mkdir -p "$WORK"

cat > "$WORK/agent.c" <<'C'
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv){
  if(argc>1){ FILE*f=fopen(argv[1],"r"); char b[4096]; size_t k;
    if(f){ while((k=fread(b,1,sizeof b,f))>0) fwrite(b,1,k,stdout); fclose(f);} fflush(stdout);}
  for(;;) pause(); return 0;
}
C
for name in claude codex gemini kimi; do
	"$CC" -o "$WORK/$name" "$WORK/agent.c" 2>/dev/null || { echo "demo-fixture: compile failed" >&2; exit 1; }
done

# screen <file> <osc-title> <footer-bytes>
# 50 blank lines push the footer to the bottom of the pane, where a live agent's
# latest output sits and where the classifier looks. The newlines are printed
# directly, not via $(...) — command substitution would strip every trailing
# newline and leave the footer stuck at the top of the screen (read as unknown).
screen() {
	local out="$1" title="$2" body="$3" _
	{ printf '\033]2;%s\033\\' "$title"; for _ in $(seq 1 50); do printf '\n'; done; printf '%b' "$body"; } > "$out"
}

# A believable spread: two working, one waiting on a permission prompt, one idle.
# classify.awk reads the full screen only for claude and codex; the other CLIs
# are classified from their terminal title (a braille-spinner prefix = working,
# a "✳ " prefix = idle), so gemini/kimi carry the state in the title.
screen "$WORK/s_editor.txt" "refactor the auth module" \
	'> pull the token check out of the request handler\n\n  Editing src/auth/middleware.py\n  \342\234\263 Working\342\200\246 (esc to interrupt)\n'
screen "$WORK/s_api.txt" "run the staging migration" \
	'This migration rewrites the whole table.\n\n  Do you want to proceed?\n  \342\235\257 1. Yes\n    2. No\n  press enter to confirm or esc to cancel\n'
screen "$WORK/s_infra.txt" "$(printf '\342\240\213') trace the timezone bug" \
	'> where does the offset get dropped\n\n  Reading reports/serialize.py\n  Thinking\342\200\246\n'
screen "$WORK/s_docs.txt" "$(printf '\342\234\263') draft the changelog entry" \
	'Done. The pagination note is written.\n\nAnything else?\n\342\235\257 \n'

"$TMUX_BIN" -L "$SOCK" new-window -d -n editor "exec '$WORK/claude' '$WORK/s_editor.txt'"
"$TMUX_BIN" -L "$SOCK" new-window -d -n api    "exec '$WORK/codex'  '$WORK/s_api.txt'"
"$TMUX_BIN" -L "$SOCK" new-window -d -n infra  "exec '$WORK/gemini' '$WORK/s_infra.txt'"
"$TMUX_BIN" -L "$SOCK" new-window -d -n docs   "exec '$WORK/kimi'   '$WORK/s_docs.txt'"

# Fixed version cache so the recording is deterministic (no live CLI probing).
mkdir -p "$WORK/cache"
printf 'codex\t0.44.0\ngemini\t3.1.0\nkimi\t2.0.0\n' > "$WORK/cache/versions.tsv"
