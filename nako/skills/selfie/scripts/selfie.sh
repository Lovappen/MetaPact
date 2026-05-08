#!/bin/bash
# grok-imagine-send.sh
# Generate an image with Grok Imagine (via fal.ai or kie.ai) and send it.
#
# Usage: ./selfie.sh "<prompt>" "<channel>" ["<caption>"] ["<aspect_ratio>"] ["<output_format>"] ["<provider>"]
#
# Environment variables:
#   FAL_KEY     - fal.ai API key (default provider)
#   KIE_API_KEY - kie.ai API key (alternative provider)
#   FEISHU_APP_ID     - Feishu app ID (for Feishu inline image)
#   FEISHU_APP_SECRET - Feishu app secret
#
# Providers:
#   fal (default) - Image edit with reference image, sync
#   kie           - Text-to-image, async task-based

set -euo pipefail

# Two-layer env load: shared defaults first, per-agent overlay last wins.
_SHARED_SKILLS_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
[ -f "$_SHARED_SKILLS_DIR/.env" ] && set -a && source "$_SHARED_SKILLS_DIR/.env" && set +a
[ -n "${HERMES_HOME:-}" ] && [ -f "$HERMES_HOME/.env" ] && set -a && source "$HERMES_HOME/.env" && set +a

_load_openclaw_selfie_env() {
  local _cfg="${NAKO_CONFIG:-${OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}}}"
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
elif [ -n "${NAKO_AGENT_WORKSPACE:-}" ] && [ -f "$NAKO_AGENT_WORKSPACE/skills/.env" ]; then
  _AGENT_ENV="$NAKO_AGENT_WORKSPACE/skills/.env"
elif [ -n "${OPENCLAW_AGENT_WORKSPACE:-}" ] && [ -f "$OPENCLAW_AGENT_WORKSPACE/skills/.env" ]; then
  _AGENT_ENV="$OPENCLAW_AGENT_WORKSPACE/skills/.env"
fi
[ -n "$_AGENT_ENV" ] && set -a && source "$_AGENT_ENV" && set +a


# Structured logging
if [ -z "${SKILL_LOG_SH:-}" ]; then
  if [ -n "${NAKO_SKILLS_DIR:-}" ] && [ -f "$NAKO_SKILLS_DIR/skill-log.sh" ]; then
    SKILL_LOG_SH="$NAKO_SKILLS_DIR/skill-log.sh"
  elif [ -n "${_SHARED_SKILLS_DIR:-}" ] && [ -f "$_SHARED_SKILLS_DIR/skill-log.sh" ]; then
    SKILL_LOG_SH="$_SHARED_SKILLS_DIR/skill-log.sh"
  elif [ -n "${QCLAW_HOME:-}" ] && [ -f "$QCLAW_HOME/skills/skill-log.sh" ]; then
    SKILL_LOG_SH="$QCLAW_HOME/skills/skill-log.sh"
  elif [ -f "$HOME/.qclaw/skills/skill-log.sh" ]; then
    SKILL_LOG_SH="$HOME/.qclaw/skills/skill-log.sh"
  elif [ -n "${HERMES_HOME:-}" ] && [ -f "$HERMES_HOME/skills/nako/skill-log.sh" ]; then
    SKILL_LOG_SH="$HERMES_HOME/skills/nako/skill-log.sh"
  else
    SKILL_LOG_SH="$HOME/.openclaw/skills/skill-log.sh"
  fi
fi
[ -n "${SKILL_LOG_SH:-}" ] && source "$SKILL_LOG_SH" 2>/dev/null || true

if [ -z "${NAKO_MEDIA_HOME:-}" ] && [ -n "${HERMES_HOME:-}" ] && [ "${NAKO_AGENT_RUNTIME:-}" = "hermes" ]; then
  NAKO_MEDIA_HOME="$HERMES_HOME/media"
fi

_detect_reference_image() {
  echo "${SELFIE_REFERENCE_IMAGE:-}"
}

_infer_ccconnect_project() {
  local value base

  for value in "${NAKO_CCCONNECT_PROJECT:-}" "${OPENCLAW_CCCONNECT_PROJECT:-}" "${NAKO_AGENT_ID:-}" "${OPENCLAW_AGENT_ID:-}" "${AGENT_ID:-}"; do
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  for value in "${NAKO_AGENT_WORKSPACE:-}" "${OPENCLAW_AGENT_WORKSPACE:-}" "$PWD"; do
    [ -n "$value" ] || continue
    base="$(basename "$value")"
    case "$base" in
      agent-*) printf '%s\n' "$base"; return 0 ;;
    esac
  done

  local session_id="${NAKO_SESSION_ID:-${OPENCLAW_SESSION_ID:-}}"
  if [ -n "$session_id" ]; then
    case "$session_id" in
      agent:*)
        value="${session_id#agent:}"
        printf '%s\n' "${value%%:*}"
        return 0
        ;;
    esac
  fi

  return 1
}

