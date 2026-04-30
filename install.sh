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
#   --non-interactive   : no prompts; expects env vars set already; picks defaults
#   --skip-skills       : skip skill install (persona only)
#   --skip-models       : skip model mapping (keep existing primary)
#   --cc-connect-source : auto|npm|lazycat|skip (default lazycat; CodeEagle fork)

set -euo pipefail

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

while [ $# -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    --force) FORCE=1; export FORCE; shift ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; export NON_INTERACTIVE; shift ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    --skip-models) SKIP_MODELS=1; shift ;;
    --reset-secrets) RESET_SECRETS=1; shift ;;
    --with-cc-connect) WITH_CC_CONNECT=1; shift ;;
    --with-feishu)     WITH_FEISHU=1; WITH_CC_CONNECT=1; shift ;;
    --with-weixin)     WITH_WEIXIN=1; WITH_CC_CONNECT=1; shift ;;
    --cc-connect-source) CC_CONNECT_SOURCE="$2"; WITH_CC_CONNECT=1; shift 2 ;;
    -h|--help)
      grep -E "^# " "$0" | head -20; exit 0 ;;
    *) err "Unknown flag: $1"; exit 1 ;;
  esac
done

case "$CC_CONNECT_SOURCE" in
  auto|npm|lazycat|skip) ;;
  *) err "--cc-connect-source 只支持 auto|npm|lazycat|skip"; exit 1 ;;
esac

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
  ${C_DIM}Pack: $PACK_ROOT${C_NC}

BANNER

# ─── Preflight ──────────────────────────────────────────────────────────────
step "1. 前置检查"

MISSING_HARD=()
for b in python3 jq curl; do
  if has_bin "$b"; then info "$b"; else err "$b"; MISSING_HARD+=("$b"); fi
done

if [ ! -d "$OPENCLAW_HOME" ]; then
  err "~/.openclaw 不存在 — 请先安装 openclaw (npm i -g openclaw)"
  exit 1
fi
info "openclaw 目录 $OPENCLAW_HOME"

[ ! -f "$OPENCLAW_CONFIG" ] && { err "openclaw.json 不存在"; exit 1; }
info "openclaw.json"

if [ "${#MISSING_HARD[@]}" -gt 0 ]; then
  err "请先装这些依赖：${MISSING_HARD[*]}"
  dim "macOS:  brew install ${MISSING_HARD[*]}"
  dim "Debian: sudo apt-get install ${MISSING_HARD[*]}"
  exit 1
fi

# Optional bins (not fatal)
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
          brew install openai-whisper ffmpeg
        elif [ "$OS" = "Linux" ]; then
          if command -v apt-get >/dev/null; then sudo apt-get install -y ffmpeg libavcodec-extra python3-pip; fi
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

# ─── Existing agent check ───────────────────────────────────────────────────
step "2. 检查 agent 冲突"

AGENT_WORKSPACE="$OPENCLAW_WORKSPACES/$AGENT_ID"
AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_ID"

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
        AGENT_WORKSPACE="$OPENCLAW_WORKSPACES/$AGENT_ID"
        AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_ID"
        ;;
      中止) err "已中止"; exit 0 ;;
    esac
  fi
fi

# ─── Provider preset (zai + sensenova) ─────────────────────────────────────
# nako 的角色扮演首选 sensenova/SenseChat-Character-Agt，fallback zai/glm-4.7。
# 这俩都不是 openclaw 内置 provider，得通过 openclaw.json 顶层 .models.providers
# 注册成 openai-compatible provider。
step "3a. Provider 预设 (zai + sensenova)"
PRESET_FILE="$PACK_ROOT/config/providers-preset.json"
if [ -f "$PRESET_FILE" ]; then
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

