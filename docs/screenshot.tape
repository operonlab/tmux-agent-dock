# tmux-agent-dock — hero screenshot: the family cockpit with the dock open on
# the right, listing four forged agents by state, the selected one previewed above.
#   Record from the repo root with:  vhs docs/screenshot.tape
#
# Fully isolated & anonymous: docs/demo-setup.sh forges four agent panes
# (docs/demo-fixture.sh) on an isolated tmux server (socket ad-demo). No real
# agent title or screen can appear in this image, and your own tmux is untouched.
Output "/tmp/tmux-agent-dock-hero.gif"
Require tmux

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 2200
Set Height 1000
Set Padding 20
Set TypingSpeed 1ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 7s
Type "clear; tmux -L ad-demo attach -t demo"
Enter
Sleep 3s
Show
Sleep 500ms
Screenshot "docs/screenshot.png"
Sleep 200ms

Hide
Type "q"
Sleep 400ms
Type "tmux -L ad-demo kill-server"
Enter
Sleep 400ms
