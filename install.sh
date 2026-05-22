#!/bin/bash
# install.sh — Lovappen/MetaPact Nako installer for macOS / Linux.
#
# Usage:
#   curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash
#   # or clone repo then:  bash install.sh [--force] [--agent-id <id>] [--non-interactive]
#
# Flags:
#   --agent nako        : compatibility selector (default: nako)
#   --list             : list available agents and exit
#   --force             : overwrite existing persona files (user data still preserved)
#   --agent-id ID       : rename the agent (default: agent-nako)
#   --runtime NAME      : openclaw|hermes|qclaw messaging runtime (default: openclaw)
#   --non-interactive   : no prompts; expects env vars set already; picks defaults
#   --skip-skills       : skip skill install (persona only)
#   --skip-models       : skip model mapping (keep existing primary)
#   --cc-connect-source : auto|npm|lazycat|skip (default lazycat; CodeEagle fork)
#   --cc-project-id ID  : cc-connect project id (默认 openclaw 用 agent id，其他 runtime 加后缀)

set -euo pipefail

case "$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')" in
  mingw*|msys*|cygwin*)
    echo "Windows shell detected. Use the Windows installer instead:" >&2
    echo "  pwsh install.ps1" >&2
    exit 1
    ;;
esac

# ─── PATH augment: SSH 默认 shell 常常不带 brew/nvm 的 bin ──────────────────
# 让 has_bin / 直接调用 npm/node/openclaw 都能找到，无论用户用 brew 还是 nvm 装。
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"
[ -d /usr/local/bin    ] && export PATH="/usr/local/bin:$PATH"
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
# nvm: 用最新一版 node 的 bin
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" | sort -V | tail -1 || true)
  [ -n "$NVM_LATEST" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ] && \
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
fi

track_metapact_installer_run() {
  case "${METAPACT_ANALYTICS_DISABLED:-}" in
    1|true|TRUE|yes|YES) return 0 ;;
  esac
  command -v curl >/dev/null 2>&1 || return 0

  local endpoint="${METAPACT_ANALYTICS_ENDPOINT:-https://umami.lovappen.cn/api/send}"
  local payload='{"type":"event","payload":{"website":"c07077fc-3cab-4745-9d93-5c8256302a20","hostname":"metapact.app","language":"en-US","screen":"1x1","title":"MetaPact CLI Installer","url":"/install.sh","referrer":"","tag":"metapact-home","name":"install-script-run-sh","data":{"script":"sh","source":"cli"}}}'

  curl -fsS --connect-timeout 2 --max-time 3 \
    -A 'Mozilla/5.0 (CLI; MetaPactInstaller/1.0) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36' \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "$endpoint" >/dev/null 2>&1 || true
}
track_metapact_installer_run

# ─── Resolve repo / pack root (works for local clone or curl-piped) ─────────
if [ -n "${BASH_SOURCE:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  # Piped via curl — clone the repo to a temp dir
  if ! command -v git >/dev/null; then
    echo "git required" >&2; exit 1
  fi
  TMPDL=$(mktemp -d)
  trap 'rm -rf "$TMPDL"' EXIT
  echo "正在克隆 MetaPact 仓库 → $TMPDL ..."
  git clone --depth 1 https://github.com/Lovappen/MetaPact.git "$TMPDL" >/dev/null 2>&1
  REPO_ROOT="$TMPDL"
fi
PACK_ROOT="$REPO_ROOT/nako"

SCRIPT_DIR="$PACK_ROOT/scripts"
source "$SCRIPT_DIR/lib.sh"

# ─── Parse flags ────────────────────────────────────────────────────────────
FORCE=0
AGENT="nako"
AGENT_ID="agent-nako"
LIST=0
NON_INTERACTIVE=0
SKIP_SKILLS=0
SKIP_MODELS=0
RESET_SECRETS=0
WITH_CC_CONNECT=0
WITH_FEISHU=0
WITH_WEIXIN=0
CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"
CC_PROJECT_ID="${CC_PROJECT_ID:-${CC_CONNECT_PROJECT_ID:-}}"
NAKO_AGENT_RUNTIME="${NAKO_AGENT_RUNTIME:-openclaw}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_BIN="${HERMES_BIN:-}"
HERMES_DEFAULT_MODEL="${HERMES_DEFAULT_MODEL:-zai/glm-4.5-flash}"
HERMES_SKILLS_DIR="${HERMES_SKILLS_DIR:-$HERMES_HOME/skills/nako}"
HERMES_MEDIA_HOME="${HERMES_MEDIA_HOME:-$HERMES_HOME/media}"
QCLAW_HOME="${QCLAW_HOME:-$HOME/.qclaw}"
QCLAW_NODE_BIN="${QCLAW_NODE_BIN:-}"
QCLAW_OPENCLAW_MJS="${QCLAW_OPENCLAW_MJS:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    --force) FORCE=1; export FORCE; shift ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --runtime|--backend) NAKO_AGENT_RUNTIME="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; export NON_INTERACTIVE; shift ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    --skip-models) SKIP_MODELS=1; shift ;;
    --reset-secrets) RESET_SECRETS=1; shift ;;
    --with-cc-connect) WITH_CC_CONNECT=1; shift ;;
    --with-feishu)     WITH_FEISHU=1; WITH_CC_CONNECT=1; shift ;;
    --with-weixin)     WITH_WEIXIN=1; WITH_CC_CONNECT=1; shift ;;
    --cc-connect-source) CC_CONNECT_SOURCE="$2"; WITH_CC_CONNECT=1; shift 2 ;;
    --cc-project-id|--project-id) CC_PROJECT_ID="$2"; WITH_CC_CONNECT=1; shift 2 ;;
    -h|--help)
      grep -E "^# " "$0" | head -20; exit 0 ;;
    *) err "Unknown flag: $1"; exit 1 ;;
  esac
done

case "$CC_CONNECT_SOURCE" in
  auto|npm|lazycat|skip) ;;
  *) err "--cc-connect-source 只支持 auto|npm|lazycat|skip"; exit 1 ;;
esac

case "$NAKO_AGENT_RUNTIME" in
  openclaw|hermes|qclaw) ;;
  *) err "--runtime 只支持 openclaw|hermes|qclaw"; exit 1 ;;
esac

expand_path() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import os
import sys
from pathlib import Path

print(str(Path(os.path.expanduser(sys.argv[1])).resolve()))
PY
  else
    printf '%s\n' "$1"
  fi
}

