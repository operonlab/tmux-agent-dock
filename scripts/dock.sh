#!/usr/bin/env bash
# dock.sh — a docked sidebar that lists every live AI-CLI pane and lets you jump
# to one, watch it, or stop it. prefix + A opens it on the right edge of the
# current window; prefix + A again closes it.
#
# The data comes from scripts/rows.sh, which scans tmux directly — there is no
# daemon. Every agent is a real pane, so jumping, previewing and killing are all
# plain tmux operations.
#
# Subcommands:
#   toggle (default)  open the sidebar, or close it if already open
#   run               the sidebar loop: fzf with a live 2s refresh
#   stats             the one-line header (working / waiting / idle counts)
#   _rows             fetch rows (prints a placeholder rather than crashing)
#   _kill/_jump/...   fzf-binding callbacks
#
# Test seams (never set in normal use): AGENT_DOCK_TARGET (target a window on a
# clientless test server), AGENT_DOCK_RUN_CMD (replace the sidebar command),
# AGENT_DOCK_ROWS_BIN (override the rows.sh path), AGENT_KILL_MODE (skip the
# interactive kill prompt: proc | pane | cancel), TMUX_BIN (isolated -L socket).

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$CURRENT_DIR/$(basename "${BASH_SOURCE[0]:-$0}")"
ROWS_BIN="${AGENT_DOCK_ROWS_BIN:-$CURRENT_DIR/rows.sh}"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux 2>/dev/null || echo tmux)}"

# ── options + i18n ──────────────────────────────────────────────────────────
opt() {
  local v; v=$("$TMUX_BIN" show-option -gqv "$1" 2>/dev/null)
  if [ -n "$v" ]; then printf '%s' "$v"; else printf '%s' "$2"; fi
}

# One source, two locales. English is the default; AGENT_DOCK_LANG=zh (or
# @agent-dock-lang zh) switches the runtime strings only. A missing key falls
# back to English rather than printing a raw key name.
_LANG="${AGENT_DOCK_LANG:-$(opt @agent-dock-lang en)}"
T() {
  local en zh
  case "$1" in
    keys)            en=' ⏎ jump · ^s sort · ^x stop · q quit'; zh=' ⏎ 跳轉 · ^s 排序 · ^x 終止 · q 離開' ;;
    no_agents)       en='(no agents)'; zh='(沒有 agent)' ;;
    kill_prompt)     en='stop %s — [p]rocess  [k]ill pane  [c]ancel: '; zh='終止 %s — [p]進程  [k]砍 pane  [c]取消：' ;;
    kill_no_pane)    en='agent-dock: pane %s not found'; zh='agent-dock: 找不到 pane %s' ;;
    kill_no_proc)    en='agent-dock: %s has no separate agent process — use pane mode'; zh='agent-dock: %s 無獨立 agent 進程，請改用 pane 模式' ;;
    kill_termed)     en='agent-dock: %s pid %s terminated (TERM)'; zh='agent-dock: %s pid %s 已終止（TERM）' ;;
    kill_killed)     en='agent-dock: %s pid %s did not stop on TERM → KILL'; zh='agent-dock: %s pid %s TERM 無效 → KILL' ;;
    kill_pane)       en='agent-dock: pane %s killed'; zh='agent-dock: pane %s 已砍除' ;;
    jump_gone)       en='agent-dock: %s no longer exists'; zh='agent-dock: %s 已不存在' ;;
    *)               en="$1"; zh="$1" ;;
  esac
  # shellcheck disable=SC2059
  if [ "$_LANG" = zh ]; then printf "$zh" "${@:2}"; else printf "$en" "${@:2}"; fi
}

DOCK_WIDTH="$(opt @agent-dock-width 27%)"

# ── row fetch (never non-zero, never so empty it looks broken) ──────────────
_rows() {
  local out sort="attention"
  [ -n "${1:-}" ] && [ -f "$1" ] && sort=$(cat "$1" 2>/dev/null)
  out=$(TMUX_BIN="$TMUX_BIN" bash "$ROWS_BIN" --pretty --sort="${sort:-attention}" 2>/dev/null)
  if [ -z "$out" ]; then
    printf '\033[90m%s\033[0m\n' "$(T no_agents)"
  else
    printf '%s\n' "$out"
  fi
}

