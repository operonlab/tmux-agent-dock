#!/usr/bin/env bash
# rows.sh — the dock's data layer. Finds every AI-CLI pane by scanning tmux
# directly and prints one row per agent, newest-attention first.
#
# There is no daemon and no state store: the state of each pane is read from its
# own screen at scan time, exactly the way tmux-agent-status classifies a pane.
# Adding a CLI = one word in the agent command set below (kept identical to
# classify.awk's).
#
# Output: a TAB-separated row per agent, coloured for the picker unless
# --no-color. Columns, in order:
#     1 state    working | waiting | idle | unknown   (ANSI-coloured unless --no-color)
#     2 session  #{session_name}
#     3 target   #{window_index}.#{pane_index}   (so session:target addresses the pane)
#     4 tool     the CLI name, normalised (a bare version number -> claude)
#     5 window   #{window_name}
#     6 title    #{pane_title}, minus a leading spinner glyph
#
# The picker addresses a pane by column 2 + column 3 (session:target); every
# other column is display only. A pane you are currently attached to is marked
# with a leading ▸ on the tool column.
#
# Flags: --pretty (starship-style high-contrast for the picker; implies the tool
# normalisation), --no-color (plain TSV for a machine consumer), --sort=MODE
# (attention | tool). Unlike the private original this reads no daemon, so it
# cannot show a listening-port column, a wait-reason, or a precise time-in-state;
# those were daemon enrichments and are simply absent here.

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLASSIFY_AWK="${CURRENT_DIR}/classify.awk"
TAB=$(printf '\t')

# tmux binary. A bare `tmux` talks to the right server because $TMUX is set when
# the dock runs; TMUX_BIN overrides it for isolated tests against a `-L` socket.
# Never name this TMUX — that is tmux's own server locator.
TMUX_BIN="${TMUX_BIN:-$(command -v tmux 2>/dev/null || echo tmux)}"

COLOR=1
NORM=1
PRETTY=0
SORT=attention
for arg in "$@"; do
  case "$arg" in
    --no-color) COLOR=0 ;;
    --raw-tool) NORM=0 ;;
    --pretty)   PRETTY=1 ;;
    --sort=*)   SORT="${arg#--sort=}" ;;
    *) printf 'rows: unknown arg: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

# The command set that counts as an agent pane. Kept identical to classify.awk's
# BEGIN list; a host runtime (node/bun/deno) is included only so its OSC title
# can be trusted — its screen text is never captured.
is_agent_cmd() {
  case "$1" in
    claude|claude-code|codex|codex-*|gemini|aider|cursor|cursor-agent|agy|copilot|opencode|amp|droid|qwen|kimi|hermes|pi|grok|grok-*|[0-9]*.[0-9]*.[0-9]*) return 0 ;;
    node|bun|deno) return 0 ;;
    *) return 1 ;;
  esac
}

# The version cache lets a bare-version-number command (new Claude Code shows its
# own version as the process name) resolve to a real CLI name + version. Queried
# in the background at most every 6h; a scan never waits on it.
VCACHE="${AGENT_DOCK_VCACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/tmux-agent-dock/versions.tsv}"
_refresh_versions() {
  local tmp v t
  tmp=$(mktemp) || return 0
  for t in codex agy qwen pi kimi opencode hermes copilot grok; do
    command -v "$t" >/dev/null 2>&1 || continue
    v=$("$t" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1 | sed 's/\.$//')
    [ -n "$v" ] && printf '%s\t%s\n' "$t" "$v" >> "$tmp"
  done
  mkdir -p "$(dirname "$VCACHE")" 2>/dev/null
  mv "$tmp" "$VCACHE" 2>/dev/null || rm -f "$tmp"
}
if [ ! -f "$VCACHE" ] || [ -n "$(find "$VCACHE" -mmin +360 2>/dev/null)" ]; then
  # Background refresh with all three fds detached (a bare & still shares stdout).
  _refresh_versions </dev/null >/dev/null 2>&1 &
fi

