#!/bin/bash
# demo-setup.sh — self-contained stage for docs/demo.tape and docs/screenshot.tape.
# Starts an ISOLATED tmux server (socket: ad-demo, own config) — your real tmux
# server and config are never touched.
#
# ANONYMOUS BY CONSTRUCTION, and for this plugin that is the whole point: the
# dock puts agent titles and live screens on the recording, so a recording made
# against a real machine would publish whatever you were working on. All four
# agents here are forged by docs/demo-fixture.sh — fictional projects, fictional
# prompts, native binaries that only print a canned screen — and the dock is
# pointed at this isolated server, never your real one.
#
# FAMILY-CONSISTENT: the same two-row pill cockpit as the rest of the plugin
# family (catppuccin mocha, half-circle end-caps).
set -u
unset TMUX TMUX_PANE
SOCK=ad-demo
WORK=/tmp/vhs-agent-dock-demo
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_BIN="${TMUX_BIN:-tmux}"

rm -rf "$WORK"; mkdir -p "$WORK"

# ── glyphs + mocha palette ──
CAPL=$(printf '\xee\x82\xb6'); CAPR=$(printf '\xee\x82\xb4')
I_TERM=$(printf '\xee\x9e\x95');   I_ROBOT=$(printf '\xf3\xb0\x9a\xa9')
I_PLAY=$(printf '\xef\x81\x8b');   I_PAUSE=$(printf '\xef\x81\x8c')
I_FLEET=$(printf '\xef\x84\x88');  I_CAL=$(printf '\xef\x86\xae')
I_THERMO=$(printf '\xef\x8b\x89'); I_CLOCK=$(printf '\xef\x80\x97')
I_CLAUDE=$(printf '\xef\x81\xa9'); I_CODEX=$(printf '\xef\x84\xa1'); I_GEMINI=$(printf '\xef\x86\xa0')
BG='#1E1E1E'; CRUST='#11111b'; FG='#cdd6f4'; SURF='#313244'
PEACH='#fab387'; YELLOW='#f9e2af'; MAROON='#eba0ac'; MAUVE='#cba6f7'
PINK='#f5c2e7'; BLUE='#89b4fa'; SKY='#89dceb'; SAPPHIRE='#74c7ec'
TEAL='#94e2d5'; GREEN='#a6e3a1'; RED='#f38ba8'

p_open()  { printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s]%s  ' "$1" "$BG" "$CAPL" "$CRUST" "$1" "$2"; }
p_text()  { printf '#[fg=%s,bg=%s] %s ' "$FG" "$SURF" "$1"; }
p_badge() { printf '#[fg=%s,bg=%s]%s#[fg=%s,bg=%s]%s ' "$1" "$SURF" "$CAPL" "$CRUST" "$1" "$2"; }
p_close() { printf '#[fg=%s,bg=%s]%s ' "$SURF" "$BG" "$CAPR"; }

LEFT_R1="#[fg=$GREEN,bg=$BG]${CAPL}#[fg=$CRUST,bg=$GREEN]${I_TERM}  #[fg=$FG,bg=$SURF] #S #[fg=$SURF,bg=$BG]${CAPR} "
WINF="#[fg=$CRUST,bg=#9399b2]#[fg=$BG,reverse]${CAPL}#[none]#I #[fg=$FG,bg=$SURF] #W "
WINCUR="#[fg=$CRUST,bg=$PEACH]#[fg=$BG,reverse]${CAPL}#[none]#I #[fg=$FG,bg=#45475a] #W "
CLUSTER="#[fg=$MAUVE,bg=$BG]${CAPL}#[fg=$CRUST,bg=$MAUVE]${I_ROBOT}  #[fg=$FG,bg=$SURF] ${I_PLAY} 2  ${I_PAUSE} 1 #[fg=$SAPPHIRE,bg=$SURF]${CAPL}#[fg=$CRUST,bg=$SAPPHIRE]${I_FLEET}  #[fg=$FG,bg=$SURF] #[fg=$GREEN,bg=$SURF]E #[fg=$RED,bg=$SURF]A #[fg=$GREEN,bg=$SURF]I #[fg=$SURF,bg=$BG]${CAPR}"
RIGHT_R1="#[fg=$PINK,bg=$BG]${CAPL}#[fg=$CRUST,bg=$PINK]${I_CAL}  #[fg=$FG,bg=$SURF] #W #[fg=$SKY,bg=$SURF]${CAPL}#[fg=$CRUST,bg=$SKY]${I_THERMO}  #[fg=$FG,bg=$SURF] $(printf "29\302\260C") #[fg=$SAPPHIRE,bg=$SURF]${CAPL}#[fg=$CRUST,bg=$SAPPHIRE]${I_CLOCK}  #[fg=$FG,bg=$SURF] %Y/%m/%d %H:%M #[fg=$SURF,bg=$BG]${CAPR}"
FMT0="#[align=left bg=$BG]${LEFT_R1}#[list=on]#{W:#{T:@pw-fmt},#{T:@pw-cur}}#[nolist align=right]${RIGHT_R1}#[align=absolute-centre]${CLUSTER}"