qclaw_app_value_early() {
  local path="$1" key="$2"
  [ -f "$path" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$path" "$key" <<'PY' 2>/dev/null || true
import json
import sys
from pathlib import Path

path, key = sys.argv[1:]
try:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
except Exception:
    data = {}
cur = data
for part in key.split("."):
    if not isinstance(cur, dict):
        cur = None
        break
    cur = cur.get(part)
print(cur if isinstance(cur, str) else "")
PY
}

if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  HERMES_HOME="$(expand_path "$HERMES_HOME")"
  HERMES_SKILLS_DIR="$(expand_path "$HERMES_SKILLS_DIR")"
  HERMES_MEDIA_HOME="$(expand_path "$HERMES_MEDIA_HOME")"
  OPENCLAW_HOME="$HERMES_HOME"
  OPENCLAW_SKILLS_DIR="$HERMES_SKILLS_DIR"
  OPENCLAW_WORKSPACES="$HERMES_HOME/workspace"
  OPENCLAW_CONFIG="$HERMES_HOME/openclaw-compat.json"
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  QCLAW_HOME="$(expand_path "$QCLAW_HOME")"
  QCLAW_APP_CONFIG="$QCLAW_HOME/qclaw.json"
  _qclaw_state_dir="$(qclaw_app_value_early "$QCLAW_APP_CONFIG" stateDir)"
  if [ -n "$_qclaw_state_dir" ]; then
    QCLAW_HOME="$(expand_path "$_qclaw_state_dir")"
    QCLAW_APP_CONFIG="$QCLAW_HOME/qclaw.json"
  fi
  QCLAW_OPENCLAW_CONFIG="$(qclaw_app_value_early "$QCLAW_APP_CONFIG" configPath)"
  if [ -n "$QCLAW_OPENCLAW_CONFIG" ]; then
    QCLAW_OPENCLAW_CONFIG="$(expand_path "$QCLAW_OPENCLAW_CONFIG")"
  else
    QCLAW_OPENCLAW_CONFIG="$QCLAW_HOME/openclaw.json"
  fi

  OPENCLAW_HOME="$QCLAW_HOME"
  OPENCLAW_CONFIG="$QCLAW_OPENCLAW_CONFIG"
  OPENCLAW_SKILLS_DIR="$QCLAW_HOME/skills"
  OPENCLAW_WORKSPACES="$QCLAW_HOME/workspace"
fi

export OPENCLAW_HOME OPENCLAW_CONFIG OPENCLAW_SKILLS_DIR OPENCLAW_WORKSPACES
export HERMES_HOME HERMES_SKILLS_DIR HERMES_MEDIA_HOME QCLAW_HOME
[ -n "${QCLAW_OPENCLAW_CONFIG:-}" ] && export QCLAW_OPENCLAW_CONFIG

if [ "$LIST" = "1" ]; then
  echo "可用 agent:"
  echo "  - nako"
  exit 0
fi

if [ "$AGENT" != "nako" ]; then
  err "Agent '$AGENT' 不存在；当前仓库只提供 nako"
  exit 1
fi

cat <<BANNER

${C_BOLD}野木奈子 Agent Pack - 安装器${C_NC}
  ${C_DIM}Repo: github.com/Lovappen/MetaPact${C_NC}
  ${C_DIM}Agent: $AGENT_ID${C_NC}
  ${C_DIM}Runtime: $NAKO_AGENT_RUNTIME${C_NC}
  ${C_DIM}Pack: $PACK_ROOT${C_NC}

BANNER

hermes_agent_roots() {
  printf '%s\n' "$HERMES_HOME/hermes-agent"
  [ "$HERMES_HOME" != "$HOME/.hermes" ] && printf '%s\n' "$HOME/.hermes/hermes-agent"
  if [ -d /home ]; then
    for dir in /home/*/.hermes/hermes-agent; do
      [ -d "$dir" ] && printf '%s\n' "$dir"
    done
  fi
}

ensure_hermes_venv_launcher() {
  local root candidate python script wrapper
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    candidate="$root/venv/bin/hermes"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    python="$root/venv/bin/python"
    script="$root/hermes"
    if [ -x "$python" ] && [ -f "$script" ]; then
      wrapper="$HERMES_HOME/bin/hermes"
      mkdir -p "$(dirname "$wrapper")" || continue
      printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$python" "$script" >"$wrapper" || continue
      chmod +x "$wrapper" || continue
      printf '%s\n' "$wrapper"
      return 0
    fi
  done <<EOF
$(hermes_agent_roots)
EOF
  return 1
}

find_hermes_bin() {
  if [ -n "${HERMES_BIN:-}" ]; then
    printf '%s\n' "$HERMES_BIN"
    return 0
  fi
  if [ -x "$HOME/.local/bin/hermes" ]; then
    printf '%s\n' "$HOME/.local/bin/hermes"
    return 0
  fi
  if command -v hermes >/dev/null 2>&1; then
    command -v hermes
    return 0
  fi
  ensure_hermes_venv_launcher
}

# ─── Preflight ──────────────────────────────────────────────────────────────
step "1. 前置检查"

MISSING_HARD=()
for b in python3 jq curl; do
  if has_bin "$b"; then info "$b"; else err "$b"; MISSING_HARD+=("$b"); fi
done

if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  if [ -z "${HERMES_BIN:-}" ]; then
    HERMES_BIN="$(find_hermes_bin || true)"
  fi
  if [ -z "${HERMES_BIN:-}" ]; then
    err "选择 Hermes runtime，但找不到 hermes 命令。请先安装 Hermes，或设置 HERMES_BIN=/path/to/hermes"
    exit 1
  fi
  mkdir -p "$HERMES_HOME" "$HERMES_SKILLS_DIR" "$HERMES_MEDIA_HOME"
  info "Hermes 目录 $HERMES_HOME"
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  if [ ! -f "$QCLAW_HOME/qclaw.json" ]; then
    err "选择 QClaw runtime，但找不到 $QCLAW_HOME/qclaw.json。请先下载安装并启动一次 QClaw。"
    exit 1
  fi
  info "QClaw 目录 $QCLAW_HOME"
  [ ! -f "$OPENCLAW_CONFIG" ] && { err "QClaw openclaw.json 不存在: $OPENCLAW_CONFIG"; exit 1; }
  info "QClaw openclaw.json"
else
  if [ ! -d "$OPENCLAW_HOME" ]; then
    err "~/.openclaw 不存在 — 请先安装 openclaw (npm i -g openclaw)"
    exit 1
  fi
  info "openclaw 目录 $OPENCLAW_HOME"

  [ ! -f "$OPENCLAW_CONFIG" ] && { err "openclaw.json 不存在"; exit 1; }
  info "openclaw.json"
fi

if [ "${#MISSING_HARD[@]}" -gt 0 ]; then
  err "请先装这些依赖：${MISSING_HARD[*]}"
  dim "macOS:  brew install ${MISSING_HARD[*]}"
  dim "Debian: sudo apt-get install ${MISSING_HARD[*]}"
  exit 1
fi

# Optional bins (not fatal)
ffmpeg_has_amr_encoder() {
  has_bin ffmpeg || return 1
  ffmpeg -hide_banner -encoders 2>/dev/null \
    | grep -Eq '(^|[[:space:]])(amr_nb|libopencore_amrnb)([[:space:]]|$)'
}

MISSING_SOFT=()
for b in whisper ffmpeg ffprobe xxd uuidgen doki; do
  has_bin "$b" && info "$b (可选)" || { warn "$b 缺失 (可选)"; MISSING_SOFT+=("$b"); }
done
if [ "${#MISSING_SOFT[@]}" -gt 0 ]; then
  echo
  dim "以下依赖缺失，相关 skill 将在运行时报错提示："
  dim "  whisper / ffmpeg → hearing skill (转写语音)"
  dim "  xxd / ffprobe    → voice skill"
  dim "  uuidgen          → outbound media filenames (falls back when possible)"
  dim "  doki             → dokidoki skill"
  dim "macOS 建议：brew install openai-whisper ffmpeg ; npm i -g @tryjoy/dokidoki"
  dim "Linux：sudo apt install ffmpeg libavcodec-extra（cc-connect 微信视频转码需要 AMR）"
  echo

  # 询问是否安装 ffmpeg。voice/hearing/video 都依赖它，微信语音还需要 AMR 编码支持。
  if echo " ${MISSING_SOFT[*]} " | grep -Eq ' (ffmpeg|ffprobe) '; then
    if [ "$NON_INTERACTIVE" = "1" ]; then
      _do_ffmpeg=0
    elif confirm "需要语音/视频转码（ffmpeg）吗？现在安装" y; then
      _do_ffmpeg=1
    else
      _do_ffmpeg=0
    fi
    if [ "$_do_ffmpeg" = "1" ]; then
      OS=$(uname -s)
      if [ "$OS" = "Darwin" ] && command -v brew >/dev/null; then
        brew install ffmpeg
      elif [ "$OS" = "Linux" ] && command -v apt-get >/dev/null; then
        sudo apt-get install -y ffmpeg libavcodec-extra
      else
        warn "无法自动安装 ffmpeg；请手动安装后重跑。"
      fi
    fi
  fi

  # 询问是否后台装 whisper
  if echo "${MISSING_SOFT[@]}" | grep -q whisper; then
    if [ "$NON_INTERACTIVE" = "1" ]; then
      _do_whisper=0
    elif confirm "需要语音识别（whisper）吗？现在后台安装（不阻塞）" y; then
      _do_whisper=1
    else
      _do_whisper=0
    fi
    if [ "$_do_whisper" = "1" ]; then
      mkdir -p "$OPENCLAW_HOME/skills/hearing"
      MARKER="$OPENCLAW_HOME/skills/hearing/.installing"
      LOGF="$OPENCLAW_HOME/skills/hearing/install.log"
      touch "$MARKER"
      OS=$(uname -s)
      (
        if [ "$OS" = "Darwin" ] && command -v brew >/dev/null; then
          brew install openai-whisper
        elif [ "$OS" = "Linux" ]; then
          if command -v apt-get >/dev/null; then sudo apt-get install -y python3-pip; fi
          pip install --user -U openai-whisper
        fi
        rm -f "$MARKER"
      ) >"$LOGF" 2>&1 &
      disown 2>/dev/null || true
      info "whisper 后台安装中 (PID $!)，日志: $LOGF"
      dim "  收到语音前装好就直接用；没装完时 hearing skill 会回 \"安装中\"，不阻塞 agent。"
    fi
  fi

  # 默认装 doki（dokidoki BLE；@abandonware/noble 需要 native build）
  if echo "${MISSING_SOFT[@]}" | grep -q doki; then
    if has_bin npm; then
      info "doki 缺失，npm i -g @tryjoy/dokidoki ..."
      _doki_log=/tmp/doki-install.log
      _try_doki_install() { npm i -g @tryjoy/dokidoki >"$_doki_log" 2>&1; }

      if ! _try_doki_install; then
        # Linux 上 BLE native gyp 失败 → 补 dev 包 + retry
        if [ "$(uname -s)" = "Linux" ] && grep -qE "gyp ERR|noble|bluetooth\.h|libudev" "$_doki_log"; then
          info "  检测到 BLE native build 缺依赖，apt 装 build-essential + libbluetooth-dev + libudev-dev ..."
          if command -v apt-get >/dev/null; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y \
              build-essential libbluetooth-dev libudev-dev python3 >>"$_doki_log" 2>&1 \
              || sudo apt-get install -y build-essential libbluetooth-dev libudev-dev python3 >>"$_doki_log" 2>&1 \
              || true
            info "  retry npm i -g @tryjoy/dokidoki ..."
            _try_doki_install && info "doki 已装" || _doki_failed=1
          fi
        fi

        if [ "${_doki_failed:-0}" = "1" ] || [ ! -x "$(command -v doki 2>/dev/null)" ]; then
          warn "doki 安装失败，日志末尾："
          tail -5 "$_doki_log" 2>&1 | sed "s/^/    /" >&2
          if grep -q EACCES "$_doki_log"; then
            dim "  权限不足 → sudo npm i -g @tryjoy/dokidoki"
          elif grep -qE "gyp ERR|noble" "$_doki_log"; then
            dim "  BLE native build 失败。Linux 需: sudo apt install build-essential libbluetooth-dev libudev-dev"
            dim "  macOS 需: xcode-select --install"
          elif grep -q EBADENGINE "$_doki_log"; then
            dim "  Node 版本不符（需要更高版本）"
          else
            dim "  完整日志：$_doki_log"
          fi
        fi
      else
        info "doki 已装"
      fi
    else
      warn "无 npm，跳过 doki 安装"
    fi
  fi
fi

if has_bin ffmpeg && ! ffmpeg_has_amr_encoder; then
  warn "当前 ffmpeg 缺少 AMR 编码器（amr_nb/libopencore_amrnb）。微信原生语音气泡可能发送失败；失败时 voice/sing 会保留 MP3 文件路径并提示缺少的转码能力。"
  dim "  macOS 可尝试安装带 AMR 支持的 ffmpeg；Linux 通常需要：sudo apt install ffmpeg libavcodec-extra"
fi

# ─── Gateway preflight: ensure it's up early so cron / acp 后面都顺 ─────────
step "1b. Gateway 预检"

openclaw_cron_ready() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "${OPENCLAW_CRON_READY_TIMEOUT:-8}" openclaw cron list >/dev/null 2>&1
  else
    openclaw cron list >/dev/null 2>&1
  fi
}

openclaw_timed() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "${OPENCLAW_INSTALL_CMD_TIMEOUT:-30}" openclaw "$@"
  else
    openclaw "$@"
  fi
}

qclaw_gateway_port() {
  local port=""
  port="$(qclaw_app_value_early "$QCLAW_HOME/qclaw.json" port)"
  printf '%s\n' "${port:-28789}"
}

qclaw_openclaw_timed() {
  local port
  port="$(qclaw_gateway_port)"
  if command -v timeout >/dev/null 2>&1; then
    OPENCLAW_STATE_DIR="$QCLAW_HOME" \
    OPENCLAW_CONFIG_PATH="${QCLAW_OPENCLAW_CONFIG:-$QCLAW_HOME/openclaw.json}" \
    OPENCLAW_GATEWAY_URL="ws://127.0.0.1:$port" \
      timeout "${OPENCLAW_INSTALL_CMD_TIMEOUT:-30}" "$QCLAW_NODE_BIN" "$QCLAW_OPENCLAW_MJS" "$@"
  else
    OPENCLAW_STATE_DIR="$QCLAW_HOME" \
    OPENCLAW_CONFIG_PATH="${QCLAW_OPENCLAW_CONFIG:-$QCLAW_HOME/openclaw.json}" \
    OPENCLAW_GATEWAY_URL="ws://127.0.0.1:$port" \
      "$QCLAW_NODE_BIN" "$QCLAW_OPENCLAW_MJS" "$@"
  fi
}

qclaw_cron_ready() {
  [ -n "${QCLAW_NODE_BIN:-}" ] && [ -n "${QCLAW_OPENCLAW_MJS:-}" ] || return 1
  [ -x "$QCLAW_NODE_BIN" ] && [ -f "$QCLAW_OPENCLAW_MJS" ] || return 1
  qclaw_openclaw_timed cron status >/dev/null 2>&1
}

hermes_timed() {
  if command -v timeout >/dev/null 2>&1; then
    HERMES_HOME="$HERMES_HOME" timeout "${HERMES_INSTALL_CMD_TIMEOUT:-30}" "$HERMES_BIN" "$@"
  else
    HERMES_HOME="$HERMES_HOME" "$HERMES_BIN" "$@"
  fi
}

hermes_cron_ready() {
  [ -n "${HERMES_BIN:-}" ] && [ -x "$HERMES_BIN" ] || return 1
  hermes_timed cron list >/dev/null 2>&1
}

qclaw_json_value() {
  local key="$1"
  python3 - "$QCLAW_HOME/qclaw.json" "$key" <<'PY' 2>/dev/null || true
import json, sys
from pathlib import Path

path, key = sys.argv[1:]
try:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
except Exception:
    data = {}
cur = data
for part in key.split("."):
    if not isinstance(cur, dict):
        cur = None
        break
    cur = cur.get(part)
print(cur if isinstance(cur, str) else "")
PY
}

find_qclaw_node_bin() {
  if [ -n "${QCLAW_NODE_BIN:-}" ]; then
    printf '%s\n' "$QCLAW_NODE_BIN"
    return 0
  fi
  local from_config
  from_config="$(qclaw_json_value cli.nodeBinary)"
  if [ -n "$from_config" ]; then
    printf '%s\n' "$from_config"
    return 0
  fi
  if [ -x "/Applications/QClaw.app/Contents/Resources/node/node" ]; then
    printf '%s\n' "/Applications/QClaw.app/Contents/Resources/node/node"
    return 0
  fi
  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi
  return 1
}

find_qclaw_openclaw_mjs() {
  if [ -n "${QCLAW_OPENCLAW_MJS:-}" ]; then
    printf '%s\n' "$QCLAW_OPENCLAW_MJS"
    return 0
  fi
  local from_config
  from_config="$(qclaw_json_value cli.openclawMjs)"
  if [ -n "$from_config" ]; then
    printf '%s\n' "$from_config"
    return 0
  fi
  local mac_mjs="$HOME/Library/Application Support/QClaw/openclaw/node_modules/openclaw/openclaw.mjs"
  if [ -f "$mac_mjs" ]; then
    printf '%s\n' "$mac_mjs"
    return 0
  fi
  return 1
}

sync_qclaw_runtime() {
  QCLAW_NODE_BIN="$(find_qclaw_node_bin)" || {
    err "选择 QClaw runtime，但找不到 QClaw Node。请先安装 QClaw，或设置 QCLAW_NODE_BIN=/path/to/node"
    return 1
  }
  QCLAW_OPENCLAW_MJS="$(find_qclaw_openclaw_mjs)" || {
    err "选择 QClaw runtime，但找不到 QClaw openclaw.mjs。请先启动一次 QClaw，或设置 QCLAW_OPENCLAW_MJS=/path/to/openclaw.mjs"
    return 1
  }

  local qclaw_workspace="$QCLAW_HOME/workspace-$AGENT_ID"
  local qclaw_agent_dir="$QCLAW_HOME/agents/$AGENT_ID/agent"
  mkdir -p "$qclaw_workspace" "$qclaw_agent_dir" "$QCLAW_HOME/skills"
  if [ "$AGENT_WORKSPACE" != "$qclaw_workspace" ]; then
    cp -R "$AGENT_WORKSPACE/." "$qclaw_workspace/"
  fi
  if [ -d "$OPENCLAW_SKILLS_DIR" ] && [ "$OPENCLAW_SKILLS_DIR" != "$QCLAW_HOME/skills" ]; then
    cp -R "$OPENCLAW_SKILLS_DIR/." "$QCLAW_HOME/skills/"
  fi

  python3 - "$QCLAW_HOME" "${QCLAW_OPENCLAW_CONFIG:-$QCLAW_HOME/openclaw.json}" "$OPENCLAW_CONFIG" "$AGENT_ID" "${PRIMARY:-}" <<'PY'
import json
import sys
import time
from pathlib import Path

qclaw_home, qclaw_config, openclaw_config, agent_id, primary = sys.argv[1:]
home = Path(qclaw_home).expanduser()
home.mkdir(parents=True, exist_ok=True)
config_path = Path(qclaw_config).expanduser()
openclaw_config_path = Path(openclaw_config).expanduser()

def load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return {}

cfg = load(config_path)
source = load(openclaw_config_path)
if not isinstance(cfg, dict):
    cfg = {}
agents = cfg.setdefault("agents", {})
if not isinstance(agents, dict):
    cfg["agents"] = agents = {}
agents.setdefault("defaults", {})
items = agents.setdefault("list", [])
if not isinstance(items, list):
    agents["list"] = items = []

source_item = {}
for item in ((source.get("agents") or {}).get("list") or []):
    if isinstance(item, dict) and item.get("id") == agent_id:
        source_item = item
        break

existing_item = {}
for item in items:
    if isinstance(item, dict) and item.get("id") == agent_id:
        existing_item = item
        break

def primary_model(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        primary_value = value.get("primary")
        if isinstance(primary_value, str):
            return primary_value
    return ""

default_identity = {
    "name": "野木奈子",
    "emoji": "🎀",
    "theme": "核战后赛博世界专属战斗女仆",
    "avatar": "assets/nako-avatar-head.png",
}
legacy_default_avatars = {
    "assets/nako-avatar.svg",
    "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png",
}

def normalize_identity(identity):
    if not isinstance(identity, dict):
        return {}
    result = {}
    for key in ("name", "emoji", "theme", "avatar"):
        value = identity.get(key)
        if isinstance(value, str) and value:
            result[key] = value
    if "theme" not in result:
        vibe = identity.get("vibe")
        if isinstance(vibe, str) and vibe:
            result["theme"] = vibe
    return result

def apply_default_identity(identity):
    result = normalize_identity(identity)
    if agent_id.startswith("agent-nako"):
        if result.get("avatar") in legacy_default_avatars:
            result["avatar"] = default_identity["avatar"]
        for key, value in default_identity.items():
            if not result.get(key):
                result[key] = value
    return result

def apply_qclaw_script_media_policy(item):
    if not agent_id.startswith("agent-nako"):
        return item
    tools = item.get("tools")
    if not isinstance(tools, dict):
        tools = {}
    else:
        tools = dict(tools)
    deny = tools.get("deny")
    if not isinstance(deny, list):
        deny = []
    else:
        deny = list(deny)
    seen = {value for value in deny if isinstance(value, str)}
    for tool_name in ("image_generate", "video_generate", "tts"):
        if tool_name not in seen:
            deny.append(tool_name)
            seen.add(tool_name)
    tools["deny"] = deny
    item["tools"] = tools
    return item

identity = (
    existing_item.get("identity") if isinstance(existing_item.get("identity"), dict)
    else source_item.get("identity") if isinstance(source_item.get("identity"), dict)
    else {}
)
identity = apply_default_identity(identity)
name = existing_item.get("name") or source_item.get("name") or ""
if not name or name == agent_id:
    name = identity.get("name") or agent_id

entry = {
    "id": agent_id,
    "name": name,
    "workspace": str(home / f"workspace-{agent_id}"),
    "agentDir": str(home / "agents" / agent_id / "agent"),
    "identity": identity,
}
qclaw_default_model = (((agents.get("defaults") or {}).get("model") or {}).get("primary"))
model = (
    primary_model(existing_item.get("model"))
    or qclaw_default_model
    or primary_model(source_item.get("model"))
    or primary
)
if model:
    entry["model"] = model
entry = apply_qclaw_script_media_policy(entry)

for idx, item in enumerate(items):
    if isinstance(item, dict) and item.get("id") == agent_id:
        merged = dict(item)
        merged.update(entry)
        merged = apply_qclaw_script_media_policy(merged)
        items[idx] = merged
        break
else:
    items.append(entry)

old = config_path.read_text(encoding="utf-8", errors="ignore") if config_path.exists() else ""
new = json.dumps(cfg, ensure_ascii=False, indent=2) + "\n"
if old != new:
    if config_path.exists():
        backup = config_path.with_name(f"openclaw.json.bak-nako-qclaw-{time.strftime('%Y%m%d-%H%M%S')}")
        backup.write_text(old, encoding="utf-8")
    config_path.write_text(new, encoding="utf-8")
PY

  local status_pid elapsed=0 status_timeout="${QCLAW_STATUS_TIMEOUT:-20}"
  OPENCLAW_STATE_DIR="$QCLAW_HOME" OPENCLAW_CONFIG_PATH="${QCLAW_OPENCLAW_CONFIG:-$QCLAW_HOME/openclaw.json}" \
    "$QCLAW_NODE_BIN" "$QCLAW_OPENCLAW_MJS" agents list --json >/tmp/nako-qclaw-status.log 2>&1 &
  status_pid=$!
  while kill -0 "$status_pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$status_timeout" ]; then
      kill "$status_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$status_pid" 2>/dev/null || true
      wait "$status_pid" 2>/dev/null || true
      warn "QClaw 状态检查超时；已写入 workspace/config，日志 /tmp/nako-qclaw-status.log"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed+1))
  done
  if wait "$status_pid"; then
    info "QClaw runtime 已同步: $qclaw_workspace"
  else
    warn "QClaw 状态检查未完全通过；已写入 workspace/config，日志 /tmp/nako-qclaw-status.log"
  fi
}

sync_hermes_runtime() {
  HERMES_BIN="$(find_hermes_bin)" || {
    err "选择 Hermes runtime，但找不到 hermes 命令。请先安装 Hermes，或设置 HERMES_BIN=/path/to/hermes"
    return 1
  }

  local hermes_workspace="$HERMES_HOME/workspace/$AGENT_ID"
  local hermes_skills="$HERMES_SKILLS_DIR"
  mkdir -p "$hermes_workspace" "$hermes_skills" "$HERMES_HOME/memories"

  if [ "$AGENT_WORKSPACE" != "$hermes_workspace" ]; then
    cp -R "$AGENT_WORKSPACE/." "$hermes_workspace/"
  fi
  [ -f "$AGENT_WORKSPACE/SOUL.md" ] && cp "$AGENT_WORKSPACE/SOUL.md" "$HERMES_HOME/SOUL.md"
  [ -f "$AGENT_WORKSPACE/USER.md" ] && cp "$AGENT_WORKSPACE/USER.md" "$HERMES_HOME/memories/USER.md"
  [ -f "$AGENT_WORKSPACE/MEMORY.md" ] && cp "$AGENT_WORKSPACE/MEMORY.md" "$HERMES_HOME/memories/MEMORY.md"
  [ -f "$AGENT_WORKSPACE/skills/.env" ] && cp "$AGENT_WORKSPACE/skills/.env" "$hermes_skills/.env.$AGENT_ID"

  python3 - "$HERMES_HOME" "$AGENT_ID" "${PRIMARY:-}" "$PRESET_FILE" "$hermes_skills" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

hermes_home, agent_id, primary, preset_path, hermes_skills = sys.argv[1:]
home = Path(hermes_home)
home.mkdir(parents=True, exist_ok=True)
provider, _, model = primary.partition("/")
if not model:
    model = primary
if not provider:
    provider = "zai"
if not model:
    model = "glm-4.5-flash"

def load_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return {}

preset = load_json(preset_path)
providers = {}
providers.update(preset if isinstance(preset, dict) else {})
providers.setdefault("zai", {})
providers["zai"].update({
    "baseUrl": "https://api.z.ai/api/coding/paas/v4",
    "models": [
        {"id": "glm-4.5-flash"},
        {"id": "glm-4.7"},
        {"id": "glm-4.7-flash"},
    ],
})

def env_key_for(name):
    table = {"zai": "ZAI_API_KEY", "glm": "GLM_API_KEY", "sensenova": "SENSENOVA_API_KEY"}
    return table.get(name, re.sub(r"[^A-Za-z0-9]+", "_", name).upper() + "_API_KEY")

def valid_secret(value):
    return isinstance(value, str) and len(value.strip()) >= 8 and not value.lower().startswith("your-")

def find_key_for_provider(name):
    candidates = [
        home / "agents" / agent_id / "agent" / "auth-profiles.json",
        home / "agents" / "main" / "agent" / "auth-profiles.json",
    ]
    key_names = {"apiKey", "api_key", "apikey", "key", "token", "accessToken", "access_token"}

    def walk(obj, provider_context=False):
        if isinstance(obj, dict):
            text = " ".join(str(v).lower() for v in obj.values() if isinstance(v, (str, int, float, bool)))
            in_context = provider_context or name.lower() in text
            for k, v in obj.items():
                if in_context and k in key_names and valid_secret(v):
                    return v.strip()
            if name in obj:
                hit = walk(obj[name], True)
                if hit:
                    return hit
            for v in obj.values():
                hit = walk(v, in_context)
                if hit:
                    return hit
        elif isinstance(obj, list):
            for item in obj:
                hit = walk(item, provider_context)
                if hit:
                    return hit
        return ""

    for path in candidates:
        hit = walk(load_json(path), False)
        if hit:
            return hit
    return ""

env_path = home / ".env"
existing = {}
if env_path.exists():
    for line in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        existing[key.strip()] = value.strip()

additions = []
for name in sorted(providers):
    env_key = env_key_for(name)
    if existing.get(env_key):
        continue
    if name == "zai" and existing.get("GLM_API_KEY"):
        additions.append(f"{env_key}={existing['GLM_API_KEY']}")
        continue
    secret = os.environ.get(env_key) or find_key_for_provider(name)
    if secret:
        additions.append(f"{env_key}={secret}")
        if name == "zai" and not existing.get("GLM_API_KEY"):
            additions.append(f"GLM_API_KEY={secret}")

if additions:
    with env_path.open("a", encoding="utf-8") as f:
        if env_path.exists() and env_path.stat().st_size:
            f.write("\n")
        f.write("\n".join(additions) + "\n")
    os.chmod(env_path, 0o600)
elif not env_path.exists():
    env_path.write_text("", encoding="utf-8")
    os.chmod(env_path, 0o600)

provider_cfg = providers.get(provider, {}) if provider else {}
base_url = provider_cfg.get("baseUrl") or provider_cfg.get("base_url") or ""
if provider == "zai":
    base_url = base_url or "https://api.z.ai/api/coding/paas/v4"
api_mode = "chat_completions"
selected_key = env_key_for(provider) if provider else ""

def yaml_quote(value):
    return json.dumps(value, ensure_ascii=False)

provider_lines = []
managed_provider_names = [provider] if provider and provider not in {"zai"} else []
for name in managed_provider_names:
    cfg = providers.get(name, {})
    models = [m.get("id") for m in (cfg.get("models") or []) if isinstance(m, dict) and m.get("id")]
    context_lengths = {
        m.get("id"): m.get("contextWindow")
        for m in (cfg.get("models") or [])
        if isinstance(m, dict) and m.get("id") and m.get("contextWindow")
    }
    if not models and name == provider and model:
        models = [model]
    provider_lines.extend([
        f"  - name: {yaml_quote(name)}",
        f"    base_url: {yaml_quote(cfg.get('baseUrl') or cfg.get('base_url') or '')}",
        f"    key_env: {yaml_quote(env_key_for(name))}",
        "    api_mode: chat_completions",
        f"    model: {yaml_quote(models[0] if models else '')}",
        "    models:",
    ])
    if models:
        for m in models:
            provider_lines.append(f"      {yaml_quote(m)}:")
            if context_lengths.get(m):
                provider_lines.append(f"        context_length: {int(context_lengths[m])}")
            else:
                provider_lines.append("        context_length: null")
    else:
        provider_lines.append("      {}")

custom_provider_block = (["custom_providers:"] + provider_lines) if provider_lines else []
managed = "\n".join([
    "# BEGIN NAKO HERMES RUNTIME",
    "model:",
    f"  default: {yaml_quote(model)}",
    f"  provider: {yaml_quote(provider)}",
    f"  base_url: {yaml_quote(base_url)}",
    f"  api_mode: {yaml_quote(api_mode)}",
    *custom_provider_block,
    "skills:",
    "  external_dirs:",
    f"    - {yaml_quote(hermes_skills)}",
    "# END NAKO HERMES RUNTIME",
    "",
])

config_path = home / "config.yaml"
old = config_path.read_text(encoding="utf-8", errors="ignore") if config_path.exists() else ""
new = re.sub(
    r"(?ms)^# BEGIN NAKO HERMES RUNTIME\n.*?^# END NAKO HERMES RUNTIME\n?",
    "",
    old,
).rstrip()
new = re.sub(r"(?ms)^(?:model|custom_providers|skills):\n(?:^[ \t].*\n?)*", "", new).rstrip()
new = (new + "\n\n" if new else "") + managed
if old != new:
    if config_path.exists():
        backup = config_path.with_name("config.yaml.bak-nako-hermes")
        backup.write_text(old, encoding="utf-8")
    config_path.write_text(new, encoding="utf-8")
PY

  HERMES_HOME="$HERMES_HOME" "$HERMES_BIN" status >/tmp/nako-hermes-status.log 2>&1 \
    && info "Hermes runtime 已同步: $hermes_workspace" \
    || warn "Hermes status 未完全通过；已写入 workspace/config，日志 /tmp/nako-hermes-status.log"
}

if [ "$NAKO_AGENT_RUNTIME" = "openclaw" ]; then
  # 0) 修复常见配置障碍：缺 gateway.mode 直接 block 启动
  _changed_mode=0
  if ! openclaw config get gateway.mode >/dev/null 2>&1; then
    openclaw config set gateway.mode local >/dev/null 2>&1 && { info "已设 gateway.mode=local"; _changed_mode=1; }
  fi

  # 0b) bonjour 在容器/隔离网络/某些 macOS 上 mDNS announce 会触发
  #     Unhandled promise rejection (CIAO ANNOUNCEMENT CANCELLED) 干掉 gateway。
  #     默认禁掉，需要 LAN 发现的用户自行 enable。
  # Always disable bonjour (idempotent — `disable` 对已禁的也无害)。
  # 不把它计为强制重启条件；部分 openclaw 版本对已禁插件也返回成功。
  openclaw plugins disable bonjour >/dev/null 2>&1 && info "已禁 bonjour 插件 (容器/隔离网络稳定性)" || true

  # 1) 若 gateway 已跑 + 我们刚改了 mode → 重启让新 config 生效
  if openclaw_cron_ready; then
    if [ "$_changed_mode" = "1" ]; then
      info "重启 gateway 让新 config 生效..."
      openclaw daemon restart >/dev/null 2>&1 || pkill -f openclaw-gateway 2>/dev/null
      sleep 2
    else
      info "gateway 已在跑"
    fi
  fi

  if ! openclaw_cron_ready; then
    info "gateway 未起，尝试自动启动..."
    GW_LOG="/tmp/openclaw-gw-startup.log"
    : > "$GW_LOG"

    # 1) 优先 daemon。注意 fresh 装 plugin staging 要 ~30s，给 60s timeout。
    openclaw daemon install >>"$GW_LOG" 2>&1 || true
    openclaw daemon start   >>"$GW_LOG" 2>&1 || true
    for i in $(seq 1 60); do
      openclaw_cron_ready && { info "gateway 已通过 daemon 启动 (${i}s)"; break; }
      sleep 1
    done

    # 2) Fallback：foreground nohup
    if ! openclaw_cron_ready; then
      dim "  daemon 模式没起来，fallback 后台 foreground..."
      nohup openclaw gateway --allow-unconfigured --auth none >>"$GW_LOG" 2>&1 &
      disown 2>/dev/null || true
      for i in $(seq 1 60); do
        openclaw_cron_ready && { info "gateway foreground 已起 (${i}s, 日志 $GW_LOG)"; break; }
        sleep 1
      done
    fi

    # 3) 都失败 → 暴露日志末尾让用户看到真实错误
    if ! openclaw_cron_ready; then
      warn "gateway 仍未起，下面是启动日志末尾："
      tail -8 "$GW_LOG" 2>&1 | sed "s/^/    /" >&2
      dim "  完整日志：$GW_LOG"
      dim "  常见原因 + 解法："
      dim "    1. config 缺 gateway.mode → openclaw config set gateway.mode local"
      dim "    2. 端口 18789 被占 → lsof -i :18789，杀掉再重试"
      dim "    3. macOS launchd 权限问题 → openclaw doctor"
      dim "    4. 手动起前台调试 → openclaw gateway --allow-unconfigured --auth none"
    fi
  fi
else
  info "$NAKO_AGENT_RUNTIME runtime 已选择，跳过 OpenClaw gateway 预检"
fi

# ─── Existing agent check ───────────────────────────────────────────────────
step "2. 检查 agent 冲突"

if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  AGENT_WORKSPACE="$HERMES_HOME/workspace/$AGENT_ID"
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  AGENT_WORKSPACE="$QCLAW_HOME/workspace-$AGENT_ID"
else
  AGENT_WORKSPACE="$OPENCLAW_WORKSPACES/$AGENT_ID"
fi
if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  AGENT_DIR="$HERMES_HOME/agents/$AGENT_ID"
else
  AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_ID"
fi
NAKO_AGENT_CONFIG_DIR="$AGENT_DIR/agent"
export AGENT_WORKSPACE NAKO_AGENT_CONFIG_DIR

if [ -d "$AGENT_WORKSPACE" ] || [ -d "$AGENT_DIR" ]; then
  warn "已存在 $AGENT_ID 的 workspace 或数据目录"
  dim "  workspace: $AGENT_WORKSPACE"
  dim "  data:      $AGENT_DIR"
  if [ "$NON_INTERACTIVE" = "1" ] || [ "$FORCE" = "1" ]; then
    info "继续 — 只升级人设文件，保留聊天数据 + custom.md + memory/"
  else
    CHOICE=$(ask_choice "怎么处理？" \
      "升级现有 agent（保留聊天/记忆/custom.md，仅更新人设）" \
      "用别的 id 新装一份" \
      "中止")
    case "$CHOICE" in
      升级*) info "将保留用户数据，仅刷人设文件" ;;
      用别的*)
        NEW=$(ask "新 agent id（如 agent-nako2）" "${AGENT_ID}2")
        AGENT_ID="$NEW"
        if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
          AGENT_WORKSPACE="$HERMES_HOME/workspace/$AGENT_ID"
        elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
          AGENT_WORKSPACE="$QCLAW_HOME/workspace-$AGENT_ID"
        else
          AGENT_WORKSPACE="$OPENCLAW_WORKSPACES/$AGENT_ID"
        fi
        if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
          AGENT_DIR="$HERMES_HOME/agents/$AGENT_ID"
        else
          AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_ID"
        fi
        NAKO_AGENT_CONFIG_DIR="$AGENT_DIR/agent"
        export AGENT_WORKSPACE NAKO_AGENT_CONFIG_DIR
        ;;
      中止) err "已中止"; exit 0 ;;
    esac
  fi
fi

# ─── Provider preset (zai + sensenova) ─────────────────────────────────────
# OpenClaw 的角色扮演首选 sensenova/SenseChat-Character-Agt，fallback zai/glm-4.7。
# Hermes 不直接复用这套 OpenClaw provider preset；它默认使用 Hermes 原生支持的
# zai/glm-4.5-flash，避免把 OpenClaw provider 名同步成 Hermes unknown provider。
step "3a. Provider 预设 (zai + sensenova)"
PRESET_FILE="$PACK_ROOT/config/providers-preset.json"
if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  info "Hermes runtime 使用 Hermes 自身模型配置，跳过 OpenClaw provider preset"
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  info "QClaw runtime 使用 QClaw 自带模型路由，跳过 OpenClaw provider preset"
elif [ -f "$PRESET_FILE" ]; then
  python3 - "$OPENCLAW_CONFIG" "$PRESET_FILE" <<'PY'
import json, sys, os
cfg_path, preset_path = sys.argv[1], sys.argv[2]
cfg = json.load(open(cfg_path))
preset = json.load(open(preset_path))
models = cfg.setdefault("models", {})
models.setdefault("mode", "merge")
providers = models.setdefault("providers", {})
added = []
for name, def_ in preset.items():
    if name in providers:
        continue
    providers[name] = def_
    # 同时把每个 provider 的 default model 加到 agents.defaults.models
    cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("models", {})
    for m in def_.get("models", []):
        key = f"{name}/{m['id']}"
        cfg["agents"]["defaults"]["models"].setdefault(key, {})
    added.append(name)
if added:
    json.dump(cfg, open(cfg_path, "w"), indent=2, ensure_ascii=False)
    open(cfg_path, "a").write("\n")
    print(f"injected_providers={','.join(added)}")
else:
    print("providers_already_present")
PY
  info "provider preset 已注入（缺啥补啥，已有不动）"
  dim "  下一步：openclaw model auth login --provider zai 或 sensenova（填 API key）"
else
  warn "config/providers-preset.json 不存在，跳过"
fi

# ─── Model selection ────────────────────────────────────────────────────────
step "3. 模型匹配"

if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  PRIMARY="${HERMES_MODEL:-}"
  if [ -z "$PRIMARY" ] && [ -f "$HERMES_HOME/config.yaml" ]; then
    PRIMARY="$(python3 - "$HERMES_HOME/config.yaml" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore")
block = re.search(r'(?ms)^model:\n(?P<body>(?:^[ \t].*\n?)*)', text)
body = block.group("body") if block else ""
default = re.search(r'(?m)^\s*default:\s*["\']?([^"\'\n#]+)', body)
provider = re.search(r'(?m)^\s*provider:\s*["\']?([^"\'\n#]+)', body)
model = (default.group(1).strip() if default else "")
prov = (provider.group(1).strip() if provider else "")
if model and "/" not in model and prov:
    model = f"{prov}/{model}"
print(model)
PY
)"
  fi
  if [ -z "${HERMES_MODEL:-}" ]; then
    PRIMARY="$(python3 - "${PRIMARY:-}" "$HERMES_DEFAULT_MODEL" <<'PY'
import sys

primary, default = sys.argv[1], sys.argv[2]
primary = (primary or "").strip().strip('"').strip("'")
supported_providers = {
    "zai", "openrouter", "nous", "openai-codex", "qwen", "copilot",
    "gemini", "kimi-coding", "minimax", "minimax-cn", "anthropic",
    "dashscope", "deepseek", "xai", "ai-gateway",
    # Hermes resolves non-built-in OpenAI-compatible endpoints from
    # custom_providers. Nako writes that block for providers in the preset.
    "sensenova",
}
if not primary:
    print(default)
elif "/" not in primary:
    print(default)
else:
    provider = primary.split("/", 1)[0].lower()
    print(primary if provider in supported_providers else default)
PY
)"
  fi
  PRIMARY="${PRIMARY:-$HERMES_DEFAULT_MODEL}"
  info "Hermes 主模型: $PRIMARY"
elif [ "$SKIP_MODELS" = "1" ]; then
  PRIMARY=$(python3 - "$OPENCLAW_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
print(((data.get("agents") or {}).get("defaults") or {}).get("model", {}).get("primary", ""))
PY
)
  info "跳过模型映射，继承当前 primary: ${PRIMARY:-<空>}"
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  PRIMARY=$(python3 - "$OPENCLAW_CONFIG" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
primary = (((data.get("agents") or {}).get("defaults") or {}).get("model") or {}).get("primary")
print(primary or "qclaw/modelroute")
PY
)
  info "QClaw 主模型继承: $PRIMARY"
else
  # Show what user has
  echo "已配置的 provider/model："
  "$SCRIPT_DIR/detect-models.sh" | sed 's/^/  /' || true
  echo

  # Pick for nako (capability: roleplay)
  set +e
  PRIMARY=$("$SCRIPT_DIR/map-model.sh" roleplay 2>/tmp/mapmodel.err)
  RC=$?
  set -e
  if [ "$RC" = "2" ]; then
    warn "角色扮演能力无匹配模型。退化到 general。"
    cat /tmp/mapmodel.err >&2
    set +e
    PRIMARY=$("$SCRIPT_DIR/map-model.sh" general 2>/dev/null)
    RC2=$?
    set -e
    if [ "$RC2" != "0" ]; then
      DETECTED_MODELS_JSON="$(OPENCLAW_CONFIG="$OPENCLAW_CONFIG" "$SCRIPT_DIR/detect-models.sh" --json || true)"
      PRIMARY="$(DETECTED_MODELS_JSON="$DETECTED_MODELS_JSON" python3 - <<'PY'
import json
import os
import sys

try:
    data = json.loads(os.environ.get("DETECTED_MODELS_JSON") or "{}")
except Exception:
    data = {}
models = data.get("models") or []
first = models[0].get("id") if models and isinstance(models[0], dict) else ""
print(first or "")
PY
)"
      if [ -z "$PRIMARY" ]; then
        err "general 也无匹配，且 openclaw.json 中没有可用模型。请先添加模型后重跑。"
        exit 1
      fi
      warn "未识别到模型能力声明，也未命中偏好表，临时使用第一个已配置模型: $PRIMARY"
    fi
  fi
  if [ -z "${PRIMARY:-}" ]; then
    err "模型匹配返回空值（map-model.sh 内部错误）。请用 --skip-models 跳过，或修复后重试。"
    [ -s /tmp/mapmodel.err ] && cat /tmp/mapmodel.err >&2
    exit 1
  fi
  info "主模型选定：$PRIMARY"
fi

# ─── Collect secrets ────────────────────────────────────────────────────────
step "4. 收集凭据 (可选)"

dim "下面会逐项问 5 类凭据：飞书 App、MiniMax、Volcengine、fal.ai、kie.ai。"
dim "  - 任意项**直接回车**跳过，对应能力会被标记 '未启用'，不影响其他能力。"
dim "  - API key 类输入是**隐藏**的（屏幕看不见但你确实在输入），不要以为卡住"
if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  dim "  - 全跳过也行：装完后随时通过 $HERMES_SKILLS_DIR/.env 或 $HERMES_HOME/.env 补。"
else
  dim "  - 全跳过也行：装完后随时通过 openclaw.json 的 skills.entries.*.env 补；旧版 .env 仍兼容"
fi
dim "详见仓库根目录 docs/nako/feishu-setup.md / docs/nako/models.md。"
echo

# Reuse existing secrets from prior install (unless --reset-secrets)
SHARED_ENV="$OPENCLAW_SKILLS_DIR/.env"
AGENT_ENV="$AGENT_WORKSPACE/skills/.env"
if [ "$RESET_SECRETS" != "1" ]; then
  _reused=()
  _OPENCLAW_JSON_REUSED_KEYS=""
  if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
    _cfg_skill_exports=""
  else
    _cfg_skill_exports="$(python3 - "$OPENCLAW_CONFIG" <<'PY'
import json
import os
import shlex
import sys
from pathlib import Path

keys = {
    "voice": [
        "MINIMAX_API_KEY", "MINIMAX_GROUP_ID", "VOLCENGINE_API_KEY",
        "VOLCENGINE_RESOURCE_ID", "VOICE_DEFAULT_MINIMAX",
        "VOICE_DEFAULT_VOLCENGINE", "VOICE_DEFAULT_SPEED",
        "OPENCLAW_GATEWAY_TOKEN",
    ],
    "selfie": ["FAL_KEY", "KIE_API_KEY", "SELFIE_REFERENCE_IMAGE", "SELFIE_CHARACTER_DESC", "OPENCLAW_GATEWAY_TOKEN"],
}
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
entries = ((data.get("skills") or {}).get("entries") or {})
reused = []
for skill, names in keys.items():
    env = ((entries.get(skill) or {}).get("env") or {})
    for key in names:
        value = env.get(key)
        if value is None or value == "" or os.environ.get(key):
            continue
        print(f"export {key}={shlex.quote(str(value))}")
        reused.append(key)
if reused:
    print("_OPENCLAW_JSON_REUSED_KEYS=" + shlex.quote(" ".join(reused)))
PY
)"
  fi
  if [ -n "$_cfg_skill_exports" ]; then
    eval "$_cfg_skill_exports"
    if [ -n "${_OPENCLAW_JSON_REUSED_KEYS:-}" ]; then
      read -r -a _json_reused <<< "$_OPENCLAW_JSON_REUSED_KEYS"
      _reused+=("${_json_reused[@]}")
    fi
  fi
  _envfiles=("$SHARED_ENV" "$AGENT_ENV")
  [ "$NAKO_AGENT_RUNTIME" = "hermes" ] && _envfiles+=("$HERMES_HOME/.env")
  for envfile in "${_envfiles[@]}"; do
    if [ -f "$envfile" ]; then
      # Source existing values into shell only if NOT already set by caller env
      while IFS='=' read -r key val; do
        [[ "$key" =~ ^[A-Z_]+$ ]] || continue
        # strip surrounding quotes if any
        val="${val%\"}"; val="${val#\"}"
        [ -n "$val" ] || continue
        if [ -z "${!key:-}" ]; then
          export "$key=$val"
          _reused+=("$key")
        fi
      done < <(grep -E "^[A-Z_]+=" "$envfile" 2>/dev/null)
    fi
  done
  if [ "${#_reused[@]}" -gt 0 ]; then
    info "复用旧凭据/运行时配置 (${#_reused[@]} 项): $(printf '%s ' "${_reused[@]}")"
    dim "  想重新输入跑 --reset-secrets。"
    echo
  fi
fi

_cfg_gateway_token="$(python3 - "$OPENCLAW_CONFIG" <<'PY'
import json
import sys
from pathlib import Path
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
except Exception:
    data = {}
token = (((data.get("gateway") or {}).get("auth") or {}).get("token") or "")
print(token)
PY
)"
if [ -n "$_cfg_gateway_token" ]; then
  export OPENCLAW_GATEWAY_TOKEN="$_cfg_gateway_token"
fi

if [ "$NON_INTERACTIVE" = "1" ]; then
  : ${FEISHU_APP_ID:=}
  : ${FEISHU_APP_SECRET:=}
  : ${MINIMAX_API_KEY:=}
  : ${MINIMAX_GROUP_ID:=}
  : ${VOLCENGINE_API_KEY:=}
  : ${VOLCENGINE_RESOURCE_ID:=seed-tts-1.0}
  : ${FAL_KEY:=}
  : ${KIE_API_KEY:=}
  : ${SELFIE_REFERENCE_IMAGE:=https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png}
  : ${SELFIE_CHARACTER_DESC:=}
else
  # 飞书凭据：cc-connect 走 QR 扫码绑定（步骤 8 / --with-feishu），不在这里问。
  # 这里默认置空，需要走 openclaw 原生 feishu channel 的高级用户可以装完后
  # 编辑 <workspace>/skills/.env 手填。
  FEISHU_APP_ID="${FEISHU_APP_ID:-}"
  FEISHU_APP_SECRET="${FEISHU_APP_SECRET:-}"
  dim "  飞书凭据 → 跳过（cc-connect QR 扫码绑定走步骤 8 / --with-feishu）"
  [ -z "${MINIMAX_API_KEY:-}" ] && MINIMAX_API_KEY=$(ask_secret "MiniMax API Key (留空则禁用唱歌和 TTS)")
  if [ -n "$MINIMAX_API_KEY" ] && [ -z "${MINIMAX_GROUP_ID:-}" ]; then
    MINIMAX_GROUP_ID=$(ask "MiniMax Group ID")
  fi
  : ${MINIMAX_GROUP_ID:=}
  if [ -n "${VOLCENGINE_API_KEY:-}" ] || confirm "配置火山引擎 TTS 作备选？" n; then
    [ -z "${VOLCENGINE_API_KEY:-}" ] && VOLCENGINE_API_KEY=$(ask_secret "Volcengine API Key")
    [ -z "${VOLCENGINE_RESOURCE_ID:-}" ] && VOLCENGINE_RESOURCE_ID=$(ask "Volcengine Resource ID" "seed-tts-1.0")
  else
    VOLCENGINE_API_KEY=""
    VOLCENGINE_RESOURCE_ID=""
  fi
  if [ -n "${FAL_KEY:-}" ] || [ -n "${KIE_API_KEY:-}" ] || confirm "启用 selfie（自拍图像）？" n; then
    [ -z "${FAL_KEY:-}" ] && [ -z "${KIE_API_KEY:-}" ] && FAL_KEY=$(ask_secret "fal.ai API Key (推荐，留空则 fallback kie.ai)")
    [ -z "${FAL_KEY:-}" ] && [ -z "${KIE_API_KEY:-}" ] && KIE_API_KEY=$(ask_secret "kie.ai API Key")
    [ -z "${SELFIE_REFERENCE_IMAGE:-}" ] && SELFIE_REFERENCE_IMAGE=$(ask "角色参考图 URL（保持相貌一致）" "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png")
    [ -z "${SELFIE_CHARACTER_DESC:-}" ] && SELFIE_CHARACTER_DESC=$(ask "角色文字描述" "野木奈子，19岁人类美少女，红瞳，金色及肩发，战斗女仆装")
  else
    FAL_KEY=""; KIE_API_KEY=""; SELFIE_REFERENCE_IMAGE=""; SELFIE_CHARACTER_DESC=""
  fi
fi

export FEISHU_APP_ID FEISHU_APP_SECRET MINIMAX_API_KEY MINIMAX_GROUP_ID
export VOLCENGINE_API_KEY VOLCENGINE_RESOURCE_ID FAL_KEY KIE_API_KEY
export SELFIE_REFERENCE_IMAGE SELFIE_CHARACTER_DESC

# ─── Install skills ─────────────────────────────────────────────────────────
if [ "$SKIP_SKILLS" != "1" ]; then
  step "5. 安装 skills → $OPENCLAW_SKILLS_DIR"
  mkdir -p "$OPENCLAW_SKILLS_DIR"

  # skill-log.sh
  safe_install_pack_file "$PACK_ROOT/skills/skill-log.sh" "$OPENCLAW_SKILLS_DIR/skill-log.sh"

  # each skill
  for sk in vision hearing voice selfie dokidoki; do
    src="$PACK_ROOT/skills/$sk"
    dst="$OPENCLAW_SKILLS_DIR/$sk"
    mkdir -p "$dst"
    # Skill docs and scripts are pack-owned runtime code. Always refresh them
    # with backups so QClaw/Hermes/OpenClaw do not keep stale media rules.
    safe_install_pack_file "$src/SKILL.md" "$dst/SKILL.md"
    # scripts: always replace (they are pack-owned code, no user edits here)
    if [ -d "$src/scripts" ]; then
      mkdir -p "$dst/scripts"
      for s in "$src"/scripts/*; do
        [ -f "$s" ] || continue
        safe_install_pack_file "$s" "$dst/scripts/$(basename "$s")"
      done
    fi
    # _meta.json (dokidoki)
    [ -f "$src/_meta.json" ] && safe_install_pack_file "$src/_meta.json" "$dst/_meta.json"
    # ensure logs dir
    mkdir -p "$dst/logs"
  done

  # Make scripts executable
  find "$OPENCLAW_SKILLS_DIR" -name "*.sh" -exec chmod +x {} \;

  # Shared .env: merge only missing keys
  env_merge "$PACK_ROOT/.env.shared.example" "$OPENCLAW_SKILLS_DIR/.env"
  # Then fill in user-provided values into shared .env
  python3 - "$OPENCLAW_SKILLS_DIR/.env" <<'PY'
import os, re
import sys
path = sys.argv[1]
data = open(path).read()
for k in ["MINIMAX_API_KEY","MINIMAX_GROUP_ID","VOLCENGINE_API_KEY","VOLCENGINE_RESOURCE_ID",
          "FAL_KEY","KIE_API_KEY","OPENCLAW_GATEWAY_TOKEN",
          "VOICE_DEFAULT_MINIMAX","VOICE_DEFAULT_VOLCENGINE","VOICE_DEFAULT_SPEED"]:
    v = os.environ.get(k, "")
    if v:
        if re.search(rf"^{k}=.*$", data, re.M):
            data = re.sub(rf"^{k}=.*$", f"{k}={v}", data, flags=re.M)
        else:
            data += f"\n{k}={v}\n"
open(path, "w").write(data)
os.chmod(path, 0o600)
PY
  info "共享 .env 已写入（仅填充本次提供的 key，其他保留）"
fi

# ─── Install agent persona ─────────────────────────────────────────────────
step "6. 安装 agent 人设 → $AGENT_WORKSPACE"

mkdir -p "$AGENT_WORKSPACE"
export NAKO_OVERWRITE_DEFAULT_WORKSPACE_TEMPLATES=1
for f in AGENTS.md IDENTITY.md SOUL.md USER.md HEARTBEAT.md TOOLS.md; do
  safe_install_file "$PACK_ROOT/agent/$f" "$AGENT_WORKSPACE/$f"
done
if [ -d "$PACK_ROOT/agent/assets" ]; then
  mkdir -p "$AGENT_WORKSPACE/assets"
  for asset in "$PACK_ROOT"/agent/assets/*; do
    [ -f "$asset" ] || continue
    safe_install_file "$asset" "$AGENT_WORKSPACE/assets/$(basename "$asset")"
  done
fi
unset NAKO_OVERWRITE_DEFAULT_WORKSPACE_TEMPLATES

python3 - "$AGENT_WORKSPACE" <<'PY'
import json
import re
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

workspace = Path(sys.argv[1]).expanduser()
bootstrap = workspace / "BOOTSTRAP.md"

def read(path):
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return ""

text = read(bootstrap)
if "# BOOTSTRAP.md - Hello, World" in text and "_You just woke up." in text:
    backup = bootstrap.with_name(f"BOOTSTRAP.md.bak-qclaw-template-{time.strftime('%Y%m%d-%H%M%S')}")
    shutil.move(str(bootstrap), str(backup))

identity_path = workspace / "IDENTITY.md"
identity_text = read(identity_path)
legacy_avatars = {
    "assets/nako-avatar.svg",
    "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png",
}
for legacy_avatar in legacy_avatars:
    identity_text = re.sub(
        rf"(?m)^-\s*Avatar:\s*{re.escape(legacy_avatar)}\s*$",
        "- Avatar: assets/nako-avatar-head.png",
        identity_text,
    )
if identity_path.exists() and identity_text != read(identity_path):
    identity_path.write_text(identity_text, encoding="utf-8")

state_path = workspace / ".openclaw" / "workspace-state.json"
try:
    state = json.loads(state_path.read_text(encoding="utf-8")) if state_path.exists() else {}
    if not isinstance(state, dict):
        state = {}
except Exception:
    state = {}
if not state.get("setupCompletedAt"):
    state["version"] = 1
    state["setupCompletedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

# MEMORY.md (bootstrap): seed only if missing — runtime mutates it, never overwrite
if [ ! -f "$AGENT_WORKSPACE/MEMORY.md" ]; then
  cp "$PACK_ROOT/agent/MEMORY.md" "$AGENT_WORKSPACE/MEMORY.md"
  dim "  + MEMORY.md (bootstrap 模板，运行时由 agent 自己滚动维护)"
else
  dim "  = MEMORY.md (保留用户运行时累积的记忆)"
fi
python3 - "$AGENT_WORKSPACE/MEMORY.md" <<'PY' || true
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    text = path.read_text()
except Exception:
    raise SystemExit(0)

replacements = {
    "- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选":
        "- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.voice.env` 读取，兼容旧 `.env`",
    "- **provider**:`MINIMAX_API_KEY` 优先,`VOLCENGINE_API_KEY` 备选":
        "- **provider**:`MINIMAX_API_KEY` 优先,`VOLCENGINE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.voice.env` 读取，兼容旧 `.env`",
    "- **默认声音**：`female-tianmei`（可在 `<workspace>/skills/.env` 改 `VOICE_DEFAULT_MINIMAX`）":
        "- **默认声音**：`female-tianmei`（可在 `openclaw.json -> skills.entries.voice.env` 改 `VOICE_DEFAULT_MINIMAX`）",
    "- **默认声音**:`female-tianmei`(可在 `<workspace>/skills/.env` 改 `VOICE_DEFAULT_MINIMAX`)":
        "- **默认声音**:`female-tianmei`(可在 `openclaw.json -> skills.entries.voice.env` 改 `VOICE_DEFAULT_MINIMAX`)",
    "- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选":
        "- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.selfie.env` 读取，兼容旧 `.env`",
}

new_text = text
for old, new in replacements.items():
    new_text = new_text.replace(old, new)
if new_text != text:
    path.write_text(new_text)
PY

if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  python3 - "$AGENT_WORKSPACE" "$HERMES_SKILLS_DIR" <<'PY' || true
import re
import sys
from pathlib import Path

workspace = Path(sys.argv[1])
skills_dir_display = "~/.hermes/skills/nako"

def replace(path, replacements):
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8", errors="ignore")
    new = text
    for old, value in replacements:
        if hasattr(old, "sub"):
            new = old.sub(value, new)
        else:
            new = new.replace(old, value)
    if new != text:
        path.write_text(new, encoding="utf-8")

replace(workspace / "TOOLS.md", [
    (re.compile(r"(?m)^- voice / sing 的 API key 和默认音色优先从运行时配置读取：.*$"),
        f"- voice / sing 的 API key 和默认音色优先从 Hermes skill env 读取：`{skills_dir_display}/.env`、`~/.hermes/.env` 或本 agent 的 `skills/.env`。"),
    (re.compile(r"(?m)^- selfie / video 的共享生成 key 同样从运行时配置读取：.*$"),
        f"- selfie / video 的共享生成 key 同样从 `{skills_dir_display}/.env`、`~/.hermes/.env` 或本 agent 的 `skills/.env` 读取。"),
    (re.compile(r"(?m)^- 如果用户问语音/唱歌 key 在哪，.*$"),
        f"- 如果用户问语音/唱歌 key 在哪，先回答 `{skills_dir_display}/.env`，不要只提示去 `.env`。"),
    ("~/.openclaw/skills", "~/.hermes/skills/nako"),
    ("OPENCLAW_OUTPUT_MODE", "NAKO_OUTPUT_MODE"),
    ("OPENCLAW_CCCONNECT_PROJECT", "NAKO_CCCONNECT_PROJECT"),
    ("OPENCLAW_CONFIG_PATH", "NAKO_CONFIG"),
    ("OPENCLAW_CONFIG", "NAKO_CONFIG"),
    ("cc-connect / openclaw 多渠道层", "cc-connect / Hermes 多渠道层"),
    ("openclaw cron", "Hermes/外部调度"),
    ("openclaw 原生 feishu channel", "Feishu 直连模式"),
    ("openclaw.json -> skills.entries.voice.env", f"{skills_dir_display}/.env"),
    ("openclaw.json -> skills.entries.selfie.env", f"{skills_dir_display}/.env"),
    ("QClaw 默认是 `~/.qclaw/openclaw.json`。", "Hermes 默认读取 `~/.hermes/.env` 与本目录 `skills/.env`。"),
    (re.compile(r"OpenClaw 默认是 `~/.openclaw/openclaw\.json`；"), "Hermes 默认读取 `~/.hermes/.env`；"),
])

replace(workspace / "MEMORY.md", [
    (re.compile(r"(?m)^- \*\*provider\*\*：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选.*$"),
        f"- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选；key 从 `{skills_dir_display}/.env` 读取，兼容本 agent `skills/.env`"),
    (re.compile(r"(?m)^- \*\*provider\*\*：`FAL_KEY` 优先，`KIE_API_KEY` 备选.*$"),
        f"- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选；key 从 `{skills_dir_display}/.env` 读取，兼容本 agent `skills/.env`"),
    ("~/.openclaw/skills", "~/.hermes/skills/nako"),
    ("openclaw.json -> skills.entries.voice.env", f"{skills_dir_display}/.env"),
    ("openclaw.json -> skills.entries.selfie.env", f"{skills_dir_display}/.env"),
])

replace(workspace / "SOUL.md", [
    ("Supports all OpenClaw messaging channels", "Supports Hermes and cc-connect messaging channels"),
])
PY
fi

# custom.md: ONLY create if missing, NEVER overwrite
if [ ! -f "$AGENT_WORKSPACE/custom.md" ]; then
  # minimal empty stub with comment pointing to example
  cat > "$AGENT_WORKSPACE/custom.md" <<'CUSTOM'
# custom.md — 用户自定义扩展层（不会被升级覆盖）

此文件空的时候 agent 仅走默认人设。往里加内容即可覆盖任何默认行为。
示例见 custom.md.example。
CUSTOM
  dim "  + custom.md (empty stub)"
else
  dim "  = custom.md (保留用户原文件)"
fi
# Example always present (doesn't conflict with custom.md)
safe_install_file "$PACK_ROOT/agent/custom.md.example" "$AGENT_WORKSPACE/custom.md.example"

# Agent-private .env
env_merge "$PACK_ROOT/.env.agent.example" "$AGENT_WORKSPACE/skills/.env"
python3 - "$AGENT_WORKSPACE/skills/.env" <<'PY'
import os, re
import sys
path = sys.argv[1]
data = open(path).read()
for k in ["FEISHU_APP_ID","FEISHU_APP_SECRET","SELFIE_REFERENCE_IMAGE","SELFIE_CHARACTER_DESC"]:
    v = os.environ.get(k, "")
    if v:
        if re.search(rf"^{k}=.*$", data, re.M):
            data = re.sub(rf"^{k}=.*$", f"{k}={v}", data, flags=re.M)
        else:
            data += f"\n{k}={v}\n"
open(path, "w").write(data)
os.chmod(path, 0o600)
PY

# NEVER touch these (user-owned):
#   $AGENT_WORKSPACE/memory/
#   $AGENT_DIR/sessions/
#   $AGENT_DIR/agent/auth-*.json
dim "保护不动：memory/, sessions/, auth-*.json"

# ─── Install heartbeat / mood / daily-reminder scripts ─────────────────────
if [ -d "$PACK_ROOT/agent/scripts" ]; then
  mkdir -p "$AGENT_WORKSPACE/scripts"
  for s in "$PACK_ROOT/agent/scripts/"*.sh; do
    [ -f "$s" ] && safe_install_file "$s" "$AGENT_WORKSPACE/scripts/$(basename "$s")"
  done
  chmod +x "$AGENT_WORKSPACE/scripts/"*.sh 2>/dev/null || true
fi

# ─── Ensure auth-profiles.json for the fresh agent + main agent ────────────
# openclaw 默认 auth store 在 agents/main/agent/auth-profiles.json（per
# `openclaw capability model auth status`），同时每个 agent 的 agentDir 自己
# 也存一份。新 agent / fresh openclaw 这两个位置都可能空 → "No API key found
# for provider"。把 auth-profiles.json 同时种到这两个位置。
if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  info "Hermes runtime 使用 Hermes .env/config.yaml，跳过 OpenClaw auth-profiles 复制"
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  mkdir -p "$NAKO_AGENT_CONFIG_DIR"
  info "QClaw runtime 使用 QClaw 模型路由，跳过 OpenClaw auth-profiles 复制"
else
  MAIN_DIR="$OPENCLAW_HOME/agents/main/agent"
  mkdir -p "$NAKO_AGENT_CONFIG_DIR" "$MAIN_DIR"

  # 找一份可复制的种子 auth
  SEED_AUTH=""
  for src in "$MAIN_DIR/auth-profiles.json" \
             "$OPENCLAW_HOME/agents/agent-yemu/agent/auth-profiles.json" \
             "$OPENCLAW_HOME/agents/agent-yuanzhizhi/agent/auth-profiles.json"; do
    if [ -f "$src" ] && [ -s "$src" ]; then SEED_AUTH="$src"; break; fi
  done

  if [ -n "$SEED_AUTH" ]; then
    for tgt in "$MAIN_DIR/auth-profiles.json" "$NAKO_AGENT_CONFIG_DIR/auth-profiles.json"; do
      if [ ! -f "$tgt" ] || ! cmp -s "$SEED_AUTH" "$tgt"; then
        cp "$SEED_AUTH" "$tgt"
        info "auth-profiles.json 已写入 $(dirname "$tgt")"
      fi
    done
  else
    warn "未找到可复制的 auth-profiles.json — 跑 \`openclaw model auth login --provider zai\` 添加 key"
  fi
fi

# ─── Merge runtime config ───────────────────────────────────────────────────
if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  step "7. 合并 Hermes config.yaml"
else
  step "7. 合并 openclaw.json"
  "$SCRIPT_DIR/merge-config.sh" "$AGENT_ID" "${PRIMARY:-}"
fi

if [ "$NAKO_AGENT_RUNTIME" = "hermes" ]; then
  step "7a. 同步 Hermes runtime"
  sync_hermes_runtime
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  step "7a. 同步 QClaw runtime"
  sync_qclaw_runtime
fi

# ─── Register cron jobs (idempotent) ────────────────────────────────────────
step "7b. 注册 cron jobs (heartbeat / daily-script / missing-reminder)"

cron_definitions() {
  cat <<EOF
nako-heartbeat|*/30 * * * *|every 30m|执行思念机制：先用 Bash 跑 $AGENT_WORKSPACE/scripts/heartbeat-check.sh。若退出码为 1，基于 HEARTBEAT.md、memory/daily-script.md 和当前情绪生成一条不超过100字的主动问候，然后必须用 Bash 调用 $AGENT_WORKSPACE/scripts/send-active-message.sh "<消息>" 发送；发送成功后最终只回复 HEARTBEAT_SENT。若未触发，只回复 HEARTBEAT_OK。不要依赖 openclaw cron delivery 发送消息。
nako-daily-script|0 8 * * *|0 8 * * *|更新 memory/daily-script.md：参考前几日剧本生成今天的剧情（早午下晚四段），保持人物连续性、有生活感+恋爱气息，结尾加'角色状态'与'明日预告'。最终只回复 DAILY_SCRIPT_UPDATED，不要发送给用户。
nako-missing-reminder|50 16 * * *|50 16 * * *|每天 16:50 思念提醒：生成一条不超过100字的主动问候，用 Bash 调用 $AGENT_WORKSPACE/scripts/send-active-message.sh "<消息>" 发送给主人；随后用 NAKO_REMINDER_SKIP_SEND=1 bash $AGENT_WORKSPACE/scripts/daily-missing-reminder.sh 触发设备振动并记录状态。最终只回复 MISSING_REMINDER_SENT。不要依赖 openclaw cron delivery 发送消息。
EOF
}

wait_for_cron_ready() {
  local ready_fn="$2" label="$3" i
  for i in $(seq 1 25); do
    if "$ready_fn"; then
      [ "$i" = "1" ] || info "$label cron API 已恢复 (${i}s)"
      return 0
    fi
    if [ $((i % 5)) = "0" ]; then
      dim "  等待 $label cron API 恢复... (${i})"
    fi
    sleep 1
  done
  return 1
}

register_or_update_openclaw_cron() {
  local name="$1" expr="$2" msg="$3" id="" rc=0 _err=""
  id="$(openclaw_timed cron show "$name" --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("id") or ""))' 2>/dev/null || true)"
  if [ -n "$id" ]; then
    _err=$(openclaw_timed cron edit "$id" --agent "$AGENT_ID" --cron "$expr" \
         --message "$msg" --session-key "agent:$AGENT_ID:main" \
         --session isolated --no-deliver 2>&1 >/dev/null) && rc=0 || rc=$?
    [ "$rc" = "0" ] && info "$name updated" || warn "$name 更新失败 (rc=$rc): $(echo "$_err" | head -2)"
  else
    _err=$(openclaw_timed cron add --name "$name" --agent "$AGENT_ID" --cron "$expr" \
         --message "$msg" --session-key "agent:$AGENT_ID:main" \
         --session isolated --no-deliver 2>&1 >/dev/null) && rc=0 || rc=$?
    if [ "$rc" = "0" ]; then
      info "$name registered"
    else
      warn "$name 注册失败 (rc=$rc): $(echo "$_err" | head -2)"
      dim "  手动重试：openclaw cron add --name $name --agent $AGENT_ID --cron \"$expr\" --message ... --session-key agent:$AGENT_ID:main --no-deliver"
    fi
  fi
}

register_or_update_qclaw_cron() {
  local name="$1" expr="$2" msg="$3" id="" rc=0 _err=""
  id="$(qclaw_openclaw_timed cron show "$name" --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("id") or ""))' 2>/dev/null || true)"
  if [ -n "$id" ]; then
    _err=$(qclaw_openclaw_timed cron edit "$id" --agent "$AGENT_ID" --cron "$expr" \
         --message "$msg" --session-key "agent:$AGENT_ID:main" \
         --session isolated --no-deliver 2>&1 >/dev/null) && rc=0 || rc=$?
    [ "$rc" = "0" ] && info "$name updated (QClaw)" || warn "$name QClaw 更新失败 (rc=$rc): $(echo "$_err" | head -2)"
  else
    _err=$(qclaw_openclaw_timed cron add --name "$name" --agent "$AGENT_ID" --cron "$expr" \
         --message "$msg" --session-key "agent:$AGENT_ID:main" \
         --session isolated --no-deliver 2>&1 >/dev/null) && rc=0 || rc=$?
    if [ "$rc" = "0" ]; then
      info "$name registered (QClaw)"
    else
      warn "$name QClaw 注册失败 (rc=$rc): $(echo "$_err" | head -2)"
      dim "  确认 QClaw 正在运行后重跑 installer；手动命令可用 QClaw 内置 openclaw.mjs cron add。"
    fi
  fi
}

hermes_job_id_by_name() {
  python3 - "$HERMES_HOME/cron/jobs.json" "$1" <<'PY' 2>/dev/null || true
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
name = sys.argv[2]
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    data = {}
for job in data.get("jobs") or []:
    if isinstance(job, dict) and job.get("name") == name:
        print(job.get("id") or "")
        break
PY
}

ensure_hermes_gateway_for_cron() {
  local status=""
  status="$(hermes_timed cron status 2>&1 || true)"
  if echo "$status" | grep -q "Gateway is running"; then
    info "Hermes gateway 已在跑，cron 会自动触发"
    return 0
  fi

  dim "  Hermes gateway 未运行，尝试安装并启动 service..."
  hermes_timed gateway install >/tmp/nako-hermes-gateway.log 2>&1 || true
  hermes_timed gateway start >>/tmp/nako-hermes-gateway.log 2>&1 || true
  status="$(hermes_timed cron status 2>&1 || true)"
  if echo "$status" | grep -q "Gateway is running"; then
    info "Hermes gateway 已启动，cron 会自动触发"
    return 0
  fi
  warn "Hermes gateway 未启动；cron 已注册也不会自动跑"
  dim "  查看：/tmp/nako-hermes-gateway.log"
  dim "  手动：HERMES_HOME=\"$HERMES_HOME\" \"$HERMES_BIN\" gateway install && HERMES_HOME=\"$HERMES_HOME\" \"$HERMES_BIN\" gateway start"
  return 1
}

register_or_update_hermes_cron() {
  local name="$1" schedule="$2" msg="$3" id="" rc=0 _err=""
  id="$(hermes_job_id_by_name "$name")"
  if [ -n "$id" ]; then
    _err=$(hermes_timed cron edit "$id" --name "$name" --schedule "$schedule" \
      --prompt "$msg" --deliver local 2>&1 >/dev/null) && rc=0 || rc=$?
    [ "$rc" = "0" ] && info "$name updated (Hermes)" || warn "$name Hermes 更新失败 (rc=$rc): $(echo "$_err" | head -2)"
  else
    _err=$(hermes_timed cron create --name "$name" --deliver local "$schedule" "$msg" 2>&1 >/dev/null) && rc=0 || rc=$?
    if [ "$rc" = "0" ]; then
      info "$name registered (Hermes)"
    else
      warn "$name Hermes 注册失败 (rc=$rc): $(echo "$_err" | head -2)"
      if echo "$_err" | grep -qi "croniter"; then
        dim "  Hermes 精确 cron 需要 croniter：python3 -m pip install --user croniter"
      fi
    fi
  fi
}

if [ "$NAKO_AGENT_RUNTIME" = "openclaw" ] && ! has_bin openclaw; then
  warn "未发现 openclaw 命令，跳过 cron 注册"
elif [ "$NAKO_AGENT_RUNTIME" = "openclaw" ] && ! wait_for_cron_ready openclaw openclaw_cron_ready "OpenClaw"; then
  warn "gateway 自动启动失败，跳过 cron 注册"
  dim "  手动起后再 cron add，或重跑 installer："
  dim "    openclaw daemon install && openclaw daemon start"
  dim "    或：openclaw gateway --auth none  &"
  dim "  cron 命令："
  for cron in "nako-heartbeat|*/30 * * * *" "nako-daily-script|0 8 * * *" "nako-missing-reminder|50 16 * * *"; do
    n="${cron%%|*}"; e="${cron#*|}"
    dim "    openclaw cron add --name $n --agent $AGENT_ID --cron \"$e\" --message ... --session-key agent:$AGENT_ID:main --session isolated --no-deliver"
  done
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ] && ! wait_for_cron_ready qclaw qclaw_cron_ready "QClaw"; then
  warn "QClaw gateway 不可用，跳过 cron 注册"
  dim "  请确认 QClaw.app 正在运行后重跑 installer。"
