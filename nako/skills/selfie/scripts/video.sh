#!/bin/bash
# video.sh — Generate video from selfie image via Grok Imagine Video
#
# Usage: ./video.sh "<image_url>" "<prompt>" "<channel>" ["<caption>"] ["<provider>"] ["<duration>"] ["<resolution>"]
#
# Providers:
#   fal (default) — fal.ai Grok Imagine Video, sync
#   kie           — kie.ai Grok Imagine Image-to-Video, async polling
#
# Environment variables:
#   FAL_KEY     — fal.ai API key
#   KIE_API_KEY — kie.ai API key
#   FEISHU_APP_ID / FEISHU_APP_SECRET — Feishu credentials (for direct send)

set -euo pipefail

# Two-layer env load: shared defaults first, per-agent overlay last wins.
_SHARED_SKILLS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
[ -f "$_SHARED_SKILLS_DIR/.env" ] && set -a && source "$_SHARED_SKILLS_DIR/.env" && set +a

_load_openclaw_selfie_env() {
  local _cfg="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
  [ -f "$_cfg" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  while IFS='=' read -r _key _value; do
    [ -n "$_key" ] || continue
    [ -n "${!_key:-}" ] && continue
    export "$_key=$_value"
  done < <(python3 - "$_cfg" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    data = {}
env = (((data.get("skills") or {}).get("entries") or {}).get("selfie") or {}).get("env") or {}
for key, value in env.items():
    if isinstance(value, (str, int, float, bool)):
        print(f"{key}={value}")
PY
)
}

_load_openclaw_selfie_env

_AGENT_ENV=""
if [ -f "$PWD/skills/.env" ]; then
  _AGENT_ENV="$PWD/skills/.env"
elif [ -n "${OPENCLAW_AGENT_WORKSPACE:-}" ] && [ -f "$OPENCLAW_AGENT_WORKSPACE/skills/.env" ]; then
  _AGENT_ENV="$OPENCLAW_AGENT_WORKSPACE/skills/.env"
fi
[ -n "$_AGENT_ENV" ] && set -a && source "$_AGENT_ENV" && set +a

export PATH="/opt/homebrew/bin:$PATH"

# Structured logging
SKILL_LOG_SH="${SKILL_LOG_SH:-$HOME/.openclaw/skills/skill-log.sh}"
source "$SKILL_LOG_SH" 2>/dev/null || true

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

command -v jq &>/dev/null || { log_error "jq required"; exit 1; }

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
    skill_log_ok selfie "$action" "path=$file" "project=${project:-unknown}"
    return 0
  fi

  log_warn "cc-connect send failed: $(printf '%s' "$cc_output" | tr '\n' ' ' | cut -c1-180)"
  skill_log_fail selfie "$action" "path=$file" "project=${project:-unknown}"
  return 1
}

IMAGE_URL="${1:-}"
PROMPT="${2:-}"
CHANNEL="${3:-}"
CAPTION="${4:-}"
PROVIDER="${5:-auto}"
DURATION="${6:-6}"
RESOLUTION="${7:-720p}"

if [ -z "$IMAGE_URL" ] || [ -z "$PROMPT" ] || [ -z "$CHANNEL" ]; then
  echo "Usage: $0 <image_url> <prompt> <channel> [caption] [provider] [duration] [resolution]"
  echo ""
  echo "  image_url:  URL of source image (from selfie generation)"
  echo "  prompt:     Motion/action description for the video"
  echo "  channel:    Feishu chat_id (oc_xxx) or open_id (ou_xxx)"
  echo "  caption:    Text message to send with video (optional)"
  echo "  provider:   fal / kie / auto (default: auto)"
  echo "  duration:   Video length in seconds, 1-15 (default: 6)"
  echo "  resolution: 480p / 720p (default: 720p)"
  exit 1
fi

# Auto-detect provider
if [ "$PROVIDER" = "auto" ]; then
  if [ -n "${FAL_KEY:-}" ]; then PROVIDER="fal"
  elif [ -n "${KIE_API_KEY:-}" ]; then PROVIDER="kie"
  else log_error "No API key. Set FAL_KEY or KIE_API_KEY"; exit 1; fi
