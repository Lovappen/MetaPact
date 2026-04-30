#!/bin/bash
# sing.sh — generate a song with MiniMax music-2.6 and deliver as Feishu audio message.
# Companion to voice.sh (which does plain TTS). Use this when user asks the agent
# to sing / write a song / deliver lyrics with melody.
#
# Usage: ./sing.sh "<lyrics>" "<channel>" ["<style_prompt>"] ["<model>"]
#   lyrics       : REQUIRED. Supports tags [verse]/[chorus]/[bridge]/[intro]/[outro]
#                  and \n line breaks. 10–600 chars recommended.
#   channel      : REQUIRED. Feishu chat_id (oc_xxx) or open_id (ou_xxx)
#   style_prompt : OPTIONAL. Genre/mood/instrumentation description,
#                  default: "Indie pop, gentle, warm female vocal"
#   model        : OPTIONAL. music-2.6 (default) | music-2.6-free

set -euo pipefail

# Two-layer env load (shared → per-agent last wins) — same as voice.sh
_SHARED_SKILLS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
[ -f "$_SHARED_SKILLS_DIR/.env" ] && set -a && source "$_SHARED_SKILLS_DIR/.env" && set +a

_AGENT_ENV=""
if [ -f "$PWD/skills/.env" ]; then
  _AGENT_ENV="$PWD/skills/.env"
elif [ -n "${OPENCLAW_AGENT_WORKSPACE:-}" ] && [ -f "$OPENCLAW_AGENT_WORKSPACE/skills/.env" ]; then
  _AGENT_ENV="$OPENCLAW_AGENT_WORKSPACE/skills/.env"
fi
[ -n "$_AGENT_ENV" ] && set -a && source "$_AGENT_ENV" && set +a

export PATH="/opt/homebrew/bin:$PATH"

SKILL_LOG_SH="${SKILL_LOG_SH:-$HOME/.openclaw/skills/skill-log.sh}"
source "$SKILL_LOG_SH" 2>/dev/null || true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

command -v jq >/dev/null || { log_error "jq required"; exit 1; }

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
  else
    python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
  fi
}