_ccconnect_session_files() {
  local project="$1"
  local candidate dir file

  for candidate in "${CC_CONNECT_SESSION_DIR:-}" \
    "${CC_CONNECT_API_DATA_DIR:-}/sessions" "${CC_CONNECT_API_DATA_DIR:-}/.cc-connect/sessions" \
    "${CC_CONNECT_DATA_DIR:-}/sessions" "${CC_CONNECT_DATA_DIR:-}/.cc-connect/sessions" \
    "$HOME/.cc-connect/sessions" "$HOME/.cc-connect/.cc-connect/sessions"; do
    [ -n "$candidate" ] || continue
    dir="$candidate"
    [ -d "$dir" ] || continue
    for file in "$dir"/"$project"_*.json; do
      [ -f "$file" ] || continue
      printf '%s\n' "$file"
    done
  done | awk '!seen[$0]++'
}

_infer_ccconnect_session() {
  local project="$1"
  local session_file="" line="" updated="" session="" best_session="" best_updated=""

  if [ -n "${NAKO_CCCONNECT_SESSION:-${OPENCLAW_CCCONNECT_SESSION:-}}" ]; then
    printf '%s\n' "${NAKO_CCCONNECT_SESSION:-${OPENCLAW_CCCONNECT_SESSION:-}}"
    return 0
  fi

  [ -n "$project" ] || return 1
  while IFS= read -r session_file; do
    [ -n "$session_file" ] || continue
    line="$(jq -r '
      (.active_session // {}) as $active
      | (.sessions // {}) as $sessions
      | $active
      | to_entries
      | map(. + {updated: ($sessions[.value].updated_at // $sessions[.value].created_at // "")})
      | sort_by(.updated)
      | last
      | select(.key)
      | "\(.updated)\t\(.key)"
    ' "$session_file" 2>/dev/null | tail -1 || true)"
    [ -n "$line" ] || continue
    updated="${line%%$'\t'*}"
    session="${line#*$'\t'}"
    [ -n "$session" ] || continue
    if [ -z "$best_session" ] || [ "$updated" \> "$best_updated" ]; then
      best_updated="$updated"
      best_session="$session"
    fi
  done < <(_ccconnect_session_files "$project")

  [ -n "$best_session" ] || return 1
  printf '%s\n' "$best_session"
}

_ccconnect_api_data_dir() {
  local candidate

  for candidate in "${CC_CONNECT_API_DATA_DIR:-}" "${CC_CONNECT_DATA_DIR:-}" "$HOME/.cc-connect" "$HOME/.cc-connect/.cc-connect"; do
    [ -n "$candidate" ] || continue
    if [ -S "$candidate/run/api.sock" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  if [ -n "${CC_CONNECT_API_DATA_DIR:-}" ]; then
    printf '%s\n' "$CC_CONNECT_API_DATA_DIR"
  elif [ -n "${CC_CONNECT_DATA_DIR:-}" ]; then
    printf '%s\n' "$CC_CONNECT_DATA_DIR"
  else
    printf '%s\n' "$HOME/.cc-connect"
  fi
}

_infer_feishu_receive() {
  local value project data_dir session_file session_key receive_id receive_type

  case "$CHANNEL" in
    oc_*) printf 'chat_id\t%s\n' "$CHANNEL"; return 0 ;;
    ou_*) printf 'open_id\t%s\n' "$CHANNEL"; return 0 ;;
  esac

  for value in "${NAKO_FEISHU_CHAT_ID:-}" "${FEISHU_CHAT_ID:-}"; do
    if [ -n "$value" ]; then
      case "$value" in
        oc_*) printf 'chat_id\t%s\n' "$value"; return 0 ;;
        ou_*) printf 'open_id\t%s\n' "$value"; return 0 ;;
      esac
    fi
  done

  project="$(_infer_ccconnect_project || true)"
  [ -n "$project" ] || return 1
  for data_dir in "$(_ccconnect_api_data_dir)" "${CC_CONNECT_DATA_DIR:-}" "$HOME/.cc-connect" "$HOME/.cc-connect/.cc-connect"; do
    [ -n "$data_dir" ] || continue
    session_file="$(ls -t "$data_dir"/sessions/"$project"_*.json 2>/dev/null | head -1 || true)"
    [ -n "$session_file" ] || continue
    session_key="$(jq -r '(.active_session // {}) | keys[] | select(startswith("feishu:"))' "$session_file" 2>/dev/null | tail -1)"
    [ -n "$session_key" ] || continue
    receive_id="$(printf '%s\n' "$session_key" | cut -d: -f2)"
    case "$receive_id" in
      oc_*) receive_type="chat_id" ;;
      ou_*) receive_type="open_id" ;;
      *) continue ;;
    esac
    printf '%s\t%s\n' "$receive_type" "$receive_id"
    return 0
  done

  return 1
}

