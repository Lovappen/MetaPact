#!/bin/bash
# smoke-test.sh — verify skills are wired up correctly.
# Safe to re-run. Offers optional live tests if user provides a channel.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

step "冒烟测试"

SKILLS="$OPENCLAW_SKILLS_DIR"
RUNTIME="${NAKO_AGENT_RUNTIME:-openclaw}"
RUNTIME_HOME="${NAKO_RUNTIME_HOME:-${HERMES_HOME:-$OPENCLAW_HOME}}"
MEDIA_HOME="${NAKO_MEDIA_HOME:-$RUNTIME_HOME/media}"
SKILL_ENV_NOTE="$SKILLS/.env"
if [ "$RUNTIME" = "hermes" ]; then
  RUNTIME_ENV_NOTE="$SKILL_ENV_NOTE 或 $HERMES_HOME/.env"
else
  RUNTIME_ENV_NOTE="$SKILL_ENV_NOTE 或 openclaw.json skills.entries.*.env"
fi
PASS=0; FAIL=0; SKIP=0

check() {
  local name="$1" shift_cmd="$1"; shift 2
  if "$shift_cmd" "$@" >/dev/null 2>&1; then
    info "$name"
    PASS=$((PASS+1))
  else
    warn "$name — 不通过"
    FAIL=$((FAIL+1))
  fi
}

has_env_key() {
  local key="$1" file="${2:-$SKILLS/.env}"
  grep -qE "^${key}=.+" "$file" 2>/dev/null
}

has_openclaw_skill_env_key() {
  [ "$RUNTIME" = "hermes" ] && return 1
  local skill="$1" key="$2"
  python3 - "$OPENCLAW_CONFIG" "$skill" "$key" <<'PY' 2>/dev/null
import json
import sys
from pathlib import Path

path, skill, key = sys.argv[1:4]
try:
    data = json.loads(Path(path).read_text())
except Exception:
    raise SystemExit(1)
env = (((data.get("skills") or {}).get("entries") or {}).get(skill) or {}).get("env") or {}
raise SystemExit(0 if env.get(key) else 1)
PY
}

has_runtime_env_key() {
  local skill="$1" key="$2"
  has_env_key "$key" "$SKILLS/.env" && return 0
  if [ "$RUNTIME" = "hermes" ] && [ -n "${HERMES_HOME:-}" ]; then
    has_env_key "$key" "$HERMES_HOME/.env" && return 0
  fi
  has_openclaw_skill_env_key "$skill" "$key"
}

# Vision
if [ -x "$SKILLS/vision/scripts/resolve.sh" ]; then
  if [ -d "$MEDIA_HOME/inbound" ] && ls "$MEDIA_HOME/inbound"/*.{jpg,png,webp} >/dev/null 2>&1; then
    OUT=$("$SKILLS/vision/scripts/resolve.sh" --latest 2>&1 || true)
    if [ -f "$OUT" ]; then
      info "vision: resolve --latest 成功（$OUT）"
      PASS=$((PASS+1))
    else
      warn "vision: resolve --latest 返回非文件路径：$OUT"
      FAIL=$((FAIL+1))
    fi
  else
    dim "vision: 无 inbound 图片可测（用户发一张图后再试）"
    SKIP=$((SKIP+1))
  fi
else
  warn "vision: 脚本不存在"
  FAIL=$((FAIL+1))
fi

# Hearing
if [ -x "$SKILLS/hearing/scripts/stt.sh" ]; then
  if has_bin whisper && has_bin ffmpeg; then
    info "hearing: whisper + ffmpeg 已装"
    PASS=$((PASS+1))
    dim "  （首次真·转写会下模型，这里不主动触发）"
  else
    warn "hearing: 缺 whisper 或 ffmpeg — brew install openai-whisper ffmpeg"
    FAIL=$((FAIL+1))
  fi
else
  warn "hearing: 脚本不存在"
  FAIL=$((FAIL+1))
fi

# Voice / Sing
if [ -x "$SKILLS/voice/scripts/voice.sh" ]; then
  if has_runtime_env_key voice MINIMAX_API_KEY || has_runtime_env_key voice VOLCENGINE_API_KEY; then
    info "voice: 至少一个 TTS key 已配"
    PASS=$((PASS+1))
  else
    warn "voice: 未发现 TTS key，说话功能不可用（支持 ${RUNTIME_ENV_NOTE}）"
    FAIL=$((FAIL+1))
  fi
  if has_runtime_env_key voice MINIMAX_API_KEY && has_runtime_env_key voice MINIMAX_GROUP_ID; then
    info "sing: MiniMax key + Group ID 已配"
    PASS=$((PASS+1))
  else
    warn "sing: 缺 MINIMAX_API_KEY 或 MINIMAX_GROUP_ID，唱歌功能不可用（支持 ${RUNTIME_ENV_NOTE}）"
    SKIP=$((SKIP+1))
  fi
fi

# Selfie
if [ -x "$SKILLS/selfie/scripts/selfie.sh" ]; then
  if has_runtime_env_key selfie FAL_KEY || has_runtime_env_key selfie KIE_API_KEY; then
    info "selfie: 图像生成 key 已配"
    PASS=$((PASS+1))
    if has_runtime_env_key selfie SELFIE_REFERENCE_IMAGE; then
      info "selfie: 参考图已配"
      PASS=$((PASS+1))
    else
      warn "selfie: 缺 SELFIE_REFERENCE_IMAGE，参考图生成不可用（支持 ${RUNTIME_ENV_NOTE} 或 workspace skills/.env）"
      FAIL=$((FAIL+1))
    fi
  else
    dim "selfie: 未配 FAL_KEY / KIE_API_KEY，自拍不可用（可选；支持 ${RUNTIME_ENV_NOTE}）"
    SKIP=$((SKIP+1))
  fi
fi

# Dokidoki
if has_bin doki; then
  info "dokidoki: doki 已装"
  PASS=$((PASS+1))
else
  dim "dokidoki: doki 未装 — npm install -g @tryjoy/dokidoki （可选）"
  SKIP=$((SKIP+1))
fi

echo
info "通过 $PASS 项，跳过 $SKIP 项，未通过 $FAIL 项"
[ "$FAIL" = "0" ]