# ── header: working / waiting / idle counts + key hints ─────────────────────
stats() {
  local out
  out=$(TMUX_BIN="$TMUX_BIN" bash "$ROWS_BIN" --no-color 2>/dev/null)
  printf '%s\n' "$out" | awk -F'\t' -v hints="$(T keys)" '
    BEGIN{
      cw="\033[1;38;2;255;215;95m"; ck="\033[1;38;2;255;85;85m"
      ci="\033[1;38;2;80;250;123m"; cdim="\033[38;2;128;128;128m"; cr="\033[0m"
    }
    $1=="working"{wk++} $1=="waiting"{wt++} $1=="idle"{id++}
    END{ printf " %s\342\227\217 %d%s   %s\342\232\221 %d%s   %s\342\227\217 %d%s   %s%s%s",
         ck, wk+0, cr, cw, wt+0, cr, ci, id+0, cr, cdim, hints, cr }'
}

# ── stop the selected agent (^x). A process kill leaves the pane so you can
#    restart or inspect; a pane kill is the heavier hammer. TERM then KILL. ──
_kill() {
  local session="$1" target="${2:-}" full pane_pid pane_tty info agent_pid mode ans
  { [ -z "$session" ] || [ -z "$target" ]; } && return 0
  full="${session}:${target}"
  pane_pid=$("$TMUX_BIN" display -p -t "$full" '#{pane_pid}' 2>/dev/null)
  if [ -z "$pane_pid" ]; then
    "$TMUX_BIN" display-message "$(T kill_no_pane "$full")" 2>/dev/null; return 0
  fi
  pane_tty=$("$TMUX_BIN" display -p -t "$full" '#{pane_tty}' 2>/dev/null)
  info=$("$TMUX_BIN" display -p -t "$full" '#{pane_title}' 2>/dev/null | cut -c1-40)

  if [ -n "${AGENT_KILL_MODE:-}" ]; then
    mode="$AGENT_KILL_MODE"
  else
    # Dependency-free confirm: fzf hands us the tty, so a one-key read is enough.
    printf "$(T kill_prompt "$full — $info")" >/dev/tty
    IFS= read -rsn1 ans </dev/tty 2>/dev/null || ans=c
    printf '\n' >/dev/tty
    case "$ans" in p|P) mode=proc ;; k|K) mode=pane ;; *) mode=cancel ;; esac
  fi

  case "$mode" in
    proc)
      # The foreground job root is the pane shell's direct child (the agent and
      # its descendants go with the process group).
      agent_pid=$(ps -t "${pane_tty#/dev/}" -o pid=,ppid= 2>/dev/null \
                  | awk -v pp="$pane_pid" '$2==pp{print $1; exit}')
      if [ -z "$agent_pid" ]; then
        "$TMUX_BIN" display-message "$(T kill_no_proc "$full")" 2>/dev/null; return 0
      fi
      kill -TERM "$agent_pid" 2>/dev/null
      # Fast poll rather than a fixed wait: a well-behaved agent dies in a few
      # hundred ms and control returns promptly.
      local _
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$agent_pid" 2>/dev/null || break
        sleep 0.3
      done
      if kill -0 "$agent_pid" 2>/dev/null; then
        kill -KILL "$agent_pid" 2>/dev/null
        "$TMUX_BIN" display-message "$(T kill_killed "$full" "$agent_pid")" 2>/dev/null
      else
        "$TMUX_BIN" display-message "$(T kill_termed "$full" "$agent_pid")" 2>/dev/null
      fi
      ;;
    pane)
      "$TMUX_BIN" kill-pane -t "$full" 2>/dev/null
      "$TMUX_BIN" display-message "$(T kill_pane "$full")" 2>/dev/null
      ;;
    *) return 0 ;;
  esac
}