# ── scan: one row of raw fields per agent pane ──────────────────────────────
# Emits: state<TAB>session<TAB>target<TAB>cmd<TAB>window<TAB>title<TAB>atme
# state is the classifier word (BUSY/WAIT/IDLE/"") before it is renamed below.
# NB: accumulate inside this one shell rather than `list-panes | while`, because
# macOS /bin/sh is bash 3.2 and mis-parses a `case` inside a `$()` pipe.
scan() {
  local panes line pid sess tgt cmd win title active text state
  panes=$("$TMUX_BIN" list-panes -a -F \
    "#{pane_id}${TAB}#{session_name}${TAB}#{window_index}.#{pane_index}${TAB}#{pane_current_command}${TAB}#{window_name}${TAB}#{pane_title}${TAB}#{?#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}},1,0}" \
    2>/dev/null) || return 1
  local OLDIFS=$IFS
  IFS='
'
  for line in $panes; do
    pid=${line%%"$TAB"*}; line=${line#*"$TAB"}
    sess=${line%%"$TAB"*}; line=${line#*"$TAB"}
    tgt=${line%%"$TAB"*}; line=${line#*"$TAB"}
    cmd=${line%%"$TAB"*}; line=${line#*"$TAB"}
    win=${line%%"$TAB"*}; line=${line#*"$TAB"}
    title=${line%%"$TAB"*}; active=${line##*"$TAB"}
    is_agent_cmd "$cmd" || continue
    case "$cmd" in
      node|bun|deno)
        # Host runtime: trust the OSC title only. Never capture the screen — a
        # dev server's log must not be classified as agent output.
        text='' ;;
      *)
        text=$("$TMUX_BIN" capture-pane -p -t "$pid" 2>/dev/null | tail -30) ;;
    esac
    state=$(printf '%s' "$text" | AISTATUS_CMD="$cmd" AISTATUS_TITLE="$title" LC_ALL=C awk -f "$CLASSIFY_AWK")
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${state:-}" "$sess" "$tgt" "$cmd" "$win" "$title" "$active"
  done
  IFS=$OLDIFS
  return 0
}

VERS=""
[ -f "$VCACHE" ] && VERS=$(tr '\t' '=' < "$VCACHE" | tr '\n' ';')

# ── format: sort, normalise the tool column, colour, drop the raw active flag ─
scan | awk -F"$TAB" -v OFS="$TAB" \
    -v color="$COLOR" -v norm="$NORM" -v pretty="$PRETTY" -v sortmode="$SORT" -v vers="$VERS" '
  BEGIN {
    nv = split(vers, va, ";")
    for (i = 1; i <= nv; i++) { p = index(va[i], "="); if (p) vmap[substr(va[i], 1, p-1)] = substr(va[i], p+1) }
    cw = "\033[1;38;2;255;215;95m"; ck = "\033[1;38;2;255;85;85m"
    ci = "\033[1;38;2;80;250;123m"; cdim = "\033[38;2;128;128;128m"
    ct = "\033[38;2;248;248;242m";  cr = "\033[0m"
  }
  # Map the classifier word to a display state; empty (agent, unclear) -> unknown.
  function disp_state(s) {
    if (s == "BUSY") return "working"
    if (s == "WAIT") return "waiting"
    if (s == "IDLE") return "idle"
    return "unknown"
  }
  # Attention priority: what needs you first, what to leave alone last.
  function prio(st) {
    if (st == "waiting") return 0
    if (st == "idle")    return 1
    if (st == "unknown") return 2
    return 3   # working
  }
  {
    st = disp_state($1)
    n++
    state[n] = st; sess[n] = $2; tgt[n] = $3; cmd[n] = $4; win[n] = $5; title[n] = $6; atme[n] = $7
    key[n] = n
  }
  END {
    # Selection sort (row counts are tiny; no gawk asort dependency).
    for (a = 1; a <= n; a++) {
      best = a
      for (b = a + 1; b <= n; b++) {
        if (sortmode == "tool") {
          if (cmd[key[b]] < cmd[key[best]] ||
              (cmd[key[b]] == cmd[key[best]] && prio(state[key[b]]) < prio(state[key[best]]))) best = b
        } else {
          if (prio(state[key[b]]) < prio(state[key[best]])) best = b
        }
      }
      tmp = key[a]; key[a] = key[best]; key[best] = tmp
    }
    for (r = 1; r <= n; r++) {
      i = key[r]
      s = state[i]; c = cmd[i]; t = title[i]

      # Strip a leading spinner token from the title (a <=3-byte non-alphanumeric
      # first word), so the title reads as the latest line of work.
      if (split(t, tp, " ") > 1 && length(tp[1]) <= 3 && tp[1] !~ /^[A-Za-z0-9]/) {
        sub(/^[^ ]+ /, "", t); sub(/^- /, "", t)
      }

      ver = ""
      if (c ~ /^[0-9.]+$/) ver = c
      if (norm == "1" || pretty == "1") {
        # A bare version number as the command name is new Claude Code showing
        # its own version; other packaged names collapse to their CLI.
        if (ver != "") c = "claude"
        else if (c ~ /^codex/) c = "codex"
        else if (c ~ /^grok/)  c = "grok"
        else if (c == "node" && title[i] ~ /^\xcf\x80/) c = "pi"   # pi runs under node; title starts "π"
      }

      mark = (atme[i] == "1")

      if (pretty == "1") {
        g = cdim "○"
        if      (s == "waiting") g = cw "\342\232\221"   # ⚑
        else if (s == "working") g = ck "\342\227\217"   # ●
        else if (s == "idle")    g = ci "\342\227\217"   # ●
        c1 = " " g cr
        v = vmap[c]
        if (c == "claude" && ver != "") v = ver
        pre = mark ? (cw "\342\226\270" cr " ") : ""     # ▸
        c4 = pre ct sprintf("%-6.6s", c) cr (v != "" ? cdim " " v cr : "")
        c5 = cdim win[i] cr
        c6 = ct t cr
        print c1, sess[i], tgt[i], c4, c5, c6
      } else {
        c4 = mark ? ("\342\226\270 " c) : c
        if (color == "1") {
          if      (s == "waiting") cc = "\033[33m"
          else if (s == "idle")    cc = "\033[32m"
          else if (s == "working") cc = "\033[31m"
          else                     cc = "\033[90m"
          s = cc s "\033[0m"
        }
        print s, sess[i], tgt[i], c4, win[i], t
      }
    }
  }
'