ROW2_L="$(p_open "$PEACH" "$I_CLAUDE")$(p_text CLAUDE)$(p_badge "$YELLOW" 5H)$(p_text 40%%)$(p_badge "$MAROON" 7D)$(p_text 61%%)$(p_close)$(p_open "#b4befe" "$I_CODEX")$(p_text CODEX)$(p_badge "$MAUVE" 5H)$(p_text 65%%)$(p_badge "$PINK" 7D)$(p_text 12%%)$(p_close)$(p_open "$BLUE" "$I_GEMINI")$(p_text GEMINI)$(p_badge "$SKY" 5H)$(p_text 8%%)$(p_badge "$SAPPHIRE" 7D)$(p_text 3%%)$(p_close)"
FMT1="#[align=left bg=$BG]${ROW2_L}"

cat > "$WORK/rc.sh" <<'RC'
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
_SEP=$(printf '\xee\x82\xb0'); _CAPL=$(printf '\xee\x82\xb6'); _CAPR=$(printf '\xee\x82\xb4')
_APPLE=$(printf '\xef\x85\xb9'); _CLOCKG=$(printf '\xef\x90\xba'); _ARROW=$(printf '\xef\x90\xb2')
_SURF0='49;50;68'; _PEACH='250;179;135'; _GREEN='166;227;161'; _TEAL='148;226;213'
_BLUE='137;180;250'; _PINK='245;194;231'; _TEXT='205;214;244'; _MANTLE='24;24;37'
_p10line() {
  printf '\033[38;2;%sm%s\033[38;2;%s;48;2;%sm%s dev \033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm …/%s \033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm%s\033[38;2;%s;48;2;%sm %s %s \033[0m\033[38;2;%sm%s\033[0m \n' \
    "$_SURF0" "$_CAPL" "$_TEXT" "$_SURF0" "$_APPLE" "$_SURF0" "$_PEACH" "$_SEP" \
    "$_MANTLE" "$_PEACH" "${PWD##*/}" "$_PEACH" "$_TEAL" "$_SEP" "$_TEAL" "$_BLUE" "$_SEP" \
    "$_BLUE" "$_PINK" "$_SEP" "$_MANTLE" "$_PINK" "$_CLOCKG" "$(date '+%I:%M %p')" "$_PINK" "$_CAPR"
}
PROMPT_COMMAND=_p10line
PS1='\[\033[1;38;2;166;227;161m\]'"$_ARROW"'\[\033[0m\] '
RC

cat > "$WORK/theme.conf" <<'CONF'
set -g default-terminal "tmux-256color"
set -as terminal-overrides ",xterm-256color:Tc"
set -g mouse on
setw -g automatic-rename off
set -g escape-time 0
set -g status 2
set -g status-interval 2
set -g status-style "bg=#1E1E1E,fg=#cdd6f4"
set -g status-left-length 30
set -g status-right-length 200
set -g window-status-separator ''
set -g message-style 'bg=#f9e2af,fg=#11111b,bold'
CONF

"$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null
sleep 0.3
# window 0 "work" is a plain shell; the dock will split into its right edge.
"$TMUX_BIN" -L "$SOCK" -f "$WORK/theme.conf" new-session -d -s demo -x 150 -y 40 -n work \
	-c "$WORK" "bash --rcfile $WORK/rc.sh -i"
"$TMUX_BIN" -L "$SOCK" set -g default-command "bash --rcfile $WORK/rc.sh -i"
"$TMUX_BIN" -L "$SOCK" set -g @pw-fmt "$WINF"
"$TMUX_BIN" -L "$SOCK" set -g @pw-cur "$WINCUR"
"$TMUX_BIN" -L "$SOCK" set -g 'status-format[0]' "$FMT0"
"$TMUX_BIN" -L "$SOCK" set -g 'status-format[1]' "$FMT1"

# forge the four agent panes in background windows
TMUX_BIN="$TMUX_BIN" bash "$PLUGIN/docs/demo-fixture.sh" "$SOCK" "$WORK" >/dev/null || {
	echo "demo-setup: fixture staging failed" >&2; exit 1; }

# A tmux shim pinned to the isolated socket, so both the toggle and the dock's
# own scan/refresh talk to ad-demo rather than your real server.
cat > "$WORK/tmux-shim" <<SHIM
#!/bin/bash
exec "$TMUX_BIN" -L "$SOCK" "\$@"
SHIM
chmod +x "$WORK/tmux-shim"

# open the dock on the right edge of window 0. AGENT_DOCK_TARGET names the window
# because no client is attached yet (the tape attaches next).
"$TMUX_BIN" -L "$SOCK" set -g @agent-dock-width 34% 2>/dev/null
AGENT_DOCK_TARGET="demo:work" \
TMUX_BIN="$WORK/tmux-shim" \
AGENT_DOCK_RUN_CMD="exec env AGENT_DOCK_ROWS_BIN='$PLUGIN/scripts/rows.sh' AGENT_DOCK_VCACHE='$WORK/cache/versions.tsv' TMUX_BIN='$WORK/tmux-shim' bash '$PLUGIN/scripts/dock.sh' run" \
	bash "$PLUGIN/scripts/dock.sh" toggle
"$TMUX_BIN" -L "$SOCK" select-window -t demo:work
# Focus the dock pane so the tape can drive it (arrow keys reach fzf).
sleep 1
dockpane=$("$TMUX_BIN" -L "$SOCK" list-panes -t demo:work -F '#{pane_id} #{@agent_dock}' | awk '$2=="1"{print $1}')
[ -n "$dockpane" ] && "$TMUX_BIN" -L "$SOCK" select-pane -t "$dockpane"