if [ "$SKIP_MODELS" = "1" ]; then
  PRIMARY=$(python3 -c 'import json,os; d=json.load(open(os.path.expanduser("~/.openclaw/openclaw.json"))); print(d.get("agents",{}).get("defaults",{}).get("model",{}).get("primary",""))')
  info "跳过模型映射，继承当前 primary: ${PRIMARY:-<空>}"
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
      err "general 也无匹配。请在 openclaw.json 添加模型后重跑。"
      exit 1
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
dim "  - 全跳过也行：装完后随时通过 openclaw.json 的 skills.entries.*.env 补；旧版 .env 仍兼容"
dim "详见仓库根目录 docs/nako/feishu-setup.md / docs/nako/models.md。"
echo

# Reuse existing secrets from prior install (unless --reset-secrets)
SHARED_ENV="$OPENCLAW_SKILLS_DIR/.env"
AGENT_ENV="$AGENT_WORKSPACE/skills/.env"
if [ "$RESET_SECRETS" != "1" ]; then
  _reused=()
  _OPENCLAW_JSON_REUSED_KEYS=""
  _cfg_skill_exports="$(python3 - <<'PY'
import json
import os
import shlex
from pathlib import Path

keys = {
    "voice": [
        "MINIMAX_API_KEY", "MINIMAX_GROUP_ID", "VOLCENGINE_API_KEY",
        "VOLCENGINE_RESOURCE_ID", "VOICE_DEFAULT_MINIMAX",
        "VOICE_DEFAULT_VOLCENGINE", "VOICE_DEFAULT_SPEED",
        "OPENCLAW_GATEWAY_TOKEN",
    ],
    "selfie": ["FAL_KEY", "KIE_API_KEY", "OPENCLAW_GATEWAY_TOKEN"],
}
try:
    data = json.loads(Path(os.path.expanduser("~/.openclaw/openclaw.json")).read_text())
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
  if [ -n "$_cfg_skill_exports" ]; then
    eval "$_cfg_skill_exports"
    if [ -n "${_OPENCLAW_JSON_REUSED_KEYS:-}" ]; then
      read -r -a _json_reused <<< "$_OPENCLAW_JSON_REUSED_KEYS"
      _reused+=("${_json_reused[@]}")
    fi
  fi
  for envfile in "$SHARED_ENV" "$AGENT_ENV"; do
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
    info "复用旧凭据/openclaw.json 配置 (${#_reused[@]} 项): $(printf '%s ' "${_reused[@]}")"
    dim "  想重新输入跑 --reset-secrets。"
    echo
  fi
fi