_feishu_cc_credentials() {
  local project cfg
  project="$(_infer_ccconnect_project || true)"
  cfg="${CC_CONNECT_CONFIG:-$HOME/.cc-connect/config.toml}"
  [ -n "$project" ] && [ -f "$cfg" ] || return 1
  python3 - "$cfg" "$project" <<'PY'
import re
import sys
from pathlib import Path

cfg_path, project_name = sys.argv[1:]
text = Path(cfg_path).read_text(encoding="utf-8")
app_id = app_secret = ""
try:
    import tomllib
    data = tomllib.loads(text)
    for project in data.get("projects", []):
        if project.get("name") != project_name:
            continue
        for platform in project.get("platforms", []):
            if platform.get("type") in ("feishu", "lark"):
                opts = platform.get("options", {})
                app_id = opts.get("app_id", "")
                app_secret = opts.get("app_secret", "")
                break
except Exception:
    parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
    for part in parts:
        if f'name = "{project_name}"' not in part:
            continue
        blocks = re.split(r"(?m)(?=^\[\[projects\.platforms\]\]\s*$)", part)
        for block in blocks[1:]:
            if re.search(r'(?m)^type\s*=\s*"(feishu|lark)"\s*$', block):
                m_id = re.search(r'(?m)^app_id\s*=\s*"([^"]+)"\s*$', block)
                m_secret = re.search(r'(?m)^app_secret\s*=\s*"([^"]+)"\s*$', block)
                app_id = m_id.group(1) if m_id else ""
                app_secret = m_secret.group(1) if m_secret else ""
                break
if app_id and app_secret:
    print(app_id)
    print(app_secret)
PY
}

_feishu_tenant_token_from_cc() {
  local creds app_id app_secret resp token
  creds="$(_feishu_cc_credentials || true)"
  app_id="$(printf '%s\n' "$creds" | sed -n '1p')"
  app_secret="$(printf '%s\n' "$creds" | sed -n '2p')"
  [ -n "$app_id" ] && [ -n "$app_secret" ] || return 1

  resp=$(curl -sS --connect-timeout 8 --max-time 20 \
    -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg app_id "$app_id" --arg app_secret "$app_secret" '{app_id:$app_id, app_secret:$app_secret}')" 2>/dev/null) || return 1
  token="$(printf '%s' "$resp" | jq -r '.tenant_access_token // empty' 2>/dev/null)"
  [ -n "$token" ] || return 1
  printf '%s\n' "$token"
}

