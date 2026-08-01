# tmux-agent-dock demo — a live sidebar of every agent pane.
#
# The clip shows the dock listing four agents by state (waiting / idle /
# working), and the preview above following the selection as you move down —
# the codex waiting on a permission prompt, then the idle one, then the two
# still working.
#
# Fully isolated & anonymous: docs/demo-setup.sh forges four agent panes
# (docs/demo-fixture.sh — fictional projects, fictional prompts, native binaries
# that only print a canned screen) on an isolated tmux server (socket ad-demo).
# No real agent title or screen can appear in this recording.
#   Re-record from the repo root with:  vhs docs/demo.tape
Output "docs/demo.gif"
Require tmux

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 2200
Set Height 1000
Set Padding 20
Set TypingSpeed 35ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 7s
Type "clear; tmux -L ad-demo attach -t demo"
Enter
Sleep 3s
Show

# The dock: four agents, newest-attention first — the one waiting on you at the
# top, the preview above showing its screen.
Sleep 2s

# Move down; the preview follows each selection.
Down
Sleep 1800ms
Down
Sleep 1800ms
Down
Sleep 1800ms
Up
Sleep 1500ms

# Cycle the sort: attention -> tool.
Ctrl+S
Sleep 2500ms

Hide
Type "q"
Sleep 400ms
Type "tmux -L ad-demo kill-server"
Enter
Sleep 400ms