# ── jump to the selected pane (switch-client with a fallback chain) ─────────
_jump() {
  local sel="$1" session target
  session=$(printf '%s' "$sel" | cut -f2)
  target=$(printf '%s' "$sel" | cut -f3)
  { [ -z "$session" ] || [ -z "$target" ]; } && return 0
  # Verify the target is still alive; a dead pane would send switch-client down
  # its fallback chain and land you on the session's current window instead.
  if ! "$TMUX_BIN" display -p -t "${session}:${target}" -F '' >/dev/null 2>&1; then
    "$TMUX_BIN" display-message "$(T jump_gone "${session}:${target}")" 2>/dev/null; return 0
  fi
  if ! "$TMUX_BIN" switch-client -t "${session}:${target}" 2>/dev/null; then
    "$TMUX_BIN" switch-client -t "$session" 2>/dev/null
    "$TMUX_BIN" select-window -t "${session}:${target%%.*}" 2>/dev/null
    "$TMUX_BIN" select-pane   -t "${session}:${target}" 2>/dev/null
  fi
}

# ── background ticker: once fzf writes its port, POST a reload every 2s ──────
# $2 = the run pid: each round checks the parent is alive and self-terminates
# when it is gone, so a killed dock pane cannot leave a curl loop behind.
_ticker() {
  local portfile="$1" ppid="$2" sortf="${3:-}" port=""
  local _
  for _ in $(seq 1 100); do
    if [ -s "$portfile" ]; then
      port=$(cat "$portfile" 2>/dev/null)
      [ -n "$port" ] && break
    fi
    kill -0 "$ppid" 2>/dev/null || return 0
    sleep 0.1
  done
  [ -n "$port" ] || return 0
  local key="${FZF_API_KEY:-}"
  while true; do
    sleep 2
    kill -0 "$ppid" 2>/dev/null || return 0
    # transform-header recomputes the counts in the same request so the header
    # cannot drift out of step with the list. The sort file rides along so ^s
    # is not washed back to the default every 2s.
    curl -s --max-time 1 -XPOST "127.0.0.1:$port" -H "x-api-key: $key" \
      -d "transform-header(bash '$SELF' stats)+reload(bash '$SELF' _rows '$sortf')" \
      >/dev/null 2>&1 || true
  done
}

# fzf --listen accepts arbitrary commands from anything that can reach the port;
# a per-run FZF_API_KEY makes fzf reject requests without the matching header.
_api_key() {
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
  else
    printf 'agent-dock-%s-%s' "$$" "${RANDOM:-0}${RANDOM:-0}"
  fi
}

_run_cleanup() { [ -n "${TICKER_PID:-}" ] && kill "$TICKER_PID" 2>/dev/null; }

