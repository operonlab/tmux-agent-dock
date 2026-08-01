#!/bin/bash
# Post-overlay pass: composite KeyCastr-style key bezels onto the raw vhs
# capture at the tape's deterministic timestamps, then re-palette the GIF.
#
#   vhs docs/demo.tape          -> docs/demo-raw.gif
#   bash docs/demo-overlay.sh   -> docs/demo.gif
#
# Bezels come from docs/keycast-bezel.py (PIL render, docs/assets/bezel-*.png).
# The demo presses ↓ ↓ ↑ ↑ then ⏎. Each key's bezel appears the instant it is
# pressed and holds until just before the next one, so the navigation reads as
# deliberate instead of happening by itself; the ⏎ bezel holds through the jump
# so the cut to the codex pane is not abrupt.
#
# The windows below are tuned to demo-raw.gif's real timeline (t=0 at Show, keys
# at the tape's cumulative Sleep offsets: ↓2.0 ↓3.7 ↑5.4 ↑6.6 ⏎8.0). vhs may
# compress a few percent vs the nominal Sleep sums — if you re-time the tape,
# re-audit these against the raw gif eyes-on and do NOT trust the Sleep sums.
set -u
cd "$(dirname "$0")"

[ -f demo-raw.gif ] || { echo "demo-raw.gif missing — run vhs docs/demo.tape first" >&2; exit 1; }
for b in assets/bezel-down.png assets/bezel-up.png assets/bezel-return.png; do
  [ -f "$b" ] || { echo "$b missing — run keycast-bezel.py first" >&2; exit 1; }
done

ffmpeg -y -loglevel error -i demo-raw.gif \
  -i assets/bezel-down.png -i assets/bezel-up.png -i assets/bezel-return.png \
  -filter_complex "\
[0:v][1:v]overlay=(W-w)/2:H-h-120:enable='between(t,2.0,3.5)+between(t,3.75,5.2)'[v1];\
[v1][2:v]overlay=(W-w)/2:H-h-120:enable='between(t,5.4,6.4)+between(t,6.65,7.85)'[v2];\
[v2][3:v]overlay=(W-w)/2:H-h-120:enable='between(t,8.0,10.88)'[v3];\
[v3]split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5[out]" \
  -map '[out]' demo.gif

echo "demo.gif written ($(du -h demo.gif | cut -f1))"