fi

skill_log_start selfie video_request "provider=$PROVIDER" "channel=$CHANNEL" "duration=$DURATION" "resolution=$RESOLUTION" "image_url=$IMAGE_URL"

VIDEO_URL=""

# ============================
# fal.ai — Grok Imagine Video (image-to-video)
# ============================
generate_fal() {
  [ -z "${FAL_KEY:-}" ] && { log_error "FAL_KEY required"; exit 1; }
  log_info "fal.ai image-to-video: duration=${DURATION}s, resolution=${RESOLUTION}"

  local payload
  payload=$(jq -n \
    --arg prompt "$PROMPT" \
    --arg image_url "$IMAGE_URL" \
    --argjson duration "$DURATION" \
    --arg resolution "$RESOLUTION" \
    '{
      prompt: $prompt,
      image_url: $image_url,
      duration: $duration,
      resolution: $resolution,
      aspect_ratio: "auto"
    }')

  local response
  response=$(curl -s --connect-timeout 15 --max-time 300 \
    -X POST "https://fal.run/xai/grok-imagine-video/image-to-video" \
    -H "Authorization: Key ${FAL_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload")

  VIDEO_URL=$(echo "$response" | jq -r '.video.url // empty')
  if [ -z "$VIDEO_URL" ] || [ "$VIDEO_URL" = "null" ]; then
    local err_msg=$(echo "$response" | jq -r '.detail // .message // .')
    log_error "fal.ai video generation failed: $err_msg"
    skill_log_fail selfie video_generate "provider=fal" "error=$err_msg"
    exit 1
  fi

  local vid_duration
  vid_duration=$(echo "$response" | jq -r '.video.duration // "?"')
  log_info "Video ready: ${VIDEO_URL} (${vid_duration}s)"
  skill_log_ok selfie video_generate "provider=fal" "video_url=$VIDEO_URL" "video_duration=${vid_duration}s"
}

# ============================
# kie.ai — Grok Imagine Image-to-Video (async)
# ============================
generate_kie() {
  [ -z "${KIE_API_KEY:-}" ] && { log_error "KIE_API_KEY required"; exit 1; }
  log_info "kie.ai image-to-video: duration=${DURATION}s, resolution=${RESOLUTION}"

  local payload
  payload=$(jq -n \
    --arg prompt "$PROMPT" \
    --arg duration "$DURATION" \
    --arg resolution "$RESOLUTION" \
    --arg image_url "$IMAGE_URL" \
    '{
      model: "grok-imagine/image-to-video",
      input: {
        image_urls: [$image_url],
        prompt: $prompt,
        mode: "normal",
        duration: $duration,
        resolution: $resolution,
        aspect_ratio: "16:9",
        nsfw_checker: false
      }
    }')

  # Submit task
  local submit_resp
  submit_resp=$(curl -s --connect-timeout 10 --max-time 30 \
    -X POST "https://api.kie.ai/api/v1/jobs/createTask" \
    -H "Authorization: Bearer ${KIE_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload")

  local task_id
  task_id=$(echo "$submit_resp" | jq -r '.data.taskId // empty')
  [ -z "$task_id" ] && { log_error "kie.ai task submit failed: $(echo "$submit_resp" | jq .)"; exit 1; }
  log_info "Task submitted: $task_id"

  # Poll for result
  local MAX_ATTEMPTS=120  # 10 min max (video gen takes longer)
  local POLL_INTERVAL=5

  for i in $(seq 1 $MAX_ATTEMPTS); do
    local result
    result=$(curl -s --connect-timeout 5 --max-time 15 \
      "https://api.kie.ai/api/v1/jobs/recordInfo?taskId=$task_id" \
      -H "Authorization: Bearer ${KIE_API_KEY}")

    local status
    status=$(echo "$result" | jq -r '.data.status // empty')

    case "$status" in
      success)
        VIDEO_URL=$(echo "$result" | jq -r '.data.output.videoUrl // .data.output.video_url // .data.output.videos[0].url // empty')
        if [ -n "$VIDEO_URL" ] && [ "$VIDEO_URL" != "null" ]; then
          log_info "Video ready: $VIDEO_URL"
          skill_log_ok selfie video_generate "provider=kie" "task_id=$task_id" "video_url=$VIDEO_URL"
          return 0
        else
          log_error "Task completed but no video URL found"
          echo "$result" | jq '.data.output'
          exit 1
        fi
        ;;
      fail)
        local err_msg=$(echo "$result" | jq -r '.data.error // .')
        log_error "kie.ai task failed: $err_msg"
        skill_log_fail selfie video_generate "provider=kie" "task_id=$task_id" "error=$err_msg"
        exit 1
        ;;
      *)
        if [ $((i % 6)) -eq 0 ]; then
          log_info "Still processing... (${i}/${MAX_ATTEMPTS}, status=$status)"
        fi
        sleep $POLL_INTERVAL
        ;;
    esac
  done

  log_error "Timed out waiting for kie.ai task"
  skill_log_fail selfie video_generate "provider=kie" "task_id=$task_id" "error=timeout"
  exit 1
}