_feishu_send_image_file() {
  local file="$1"
  local receive receive_type receive_id token upload_resp image_key send_resp msg_id

  receive="$(_infer_feishu_receive || true)"
  receive_type="$(printf '%s' "$receive" | awk -F '\t' '{print $1}')"
  receive_id="$(printf '%s' "$receive" | awk -F '\t' '{print $2}')"
  [ -n "$receive_type" ] && [ -n "$receive_id" ] || return 1
  token="$(_feishu_tenant_token_from_cc || true)"
  [ -n "$token" ] || return 1

  upload_resp=$(curl -sS --connect-timeout 10 --max-time 60 \
    -X POST "https://open.feishu.cn/open-apis/im/v1/images" \
    -H "Authorization: Bearer $token" \
    -F "image_type=message" \
    -F "image=@${file}" 2>/dev/null) || return 1
  image_key="$(printf '%s' "$upload_resp" | jq -r '.data.image_key // empty' 2>/dev/null)"
  [ -n "$image_key" ] || return 1

  send_resp=$(curl -sS --connect-timeout 10 --max-time 30 \
    -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=${receive_type}" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg receive_id "$receive_id" --arg image_key "$image_key" '{receive_id:$receive_id,msg_type:"image",content:({image_key:$image_key}|tojson)}')" 2>/dev/null) || return 1
  msg_id="$(printf '%s' "$send_resp" | jq -r '.data.message_id // empty' 2>/dev/null)"
  [ -n "$msg_id" ] || return 1
  skill_log_ok selfie feishu_image_send "message_id=$msg_id" "receive_type=$receive_type"
  return 0
}

_should_use_ccconnect_delivery() {
  [ "${NAKO_OUTPUT_MODE:-${OPENCLAW_OUTPUT_MODE:-}}" = "acp" ] && return 0
  [ -n "${NAKO_CCCONNECT_PROJECT:-}" ] && return 0
  [ -n "${OPENCLAW_CCCONNECT_PROJECT:-}" ] && return 0

  case "$CHANNEL" in
    acp|cli|webchat|cc-connect) return 0 ;;
  esac

  return 1
}

_ccconnect_send_image_file() {
  local temp_file="$1"
  local project session data_dir cc_output
  local send_args

  command -v cc-connect >/dev/null 2>&1 || return 1
  project="$(_infer_ccconnect_project || true)"
  session="$(_infer_ccconnect_session "$project" || true)"
  data_dir="$(_ccconnect_api_data_dir)"
  send_args=(send --data-dir "$data_dir" --image "$temp_file" -m "$CAPTION")
  [ -n "$project" ] && send_args+=(-p "$project")
  [ -n "$session" ] && send_args+=(--session "$session")

  if cc_output="$(cc-connect "${send_args[@]}" 2>&1)"; then
    skill_log_ok selfie ccconnect_send "path=$temp_file" "project=${project:-unknown}"
    return 0
  fi

  log_warn "cc-connect image send failed: $(printf '%s' "$cc_output" | tr '\n' ' ' | cut -c1-180)"
  skill_log_fail selfie ccconnect_send "path=$temp_file" "project=${project:-unknown}"
  return 1
}

_emit_or_send_acp_image() {
  local temp_file

  temp_file="/tmp/selfie_$(date +%s).${OUTPUT_FORMAT:-png}"
  if curl -s -o "$temp_file" "$IMAGE_URL" && [ -s "$temp_file" ]; then
    skill_log_ok selfie acp_emit "path=$temp_file" "provider=$PROVIDER"
    if _ccconnect_send_image_file "$temp_file"; then
      printf '{"type":"image","path":"%s","url":"%s","provider":"%s"}\n' "$temp_file" "$IMAGE_URL" "$PROVIDER"
      return 0
    fi
    if _feishu_send_image_file "$temp_file"; then
      printf '{"type":"image","path":"%s","url":"%s","provider":"%s"}\n' "$temp_file" "$IMAGE_URL" "$PROVIDER"
      return 0
    fi
    printf '{"type":"image","path":"%s","url":"%s","provider":"%s"}\n' "$temp_file" "$IMAGE_URL" "$PROVIDER"
  else
    skill_log_ok selfie acp_emit_url "url=$IMAGE_URL" "provider=$PROVIDER"
    printf '{"type":"image","url":"%s","provider":"%s"}\n' "$IMAGE_URL" "$PROVIDER"
  fi
}


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for jq
if ! command -v jq &> /dev/null; then
  log_error "jq is required but not installed"
  exit 1
fi

