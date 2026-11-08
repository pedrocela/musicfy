#!/bin/bash
# Measures what Musicfy costs over a stretch of time, next to Music and Spotify:
# average CPU, idle wakeups and energy impact, plus memory at the end.
#   tools/measure.sh [seconds] [label]
# Leave the mouse still while it runs: moving it over the player changes the numbers.
set -euo pipefail
SECS="${1:-40}"
LABEL="${2:-run}"
INTERVAL=2

args=()
for name in Musicfy Music Spotify; do
  pid="$(pgrep -x "$name" | head -1 || true)"
  [[ -n "$pid" ]] && args+=(-pid "$pid")
done
if [[ ${#args[@]} -eq 0 ]]; then
  echo "$LABEL: nothing to measure (Musicfy, Music and Spotify are closed)"
  exit 0
fi

samples=$(( SECS / INTERVAL + 1 ))
top -l "$samples" -s "$INTERVAL" -c d -stats pid,command,cpu,idlew,power,mem "${args[@]}" |
  awk -v label="$LABEL" -v interval="$INTERVAL" '
    /^PID/ { sample++; next }
    sample > 1 && $1 ~ /^[0-9]+$/ {
      name = $2
      cpu[name] += $3; idlew[name] += $4; power[name] += $5; n[name]++
      mem[name] = $6
    }
    END {
      printf "%s\n", label
      printf "  %-8s %7s %13s %7s %8s\n", "process", "CPU %", "wakeups/s", "energy", "memory"
      for (p in n) {
        printf "  %-8s %7.2f %13.1f %7.2f %8s\n", p, cpu[p] / n[p], idlew[p] / n[p] / interval, power[p] / n[p], mem[p]
      }
    }'
