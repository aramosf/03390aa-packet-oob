#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cast="$repo_dir/assets/03390aa-packet-oob.cast"
gif="$repo_dir/assets/03390aa-packet-oob.gif"

for command in asciinema agg; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "missing required command: $command" >&2
    exit 2
  fi
done

TERM=xterm-256color asciinema rec --overwrite --cols 120 --rows 36 \
  -c "$repo_dir/scripts/record-live.sh" "$cast"
transcript="$(asciinema cat "$cast")"
if [[ "$transcript" != *"uid=0(root) gid=0(root) groups=0(root)"* ]]; then
  echo "recording does not contain the root proof; refusing to render" >&2
  exit 1
fi
agg --theme github-dark --speed 0.7 --idle-time-limit 3 --last-frame-duration 5 \
  "$cast" "$gif"