# Parse arguments
PROMPT="${1:-}"
CHANNEL="${2:-}"
CAPTION="${3:-Generated with Grok Imagine}"
ASPECT_RATIO="${4:-1:1}"
OUTPUT_FORMAT="${5:-jpeg}"
PROVIDER="${6:-auto}"

if [ -z "$PROMPT" ] || [ -z "$CHANNEL" ]; then
  echo "Usage: $0 <prompt> <channel> [caption] [aspect_ratio] [output_format] [provider]"
  echo ""
  echo "Arguments:"
  echo "  prompt        - Image description (required)"
  echo "  channel       - Target channel (required)"
  echo "  caption       - Message caption (default: 'Generated with Grok Imagine')"
  echo "  aspect_ratio  - Image ratio (default: 1:1)"
  echo "  output_format - Image format (default: jpeg) [fal only]"
  echo "  provider      - fal|kie|auto (default: auto)"
  echo ""
  echo "Providers:"
  echo "  fal  - fal.ai image edit (sync, uses reference image)"
  echo "  kie  - kie.ai text-to-image (async, prompt-only)"
  echo "  auto - Use fal if FAL_KEY set, else kie"
  exit 1
fi

if _should_use_ccconnect_delivery; then
  USE_CLI=false
elif command -v openclaw &> /dev/null; then
  USE_CLI=true
else
  log_warn "openclaw CLI not found - will attempt direct API call"
  USE_CLI=false
fi

# Auto-detect provider: fal preferred (faster, sync), kie as fallback
if [ "$PROVIDER" = "auto" ]; then
  if [ -n "${FAL_KEY:-}" ]; then
    PROVIDER="fal"
  elif [ -n "${KIE_API_KEY:-}" ]; then
    PROVIDER="kie"
  else
    log_error "No provider API key set. Set FAL_KEY or KIE_API_KEY."
    exit 1
  fi
fi

skill_log_start selfie image_request "provider=$PROVIDER" "channel=$CHANNEL" "aspect_ratio=$ASPECT_RATIO"
log_info "Provider: $PROVIDER"
log_info "Prompt: $PROMPT"
log_info "Aspect ratio: $ASPECT_RATIO"

# ──────────────────────────────────────────────
# Provider: fal.ai (sync, image edit)
# ──────────────────────────────────────────────
generate_fal() {
  if [ -z "${FAL_KEY:-}" ]; then
    log_error "FAL_KEY not set"
    exit 1
  fi

  # Fixed reference image for character identity
  REFERENCE_IMAGE="$(_detect_reference_image)"
  if [ -z "$REFERENCE_IMAGE" ]; then
    log_error "No reference image found. Set SELFIE_REFERENCE_IMAGE or add to SKILL.md"
    exit 1
  fi

  log_info "Generating via fal.ai with reference image..."

  RESPONSE=$(curl -s -X POST "https://fal.run/xai/grok-imagine-image/edit" \
    -H "Authorization: Key $FAL_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"image_url\": \"$REFERENCE_IMAGE\",
      \"prompt\": $(echo "$PROMPT" | jq -Rs .),
      \"num_images\": 1,
      \"output_format\": \"$OUTPUT_FORMAT\"
    }")

  if echo "$RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    ERROR_MSG=$(echo "$RESPONSE" | jq -r '.error // .detail // "Unknown error"')
    log_error "fal.ai generation failed: $ERROR_MSG"
    skill_log_fail selfie image_generate "provider=fal" "error=$ERROR_MSG"
    return 1
  fi

  IMAGE_URL=$(echo "$RESPONSE" | jq -r '.images[0].url // empty')

  if [ -z "$IMAGE_URL" ]; then
    log_error "Failed to extract image URL from fal.ai response"
    echo "Response: $RESPONSE" >&2
    return 1
  fi

  REVISED_PROMPT=$(echo "$RESPONSE" | jq -r '.revised_prompt // empty')
  if [ -n "$REVISED_PROMPT" ]; then
    log_info "Revised prompt: $REVISED_PROMPT"
  fi
  skill_log_ok selfie image_generate "provider=fal" "image_url=$IMAGE_URL"
}