_cfg_gateway_token="$(python3 - <<'PY'
import json, os
try:
    data = json.load(open(os.path.expanduser("~/.openclaw/openclaw.json")))
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
  safe_install_file "$PACK_ROOT/skills/skill-log.sh" "$OPENCLAW_SKILLS_DIR/skill-log.sh"

  # each skill
  for sk in vision hearing voice selfie dokidoki; do
    src="$PACK_ROOT/skills/$sk"
    dst="$OPENCLAW_SKILLS_DIR/$sk"
    mkdir -p "$dst"
    # SKILL.md always (forced if --force)
    safe_install_file "$src/SKILL.md" "$dst/SKILL.md"
    # scripts: always replace (they are pack-owned code, no user edits here)
    if [ -d "$src/scripts" ]; then
      mkdir -p "$dst/scripts"
      for s in "$src"/scripts/*; do
        [ -f "$s" ] || continue
        safe_install_file "$s" "$dst/scripts/$(basename "$s")"
      done
    fi
    # _meta.json (dokidoki)
    [ -f "$src/_meta.json" ] && safe_install_file "$src/_meta.json" "$dst/_meta.json"
    # ensure logs dir
    mkdir -p "$dst/logs"
  done

  # Make scripts executable
  find "$OPENCLAW_SKILLS_DIR" -name "*.sh" -exec chmod +x {} \;

  # Shared .env: merge only missing keys
  env_merge "$PACK_ROOT/.env.shared.example" "$OPENCLAW_SKILLS_DIR/.env"
  # Then fill in user-provided values into shared .env
  python3 - <<PY
import os, re
path = os.path.expanduser("~/.openclaw/skills/.env")
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
for f in AGENTS.md IDENTITY.md SOUL.md USER.md HEARTBEAT.md TOOLS.md; do
  safe_install_file "$PACK_ROOT/agent/$f" "$AGENT_WORKSPACE/$f"
done

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
python3 - <<PY
import os, re
path = os.path.expanduser(f"~/.openclaw/workspace/$AGENT_ID/skills/.env")
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
MAIN_DIR="$OPENCLAW_HOME/agents/main/agent"
mkdir -p "$AGENT_DIR" "$MAIN_DIR"

# 找一份可复制的种子 auth
SEED_AUTH=""
for src in "$MAIN_DIR/auth-profiles.json" \
           "$OPENCLAW_HOME/agents/agent-yemu/agent/auth-profiles.json" \
           "$OPENCLAW_HOME/agents/agent-yuanzhizhi/agent/auth-profiles.json"; do
  if [ -f "$src" ] && [ -s "$src" ]; then SEED_AUTH="$src"; break; fi
done

if [ -n "$SEED_AUTH" ]; then
  for tgt in "$MAIN_DIR/auth-profiles.json" "$AGENT_DIR/auth-profiles.json"; do
    if [ ! -f "$tgt" ] || ! cmp -s "$SEED_AUTH" "$tgt"; then
      cp "$SEED_AUTH" "$tgt"
      info "auth-profiles.json 已写入 $(dirname "$tgt")"
    fi
  done
else
  warn "未找到可复制的 auth-profiles.json — 跑 \`openclaw model auth login --provider zai\` 添加 key"
fi

# ─── Merge openclaw.json ────────────────────────────────────────────────────
step "7. 合并 openclaw.json"
"$SCRIPT_DIR/merge-config.sh" "$AGENT_ID" "${PRIMARY:-}"

# ─── Register cron jobs (idempotent) ────────────────────────────────────────
step "7b. 注册 cron jobs (heartbeat / daily-script / missing-reminder)"

gateway_up=0
if has_bin openclaw; then
  for i in $(seq 1 25); do
    if openclaw_cron_ready; then
      gateway_up=1
      [ "$i" = "1" ] || info "gateway cron API 已恢复 (${i}s)"
      break
    fi
    if [ $((i % 5)) = "0" ]; then
      dim "  等待 gateway cron API 恢复... (${i})"
    fi
    sleep 1
  done
fi

if [ "$gateway_up" = "0" ]; then
  warn "gateway 自动启动失败，跳过 cron 注册"
  dim "  手动起后再 cron add，或重跑 installer："
  dim "    openclaw daemon install && openclaw daemon start"
  dim "    或：openclaw gateway --auth none  &"
  dim "  cron 命令："
  for cron in "nako-heartbeat|*/30 * * * *" "nako-daily-script|0 8 * * *" "nako-missing-reminder|50 16 * * *"; do
    n="${cron%%|*}"; e="${cron#*|}"
    dim "    openclaw cron add --name $n --agent $AGENT_ID --cron \"$e\" --message ... --session-key agent:$AGENT_ID:main --session isolated --no-deliver"
  done