# ============================
# Generate video
# ============================
case "$PROVIDER" in
  fal) generate_fal ;;
  kie) generate_kie ;;
  *)   log_error "Unknown provider: $PROVIDER"; exit 1 ;;
esac

[ -z "$VIDEO_URL" ] && { log_error "No video URL after generation"; exit 1; }

# ============================
# cc-connect / ACP delivery
# ============================
if _should_use_ccconnect_delivery; then
  OUTDIR="${OPENCLAW_HOME:-$HOME/.openclaw}/media/outbound"
  mkdir -p "$OUTDIR"
  VIDEO_FILE="${OUTDIR}/$(new_uuid).mp4"
  if curl -s -o "$VIDEO_FILE" "$VIDEO_URL" && [ -s "$VIDEO_FILE" ]; then
    skill_log_ok selfie acp_emit_video "path=$VIDEO_FILE" "provider=$PROVIDER"
    _ccconnect_send_file "$VIDEO_FILE" "${CAPTION:-🎬}" ccconnect_send_video || true
    printf '{"type":"video","path":"%s","url":"%s","provider":"%s"}\n' "$VIDEO_FILE" "$VIDEO_URL" "$PROVIDER"
  else
    rm -f "$VIDEO_FILE"
    log_warn "Video download failed, emitting URL only"
    skill_log_ok selfie acp_emit_video_url "url=$VIDEO_URL" "provider=$PROVIDER"
    if command -v cc-connect >/dev/null 2>&1; then
      project="$(_infer_ccconnect_project || true)"
      session="$(_infer_ccconnect_session "$project" || true)"
      send_args=(send -m "${CAPTION:+$CAPTION }$VIDEO_URL")
      [ -n "$project" ] && send_args+=(-p "$project")
      [ -n "$session" ] && send_args+=(--session "$session")
      cc-connect "${send_args[@]}" >/dev/null 2>&1 || true
    fi
    printf '{"type":"video","url":"%s","provider":"%s"}\n' "$VIDEO_URL" "$PROVIDER"
  fi
  exit 0
fi

# ============================
# Send via Feishu or OpenClaw gateway
# ============================
log_info "Sending video to $CHANNEL..."

SEND_OK=false

