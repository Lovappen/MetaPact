#!/bin/bash
# resolve.sh — map a Feishu image_key (or file_key) to the local inbound file path.
#
# The runtime auto-downloads inbound media to <runtime>/media/inbound/<uuid>.<ext>
# and logs "downloaded <type> media, saved to <path>" in gateway.log right after
# the message line that contains the key. We grep the key in gateway.log, then
# grab the first "saved to <path>" that follows.
#
# Usage: resolve.sh <image_key|file_key>
#        resolve.sh --latest [jpg|png|webp]   # fallback: most recent image

set -euo pipefail

RUNTIME_HOME="${NAKO_RUNTIME_HOME:-${HERMES_HOME:-${OPENCLAW_HOME:-$HOME/.openclaw}}}"
MEDIA_HOME="${NAKO_MEDIA_HOME:-$RUNTIME_HOME/media}"
GATEWAY_LOG="${NAKO_GATEWAY_LOG:-${OPENCLAW_GATEWAY_LOG:-$RUNTIME_HOME/logs/gateway.log}}"
INBOUND_DIR="$MEDIA_HOME/inbound"

ARG="${1:-}"
[ -z "$ARG" ] && { echo "Usage: $0 <image_key|file_key|--latest [ext]>" >&2; exit 1; }

if [ "$ARG" = "--latest" ]; then
  EXT="${2:-jpg,png,webp,jpeg}"
  LATEST=""
  IFS=',' read -ra EXTS <<< "$EXT"
  for e in "${EXTS[@]}"; do
    for f in "$INBOUND_DIR"/*."$e"; do
      [ -f "$f" ] || continue
      if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then
        LATEST="$f"
      fi
    done
  done
  [ -z "$LATEST" ] && { echo "No recent inbound media" >&2; exit 2; }
  echo "$LATEST"
  exit 0
fi

[ ! -f "$GATEWAY_LOG" ] && { echo "Gateway log missing: $GATEWAY_LOG" >&2; exit 1; }

# Find the last line containing the key, then the first "saved to <path>" after it.
LN=$(grep -n -- "$ARG" "$GATEWAY_LOG" | tail -1 | cut -d: -f1)
[ -z "$LN" ] && { echo "Key not found in gateway log: $ARG" >&2; exit 2; }

PATH_FOUND=$(tail -n +"$LN" "$GATEWAY_LOG" | awk '
  index($0, "saved to ") {
    path = substr($0, index($0, "saved to ") + length("saved to "))
    sub(/\r$/, "", path)
    sub(/"$/, "", path)
    print path
    exit
  }
')
[ -z "$PATH_FOUND" ] && { echo "No 'saved to' line after key in log (not yet downloaded?)" >&2; exit 2; }
[ ! -f "$PATH_FOUND" ] && { echo "File gone from disk: $PATH_FOUND" >&2; exit 3; }

echo "$PATH_FOUND"