# ──────────────────────────────────────────────
# Provider: kie.ai (async, text-to-image)
# ──────────────────────────────────────────────
generate_kie() {
  if [ -z "${KIE_API_KEY:-}" ]; then
    log_error "KIE_API_KEY not set. Get key from https://kie.ai/api-key"
    exit 1
  fi

  log_info "Submitting task to kie.ai (image-to-image with reference)..."

  REFERENCE_IMAGE="$(_detect_reference_image)"
  if [ -z "$REFERENCE_IMAGE" ]; then
    log_error "No reference image found. Set SELFIE_REFERENCE_IMAGE or add to SKILL.md"
    exit 1
  fi

  SUBMIT_RESPONSE=$(curl -s -X POST "https://api.kie.ai/api/v1/jobs/createTask" \
    -H "Authorization: Bearer $KIE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"model\": \"grok-imagine/image-to-image\",
      \"input\": {
        \"image_urls\": [\"$REFERENCE_IMAGE\"],
        \"prompt\": $(echo "$PROMPT" | jq -Rs .)
      }
    }")

  SUBMIT_CODE=$(echo "$SUBMIT_RESPONSE" | jq -r '.code // empty')
  if [ "$SUBMIT_CODE" != "200" ]; then
    ERROR_MSG=$(echo "$SUBMIT_RESPONSE" | jq -r '.msg // "Unknown error"')
    log_error "kie.ai task submission failed (code=$SUBMIT_CODE): $ERROR_MSG"
    skill_log_fail selfie image_generate "provider=kie" "error=$ERROR_MSG"
    return 1
  fi

  TASK_ID=$(echo "$SUBMIT_RESPONSE" | jq -r '.data.taskId')
  log_info "Task submitted: $TASK_ID"

  # Poll for result
  MAX_ATTEMPTS=40
  POLL_INTERVAL=3

  log_info "Polling for result..."

  for i in $(seq 1 $MAX_ATTEMPTS); do
    RESULT=$(curl -s "https://api.kie.ai/api/v1/jobs/recordInfo?taskId=$TASK_ID" \
      -H "Authorization: Bearer $KIE_API_KEY")

    STATUS=$(echo "$RESULT" | jq -r '.data.state // empty')

    case "$STATUS" in
      success)
        # Try multiple possible output paths
        RESULT_JSON=$(echo "$RESULT" | jq -r '.data.resultJson // empty')
        IMAGE_URL=$(echo "$RESULT_JSON" | jq -r '.resultUrls[0] // empty' 2>/dev/null)

        if [ -z "$IMAGE_URL" ] || [ "$IMAGE_URL" = "null" ]; then
          log_warn "Task completed but no image URL found in expected paths"
          log_info "Full output: $(echo "$RESULT" | jq -r '.data.output // .data')"
          # Try to find any URL in output
          IMAGE_URL=$(echo "$RESULT" | jq -r '.. | select(type == "string" and startswith("http")) | select(test("\\.(jpg|jpeg|png|webp)")) ' 2>/dev/null | head -1)
        fi

        if [ -n "$IMAGE_URL" ] && [ "$IMAGE_URL" != "null" ]; then
          log_info "Image generated: $IMAGE_URL"
          skill_log_ok selfie image_generate "provider=kie" "task_id=$TASK_ID" "image_url=$IMAGE_URL"
          return 0
        else
          log_error "Could not extract image URL from completed task"
          echo "Response: $(echo "$RESULT" | jq .)"
          exit 1
        fi
        ;;
      fail)
        log_error "kie.ai task failed"
        skill_log_fail selfie image_generate "provider=kie" "task_id=$TASK_ID" "error=task_failed"
        echo "Response: $(echo "$RESULT" | jq .)"
        exit 1
        ;;
      *)
        # Still processing
        if [ $((i % 5)) -eq 0 ]; then
          log_info "Still processing... (attempt $i/$MAX_ATTEMPTS, status=$STATUS)"
        fi
        sleep $POLL_INTERVAL
        ;;
    esac
  done

  log_error "Timed out waiting for kie.ai task (${MAX_ATTEMPTS}x${POLL_INTERVAL}s)"
  skill_log_fail selfie image_generate "provider=kie" "task_id=$TASK_ID" "error=timeout"
  exit 1
}

# Generate image based on provider, with fallback
IMAGE_URL=""
_try_generate() {
  case "$1" in
    fal) generate_fal ;;
    kie) generate_kie ;;
    *) log_error "Unknown provider: $1" ; return 1 ;;
  esac
}