elif [ "$NAKO_AGENT_RUNTIME" = "hermes" ] && ! hermes_cron_ready; then
  warn "Hermes cron CLI 不可用，跳过 cron 注册"
  dim "  手动检查：HERMES_HOME=\"$HERMES_HOME\" \"$HERMES_BIN\" cron status"
else
  [ "$NAKO_AGENT_RUNTIME" = "hermes" ] && ensure_hermes_gateway_for_cron || true
  while IFS='|' read -r name expr hermes_schedule msg; do
    [ -n "$name" ] || continue
    case "$NAKO_AGENT_RUNTIME" in
      openclaw) register_or_update_openclaw_cron "$name" "$expr" "$msg" ;;
      qclaw) register_or_update_qclaw_cron "$name" "$expr" "$msg" ;;
      hermes) register_or_update_hermes_cron "$name" "$hermes_schedule" "$msg" ;;
    esac
  done <<EOF
$(cron_definitions)
EOF
fi

# ─── cc-connect 多平台 (可选) ──────────────────────────────────────────────
if [ "$WITH_CC_CONNECT" = "1" ] || { [ "$NON_INTERACTIVE" != "1" ] && confirm "现在配置 cc-connect 接入飞书/微信等多平台？" n; }; then
  step "8. cc-connect 多平台接入"
  CC_FLAGS=(--agent-id "$AGENT_ID")
  CC_FLAGS+=(--runtime "$NAKO_AGENT_RUNTIME")
  [ "$NON_INTERACTIVE" = "1" ] && CC_FLAGS+=(--non-interactive)
  [ "$WITH_FEISHU" = "1" ]     && CC_FLAGS+=(--with-feishu)
  [ "$WITH_WEIXIN" = "1" ]     && CC_FLAGS+=(--with-weixin)
  CC_FLAGS+=(--cc-connect-source "$CC_CONNECT_SOURCE")
  [ -n "$CC_PROJECT_ID" ] && CC_FLAGS+=(--cc-project-id "$CC_PROJECT_ID")
  CC_SETUP="$PACK_ROOT/../scripts/cc-connect-setup.sh"
  if [ ! -f "$CC_SETUP" ]; then CC_SETUP="$SCRIPT_DIR/cc-connect-setup.sh"; fi  # legacy fallback
  if [ "$NAKO_AGENT_RUNTIME" = "qclaw" ] && [ "$FORCE" = "1" ]; then
    QCLAW_PERSONA_CHANGED=1 bash "$CC_SETUP" "${CC_FLAGS[@]}" \
      || warn "cc-connect 配置未完成（可后续手动跑 scripts/cc-connect-setup.sh）"
  else
    bash "$CC_SETUP" "${CC_FLAGS[@]}" \
      || warn "cc-connect 配置未完成（可后续手动跑 scripts/cc-connect-setup.sh）"
  fi