# ── the sidebar loop ────────────────────────────────────────────────────────
run() {
  local sel rc portfile hdr sortf
  TICKER_PID=""
  sortf=$(mktemp 2>/dev/null) || sortf="${TMPDIR:-/tmp}/agent-dock-sort.$$"
  printf 'attention' > "$sortf"
  FZF_API_KEY="${FZF_API_KEY:-$(_api_key)}"; export FZF_API_KEY
  # Only trap EXIT (a safety net that reaps the ticker on a clean quit). Do NOT
  # trap HUP/TERM: when the pane is killed, let run die with SIGHUP rather than
  # surviving as an orphan; the ticker has its own parent-alive guard.
  trap '_run_cleanup; rm -f "$sortf" 2>/dev/null' EXIT
  while true; do
    portfile=$(mktemp 2>/dev/null) || portfile="${TMPDIR:-/tmp}/agent-dock-port.$$"
    : > "$portfile"
    _ticker "$portfile" "$$" "$sortf" >/dev/null 2>&1 &
    TICKER_PID=$!
    hdr=$(stats)
    # Layout: preview 85% (the live screen of the selected agent), a thin list
    # strip below. {2}:{3} = session:target addresses the pane. Every fzf
    # placeholder is BARE so fzf quotes it — a pane whose title or name contains
    # $(...) must never reach a shell unquoted (see the SECURITY note below).
    sel=$(_rows "$sortf" | fzf \
        --ansi \
        --delimiter='\t' \
        --with-nth=1,4,6 \
        --listen 0 \
        --layout=reverse \
        --prompt='❯ ' \
        --pointer='▌' \
        --no-scrollbar \
        --info=inline-right \
        --padding=0,1 \
        --separator='─' \
        --header="$hdr" \
        --color='bg:-1,gutter:-1,fg:#e6e6e6,bg+:#44475a,fg+:#ffffff:bold,hl:#8be9fd,hl+:#8be9fd,info:#a0a8b7,prompt:#50fa7b:bold,pointer:#ff79c6,header:#a0a8b7,border:#6272a4,preview-border:#6272a4,separator:#6272a4,label:#ffb86c:bold' \
        --preview '[ -n {2} ] && tmux capture-pane -ep -t {2}:{3}' \
        --preview-window=up,85%,wrap,follow,border-bottom \
        --preview-label=' dock ' \
        `# SECURITY: bare {N} only. fzf single-quotes each placeholder; wrapping` \
        `# one in your own quotes breaks that quoting, and a pane named $(...)` \
        `# would then run on focus. printf's literal format keeps {2}/{3} bare.` \
        --bind 'focus:transform-preview-label:[ -n {2} ] && printf " %s:%s " {2} {3} || printf " dock "' \
        --bind 'load:refresh-preview' \
        --bind "start:execute-silent(printf '%s' \"\$FZF_PORT\" > '$portfile')" \
        --bind "ctrl-s:execute-silent(bash '$SELF' _cycle_sort '$sortf')+reload(bash '$SELF' _rows '$sortf')" \
        --bind "ctrl-x:execute([ -n {2} ] && bash '$SELF' _kill {2} {3})+reload(bash '$SELF' _rows '$sortf')" \
        --bind 'q:abort' \
        --bind 'esc:ignore')
    rc=$?
    kill "$TICKER_PID" 2>/dev/null; wait "$TICKER_PID" 2>/dev/null; TICKER_PID=""
    rm -f "$portfile" 2>/dev/null

    if [ "$rc" -eq 0 ] && [ -n "$sel" ]; then
      _jump "$sel"
      continue
    fi
    break
  done
  trap - EXIT
  "$TMUX_BIN" kill-pane 2>/dev/null
}

# ── toggle: open / close the sidebar ────────────────────────────────────────
toggle() {
  local tgt=() dockid runcmd
  [ -n "${AGENT_DOCK_TARGET:-}" ] && tgt=(-t "$AGENT_DOCK_TARGET")
  dockid=$("$TMUX_BIN" list-panes ${tgt[@]+"${tgt[@]}"} -F '#{pane_id} #{@agent_dock}' 2>/dev/null \
           | awk '$2=="1"{print $1; exit}')
  if [ -n "$dockid" ]; then
    "$TMUX_BIN" kill-pane -t "$dockid" 2>/dev/null; return 0
  fi
  # shellcheck disable=SC2016
  runcmd="${AGENT_DOCK_RUN_CMD:-exec env AGENT_DOCK_ROWS_BIN='$ROWS_BIN' AGENT_DOCK_LANG='$_LANG' bash '$SELF' run}"
  # -f: dock full-height on the window's right edge, width taken from the whole
  # window (splitting inside the active pane would crush it). -d: keep focus.
  dockid=$("$TMUX_BIN" split-window ${tgt[@]+"${tgt[@]}"} -f -h -l "$DOCK_WIDTH" -d -P -F '#{pane_id}' "$runcmd" 2>/dev/null)
  [ -n "$dockid" ] && "$TMUX_BIN" set -p -t "$dockid" @agent_dock 1 2>/dev/null
}

_cycle_sort() { # attention → tool → attention
  local cur next
  cur=$(cat "$1" 2>/dev/null)
  case "$cur" in
    attention) next=tool ;;
    *)         next=attention ;;
  esac
  printf '%s' "$next" > "$1"
}

case "${1:-toggle}" in
  toggle) toggle ;;
  run)    run ;;
  stats)  stats ;;
  _rows)  _rows "${2:-}" ;;
  # Drain any keystroke the confirm prompt left on the tty so a stray Enter does
  # not leak back into fzf as an accept. Non-tty (tests) hits EOF immediately.
  _kill)  _kill "${2:-}" "${3:-}"; IFS= read -rs -t 0.15 -d '' _drain 2>/dev/null || true ;;
  _cycle_sort) _cycle_sort "$2" ;;
  *) printf 'usage: dock.sh {toggle|run|stats}\n' >&2; exit 1 ;;
esac
