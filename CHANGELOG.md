# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [SemVer](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-08-01

First public release.

### Added

- One prefix key (`A` by default) opens a docked sidebar listing every live
  AI-CLI pane on the tmux server: state (working / waiting / idle), tool, and
  the latest line of work, newest-attention first, with the selected agent's
  live screen previewed above.
- ⏎ jumps to the agent's pane, `⌃x` stops it (its process, keeping the pane, or
  the whole pane), `⌃s` cycles the sort, a 2-second ticker keeps it live.
- No daemon: agents are found by scanning tmux directly (`list-panes` +
  `capture-pane`), and state is read from each pane's screen by `classify.awk`,
  shared with tmux-agent-status.
- `@agent-dock-lang` switches the runtime strings between English and
  Traditional Chinese; `@agent-dock-width` and `@agent-dock-bind` are
  configurable.

### Security

- The fzf `--listen` control port is protected by a per-run `FZF_API_KEY`, and
  every fzf placeholder is kept bare so fzf quotes it. A pane or session named
  `$(...)` is displayed, never executed. A regression test in `tests/smoke.sh`
  drives the real binding with such a session and asserts it does not run; it is
  verified to fail on a quoted-placeholder form.

### Notes

- Extracted from a private sidebar that read a local status daemon. The daemon
  is gone; with it go the precise time-in-state, listening-port, and
  wait-reason columns, which a stateless scan cannot reconstruct.
