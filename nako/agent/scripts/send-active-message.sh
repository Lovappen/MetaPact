#!/bin/bash
# Send a proactive text message through the currently active cc-connect session.

set -euo pipefail

WORKSPACE="${OPENCLAW_AGENT_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_DIR="$WORKSPACE/memory"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/heartbeat-state.json.log"
SEND_LOG="$(mktemp "${TMPDIR:-/tmp}/nako-proactive-send.XXXXXX")"
trap 'rm -f "$SEND_LOG"' EXIT

if [ "$#" -gt 0 ]; then
  MSG="$*"
else
  MSG="$(cat)"
fi
MSG="$(printf '%s' "${MSG:-}" | sed 's/[[:space:]]*$//')"
[ -n "$MSG" ] || { echo "$(date -Iseconds) proactive-send-skipped empty-message" >> "$LOG_FILE"; exit 1; }

infer_project() {
  local value base
  for value in "${OPENCLAW_CCCONNECT_PROJECT:-}" "${OPENCLAW_AGENT_ID:-}" "${AGENT_ID:-}"; do
    [ -n "$value" ] && { printf '%s\n' "$value"; return 0; }
  done
  for value in "${OPENCLAW_AGENT_WORKSPACE:-}" "$WORKSPACE" "$PWD"; do
    [ -n "$value" ] || continue
    base="$(basename "$value")"
    case "$base" in
      agent-*) printf '%s\n' "$base"; return 0 ;;
    esac
  done
  if [ -n "${OPENCLAW_SESSION_ID:-}" ]; then
    case "$OPENCLAW_SESSION_ID" in
      agent:*)
        value="${OPENCLAW_SESSION_ID#agent:}"
        printf '%s\n' "${value%%:*}"
        return 0
        ;;
    esac
  fi
  return 1
}

infer_session() {
  local project="$1" data_dir="${CC_CONNECT_DATA_DIR:-$HOME/.cc-connect}" session_file
  [ -n "${OPENCLAW_CCCONNECT_SESSION:-}" ] && { printf '%s\n' "$OPENCLAW_CCCONNECT_SESSION"; return 0; }
  [ -n "$project" ] || return 1
  session_file="$(ls -t "$data_dir"/sessions/"$project"_*.json 2>/dev/null | head -1 || true)"
  [ -n "$session_file" ] || return 1
  jq -r '
    (.active_session // empty) as $active
    | (.sessions // {}) as $sessions
    | if ($active | type) == "object" then
        $active
        | to_entries
        | map(. + {updated: ($sessions[.value].updated_at // $sessions[.value].created_at // "")})
        | sort_by(.updated)
        | last
        | .key // empty
      elif ($active | type) == "string" then
        $active
      else
        empty
      end
  ' "$session_file" 2>/dev/null
}

command -v cc-connect >/dev/null 2>&1 || {
  echo "$(date -Iseconds) proactive-send-failed cc-connect-missing" >> "$LOG_FILE"
  exit 1
}

session_label() {
  local value="${1:-}"
  [ -n "$value" ] || { printf '%s\n' "auto"; return 0; }
  printf '%s\n' "${value%%:*}"
}

PROJECT="$(infer_project || true)"
SESSION="$(infer_session "$PROJECT" || true)"
SESSION_LABEL="$(session_label "$SESSION")"

send_args=(send -m "$MSG")
[ -n "$PROJECT" ] && send_args+=(-p "$PROJECT")
[ -n "$SESSION" ] && send_args+=(--session "$SESSION")

if cc-connect "${send_args[@]}" >"$SEND_LOG" 2>&1; then
  echo "$(date -Iseconds) proactive-send-ok project=${PROJECT:-none} session=${SESSION_LABEL}" >> "$LOG_FILE"
  exit 0
fi

if [ -n "$SESSION" ]; then
  retry_args=(send -m "$MSG")
  [ -n "$PROJECT" ] && retry_args+=(-p "$PROJECT")
  if cc-connect "${retry_args[@]}" >"$SEND_LOG" 2>&1; then
    echo "$(date -Iseconds) proactive-send-ok project=${PROJECT:-none} session=auto" >> "$LOG_FILE"
    exit 0
  fi
fi

echo "$(date -Iseconds) proactive-send-failed $(tr '\n' ' ' <"$SEND_LOG" | cut -c1-220)" >> "$LOG_FILE"
exit 1