if ! _try_generate "$PROVIDER"; then
  # Determine fallback
  if [ "$PROVIDER" = "fal" ] && [ -n "${KIE_API_KEY:-}" ]; then
    log_warn "fal.ai failed, falling back to kie.ai..."
    PROVIDER="kie"
    skill_log_start selfie image_fallback "from=fal" "to=kie"
    _try_generate "kie"
  elif [ "$PROVIDER" = "kie" ] && [ -n "${FAL_KEY:-}" ]; then
    log_warn "kie.ai failed, falling back to fal.ai..."
    PROVIDER="fal"
    skill_log_start selfie image_fallback "from=kie" "to=fal"
    _try_generate "fal"
  else
    log_error "Provider $PROVIDER failed and no fallback available."
    exit 1
  fi
fi

if [ -z "$IMAGE_URL" ]; then
  log_error "No image URL after generation"
  exit 1
fi

log_info "Image ready: $IMAGE_URL"

# ──────────────────────────────────────────────
# ACP mode short-circuit: emit artifact path; host fans out per-platform.
# ──────────────────────────────────────────────
if _should_use_ccconnect_delivery; then
  _emit_or_send_acp_image
  exit 0
fi

# ──────────────────────────────────────────────
# Feishu special handling: upload image first for inline display
# ──────────────────────────────────────────────
_send_to_feishu() {
  log_info "Detected Feishu channel, uploading image for inline display..."
  
  # Download image to temp file
  TEMP_FILE="/tmp/selfie_$(date +%s).${OUTPUT_FORMAT}"
  curl -s -o "$TEMP_FILE" "$IMAGE_URL"
  
  if [ ! -s "$TEMP_FILE" ]; then
    log_error "Failed to download image"
    rm -f "$TEMP_FILE"
    return 1
  fi
  
  log_info "Image downloaded to $TEMP_FILE ($(wc -c < "$TEMP_FILE") bytes)"
  
  # Get Feishu credentials from env
  FEISHU_APP_ID="${FEISHU_APP_ID:-}"
  FEISHU_APP_SECRET="${FEISHU_APP_SECRET:-}"
  
  if [ -z "$FEISHU_APP_ID" ] || [ -z "$FEISHU_APP_SECRET" ]; then
    log_warn "Feishu credentials (FEISHU_APP_ID/FEISHU_APP_SECRET) not set, falling back to regular send"
    rm -f "$TEMP_FILE"
    return 1
  fi
  
  # Get tenant access token
  TOKEN_RESPONSE=$(curl -s -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
    -H "Content-Type: application/json" \
    -d "{\"app_id\":\"$FEISHU_APP_ID\",\"app_secret\":\"$FEISHU_APP_SECRET\"}")
  
  TENANT_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.tenant_access_token // empty')
  
  if [ -z "$TENANT_TOKEN" ]; then
    log_error "Failed to get Feishu tenant access token"
    echo "Response: $TOKEN_RESPONSE" >&2
    rm -f "$TEMP_FILE"
    return 1
  fi
  
  log_info "Got Feishu access token"
  
  # Upload image to Feishu
  UPLOAD_RESPONSE=$(curl -s -X POST "https://open.feishu.cn/open-apis/im/v1/images" \
    -H "Authorization: Bearer $TENANT_TOKEN" \
    -F "image_type=message" \
    -F "image=@$TEMP_FILE")
  
  IMAGE_KEY=$(echo "$UPLOAD_RESPONSE" | jq -r '.data.image_key // empty')
  
  if [ -z "$IMAGE_KEY" ]; then
    log_error "Failed to upload image to Feishu"
    echo "Response: $UPLOAD_RESPONSE" >&2
    rm -f "$TEMP_FILE"
    return 1
  fi
  
  log_info "Image uploaded to Feishu: $IMAGE_KEY"
  rm -f "$TEMP_FILE"
  
  # Extract chat_id from channel (format: "chat:oc_xxx" or just "oc_xxx")
  CHAT_ID="$CHANNEL"
  if [[ "$CHAT_ID" == chat:* ]]; then
    CHAT_ID="${CHAT_ID#chat:}"
  fi
  
  # Send image message with image_key (inline display)
  SEND_RESPONSE=$(curl -s -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id" \
    -H "Authorization: Bearer $TENANT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"receive_id\":\"$CHAT_ID\",\"msg_type\":\"image\",\"content\":\"{\\\"image_key\\\":\\\"$IMAGE_KEY\\\"}\"}")
  
  SEND_CODE=$(echo "$SEND_RESPONSE" | jq -r '.code // empty')
  if [ "$SEND_CODE" != "0" ]; then
    log_error "Failed to send image message (code=$SEND_CODE)"
    echo "Response: $SEND_RESPONSE" >&2
    return 1
  fi
  
  log_info "Image sent to Feishu chat: $CHAT_ID"
  skill_log_ok selfie image_send "channel=$CHANNEL" "provider=$PROVIDER" "image_key=$IMAGE_KEY" "method=feishu_upload"
  
  # If there's a custom caption, send it as a separate text message
  if [ -n "$CAPTION" ] && [ "$CAPTION" != "Generated with Grok Imagine" ]; then
    CAPTION_ESCAPED=$(echo "$CAPTION" | jq -Rs .)
    curl -s -X POST "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id" \
      -H "Authorization: Bearer $TENANT_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"receive_id\":\"$CHAT_ID\",\"msg_type\":\"text\",\"content\":\"{\\\"text\\\":$CAPTION_ESCAPED}\"}" > /dev/null
    log_info "Caption sent separately"
  fi
  
  return 0
}