_infer_ccconnect_project() {
  local value base

  for value in "${OPENCLAW_CCCONNECT_PROJECT:-}" "${OPENCLAW_AGENT_ID:-}" "${AGENT_ID:-}"; do
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  for value in "${OPENCLAW_AGENT_WORKSPACE:-}" "$PWD"; do
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

_infer_ccconnect_session() {
  local project="$1"
  local data_dir="${CC_CONNECT_DATA_DIR:-$HOME/.cc-connect}"
  local session_file=""

  if [ -n "${OPENCLAW_CCCONNECT_SESSION:-}" ]; then
    printf '%s\n' "$OPENCLAW_CCCONNECT_SESSION"
    return 0
  fi

  [ -n "$project" ] || return 1
  session_file="$(ls -t "$data_dir"/sessions/"$project"_*.json 2>/dev/null | head -1 || true)"
  [ -n "$session_file" ] || return 1

  jq -r '
    (.active_session // {}) as $active
    | (.sessions // {}) as $sessions
    | $active
    | to_entries
    | map(. + {updated: ($sessions[.value].updated_at // $sessions[.value].created_at // "")})
    | sort_by(.updated)
    | last
    | .key // empty
  ' "$session_file" 2>/dev/null
}

_should_use_ccconnect_delivery() {
  [ "${OPENCLAW_OUTPUT_MODE:-}" = "acp" ] && return 0
  [ -n "${OPENCLAW_CCCONNECT_PROJECT:-}" ] && return 0

  case "$CHANNEL" in
    acp|cli|webchat|cc-connect) return 0 ;;
  esac

  return 1
}

_ccconnect_send_file() {
  local file="$1"
  local message="$2"
  local action="$3"
  local project session cc_output
  local send_args

  command -v cc-connect >/dev/null 2>&1 || return 1
  project="$(_infer_ccconnect_project || true)"
  session="$(_infer_ccconnect_session "$project" || true)"
  send_args=(send --file "$file" -m "$message")
  [ -n "$project" ] && send_args+=(-p "$project")
  [ -n "$session" ] && send_args+=(--session "$session")

  if cc_output="$(cc-connect "${send_args[@]}" 2>&1)"; then
    skill_log_ok voice "$action" "path=$file" "project=${project:-unknown}"
    return 0
  fi

  log_warn "cc-connect send failed: $(printf '%s' "$cc_output" | tr '\n' ' ' | cut -c1-180)"
  skill_log_fail voice "$action" "path=$file" "project=${project:-unknown}"
  return 1
}

LYRICS="${1:-}"
CHANNEL="${2:-}"
STYLE_PROMPT="${3:-Indie pop, gentle, warm female vocal, acoustic guitar}"
MODEL="${4:-music-2.6}"

if [ -z "$LYRICS" ] || [ -z "$CHANNEL" ]; then
  cat >&2 <<EOF
Usage: $0 <lyrics> <channel> [style_prompt] [model]

Examples:
  $0 "[verse]\nStreetlights flicker, the night breeze sighs\n[chorus]\nI walk alone" "oc_xxx"
  $0 "[verse]\n月色洒在窗台\n[chorus]\n思念像潮水" "ou_xxx" "Chinese ballad, piano, female vocal"
EOF
  exit 1
fi

[ -z "${MINIMAX_API_KEY:-}" ] || [ -z "${MINIMAX_GROUP_ID:-}" ] && { log_error "MINIMAX_API_KEY and MINIMAX_GROUP_ID required"; exit 1; }
if ! _should_use_ccconnect_delivery; then
  if [ -z "${FEISHU_APP_ID:-}" ] || [ -z "${FEISHU_APP_SECRET:-}" ]; then
    log_error "FEISHU_APP_ID and FEISHU_APP_SECRET required"
    exit 1
  fi
fi

skill_log_start voice music_request "model=$MODEL" "channel=$CHANNEL" "lyrics_len=${#LYRICS}"

OUTDIR="${OPENCLAW_HOME:-$HOME/.openclaw}/media/outbound"
mkdir -p "$OUTDIR"
REQUEST_ID="$(new_uuid)"
MP3_FILE="${OUTDIR}/${REQUEST_ID}.mp3"

log_info "MiniMax music_generation: model=$MODEL, style=\"$STYLE_PROMPT\""
PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --arg prompt "$STYLE_PROMPT" \
  --arg lyrics "$LYRICS" \
  '{
    model: $model,
    prompt: $prompt,
    lyrics: $lyrics,
    audio_setting: { sample_rate: 44100, bitrate: 256000, format: "mp3" }
  }')

RESPONSE=$(curl -s --connect-timeout 15 --max-time 180 \
  -X POST "https://api.minimaxi.com/v1/music_generation?GroupId=${MINIMAX_GROUP_ID}" \
  -H "Authorization: Bearer ${MINIMAX_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

STATUS=$(echo "$RESPONSE" | jq -r '.base_resp.status_code // empty')
if [ "$STATUS" != "0" ]; then
  ERR=$(echo "$RESPONSE" | jq -r '.base_resp.status_msg // .' | head -c 500)
  log_error "MiniMax music error: $ERR"
  skill_log_fail voice music_generate "error=$ERR"
  exit 1
fi

DURATION_MS=$(echo "$RESPONSE" | jq -r '.extra_info.music_duration // 0')
echo "$RESPONSE" | jq -r '.data.audio' | xxd -r -p > "$MP3_FILE"
FSIZE=$(wc -c < "$MP3_FILE" | tr -d ' ')
if [ "$FSIZE" -lt 1000 ]; then
  log_error "Generated mp3 too small ($FSIZE bytes) — likely empty response"
  skill_log_fail voice music_generate "error=empty_audio" "file_size=$FSIZE"
  exit 1
fi
log_info "Song generated: ${FSIZE} bytes, ${DURATION_MS}ms"
skill_log_ok voice music_generate "model=$MODEL" "duration_ms=$DURATION_MS" "file_size=$FSIZE"

# -----------------------------------------------------------
# ACP mode short-circuit
# -----------------------------------------------------------
if _should_use_ccconnect_delivery; then
  skill_log_ok voice acp_emit_song "path=$MP3_FILE" "model=$MODEL" "duration_ms=$DURATION_MS"
  _ccconnect_send_file "$MP3_FILE" "🎵" ccconnect_send_song || true
  printf '{"type":"audio","path":"%s","duration_ms":%s,"model":"%s","kind":"song"}\n' "$MP3_FILE" "${DURATION_MS:-0}" "$MODEL"
  exit 0
fi

# -----------------------------------------------------------
# Feishu upload + send (same pattern as voice.sh)
# -----------------------------------------------------------
log_info "Getting Feishu tenant token..."
TENANT_TOKEN=$(curl -s --connect-timeout 5 --max-time 10 \
  -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\":\"${FEISHU_APP_ID}\",\"app_secret\":\"${FEISHU_APP_SECRET}\"}" \
  | jq -r '.tenant_access_token // empty')
[ -z "$TENANT_TOKEN" ] && { log_error "Feishu token failed"; exit 1; }

log_info "Uploading song to Feishu..."
UPLOAD_RESP=$(curl -s --connect-timeout 10 --max-time 60 \
  -X POST "https://open.feishu.cn/open-apis/im/v1/files" \
  -H "Authorization: Bearer $TENANT_TOKEN" \
  -F 'file_type=opus' \
  -F "file_name=${REQUEST_ID}.mp3" \
  -F "duration=${DURATION_MS}" \
  -F "file=@${MP3_FILE}")

FILE_KEY=$(echo "$UPLOAD_RESP" | jq -r '.data.file_key // empty')
if [ -z "$FILE_KEY" ]; then
  log_error "Upload failed: $(echo "$UPLOAD_RESP" | jq -c .)"
  skill_log_fail voice feishu_upload_song "error=upload_failed"
  exit 1
fi
log_info "Uploaded: file_key=$FILE_KEY"

RECEIVE_ID_TYPE="chat_id"
echo "$CHANNEL" | grep -q "^ou_" && RECEIVE_ID_TYPE="open_id"

log_info "Sending song to $CHANNEL..."
SEND_RESP=$(curl -s --connect-timeout 5 --max-time 10 \
  -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${RECEIVE_ID_TYPE}" \
  -H "Authorization: Bearer $TENANT_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"receive_id\":\"$CHANNEL\",\"msg_type\":\"audio\",\"content\":\"{\\\"file_key\\\":\\\"${FILE_KEY}\\\"}\"}")

MSG_ID=$(echo "$SEND_RESP" | jq -r '.data.message_id // empty')
if [ -z "$MSG_ID" ]; then
  log_error "Send failed: $(echo "$SEND_RESP" | jq -c .)"
  skill_log_fail voice feishu_send_song "channel=$CHANNEL" "error=send_failed"
  exit 1
fi

log_info "Song sent! message_id=$MSG_ID"
skill_log_ok voice feishu_send_song "channel=$CHANNEL" "message_id=$MSG_ID" "model=$MODEL" "duration_ms=$DURATION_MS"

# Delayed cleanup
(sleep 600 && rm -f "$MP3_FILE") &>/dev/null &

echo
echo "--- Result ---"
jq -n \
  --arg file_key "$FILE_KEY" \
  --arg message_id "$MSG_ID" \
  --arg channel "$CHANNEL" \
  --arg model "$MODEL" \
  --arg duration_ms "$DURATION_MS" \
  '{ success: true, kind: "song", file_key: $file_key, message_id: $message_id, channel: $channel, model: $model, duration_ms: $duration_ms }'