# Try Feishu direct API (video as file message)
if [ -n "${FEISHU_APP_ID:-}" ] && [ -n "${FEISHU_APP_SECRET:-}" ]; then
  log_info "Sending via Feishu API..."

  # Get token
  TENANT_TOKEN=$(curl -s --connect-timeout 5 --max-time 10 \
    -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
    -H "Content-Type: application/json" \
    -d "{\"app_id\":\"${FEISHU_APP_ID}\",\"app_secret\":\"${FEISHU_APP_SECRET}\"}" | jq -r '.tenant_access_token // empty')

  if [ -n "$TENANT_TOKEN" ]; then
    # Download video to temp file
    OUTDIR="${OPENCLAW_HOME:-$HOME/.openclaw}/media/outbound"
    mkdir -p "$OUTDIR"
    TMPFILE="$OUTDIR/$(new_uuid).mp4"
    curl -s -o "$TMPFILE" "$VIDEO_URL"

    if [ -s "$TMPFILE" ]; then
      # Upload to Feishu as mp4 video
      UPLOAD_RESP=$(curl -s --connect-timeout 10 --max-time 60 \
        -X POST "https://open.feishu.cn/open-apis/im/v1/files" \
        -H "Authorization: Bearer $TENANT_TOKEN" \
        -F 'file_type=mp4' \
        -F 'file_name=selfie_video.mp4' \
        -F "file=@${TMPFILE}")

      FILE_KEY=$(echo "$UPLOAD_RESP" | jq -r '.data.file_key // empty')

      if [ -n "$FILE_KEY" ]; then
        skill_log_ok selfie video_upload "file_key=$FILE_KEY"
        RECEIVE_ID_TYPE="chat_id"
        echo "$CHANNEL" | grep -q "^ou_" && RECEIVE_ID_TYPE="open_id"

        # Send caption first if provided
        if [ -n "$CAPTION" ]; then
          curl -s -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${RECEIVE_ID_TYPE}" \
            -H "Authorization: Bearer $TENANT_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"receive_id\":\"$CHANNEL\",\"msg_type\":\"text\",\"content\":\"{\\\"text\\\":\\\"$CAPTION\\\"}\"}" > /dev/null
        fi

        # Send video as inline media
        SEND_RESP=$(curl -s -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${RECEIVE_ID_TYPE}" \
          -H "Authorization: Bearer $TENANT_TOKEN" \
          -H "Content-Type: application/json" \
          -d "{\"receive_id\":\"$CHANNEL\",\"msg_type\":\"media\",\"content\":\"{\\\"file_key\\\":\\\"$FILE_KEY\\\"}\"}")

        MSG_ID=$(echo "$SEND_RESP" | jq -r '.data.message_id // empty')
        if [ -n "$MSG_ID" ]; then
          log_info "Video sent via Feishu! message_id=$MSG_ID"
          skill_log_ok selfie video_send "channel=$CHANNEL" "message_id=$MSG_ID" "provider=$PROVIDER" "method=feishu_media"
          SEND_OK=true
        else
          skill_log_fail selfie video_send "channel=$CHANNEL" "error=feishu_send_failed" "response=$(echo "$SEND_RESP" | jq -c .)"
        fi
      fi

      # Cleanup
      (sleep 600 && rm -f "$TMPFILE") &>/dev/null &
    fi
  fi
fi

# Fallback: send video URL via gateway
if [ "$SEND_OK" = false ]; then
  log_info "Sending video URL via gateway..."
  GATEWAY_URL="${OPENCLAW_GATEWAY_URL:-http://localhost:18789}"
  GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"

  SEND_MSG="${CAPTION:+$CAPTION\n}$VIDEO_URL"

  curl -s -X POST "$GATEWAY_URL/message" \
    -H "Content-Type: application/json" \
    ${GATEWAY_TOKEN:+-H "Authorization: Bearer $GATEWAY_TOKEN"} \
    -d "{
      \"action\": \"send\",
      \"channel\": \"$CHANNEL\",
      \"message\": $(echo "$SEND_MSG" | jq -Rs .),
      \"media\": \"$VIDEO_URL\"
    }" > /dev/null 2>&1 || true

  log_info "Video URL sent to channel"
  skill_log_ok selfie video_send "channel=$CHANNEL" "provider=$PROVIDER" "method=gateway_fallback"
  SEND_OK=true
fi

echo ""
echo "--- Result ---"
jq -n \
  --arg video_url "$VIDEO_URL" \
  --arg channel "$CHANNEL" \
  --arg provider "$PROVIDER" \
  '{
    success: true,
    video_url: $video_url,
    channel: $channel,
    provider: $provider
  }'