elif has_bin openclaw; then
  register_or_update_cron() {
    local name="$1" expr="$2" msg="$3" id="" rc=0 _err=""
    id="$(openclaw_timed cron show "$name" --json 2>/dev/null | python3 -c 'import json,sys; print((json.load(sys.stdin).get("id") or ""))' 2>/dev/null || true)"
    if [ -n "$id" ]; then
      _err=$(openclaw_timed cron edit "$id" --agent "$AGENT_ID" --cron "$expr" \
           --message "$msg" --session-key "agent:$AGENT_ID:main" \
           --session isolated --no-deliver 2>&1 >/dev/null) && rc=0 || rc=$?
      if [ "$rc" = "0" ]; then
        info "$name updated"
      else
        warn "$name 更新失败 (rc=$rc): $(echo "$_err" | head -2)"
      fi
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

  for line in \
      "nako-heartbeat|*/30 * * * *|执行思念机制：先用 Bash 跑 $AGENT_WORKSPACE/scripts/heartbeat-check.sh。若退出码为 1，基于 HEARTBEAT.md、memory/daily-script.md 和当前情绪生成一条不超过100字的主动问候，然后必须用 Bash 调用 $AGENT_WORKSPACE/scripts/send-active-message.sh \"<消息>\" 发送；发送成功后最终只回复 HEARTBEAT_SENT。若未触发，只回复 HEARTBEAT_OK。不要依赖 openclaw cron delivery 发送消息。" \
      "nako-daily-script|0 8 * * *|更新 memory/daily-script.md：参考前几日剧本生成今天的剧情（早午下晚四段），保持人物连续性、有生活感+恋爱气息，结尾加'角色状态'与'明日预告'。最终只回复 DAILY_SCRIPT_UPDATED，不要发送给用户。" \
      "nako-missing-reminder|50 16 * * *|每天 16:50 思念提醒：生成一条不超过100字的主动问候，用 Bash 调用 $AGENT_WORKSPACE/scripts/send-active-message.sh \"<消息>\" 发送给主人；随后用 NAKO_REMINDER_SKIP_SEND=1 bash $AGENT_WORKSPACE/scripts/daily-missing-reminder.sh 触发设备振动并记录状态。最终只回复 MISSING_REMINDER_SENT。不要依赖 openclaw cron delivery 发送消息。"; do
    name="${line%%|*}"; rest="${line#*|}"
    expr="${rest%%|*}";  msg="${rest#*|}"
    register_or_update_cron "$name" "$expr" "$msg"
  done
else
  warn "未发现 openclaw 命令，跳过 cron 注册"
fi

# ─── cc-connect 多平台 (可选) ──────────────────────────────────────────────
if [ "$WITH_CC_CONNECT" = "1" ] || { [ "$NON_INTERACTIVE" != "1" ] && confirm "现在配置 cc-connect 接入飞书/微信等多平台？" n; }; then
  step "8. cc-connect 多平台接入"
  CC_FLAGS=(--agent-id "$AGENT_ID")
  [ "$NON_INTERACTIVE" = "1" ] && CC_FLAGS+=(--non-interactive)
  [ "$WITH_FEISHU" = "1" ]     && CC_FLAGS+=(--with-feishu)
  [ "$WITH_WEIXIN" = "1" ]     && CC_FLAGS+=(--with-weixin)
  CC_FLAGS+=(--cc-connect-source "$CC_CONNECT_SOURCE")
  CC_SETUP="$PACK_ROOT/../scripts/cc-connect-setup.sh"
  if [ ! -f "$CC_SETUP" ]; then CC_SETUP="$SCRIPT_DIR/cc-connect-setup.sh"; fi  # legacy fallback
  bash "$CC_SETUP" "${CC_FLAGS[@]}" || warn "cc-connect 配置未完成（可后续手动跑 scripts/cc-connect-setup.sh）"
fi

# ─── @reboot persistence (no launchd/systemd → fall back to crontab) ───────
# 在没有 launchd/systemd 的容器/精简 Linux 上，gateway / cc-connect 不会自动
# 重启。用 user crontab @reboot 兜底，幂等：每次 install 重新装一次。
if has_bin crontab && ! has_bin launchctl && ! systemctl --user status >/dev/null 2>&1; then
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
dim "  1. 重启 gateway: launchctl kickstart -k gui/\$(id -u)/ai.openclaw.gateway  (macOS)"
dim "  2. 在飞书里 @ $AGENT_ID 或私聊它"
dim "  3. 要定制：编辑 $AGENT_WORKSPACE/custom.md（升级不会动它）"
dim "  4. 文档：仓库根目录 docs/nako/ 和 docs/advanced.md"