# Detect if channel is Feishu
IS_FEISHU=false
if [[ "$CHANNEL" == *feishu* ]] || [[ "$CHANNEL" == oc_* ]] || [[ "$CHANNEL" == chat:oc_* ]]; then
  IS_FEISHU=true
fi

# Send via direct channel or OpenClaw gateway fallback
log_info "Sending to channel: $CHANNEL"

if [ "$IS_FEISHU" = true ]; then
  if _send_to_feishu; then
    log_info "Done! Image sent to $CHANNEL via Feishu API (inline display)"
  else
    log_warn "Feishu upload failed, falling back to gateway send (may appear as file)"
    # Fall back to regular OpenClaw-compatible send.
    if [ "$USE_CLI" = true ]; then
      openclaw message send \
        --action send \
        --channel "$CHANNEL" \
        --message "$CAPTION" \
        --media "$IMAGE_URL"
    else
      GATEWAY_URL="${OPENCLAW_GATEWAY_URL:-http://localhost:18789}"
      GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
      curl -s -X POST "$GATEWAY_URL/message" \
        -H "Content-Type: application/json" \
        ${GATEWAY_TOKEN:+-H "Authorization: Bearer $GATEWAY_TOKEN"} \
        -d "{\"action\":\"send\",\"channel\":\"$CHANNEL\",\"message\":$(echo "$CAPTION" | jq -Rs .),\"media\":\"$IMAGE_URL\"}"
    fi
  fi
else
  # Non-Feishu channel, use regular send
  if [ "$USE_CLI" = true ]; then
    openclaw message send \
      --action send \
      --channel "$CHANNEL" \
      --message "$CAPTION" \
      --media "$IMAGE_URL"
  else
    GATEWAY_URL="${OPENCLAW_GATEWAY_URL:-http://localhost:18789}"
    GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
    curl -s -X POST "$GATEWAY_URL/message" \
      -H "Content-Type: application/json" \
      ${GATEWAY_TOKEN:+-H "Authorization: Bearer $GATEWAY_TOKEN"} \
      -d "{\"action\":\"send\",\"channel\":\"$CHANNEL\",\"message\":$(echo "$CAPTION" | jq -Rs .),\"media\":\"$IMAGE_URL\"}"
  fi
fi

log_info "Done! Image sent to $CHANNEL"
skill_log_ok selfie image_send "channel=$CHANNEL" "provider=$PROVIDER" "image_url=$IMAGE_URL"

echo ""
echo "--- Result ---"
jq -n \
  --arg url "$IMAGE_URL" \
  --arg channel "$CHANNEL" \
  --arg prompt "$PROMPT" \
  --arg provider "$PROVIDER" \
  '{
    success: true,
    image_url: $url,
    channel: $channel,
    prompt: $prompt,
    provider: $provider
  }'