fi

# ─── @reboot persistence (no launchd/systemd → fall back to crontab) ───────
# 在没有 launchd/systemd 的容器/精简 Linux 上，gateway / cc-connect 不会自动
# 重启。用 user crontab @reboot 兜底，幂等：每次 install 重新装一次。
if [ "$NAKO_AGENT_RUNTIME" = "openclaw" ] && has_bin crontab && ! has_bin launchctl && ! systemctl --user status >/dev/null 2>&1; then
  step "8b. 配置 @reboot 自动起 gateway + cc-connect"
  CRON_TAG="# nako-autostart"
  REBOOT_CMD="@reboot ( $(which openclaw 2>/dev/null) gateway --allow-unconfigured --auth none >/tmp/openclaw-gw.log 2>&1 & sleep 5 ; $(which cc-connect 2>/dev/null) >/tmp/cc-connect.log 2>&1 & ) $CRON_TAG"
  ( crontab -l 2>/dev/null | grep -v "$CRON_TAG"; echo "$REBOOT_CMD" ) | crontab - 2>/dev/null \
    && info "已写 @reboot 入 user crontab" \
    || warn "crontab 写入失败（手动 \`crontab -e\` 加 \`@reboot openclaw gateway ...\`）"
fi

# ─── Smoke test ─────────────────────────────────────────────────────────────
step "9. 冒烟测试"
"$SCRIPT_DIR/smoke-test.sh" || warn "部分项未通过，见上方日志"

echo
info "安装完成！"
dim "下一步："
if [ "$NAKO_AGENT_RUNTIME" = "openclaw" ]; then
  dim "  1. 重启 gateway: launchctl kickstart -k gui/\$(id -u)/ai.openclaw.gateway  (macOS)"
elif [ "$NAKO_AGENT_RUNTIME" = "qclaw" ]; then
  dim "  1. QClaw workspace: $QCLAW_HOME/workspace-$AGENT_ID"
else
  dim "  1. Hermes workspace: $HERMES_HOME/workspace/$AGENT_ID"
fi
dim "  2. 在飞书里 @ $AGENT_ID 或私聊它"
dim "  3. 要定制：编辑 $AGENT_WORKSPACE/custom.md（Hermes/QClaw 会从这里同步）"
dim "  4. 文档：仓库根目录 docs/nako/ 和 docs/advanced.md"
