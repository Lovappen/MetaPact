#!/bin/bash
# cc-connect-setup.sh — 把 agent 接到 cc-connect 多平台 host
#
# 这个脚本与具体 agent 无关，可独立使用：
#   1. 装/复用 cc-connect
#   2. 在 ~/.cc-connect/config.toml idempotent 写入指向
#      OpenClaw / Hermes / QClaw ACP 的 project
#   3. 引导 QR-onboarding 飞书/微信等平台
#
# Usage:
#   bash scripts/cc-connect-setup.sh [options]
#
# Flags:
#   --agent-id <id>      agent id (默认 agent-nako)
#   --runtime <name>     openclaw|hermes|qclaw (默认 openclaw)
#   --display-name <n>   cc-connect 内显示名 (默认按 runtime 生成)
#   --with-feishu        自动跑 feishu QR 引导（若未配 feishu）
#   --with-weixin        自动跑 weixin QR 引导（若未配 weixin）
#   --cc-connect-source  auto|npm|lazycat|skip (默认 lazycat；CodeEagle fork)
#   --uninstall          移除当前 agent 的 cc-connect project 与 session
#   --purge-cc-connect   配合 --uninstall，额外卸载 daemon 并移除 cc-connect 二进制
#   --uninstall-all      停止并完整移除 cc-connect，并移除当前 agent 的 runtime 数据
#   --non-interactive    不询问，缺什么就跳过

set -euo pipefail

# ─── PATH augment for SSH 默认 shell（brew/nvm bin 不一定 inherits） ────────
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"
[ -d /usr/local/bin    ] && export PATH="/usr/local/bin:$PATH"
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_LATEST=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | sort -V | tail -1 || true)
  [ -n "${NVM_LATEST:-}" ] && [ -d "$HOME/.nvm/versions/node/$NVM_LATEST/bin" ] && \
    export PATH="$HOME/.nvm/versions/node/$NVM_LATEST/bin:$PATH"
fi

# ─── Self-contained logging / prompt helpers ────────────────────────────────
if [ -t 1 ]; then
  C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'
  C_CYAN='\033[0;36m'; C_BOLD='\033[1m'; C_DIM='\033[2m'; C_NC='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_NC=''
fi
info(){ echo -e "${C_GREEN}[✓]${C_NC} $*"; }
warn(){ echo -e "${C_YELLOW}[!]${C_NC} $*"; }
err(){  echo -e "${C_RED}[✗]${C_NC} $*" >&2; }
step(){ echo -e "\n${C_BOLD}${C_CYAN}▸ $*${C_NC}"; }
dim(){  echo -e "${C_DIM}$*${C_NC}"; }
has_bin(){ command -v "$1" >/dev/null 2>&1; }
os_name_lc(){ uname -s | tr '[:upper:]' '[:lower:]'; }
is_windows_shell(){
  case "$(os_name_lc)" in
    mingw*|msys*|cygwin*) return 0 ;;
    *) return 1 ;;
  esac
}
cc_connect_exe_suffix(){
  if is_windows_shell; then
    printf '.exe'
  fi
  return 0
}
confirm(){
  local q="$1" def="${2:-n}" reply hint="[y/N]"
  [ "$def" = "y" ] && hint="[Y/n]"
  echo -en "${C_CYAN}?${C_NC} $q $hint: "
  if [ "${NAKO_CONFIRM_STDIN:-0}" = "1" ]; then
    read -r reply || reply=""
  elif { : </dev/tty; } 2>/dev/null; then
    read -r reply </dev/tty || reply=""
  else
    read -r reply || reply=""
  fi
  reply="${reply:-$def}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

WITH_FEISHU=0
WITH_WEIXIN=0
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"
CC_CONNECT_LAZYCAT_REPO="${CC_CONNECT_LAZYCAT_REPO:-https://github.com/CodeEagle/cc-connect.git}"
CC_CONNECT_LAZYCAT_VERSION="${CC_CONNECT_LAZYCAT_VERSION:-v1.3.3}"
CC_CONNECT_LAZYCAT_REF="${CC_CONNECT_LAZYCAT_REF:-lazycat/v1.3.3}"
CC_CONNECT_LAZYCAT_RELEASE_BASE="${CC_CONNECT_LAZYCAT_RELEASE_BASE:-https://github.com/CodeEagle/cc-connect/releases/download/$CC_CONNECT_LAZYCAT_VERSION}"
CC_CONNECT_GO_MIN_VERSION="${CC_CONNECT_GO_MIN_VERSION:-1.25.0}"
CC_CONNECT_GO_DOWNLOAD_VERSION="${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}"
AGENT_ID="agent-nako"
RUNTIME="${NAKO_AGENT_RUNTIME:-openclaw}"
DISPLAY_NAME=""
CC_CONNECT_CHANGED=0
GO_FOR_CC_CONNECT=""
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_BIN="${HERMES_BIN:-}"
QCLAW_HOME="${QCLAW_HOME:-$HOME/.qclaw}"
QCLAW_BASE_HOME="$QCLAW_HOME"
QCLAW_OPENCLAW_CONFIG="${QCLAW_OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-}}"
QCLAW_NODE_BIN="${QCLAW_NODE_BIN:-}"
QCLAW_OPENCLAW_MJS="${QCLAW_OPENCLAW_MJS:-}"
QCLAW_CC_SESSION_SUFFIX="${QCLAW_CC_SESSION_SUFFIX:-session-cc-connect}"
QCLAW_CC_SESSION_LABEL="${QCLAW_CC_SESSION_LABEL:-cc-connect 飞书/微信}"
QCLAW_PERSONA_CHANGED="${QCLAW_PERSONA_CHANGED:-0}"
UNINSTALL=0
PURGE_CC_CONNECT=0
UNINSTALL_ALL=0

CC_SETUP_SCRIPT="${BASH_SOURCE[0]:-$0}"
if [ -f "$CC_SETUP_SCRIPT" ]; then
  CC_SETUP_SCRIPT_DIR="$(cd "$(dirname "$CC_SETUP_SCRIPT")" && pwd)"
  CC_SETUP_REPO_ROOT="$(cd "$CC_SETUP_SCRIPT_DIR/.." && pwd)"
else
  CC_SETUP_REPO_ROOT=""
fi
NAKO_AGENT_SOURCE_DIR="${NAKO_AGENT_SOURCE_DIR:-${CC_SETUP_REPO_ROOT:+$CC_SETUP_REPO_ROOT/nako/agent}}"

while [ $# -gt 0 ]; do
  case "$1" in
    --with-feishu) WITH_FEISHU=1; shift ;;
    --with-weixin) WITH_WEIXIN=1; shift ;;
    --cc-connect-source) CC_CONNECT_SOURCE="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --runtime|--backend) RUNTIME="$2"; shift 2 ;;
    --display-name) DISPLAY_NAME="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --purge-cc-connect) PURGE_CC_CONNECT=1; shift ;;
    --uninstall-all) UNINSTALL_ALL=1; shift ;;
    -h|--help)
      cat <<'HELP'
cc-connect-setup.sh — 把 agent 接到 cc-connect 多平台 host

Usage:
  curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/cc-connect-setup.sh | bash
  curl -fsSL ... | bash -s -- --agent-id agent-foo --with-feishu --with-weixin
  bash scripts/cc-connect-setup.sh [options]

Flags:
  --agent-id <id>      agent id (默认 agent-nako)
  --runtime <name>     openclaw|hermes|qclaw (默认 openclaw)
  --display-name <n>   cc-connect 内显示名 (默认按 runtime 生成)
  --with-feishu        自动跑 feishu QR 引导（若未配 feishu）
  --with-weixin        自动跑 weixin QR 引导（若未配 weixin）
  --cc-connect-source  auto|npm|lazycat|skip (默认 lazycat；CodeEagle fork)
  --uninstall          移除当前 agent 的 cc-connect project 与 session
  --purge-cc-connect   配合 --uninstall，额外卸载 daemon 并移除 cc-connect 二进制
  --uninstall-all      停止并完整移除 cc-connect，并移除当前 agent 的 runtime 数据
  --non-interactive    不询问，缺什么就跳过
  -h, --help           本帮助
HELP
      exit 0 ;;
    *) err "Unknown flag: $1"; exit 1 ;;
  esac
done

case "$CC_CONNECT_SOURCE" in
  auto|npm|lazycat|skip) ;;
  *) err "--cc-connect-source 只支持 auto|npm|lazycat|skip"; exit 1 ;;
esac

case "$RUNTIME" in
  openclaw|hermes|qclaw) ;;
  *) err "--runtime 只支持 openclaw|hermes|qclaw"; exit 1 ;;
esac

if [ -z "$DISPLAY_NAME" ]; then
  if [ "$RUNTIME" = "hermes" ]; then
    DISPLAY_NAME="Hermes $AGENT_ID"
  elif [ "$RUNTIME" = "qclaw" ]; then
    DISPLAY_NAME="QClaw $AGENT_ID"
  else
    DISPLAY_NAME="OpenClaw $AGENT_ID"
  fi
fi

CC_CONFIG="$HOME/.cc-connect/config.toml"
WORKSPACE="$HOME/.openclaw/workspace/$AGENT_ID"
HERMES_WORKSPACE="$HERMES_HOME/workspace/$AGENT_ID"
QCLAW_WORKSPACE="$QCLAW_HOME/workspace-$AGENT_ID"

expand_path() {
  python3 - "$1" <<'PY'
import os
import sys
from pathlib import Path

print(str(Path(os.path.expanduser(sys.argv[1])).resolve()))
PY
}

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

resolve_hermes_bin() {
  if [ -n "$HERMES_BIN" ]; then
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

qclaw_json_file_value() {
  local path="$1" key="$2"
  python3 - "$path" "$key" <<'PY' 2>/dev/null || true
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

qclaw_json_value() {
  local key="$1" value
  value="$(qclaw_json_file_value "$QCLAW_HOME/qclaw.json" "$key")"
  if [ -z "$value" ] && [ "$QCLAW_BASE_HOME" != "$QCLAW_HOME" ]; then
    value="$(qclaw_json_file_value "$QCLAW_BASE_HOME/qclaw.json" "$key")"
  fi
  printf '%s\n' "$value"
}

resolve_qclaw_layout() {
  local state_dir config_path state_config_path base_config
  QCLAW_BASE_HOME="$(expand_path "$QCLAW_HOME")"
  QCLAW_HOME="$QCLAW_BASE_HOME"
  base_config="$QCLAW_BASE_HOME/qclaw.json"

  state_dir="$(qclaw_json_file_value "$base_config" stateDir)"
  if [ -n "$state_dir" ]; then
    QCLAW_HOME="$(expand_path "$state_dir")"
  fi

  if [ -n "$QCLAW_OPENCLAW_CONFIG" ]; then
    QCLAW_OPENCLAW_CONFIG="$(expand_path "$QCLAW_OPENCLAW_CONFIG")"
  else
    state_config_path="$(qclaw_json_file_value "$QCLAW_HOME/qclaw.json" configPath)"
    config_path="${state_config_path:-$(qclaw_json_file_value "$base_config" configPath)}"
    if [ -n "$config_path" ]; then
      QCLAW_OPENCLAW_CONFIG="$(expand_path "$config_path")"
    else
      QCLAW_OPENCLAW_CONFIG="$QCLAW_HOME/openclaw.json"
    fi
  fi

  QCLAW_WORKSPACE="$QCLAW_HOME/workspace-$AGENT_ID"
}

if [ "$RUNTIME" = "qclaw" ]; then
  resolve_qclaw_layout
fi

resolve_qclaw_node_bin() {
  if [ -n "$QCLAW_NODE_BIN" ]; then
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

resolve_qclaw_openclaw_mjs() {
  if [ -n "$QCLAW_OPENCLAW_MJS" ]; then
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

ensure_qclaw_cc_session() {
  python3 - "$QCLAW_HOME" "$AGENT_ID" "$QCLAW_WORKSPACE" "$QCLAW_CC_SESSION_SUFFIX" "$QCLAW_CC_SESSION_LABEL" "${QCLAW_PERSONA_CHANGED:-0}" <<'PY'
import json
import re
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

qclaw_home, agent_id, workspace, suffix, label, force_reset = sys.argv[1:]
session_dir = Path(qclaw_home).expanduser() / "agents" / agent_id / "sessions"
session_dir.mkdir(parents=True, exist_ok=True)
sessions_file = session_dir / "sessions.json"
try:
    sessions = json.loads(sessions_file.read_text(encoding="utf-8")) if sessions_file.exists() else {}
    if not isinstance(sessions, dict):
        sessions = {}
except Exception:
    sessions = {}

key = f"agent:{agent_id}:{suffix}"
now_ms = int(time.time() * 1000)

entry = sessions.get(key)
if not isinstance(entry, dict):
    entry = {}

def session_looks_bootstrapped(path_value):
    if not isinstance(path_value, str) or not path_value:
        return False
    path = Path(path_value).expanduser()
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return False
    markers = [
        "# BOOTSTRAP.md - Hello, World",
        "# IDENTITY.md - Who Am I?",
        "# SOUL.md - Who You Are",
        "BOOTSTRAP.md says I have no name yet",
        "BOOTSTRAP.md file in the workspace",
        "我还没有名字",
    ]
    return any(marker in text for marker in markers)

reset_existing = bool(entry) and (
    force_reset == "1" or session_looks_bootstrapped(entry.get("sessionFile"))
)
if reset_existing:
    old_session_file = entry.get("sessionFile")
    if isinstance(old_session_file, str) and old_session_file:
        old_path = Path(old_session_file).expanduser()
        if old_path.exists():
            backup = old_path.with_name(f"{old_path.name}.bak-cc-connect-stale-{time.strftime('%Y%m%d-%H%M%S')}")
            shutil.move(str(old_path), str(backup))
    entry = {}

for other_key, other_entry in list(sessions.items()):
    if other_key == key or not other_key.startswith(f"agent:{agent_id}:"):
        continue
    if not isinstance(other_entry, dict):
        continue
    origin = other_entry.get("origin") if isinstance(other_entry.get("origin"), dict) else {}
    delivery = other_entry.get("deliveryContext") if isinstance(other_entry.get("deliveryContext"), dict) else {}
    stale_cc = (
        other_entry.get("label") in ("ACP", "cc-connect", label)
        or origin.get("provider") == "acp"
        or origin.get("surface") == "cc-connect"
        or delivery.get("channel") == "cc-connect"
        or other_entry.get("lastChannel") == "cc-connect"
    )
    if stale_cc:
        sessions.pop(other_key, None)

session_id = str(entry.get("sessionId") or uuid4())
session_file = entry.get("sessionFile")
if not isinstance(session_file, str) or not session_file:
    session_file = str(session_dir / f"{session_id}.jsonl")
try:
    updated_at = int(entry.get("updatedAt") or now_ms)
except Exception:
    updated_at = now_ms

entry.update({
    "sessionId": session_id,
    "updatedAt": updated_at,
    "label": label,
    "systemSent": bool(entry.get("systemSent", False)),
    "abortedLastRun": bool(entry.get("abortedLastRun", False)),
    "chatType": entry.get("chatType") or "direct",
    "deliveryContext": {"channel": "webchat"},
    "lastChannel": "webchat",
    "origin": {
        "label": label,
        "provider": "webchat",
        "surface": "webchat",
        "chatType": "direct",
    },
    "sessionFile": session_file,
})
sessions[key] = entry

path = Path(session_file).expanduser()
path.parent.mkdir(parents=True, exist_ok=True)
if not path.exists():
    header = {
        "type": "session",
        "version": 3,
        "id": session_id,
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "cwd": str(Path(workspace).expanduser()),
    }
    path.write_text(json.dumps(header, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

if force_reset == "1":
    referenced = set()
    for value in sessions.values():
        if not isinstance(value, dict):
            continue
        file_value = value.get("sessionFile")
        if isinstance(file_value, str) and file_value:
            referenced.add(Path(file_value).expanduser().resolve())
    current = path.resolve()
    stamp = time.strftime('%Y%m%d-%H%M%S')
    for stale in session_dir.glob("*.jsonl"):
        stale_resolved = stale.resolve()
        if stale_resolved == current or stale_resolved in referenced:
            continue
        backup = stale.with_name(f"{stale.name}.bak-cc-connect-stale-{stamp}")
        shutil.move(str(stale), str(backup))

serialized = json.dumps(sessions, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
old = sessions_file.read_text(encoding="utf-8") if sessions_file.exists() else ""
if old != serialized:
    if sessions_file.exists():
        backup = sessions_file.with_name(f"sessions.json.bak-cc-connect-{time.strftime('%Y%m%d-%H%M%S')}")
        backup.write_text(old, encoding="utf-8")
    sessions_file.write_text(serialized, encoding="utf-8")
print("reset" if reset_existing else "ok")
PY
}

ensure_qclaw_nako_persona() {
  [ -n "${NAKO_AGENT_SOURCE_DIR:-}" ] || return 0
  [ -d "$NAKO_AGENT_SOURCE_DIR" ] || return 0
  if [ "${NAKO_CC_CONNECT_SEED_PERSONA:-0}" != "1" ]; then
    case "$AGENT_ID" in
      agent-nako*) ;;
      *) return 0 ;;
    esac
  fi

  local result
  result="$(python3 - "$NAKO_AGENT_SOURCE_DIR" "$QCLAW_WORKSPACE" <<'PY'
import json
import re
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

source_dir, workspace = map(lambda p: Path(p).expanduser(), sys.argv[1:])
files = ["AGENTS.md", "IDENTITY.md", "SOUL.md", "USER.md", "HEARTBEAT.md", "TOOLS.md"]
bootstrap_markers = [
    "# BOOTSTRAP.md - Hello, World",
    "_You just woke up.",
]

def read(path):
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return ""

def looks_like_qclaw_template(path, name):
    text = read(path)
    if name == "AGENTS.md":
        return "# AGENTS.md - Your Workspace" in text and "@custom.md" not in text
    markers = {
        "IDENTITY.md": "# IDENTITY.md - Who Am I?",
        "SOUL.md": "# SOUL.md - Who You Are",
        "USER.md": "# USER.md - About Your Human",
        "HEARTBEAT.md": "# HEARTBEAT.md Template",
        "TOOLS.md": ("# TOOLS.md - Local Notes", "# TOOLS.md - 本地工具速查"),
    }
    marker = markers.get(name)
    if isinstance(marker, tuple):
        return any(item in text for item in marker)
    return bool(marker and marker in text)

def looks_like_qclaw_bootstrap(path):
    text = read(path)
    return all(marker in text for marker in bootstrap_markers)

def ensure_qclaw_identity_sync_fields(path):
    if not path.exists():
        return False
    text = read(path)
    updated = text
    legacy_avatars = {
        "assets/nako-avatar.svg",
        "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png",
    }
    for legacy_avatar in legacy_avatars:
        updated = re.sub(
            rf"(?m)^-\s*Avatar:\s*{re.escape(legacy_avatar)}\s*$",
            "- Avatar: assets/nako-avatar-head.png",
            updated,
        )
    seen = set()
    for line in updated.splitlines():
        match = re.match(r"^-?\s*(\w+)\s*:\s*(.+)$", line.strip())
        if match:
            seen.add(match.group(1).lower())
    fields = [
        ("Name", "野木奈子"),
        ("Emoji", "🎀"),
        ("Vibe", "核战后赛博世界专属战斗女仆"),
        ("Avatar", "assets/nako-avatar-head.png"),
    ]
    missing = [(key, value) for key, value in fields if key.lower() not in seen]
    if not missing:
        if updated != text:
            path.write_text(updated, encoding="utf-8")
            return True
        return False
    block = ["", "<!-- QClaw sync fields: keep these plain English keys parseable. -->"]
    block.extend(f"- {key}: {value}" for key, value in missing)
    path.write_text(updated.rstrip() + "\n" + "\n".join(block) + "\n", encoding="utf-8")
    return True

def insert_after_anchor(path, anchor_prefix, marker, rule):
    if not path.exists():
        return False
    text = read(path)
    if marker in text:
        return False
    lines = text.splitlines()
    insert_at = None
    for idx, line in enumerate(lines):
        if line.startswith(anchor_prefix):
            insert_at = idx + 1
            while insert_at < len(lines) and lines[insert_at].strip():
                insert_at += 1
            break
    if insert_at is None:
        return False
    lines[insert_at:insert_at] = ["", rule]
    path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return True

def ensure_qclaw_runtime_safety_rules(workspace):
    changed = False
    changed = insert_after_anchor(
        workspace / "AGENTS.md",
        "**Skill script path rule:**",
        "Installed skill scripts are read-only runtime artifacts",
        "**Installed skill scripts are read-only runtime artifacts:** Never edit files under `$HOME/.qclaw/skills`, `$HOME/.openclaw/skills`, or `$HOME/.hermes/skills/nako` to debug a live chat. If a skill script is wrong, report the failing command and ask the operator to patch the source repository, then reinstall or rerun cc-connect setup. Do not use `sed -i`, `cp`, `mv`, or an editor against installed skill scripts.",
    ) or changed
    changed = insert_after_anchor(
        workspace / "TOOLS.md",
        "- **脚本路径解析**",
        "不要热修已安装脚本",
        "- **不要热修已安装脚本**：`$HOME/.qclaw/skills`、`$HOME/.openclaw/skills`、`$HOME/.hermes/skills/nako` 是安装产物，不是工作区源码。会话里不要用 `sed -i`、`cp`、`mv` 或编辑器修改这些脚本；发现脚本问题只报告命令、日志和现象，由操作者改仓库源码后重新安装/重配。",
    ) or changed
    return changed

workspace.mkdir(parents=True, exist_ok=True)
changed = False
for name in files:
    src = source_dir / name
    dst = workspace / name
    if not src.exists():
        continue
    src_text = src.read_text(encoding="utf-8")
    if dst.exists() and read(dst) == src_text:
        continue
    if (not dst.exists()) or looks_like_qclaw_template(dst, name):
        dst.write_text(src_text, encoding="utf-8")
        changed = True

assets_src = source_dir / "assets"
assets_dst = workspace / "assets"
if assets_src.is_dir():
    assets_dst.mkdir(parents=True, exist_ok=True)
    for src in assets_src.iterdir():
        if not src.is_file():
            continue
        dst = assets_dst / src.name
        if not dst.exists():
            shutil.copy2(src, dst)
            changed = True

identity_path = workspace / "IDENTITY.md"
if ensure_qclaw_identity_sync_fields(identity_path):
    changed = True
if ensure_qclaw_runtime_safety_rules(workspace):
    changed = True

bootstrap = workspace / "BOOTSTRAP.md"
if bootstrap.exists() and looks_like_qclaw_bootstrap(bootstrap):
    backup = bootstrap.with_name(f"BOOTSTRAP.md.bak-qclaw-template-{time.strftime('%Y%m%d-%H%M%S')}")
    shutil.move(str(bootstrap), str(backup))
    changed = True

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
    changed = True

print("changed" if changed else "unchanged")
PY
)"
  if [ "$result" = "changed" ]; then
    QCLAW_PERSONA_CHANGED=1
    info "QClaw Nako 人设已写入: $QCLAW_WORKSPACE"
  fi
}

ensure_qclaw_agent_registration() {
  python3 - "$QCLAW_HOME" "${QCLAW_OPENCLAW_CONFIG:-$QCLAW_HOME/openclaw.json}" "$AGENT_ID" "$QCLAW_WORKSPACE" "$DISPLAY_NAME" <<'PY'
import json
import re
import sys
import time
from pathlib import Path

qclaw_home, config_path, agent_id, workspace, display_name = sys.argv[1:]
home = Path(qclaw_home).expanduser()
config = Path(config_path).expanduser()
workspace_path = Path(workspace).expanduser()
agent_dir = home / "agents" / agent_id / "agent"
workspace_path.mkdir(parents=True, exist_ok=True)
agent_dir.mkdir(parents=True, exist_ok=True)
config.parent.mkdir(parents=True, exist_ok=True)

def load(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}

def identity_from_workspace():
    text = ""
    for name in ("IDENTITY.md", "AGENTS.md", "SOUL.md"):
        path = workspace_path / name
        if path.exists():
            text += "\n" + path.read_text(encoding="utf-8", errors="ignore")
    identity = {}
    for line in text.splitlines():
        match = re.match(r"^-?\s*(\w+)\s*:\s*(.+)$", line.strip())
        if not match:
            continue
        label = match.group(1).lower()
        value = match.group(2).strip()
        if label == "name":
            identity["name"] = value
        elif label == "emoji":
            identity["emoji"] = value
        elif label == "vibe":
            identity.setdefault("theme", value)
        elif label == "avatar":
            identity["avatar"] = value
    if identity:
        return identity
    patterns = [
        r"\*\*姓名\*\*[：:]\s*([^\n\r ]+)",
        r"姓名[：:]\s*([^\n\r ]+)",
        r"name[：:]\s*([^\n\r ]+)",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.I)
        if match:
            return {"name": match.group(1).strip()}
    return {}

cfg = load(config)
agents = cfg.setdefault("agents", {})
if not isinstance(agents, dict):
    cfg["agents"] = agents = {}
items = agents.setdefault("list", [])
if not isinstance(items, list):
    agents["list"] = items = []

existing = {}
existing_index = None
for idx, item in enumerate(items):
    if isinstance(item, dict) and item.get("id") == agent_id:
        existing = item
        existing_index = idx
        break

def normalize_identity(value):
    if not isinstance(value, dict):
        return {}
    result = {}
    for key in ("name", "emoji", "theme", "avatar"):
        item = value.get(key)
        if isinstance(item, str) and item:
            result[key] = item
    if "theme" not in result:
        vibe = value.get("vibe")
        if isinstance(vibe, str) and vibe:
            result["theme"] = vibe
    return result

identity = normalize_identity(existing.get("identity")) or identity_from_workspace()
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
if agent_id.startswith("agent-nako"):
    base = normalize_identity(identity)
    if base.get("avatar") in legacy_default_avatars:
        base["avatar"] = default_identity["avatar"]
    for key, value in default_identity.items():
        if not base.get(key):
            base[key] = value
    identity = base

name = existing.get("name") or (identity.get("name") if isinstance(identity, dict) else "")
if not name:
    fallback = display_name.strip()
    prefix = "QClaw "
    name = fallback[len(prefix):] if fallback.startswith(prefix) else fallback
if not name:
    name = agent_id

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

entry = dict(existing)
entry.update({
    "id": agent_id,
    "name": name,
    "workspace": str(workspace_path),
    "agentDir": str(agent_dir),
})
if identity:
    entry["identity"] = identity
model = (
    existing.get("model")
    or (((agents.get("defaults") or {}).get("model") or {}).get("primary"))
)
if model:
    entry["model"] = model
entry = apply_qclaw_script_media_policy(entry)

if existing_index is None:
    items.append(entry)
else:
    items[existing_index] = entry

old = config.read_text(encoding="utf-8", errors="ignore") if config.exists() else ""
new = json.dumps(cfg, ensure_ascii=False, indent=2) + "\n"
if old != new:
    if config.exists():
        backup = config.with_name(f"openclaw.json.bak-cc-connect-qclaw-{time.strftime('%Y%m%d-%H%M%S')}")
        backup.write_text(old, encoding="utf-8")
    config.write_text(new, encoding="utf-8")
    print("changed")
else:
    print("ok")
PY
}

sync_qclaw_pack_skills() {
  local src="$CC_SETUP_REPO_ROOT/nako/skills" dst="$QCLAW_HOME/skills" result
  [ -d "$src" ] || return 0
  result="$(python3 - "$src" "$dst" <<'PY'
import filecmp
import shutil
import sys
import time
from pathlib import Path

src_root, dst_root = map(lambda p: Path(p).expanduser(), sys.argv[1:])
dst_root.mkdir(parents=True, exist_ok=True)
changed = False
stamp = time.strftime("%Y%m%d-%H%M%S")

def install(src: Path, dst: Path):
    global changed
    if not src.exists() or not src.is_file():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and filecmp.cmp(src, dst, shallow=False):
        return
    if dst.exists():
        backup = dst.with_name(f"{dst.name}.bak-cc-connect-skill-{stamp}")
        shutil.copy2(dst, backup)
    shutil.copy2(src, dst)
    changed = True

install(src_root / "skill-log.sh", dst_root / "skill-log.sh")
for name in ("vision", "hearing", "voice", "selfie", "dokidoki"):
    src_skill = src_root / name
    dst_skill = dst_root / name
    if not src_skill.exists():
        continue
    install(src_skill / "SKILL.md", dst_skill / "SKILL.md")
    install(src_skill / "_meta.json", dst_skill / "_meta.json")
    scripts = src_skill / "scripts"
    if scripts.exists():
        for item in sorted(scripts.iterdir()):
            if item.is_file():
                install(item, dst_skill / "scripts" / item.name)
    (dst_skill / "logs").mkdir(parents=True, exist_ok=True)

print("changed" if changed else "unchanged")
PY
)"
  if [ "$result" = "changed" ]; then
    info "QClaw skills 已从仓库源刷新: $dst"
  fi
}

find_go() {
  local g
  for g in /usr/local/go/bin/go /usr/lib/go-1.25/bin/go /usr/lib/go-1.24/bin/go go; do
    if command -v "$g" >/dev/null 2>&1; then
      command -v "$g"
      return 0
    fi
  done
  return 1
}

go_version_value() {
  "$1" version 2>/dev/null | awk '{print $3}' | sed 's/^go//'
}

version_ge() {
  python3 - "$1" "$2" <<'PY'
import sys

def parts(value):
    out = []
    for item in value.split("."):
        digits = ""
        for char in item:
            if char.isdigit():
                digits += char
            else:
                break
        out.append(int(digits or 0))
    return out

got = parts(sys.argv[1])
need = parts(sys.argv[2])
size = max(len(got), len(need))
got += [0] * (size - len(got))
need += [0] * (size - len(need))
sys.exit(0 if got >= need else 1)
PY
}

go_meets_min() {
  local g="$1" v
  v="$(go_version_value "$g")"
  [ -n "$v" ] && version_ge "$v" "${CC_CONNECT_GO_MIN_VERSION:-1.25.0}"
}

find_go_for_lazycat() {
  local g
  for g in /usr/local/go/bin/go /usr/lib/go-1.25/bin/go go; do
    if command -v "$g" >/dev/null 2>&1; then
      g="$(command -v "$g")"
      if go_meets_min "$g"; then
        printf '%s\n' "$g"
        return 0
      fi
    fi
  done
  return 1
}

install_go_linux_tarball() {
  local arch url tmp archive install_root gobin
  has_bin curl || { warn "缺少 curl，无法下载 Go ${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}"; return 1; }
  has_bin tar || { warn "缺少 tar，无法安装 Go ${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}"; return 1; }
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) warn "不支持自动安装 Go 的架构: $arch"; return 1 ;;
  esac

  url="https://dl.google.com/go/go${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}.linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  archive="$tmp/go.tgz"
  info "下载 Go ${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0} (${arch}) ..."
  if ! curl -fL --retry 3 --connect-timeout 20 "$url" -o "$archive"; then
    rm -rf "$tmp"
    return 1
  fi

  if [ "$(id -u)" -eq 0 ]; then
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "$archive"
    gobin="/usr/local/go/bin/go"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "$archive"
    gobin="/usr/local/go/bin/go"
  else
    install_root="$HOME/.local/go-${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}"
    rm -rf "$install_root"
    mkdir -p "$(dirname "$install_root")"
    tar -C "$(dirname "$install_root")" -xzf "$archive"
    mv "$(dirname "$install_root")/go" "$install_root"
    gobin="$install_root/bin/go"
  fi
  rm -rf "$tmp"

  if go_meets_min "$gobin"; then
    GO_FOR_CC_CONNECT="$gobin"
    info "Go $("$gobin" version | awk '{print $3}') 已就绪"
    return 0
  fi
  return 1
}

ensure_go_for_lazycat() {
  local g os
  if g="$(find_go_for_lazycat)"; then
    GO_FOR_CC_CONNECT="$g"
    return 0
  fi

  os="$(uname -s)"
  case "$os" in
    Linux)
      install_go_linux_tarball || return 1
      ;;
    Darwin)
      if has_bin brew; then
        info "安装 Go（CodeEagle/cc-connect 构建需要 >= ${CC_CONNECT_GO_MIN_VERSION:-1.25.0}）..."
        brew install go || true
      fi
      g="$(find_go_for_lazycat)" || return 1
      GO_FOR_CC_CONNECT="$g"
      ;;
    *)
      return 1
      ;;
  esac
}

cc_connect_has_native_video() {
  local bin
  bin="$(command -v cc-connect 2>/dev/null || true)"
  [ -n "$bin" ] || return 1
  if cc-connect --version 2>&1 | grep -qE 'lazycat/v1\.3\.3|1\.3\.3-beta|1\.3\.[3-9]'; then
    return 0
  fi
  if command -v strings >/dev/null 2>&1 && strings "$bin" 2>/dev/null | grep -qE 'SendFileVideo|uploadMediaVideo|buildVideoMessageItem'; then
    return 0
  fi
  if grep -aE 'SendFileVideo|uploadMediaVideo|buildVideoMessageItem' "$bin" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

copy_cc_connect_binary() {
  local src="$1" dest="$2"
  if has_bin install; then
    install -m 0755 "$src" "$dest"
  else
    cp "$src" "$dest"
    chmod 0755 "$dest" 2>/dev/null || true
  fi
}

sudo_copy_cc_connect_binary() {
  local src="$1" dest="$2"
  if has_bin install; then
    sudo install -m 0755 "$src" "$dest"
  else
    sudo cp "$src" "$dest"
    sudo chmod 0755 "$dest" 2>/dev/null || true
  fi
}

install_cc_connect_binary() {
  local src="$1" dest="${CC_CONNECT_BIN:-}"
  local exe_suffix
  exe_suffix="$(cc_connect_exe_suffix)"
  if [ -z "$dest" ]; then
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
      dest="/usr/local/bin/cc-connect${exe_suffix}"
    elif [ -d /usr/local/bin ] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      dest="/usr/local/bin/cc-connect${exe_suffix}"
    else
      mkdir -p "$HOME/.local/bin"
      dest="$HOME/.local/bin/cc-connect${exe_suffix}"
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  if [ -w "$(dirname "$dest")" ]; then
    copy_cc_connect_binary "$src" "$dest"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo_copy_cc_connect_binary "$src" "$dest"
  else
    err "无法写入 ${dest}；请用 sudo 运行，或设置 CC_CONNECT_BIN=$HOME/.local/bin/cc-connect${exe_suffix}"
    return 1
  fi
  hash -r 2>/dev/null || true
  CC_CONNECT_CHANGED=1
  info "cc-connect 已安装到 $dest"
}

cc_connect_asset_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) return 1 ;;
  esac
  case "$os" in
    linux|darwin) printf '%s-%s\n' "$os" "$arch" ;;
    mingw*|msys*|cygwin*) printf 'windows-%s\n' "$arch" ;;
    *) return 1 ;;
  esac
}

install_cc_connect_lazycat_release() {
  local platform asset tmp archive checksum url checksum_url bin
  if ! has_bin curl || ! has_bin tar; then
    return 1
  fi
  platform="$(cc_connect_asset_platform)" || return 1
  asset="cc-connect-${CC_CONNECT_LAZYCAT_VERSION}-${platform}.tar.gz"
  url="${CC_CONNECT_LAZYCAT_RELEASE_BASE}/${asset}"
  checksum_url="${url}.sha256"
  tmp="$(mktemp -d)"

  info "下载 cc-connect fork release: $asset"
  archive="$tmp/$asset"
  if ! curl -fL --retry 2 --connect-timeout 10 "$url" -o "$archive"; then
    rm -rf "$tmp"
    return 1
  fi
  checksum="$tmp/$asset.sha256"
  if curl -fsSL "$checksum_url" -o "$checksum"; then
    expected="$(awk '{print $1}' "$checksum")"
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "$archive" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
    else
      actual="$expected"
    fi
    [ "$expected" = "$actual" ] || { rm -rf "$tmp"; return 1; }
  fi
  tar -C "$tmp" -xzf "$archive"
  case "$platform" in
    windows-*) bin="$tmp/cc-connect-$platform.exe" ;;
    *) bin="$tmp/cc-connect-$platform" ;;
  esac
  if [ ! -f "$bin" ]; then
    bin="$(find "$tmp" -type f -name 'cc-connect*' | head -1 || true)"
  fi
  [ -n "$bin" ] || { rm -rf "$tmp"; return 1; }
  chmod 0755 "$bin" 2>/dev/null || true
  install_cc_connect_binary "$bin"
  local rc=$?
  rm -rf "$tmp"
  return "$rc"
}

install_cc_connect_lazycat() {
  local gobin tmp
  if ! has_bin git; then
    warn "缺少 git，无法安装 CodeEagle/cc-connect fork"
    return 1
  fi
  if ! ensure_go_for_lazycat; then
    warn "缺少 Go >= ${CC_CONNECT_GO_MIN_VERSION:-1.25.0}，无法构建 CodeEagle/cc-connect fork"
    dim "  Linux 会尝试从 dl.google.com 自动安装 Go；失败时请手动安装后重跑"
    dim "  macOS: brew install go"
    return 1
  fi
  gobin="$GO_FOR_CC_CONNECT"

  tmp="$(mktemp -d)"
  info "安装支持微信原生视频的 cc-connect fork ($CC_CONNECT_LAZYCAT_REF) ..."
  if ! git clone --depth 1 --branch "$CC_CONNECT_LAZYCAT_REF" "$CC_CONNECT_LAZYCAT_REPO" "$tmp" >/dev/null; then
    rm -rf "$tmp"
    return 1
  fi
  if ! (
    cd "$tmp"
    build_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    GOTOOLCHAIN="${GOTOOLCHAIN:-local}" "$gobin" build -tags no_web \
      -ldflags "-s -w -X main.version=$CC_CONNECT_LAZYCAT_REF -X main.commit=Lovappen-install -X main.buildTime=$build_time" \
      -o "$tmp/cc-connect" ./cmd/cc-connect
  ); then
    rm -rf "$tmp"
    return 1
  fi
  install_cc_connect_binary "$tmp/cc-connect"
  local rc=$?
  rm -rf "$tmp"
  return "$rc"
}

should_npm_fallback() {
  [ "${CC_CONNECT_ALLOW_NPM_FALLBACK:-0}" = "1" ] && return 0
  [ "$(uname -s)" = "Darwin" ] && return 0
  return 1
}

install_cc_connect_npm() {
  if ! has_bin npm; then
    err "需要 npm 来装 cc-connect。先装 Node 22+ 再重跑（macOS: brew install node；Linux: see https://nodejs.org）"
    return 1
  fi
  info "cc-connect 未装，npm i -g cc-connect ..."
  npm i -g cc-connect 2>&1 | tail -3 || { err "cc-connect 安装失败"; return 1; }
  CC_CONNECT_CHANGED=1
}

cc_connect_running_pids() {
  if is_windows_shell; then
    if has_bin tasklist; then
      tasklist //FI "IMAGENAME eq cc-connect.exe" //FO CSV //NH 2>/dev/null | awk -F',' '
        {
          image = $1
          pid = $2
          gsub(/^"|"$/, "", image)
          gsub(/^"|"$/, "", pid)
          if (tolower(image) == "cc-connect.exe" && pid ~ /^[0-9]+$/) print pid
        }'
      return 0
    fi
    ps -W 2>/dev/null | awk '
      tolower($0) ~ /(^|[\\\/[:space:]])cc-connect(\.exe)?([[:space:]]|$)/ { print $1 }
    '
    return 0
  fi

  ps -eo pid=,args= 2>/dev/null | awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function looks_like_cc_connect_main(args) {
      args = trim(args)
      return args == "cc-connect" \
        || args == "cc-connect --force" \
        || args ~ /^([^[:space:]]+\/)?cc-connect( --force)?$/ \
        || args ~ /^node[[:space:]]+[^[:space:]]+\/cc-connect( --force)?$/
    }
    {
      pid = $1
      args = $0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", args)
      if (looks_like_cc_connect_main(args)) print pid
	    }'
}

ensure_cc_connect_api_socket_compat() {
  local base="$HOME/.cc-connect"
  local public_run="$base/run"
  local nested_run="$base/.cc-connect/run"

  [ -S "$public_run/api.sock" ] && return 0
  [ -S "$nested_run/api.sock" ] || return 0

  if [ -L "$public_run" ]; then
    rm -f "$public_run"
  elif [ -e "$public_run" ]; then
    if [ -d "$public_run" ] && [ -z "$(find "$public_run" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
      rmdir "$public_run" 2>/dev/null || return 0
    else
      return 0
    fi
  fi

  ln -s ".cc-connect/run" "$public_run" 2>/dev/null || true
}

cc_connect_project_count() {
  [ -f "$CC_CONFIG" ] || { printf '0\n'; return 0; }
  python3 - "$CC_CONFIG" <<'PY'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except Exception:
    text = ""
print(len([p for p in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text) if p.startswith("[[projects]]")]))
PY
}

cc_connect_has_startable_projects() {
  [ -f "$CC_CONFIG" ] || { printf 'no\n'; return 0; }
  python3 - "$CC_CONFIG" <<'PY'
import re
import sys

try:
    text = open(sys.argv[1], encoding="utf-8").read()
except Exception:
    print("no")
    raise SystemExit(0)

for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
    if part.startswith("[[projects]]") and re.search(r"(?m)^\[\[projects\.platforms\]\]\s*$", part):
        print("yes")
        raise SystemExit(0)
print("no")
PY
}

remove_cc_connect_project() {
  [ -f "$CC_CONFIG" ] || return 1
  python3 - "$CC_CONFIG" "$AGENT_ID" <<'PY'
import os, re, sys, time
from pathlib import Path

path = Path(sys.argv[1])
agent = sys.argv[2]
text = path.read_text(encoding="utf-8")
parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
kept = []
removed = False
for part in parts:
    if not part.startswith("[[projects]]"):
        kept.append(part)
        continue
    m = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
    if (m.group(1) if m else "") == agent:
        removed = True
        continue
    kept.append(part)

if not removed:
    sys.exit(1)

backup = path.with_name(f"config.toml.bak-uninstall-{agent}-{time.strftime('%Y%m%d-%H%M%S')}")
backup.write_text(text, encoding="utf-8")
new = "".join(kept).rstrip() + "\n"
path.write_text(new, encoding="utf-8")
os.chmod(path, 0o600)
PY
}

remove_cc_connect_sessions() {
  local session_dir="$HOME/.cc-connect/sessions" removed=0 file
  [ -d "$session_dir" ] || return 0
  for file in "$session_dir"/"$AGENT_ID"_*.json; do
    [ -e "$file" ] || continue
    rm -f "$file"
    removed=$((removed + 1))
  done
  [ "$removed" -gt 0 ] && info "已删除 $removed 个 session 文件"
  return 0
}

stop_cc_connect_pids() {
  local mode="${1:-graceful}" pid
  shift || true
  [ "$#" -gt 0 ] || return 0
  if is_windows_shell && has_bin taskkill; then
    for pid in "$@"; do
      [ -n "$pid" ] || continue
      if [ "$mode" = "force" ]; then
        taskkill //F //PID "$pid" >/dev/null 2>&1 || taskkill /F /PID "$pid" >/dev/null 2>&1 || true
      else
        taskkill //PID "$pid" >/dev/null 2>&1 || taskkill /PID "$pid" >/dev/null 2>&1 || kill "$pid" 2>/dev/null || true
      fi
    done
    return 0
  fi
  if [ "$mode" = "force" ]; then
    kill -9 "$@" 2>/dev/null || true
  else
    kill "$@" 2>/dev/null || true
  fi
}

stop_cc_connect_processes() {
  local old_pids
  old_pids="$(cc_connect_running_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ -n "${old_pids:-}" ]; then
    warn "停止 cc-connect 进程: $old_pids"
    stop_cc_connect_pids graceful $old_pids
  fi
}

start_cc_connect_background() {
  local message="${1:-cc-connect 后台已启}" bg_pid
  mkdir -p "$HOME/.cc-connect"
  if has_bin nohup; then
    nohup cc-connect </dev/null >"$HOME/.cc-connect/cc-connect.log" 2>&1 &
  else
    cc-connect </dev/null >"$HOME/.cc-connect/cc-connect.log" 2>&1 &
  fi
  bg_pid=$!
  disown 2>/dev/null || true
  info "${message} (PID $bg_pid)，日志: ~/.cc-connect/cc-connect.log"
}

purge_cc_connect_binary() {
  local bin
  bin="$(command -v cc-connect 2>/dev/null || true)"
  if [ -n "$bin" ]; then
    if [ -w "$bin" ]; then
      rm -f "$bin"
    elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      sudo rm -f "$bin"
    else
      warn "无法删除 ${bin}；请手动删除或用 sudo 重跑"
      return 0
    fi
    info "已删除 cc-connect 二进制: $bin"
  fi
}

backup_and_remove_cc_connect_home() {
  local cc_home="$HOME/.cc-connect" backup
  [ -e "$cc_home" ] || { dim "$cc_home 不存在，跳过"; return 0; }
  backup="$HOME/.cc-connect.bak-uninstall-all-$(date +%Y%m%d-%H%M%S)"
  if mv "$cc_home" "$backup"; then
    info "已移除 ~/.cc-connect（备份: ${backup}）"
  else
    warn "无法移动 ${cc_home} 到 ${backup}；尝试直接删除原目录"
    rm -rf "$cc_home"
    info "已删除 $cc_home"
  fi
}

backup_path_to_dir() {
  local src="$1" backup_root="$2" label="$3" dest base n
  [ -e "$src" ] || return 0
  mkdir -p "$backup_root"
  base="${label//\//_}"
  dest="$backup_root/$base"
  n=1
  while [ -e "$dest" ]; do
    dest="$backup_root/$base.$n"
    n=$((n + 1))
  done
  if mv "$src" "$dest"; then
    info "已移除 ${src}（备份: ${dest}）"
  else
    warn "无法移动 ${src} 到 ${dest}；跳过"
  fi
}

remove_agent_from_openclaw_config() {
  local config_path="$1" backup_root="$2" label="$3"
  [ -f "$config_path" ] || return 0
  python3 - "$config_path" "$AGENT_ID" "$backup_root" "$label" <<'PY'
import json
import sys
import time
from pathlib import Path

config_path, agent_id, backup_root, label = sys.argv[1:]
path = Path(config_path).expanduser()
try:
    cfg = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)
if not isinstance(cfg, dict):
    raise SystemExit(0)

agents = cfg.get("agents")
items = agents.get("list") if isinstance(agents, dict) else None
if not isinstance(items, list):
    raise SystemExit(0)

new_items = [item for item in items if not (isinstance(item, dict) and item.get("id") == agent_id)]
if len(new_items) == len(items):
    raise SystemExit(0)

backup_dir = Path(backup_root).expanduser()
backup_dir.mkdir(parents=True, exist_ok=True)
backup = backup_dir / f"{label}-openclaw.json.bak-{time.strftime('%Y%m%d-%H%M%S')}"
backup.write_text(path.read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
agents["list"] = new_items
path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"removed {agent_id} from {path} (backup: {backup})")
PY
}

uninstall_agent_runtime_data() {
  local ts backup_root qclaw_root qclaw_app_config qclaw_config_path qclaw_state_dir state_config_path
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_root="$HOME/.nako-agent.bak-uninstall-all-$AGENT_ID-$ts"
  step "移除 agent runtime 数据: $AGENT_ID"

  remove_agent_from_openclaw_config "$HOME/.openclaw/openclaw.json" "$backup_root" "openclaw" || true
  backup_path_to_dir "$HOME/.openclaw/workspace/$AGENT_ID" "$backup_root" "openclaw-workspace-$AGENT_ID"
  backup_path_to_dir "$HOME/.openclaw/agents/$AGENT_ID" "$backup_root" "openclaw-agent-$AGENT_ID"

  backup_path_to_dir "$HERMES_HOME/workspace/$AGENT_ID" "$backup_root" "hermes-workspace-$AGENT_ID"
  backup_path_to_dir "$HERMES_HOME/skills/nako/.env.$AGENT_ID" "$backup_root" "hermes-env-$AGENT_ID"
  backup_path_to_dir "$HERMES_HOME/skills/openclaw-imports/.env.$AGENT_ID" "$backup_root" "hermes-env-$AGENT_ID"

  qclaw_root="$(expand_path "$QCLAW_HOME")"
  qclaw_app_config="$qclaw_root/qclaw.json"
  qclaw_state_dir="$(qclaw_json_file_value "$qclaw_app_config" stateDir)"
  qclaw_config_path="$(qclaw_json_file_value "$qclaw_app_config" configPath)"
  if [ -n "$qclaw_state_dir" ]; then
    qclaw_root="$(expand_path "$qclaw_state_dir")"
    qclaw_app_config="$qclaw_root/qclaw.json"
    state_config_path="$(qclaw_json_file_value "$qclaw_app_config" configPath)"
    [ -n "$state_config_path" ] && qclaw_config_path="$state_config_path"
  fi
  if [ -n "$qclaw_config_path" ]; then
    qclaw_config_path="$(expand_path "$qclaw_config_path")"
  else
    qclaw_config_path="$qclaw_root/openclaw.json"
  fi
  remove_agent_from_openclaw_config "$qclaw_config_path" "$backup_root" "qclaw" || true
  backup_path_to_dir "$qclaw_root/workspace-$AGENT_ID" "$backup_root" "qclaw-workspace-$AGENT_ID"
  backup_path_to_dir "$qclaw_root/agents/$AGENT_ID" "$backup_root" "qclaw-agent-$AGENT_ID"

  if [ -d "$backup_root" ]; then
    info "agent runtime 数据已移出；备份目录: $backup_root"
  else
    dim "未发现 $AGENT_ID 的 runtime 数据"
  fi
}

uninstall_cc_connect_all() {
  step "完整卸载 cc-connect"
  if command -v cc-connect >/dev/null 2>&1; then
    cc-connect daemon stop --work-dir "$HOME/.cc-connect" >/dev/null 2>&1 || true
    cc-connect daemon uninstall --work-dir "$HOME/.cc-connect" >/dev/null 2>&1 || true
  fi
  stop_cc_connect_processes
  backup_and_remove_cc_connect_home
  purge_cc_connect_binary
  uninstall_agent_runtime_data
  info "cc-connect 和 agent 已完整卸载"
}

uninstall_cc_connect_project() {
  step "卸载 cc-connect 接入: $AGENT_ID"
  if command -v cc-connect >/dev/null 2>&1; then
    cc-connect daemon stop --work-dir "$HOME/.cc-connect" >/dev/null 2>&1 || true
    [ "$PURGE_CC_CONNECT" = "1" ] && cc-connect daemon uninstall --work-dir "$HOME/.cc-connect" >/dev/null 2>&1 || true
  fi
  stop_cc_connect_processes

  if remove_cc_connect_project; then
    info "已从 $CC_CONFIG 移除 project: $AGENT_ID"
  else
    dim "$CC_CONFIG 中未找到 project: $AGENT_ID"
  fi
  remove_cc_connect_sessions

  if [ "$PURGE_CC_CONNECT" = "1" ]; then
    purge_cc_connect_binary
    info "cc-connect purge 完成"
    return 0
  fi

  if [ "$(cc_connect_project_count)" -gt 0 ]; then
    if command -v cc-connect >/dev/null 2>&1; then
      if cc-connect daemon start --work-dir "$HOME/.cc-connect" >/dev/null 2>&1; then
        sleep 2
        ensure_cc_connect_api_socket_compat
        info "仍有其他 project，已重新启动 cc-connect daemon"
      else
        start_cc_connect_background "仍有其他 project，已后台启动 cc-connect"
      fi
    fi
  else
    info "已无 cc-connect project，保持停止状态"
  fi
}

if [ "$UNINSTALL_ALL" = "1" ]; then
  uninstall_cc_connect_all
  exit 0
fi

if [ "$UNINSTALL" = "1" ]; then
  uninstall_cc_connect_project
  exit 0
fi

# ── 1. 装 cc-connect ──────────────────────────────────────────────────
# 既然你跑了这个脚本，说明你想用 cc-connect — 默认直接装，不再问。
step "1. 检查 cc-connect"
if [ "$CC_CONNECT_SOURCE" = "skip" ]; then
  has_bin cc-connect || { err "--cc-connect-source skip 但系统里找不到 cc-connect"; exit 1; }
elif [ "$CC_CONNECT_SOURCE" = "lazycat" ] || [ "$CC_CONNECT_SOURCE" = "auto" ]; then
  if cc_connect_has_native_video; then
    info "当前 cc-connect 已支持微信原生视频"
  elif ! install_cc_connect_lazycat_release && ! install_cc_connect_lazycat; then
    if should_npm_fallback; then
      warn "CodeEagle/cc-connect 安装失败，回退 npm 版 cc-connect"
      install_cc_connect_npm || exit 1
    else
      err "CodeEagle/cc-connect 安装失败；请修复网络/下载 release 制品后重跑，或显式设置 --cc-connect-source npm"
      exit 1
    fi
  fi
elif ! has_bin cc-connect; then
  install_cc_connect_npm || exit 1
fi
info "cc-connect $(cc-connect --version 2>&1 | head -1)"
if ! cc_connect_has_native_video; then
  warn "当前 cc-connect 不支持微信原生视频分流，mp4 会按文件附件发送"
  dim "  解决：修复 CodeEagle/cc-connect 安装，或显式使用 --cc-connect-source lazycat 重跑"
fi

# ── 2. 初始化 / merge config.toml ─────────────────────────────────────
step "2. 配置 cc-connect 项目: $AGENT_ID"
mkdir -p "$(dirname "$CC_CONFIG")"

if [ "$RUNTIME" = "hermes" ]; then
  HERMES_BIN="$(resolve_hermes_bin)" || {
    err "选择 Hermes runtime，但找不到 hermes 命令。请先安装 Hermes，或设置 HERMES_BIN=/path/to/hermes"
    exit 1
  }
  mkdir -p "$HERMES_WORKSPACE" "$HERMES_HOME/skills/nako" "$HERMES_HOME/media"
elif [ "$RUNTIME" = "qclaw" ]; then
  QCLAW_NODE_BIN="$(resolve_qclaw_node_bin)" || {
    err "选择 QClaw runtime，但找不到 QClaw Node。请先安装 QClaw，或设置 QCLAW_NODE_BIN=/path/to/node"
    exit 1
  }
  QCLAW_OPENCLAW_MJS="$(resolve_qclaw_openclaw_mjs)" || {
    err "选择 QClaw runtime，但找不到 QClaw openclaw.mjs。请先启动一次 QClaw，或设置 QCLAW_OPENCLAW_MJS=/path/to/openclaw.mjs"
    exit 1
  }
  mkdir -p "$QCLAW_WORKSPACE"
  sync_qclaw_pack_skills
  ensure_qclaw_nako_persona
  QCLAW_AGENT_REGISTRATION_STATUS="$(ensure_qclaw_agent_registration)"
  if [ "$QCLAW_AGENT_REGISTRATION_STATUS" = "changed" ]; then
    QCLAW_PERSONA_CHANGED=1
  fi
  QCLAW_CC_SESSION_STATUS="$(ensure_qclaw_cc_session)"
  if [ "$QCLAW_CC_SESSION_STATUS" = "reset" ] || [ "$QCLAW_PERSONA_CHANGED" = "1" ]; then
    remove_cc_connect_sessions
    CC_CONNECT_CHANGED=1
  fi
fi

CONFIG_CHANGED="$(python3 - "$CC_CONFIG" "$AGENT_ID" "$RUNTIME" "$DISPLAY_NAME" "$HOME" "$WORKSPACE" "$HERMES_HOME" "$HERMES_WORKSPACE" "${HERMES_BIN:-}" "$QCLAW_HOME" "$QCLAW_WORKSPACE" "${QCLAW_NODE_BIN:-}" "${QCLAW_OPENCLAW_MJS:-}" "${QCLAW_OPENCLAW_CONFIG:-$QCLAW_HOME/openclaw.json}" "$QCLAW_CC_SESSION_SUFFIX" "$PATH" <<'PY'
import os
import json
import re
import sys
import time
from pathlib import Path

cfg_path, agent_id, runtime, display_name, home, openclaw_workspace, hermes_home, hermes_workspace, hermes_bin, qclaw_home, qclaw_workspace, qclaw_node_bin, qclaw_openclaw_mjs, qclaw_config_path, qclaw_session_suffix, path_value = sys.argv[1:]
path = Path(cfg_path)

def q(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'

def arr(values):
    return "[" + ", ".join(q(v) for v in values) + "]"

def inline_table(items):
    return "{ " + ", ".join(f"{key} = {q(value)}" for key, value in items) + " }"

def gateway_auth_token(config_path):
    try:
        data = json.loads(Path(config_path).expanduser().read_text(encoding="utf-8"))
    except Exception:
        return ""
    gateway = data.get("gateway") if isinstance(data.get("gateway"), dict) else {}
    auth = gateway.get("auth") if isinstance(gateway.get("auth"), dict) else {}
    token = auth.get("token")
    return token if isinstance(token, str) and token else ""

def normalize_global_options(text):
    project_match = re.search(r"(?m)^\[\[projects\]\]\s*$", text)
    prefix_end = project_match.start() if project_match else len(text)
    prefix = text[:prefix_end]
    rest = text[prefix_end:]

    def ensure_section_value(src, section, key, value):
        match = re.search(rf"(?ms)(^\[{re.escape(section)}\]\s*\n)(.*?)(?=^\[|\Z)", src)
        if match:
            body = match.group(2)
            if re.search(rf"(?m)^{re.escape(key)}\s*=", body):
                body = re.sub(rf"(?m)^{re.escape(key)}\s*=.*$", f"{key} = {value}", body)
            else:
                body = f"{key} = {value}\n" + body
            return src[:match.start(2)] + body + src[match.end(2):]
        if src and not src.endswith("\n"):
            src += "\n"
        return src + f"\n[{section}]\n{key} = {value}\n"

    prefix = ensure_section_value(prefix, "stream_preview", "enabled", "true")
    prefix = ensure_section_value(prefix, "display", "tool_messages", "false")
    return prefix + rest

cc_data_dir = str(Path(home) / ".cc-connect")
cc_api_data_dir = cc_data_dir
cc_env = {
    "CC_CONNECT_DATA_DIR": cc_data_dir,
    "CC_CONNECT_API_DATA_DIR": cc_api_data_dir,
    "CC_CONNECT_SESSION_DIR": str(Path(cc_api_data_dir) / "sessions"),
    "CC_CONNECT_CONFIG": str(Path(cc_data_dir) / "config.toml"),
}

if runtime == "hermes":
    command = hermes_bin or "hermes"
    work_dir = hermes_workspace
    args = ["acp"]
    hermes_skills = str(Path(hermes_home) / "skills" / "nako")
    hermes_media = str(Path(hermes_home) / "media")
    env = {
        "HOME": home,
        "HERMES_HOME": hermes_home,
        "PATH": path_value,
        **cc_env,
        "NAKO_OUTPUT_MODE": "acp",
        "NAKO_CCCONNECT_PROJECT": agent_id,
        "NAKO_AGENT_WORKSPACE": hermes_workspace,
        "NAKO_SKILLS_DIR": hermes_skills,
        "NAKO_MEDIA_HOME": hermes_media,
        "NAKO_AGENT_RUNTIME": "hermes",
    }
elif runtime == "qclaw":
    command = qclaw_node_bin or "node"
    work_dir = qclaw_workspace
    args = [qclaw_openclaw_mjs, "acp", "--session", f"agent:{agent_id}:{qclaw_session_suffix}"]
    env = {
        "HOME": home,
        "QCLAW_HOME": qclaw_home,
        "OPENCLAW_STATE_DIR": qclaw_home,
        "OPENCLAW_CONFIG": qclaw_config_path,
        "OPENCLAW_CONFIG_PATH": qclaw_config_path,
        "PATH": path_value,
        **cc_env,
        "OPENCLAW_OUTPUT_MODE": "acp",
        "OPENCLAW_CCCONNECT_PROJECT": agent_id,
        "NAKO_OUTPUT_MODE": "acp",
        "NAKO_CCCONNECT_PROJECT": agent_id,
        "NAKO_AGENT_WORKSPACE": qclaw_workspace,
        "NAKO_SKILLS_DIR": str(Path(qclaw_home) / "skills"),
        "NAKO_MEDIA_HOME": str(Path(qclaw_home) / "media"),
        "NAKO_AGENT_RUNTIME": "qclaw",
    }
    gateway_token = gateway_auth_token(qclaw_config_path)
    if gateway_token:
        env["OPENCLAW_GATEWAY_TOKEN"] = gateway_token
else:
    command = "openclaw"
    work_dir = str(Path(home) / ".openclaw")
    args = ["acp", "--session", f"agent:{agent_id}:main"]
    openclaw_home = str(Path(home) / ".openclaw")
    env = {
        "HOME": home,
        "OPENCLAW_HOME": openclaw_home,
        "PATH": path_value,
        **cc_env,
        "OPENCLAW_OUTPUT_MODE": "acp",
        "OPENCLAW_CCCONNECT_PROJECT": agent_id,
        "NAKO_OUTPUT_MODE": "acp",
        "NAKO_CCCONNECT_PROJECT": agent_id,
        "NAKO_AGENT_WORKSPACE": openclaw_workspace,
        "NAKO_SKILLS_DIR": str(Path(openclaw_home) / "skills"),
        "NAKO_MEDIA_HOME": str(Path(openclaw_home) / "media"),
        "NAKO_AGENT_RUNTIME": "openclaw",
    }
    gateway_token = gateway_auth_token(Path(openclaw_home) / "openclaw.json")
    if gateway_token:
        env["OPENCLAW_GATEWAY_TOKEN"] = gateway_token

agent_section = "\n".join([
    "[projects.agent]",
    'type = "acp"',
    "",
    "[projects.agent.options]",
    f"work_dir = {q(work_dir)}",
    f"command = {q(command)}",
    f"args = {arr(args)}",
    f"display_name = {q(display_name)}",
    f"env = {inline_table(env.items())}",
    "",
])

if path.exists():
    text = path.read_text(encoding="utf-8")
else:
    text = 'language = "en"\n\n[stream_preview]\nenabled = true\n\n[display]\ntool_messages = false\n\n[log]\nlevel = "info"\n'

normalized_text = normalize_global_options(text)
global_changed = normalized_text != text
text = normalized_text

parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
kept = []
found = False
changed = global_changed

for part in parts:
    if not part.startswith("[[projects]]"):
        kept.append(part)
        continue

    name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
    name = name_match.group(1) if name_match else ""
    if name != agent_id:
        kept.append(part)
        continue

    found = True
    platform_match = re.search(r"(?m)^\[\[projects\.platforms\]\]\s*$", part)
    platforms = part[platform_match.start():].lstrip("\n") if platform_match else ""
    new_part = f'[[projects]]\nname = {q(agent_id)}\n\n{agent_section}'
    if platforms:
        new_part += "\n" + platforms
    if new_part != part:
        changed = True
    kept.append(new_part)

if not found:
    if kept and kept[-1] and not kept[-1].endswith("\n"):
        kept[-1] += "\n"
    kept.append(f'\n[[projects]]\nname = {q(agent_id)}\n\n{agent_section}')
    changed = True

new_text = "".join(kept)
path.parent.mkdir(parents=True, exist_ok=True)
if changed or not path.exists():
    if path.exists():
        backup = path.with_name(f"config.toml.bak-runtime-{agent_id}-{runtime}-{time.strftime('%Y%m%d-%H%M%S')}")
        backup.write_text(text, encoding="utf-8")
    path.write_text(new_text, encoding="utf-8")
    os.chmod(path, 0o600)
print("updated" if changed else "unchanged")
PY
)"
[ "$CONFIG_CHANGED" = "updated" ] && CC_CONNECT_CHANGED=1
CONFIG_RESULT="$(python3 - "$CC_CONFIG" "$AGENT_ID" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
agent = sys.argv[2]
parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
for part in parts:
    if f'name = "{agent}"' in part:
        command = re.search(r'(?m)^command\s*=\s*"([^"]+)"', part)
        args = re.search(r'(?m)^args\s*=\s*(.+)$', part)
        print((command.group(1) if command else "?") + " " + (args.group(1) if args else "[]"))
        break
PY
)"
info "cc-connect project 已配置: $AGENT_ID → $RUNTIME ($CONFIG_RESULT)"

ensure_cc_connect_running() {
  local reason="${1:-启动 cc-connect}" old_pids
  if [ "$CC_CONNECT_CHANGED" = "1" ]; then
    old_pids="$(cc_connect_running_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    if [ -n "${old_pids:-}" ]; then
      warn "${reason}，重启旧 cc-connect 进程: $old_pids"
      stop_cc_connect_pids graceful $old_pids
      for _ in 1 2 3 4 5; do
        [ -z "$(cc_connect_running_pids)" ] && break
        sleep 1
      done
      old_pids="$(cc_connect_running_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      if [ -n "${old_pids:-}" ]; then
        warn "cc-connect 未及时退出，强制停止: $old_pids"
        stop_cc_connect_pids force $old_pids
        sleep 1
      fi
    fi
    CC_CONNECT_CHANGED=0
  fi

  if [ "$(cc_connect_has_startable_projects)" != "yes" ]; then
    cc-connect daemon stop --work-dir "$HOME/.cc-connect" >/dev/null 2>&1 || true
    stop_cc_connect_processes
    dim "cc-connect 还没有平台绑定，跳过启动；扫码完成后 Nako Factory 会自动重启"
    return 0
  fi

  if [ -n "$(cc_connect_running_pids)" ]; then
    info "cc-connect 已在跑，跳过"
    return 0
  fi

  if cc-connect daemon install --work-dir "$HOME/.cc-connect" --force >/dev/null 2>&1 && cc-connect daemon start --work-dir "$HOME/.cc-connect" >/dev/null 2>&1; then
    info "cc-connect daemon 已启动 (launchd/systemd)"
    dim "  状态: cc-connect daemon status   日志: cc-connect daemon logs -f"
  else
    start_cc_connect_background "cc-connect 后台已启"
  fi
  sleep 2
  ensure_cc_connect_api_socket_compat
}

# ── 3. 引导平台 QR onboarding ─────────────────────────────────────────
has_platform() {
  python3 - "$1" "$AGENT_ID" "$CC_CONFIG" <<'PY'
import sys, re
ptype, agent, cfg = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(cfg).read()
# Naive scan: look for [[projects.platforms]] type=ptype within agent's project block
in_proj = False
for line in text.splitlines():
    if line.strip().startswith("[[projects]]"):
        in_proj = False
    if f'name = "{agent}"' in line:
        in_proj = True
    if in_proj and f'type = "{ptype}"' in line:
        print("yes"); sys.exit(0)
print("no")
PY
}

remove_platform_binding() {
  python3 - "$1" "$AGENT_ID" "$CC_CONFIG" <<'PY'
import os
import re
import sys
import time
from pathlib import Path

ptype, agent_id, cfg_path = sys.argv[1:]
path = Path(cfg_path)
if not path.exists():
    print("unchanged")
    raise SystemExit(0)

targets = {"feishu", "lark"} if ptype == "feishu" else {ptype}
text = path.read_text(encoding="utf-8")
parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
changed = False
out = []

for part in parts:
    if not part.startswith("[[projects]]"):
        out.append(part)
        continue
    name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
    if (name_match.group(1) if name_match else "") != agent_id:
        out.append(part)
        continue

    blocks = re.split(r"(?m)(?=^\[\[projects\.platforms\]\]\s*$)", part)
    fixed = [blocks[0]]
    for block in blocks[1:]:
        type_match = re.search(r'(?m)^type\s*=\s*"([^"]+)"\s*$', block)
        block_type = type_match.group(1) if type_match else ""
        if block_type in targets:
            changed = True
            continue
        fixed.append(block)
    out.append("".join(fixed))

if changed:
    backup = path.with_name(f"config.toml.bak-rebind-{agent_id}-{ptype}-{time.strftime('%Y%m%d-%H%M%S')}")
    backup.write_text(text, encoding="utf-8")
    path.write_text("".join(out).rstrip() + "\n", encoding="utf-8")
    os.chmod(path, 0o600)
print("removed" if changed else "unchanged")
PY
}

normalize_platform_options() {
  python3 - "$CC_CONFIG" "$AGENT_ID" <<'PY'
import os
import re
import sys
import time
from pathlib import Path

cfg_path, agent_id = sys.argv[1:]
path = Path(cfg_path)
if not path.exists():
    print("unchanged")
    raise SystemExit(0)

text = path.read_text(encoding="utf-8")
parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
changed = False
out = []

for part in parts:
    if not part.startswith("[[projects]]"):
        out.append(part)
        continue
    name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
    if (name_match.group(1) if name_match else "") != agent_id:
        out.append(part)
        continue

    blocks = re.split(r"(?m)(?=^\[\[projects\.platforms\]\]\s*$)", part)
    fixed = [blocks[0]]
    for block in blocks[1:]:
        type_match = re.search(r'(?m)^type\s*=\s*"([^"]+)"\s*$', block)
        ptype = type_match.group(1) if type_match else ""
        if ptype in {"feishu", "lark"}:
            new_block = re.sub(r"(?m)^(enable_feishu_card|reply_to_trigger)\s*=.*\n?", "", block).rstrip()
            if "[projects.platforms.options]" not in new_block:
                new_block += "\n\n[projects.platforms.options]"
            new_block += "\nenable_feishu_card = false\nreply_to_trigger = false\n"
            if new_block != block:
                changed = True
            block = new_block
        fixed.append(block)
    out.append("".join(fixed))

new_text = "".join(out)
if changed:
    backup = path.with_name(f"config.toml.bak-platform-options-{agent_id}-{time.strftime('%Y%m%d-%H%M%S')}")
    backup.write_text(text, encoding="utf-8")
    path.write_text(new_text, encoding="utf-8")
    os.chmod(path, 0o600)
print("updated" if changed else "unchanged")
PY
}

sync_hermes_feishu_env_from_cc_config() {
  [ "$RUNTIME" = "hermes" ] || { echo "skipped"; return 0; }
  python3 - "$CC_CONFIG" "$AGENT_ID" "$HERMES_WORKSPACE/skills/.env" <<'PY'
import os
import re
import sys
from pathlib import Path

cfg_path, agent_id, env_path = sys.argv[1:]
cfg = Path(cfg_path)
if not cfg.exists():
    print("missing")
    raise SystemExit(0)

text = cfg.read_text(encoding="utf-8")
app_id = app_secret = ""
try:
    import tomllib
    data = tomllib.loads(text)
    for project in data.get("projects", []):
        if project.get("name") != agent_id:
            continue
        for platform in project.get("platforms", []):
            if platform.get("type") in ("feishu", "lark"):
                options = platform.get("options", {})
                app_id = str(options.get("app_id") or "")
                app_secret = str(options.get("app_secret") or "")
                break
except Exception:
    for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
        if not part.startswith("[[projects]]") or f'name = "{agent_id}"' not in part:
            continue
        blocks = re.split(r"(?m)(?=^\[\[projects\.platforms\]\]\s*$)", part)
        for block in blocks[1:]:
            if not re.search(r'(?m)^type\s*=\s*"(feishu|lark)"\s*$', block):
                continue
            match_id = re.search(r'(?m)^app_id\s*=\s*"([^"]+)"\s*$', block)
            match_secret = re.search(r'(?m)^app_secret\s*=\s*"([^"]+)"\s*$', block)
            app_id = match_id.group(1) if match_id else ""
            app_secret = match_secret.group(1) if match_secret else ""
            break

if not app_id or not app_secret:
    print("missing")
    raise SystemExit(0)

path = Path(env_path)
path.parent.mkdir(parents=True, exist_ok=True)
data = path.read_text(encoding="utf-8") if path.exists() else ""

def set_env(src, key, value):
    line = f"{key}={value}"
    pattern = rf"(?m)^#?\s*{re.escape(key)}=.*$"
    if re.search(pattern, src):
        return re.sub(pattern, line, src)
    if src and not src.endswith("\n"):
        src += "\n"
    return src + line + "\n"

new_data = set_env(data, "FEISHU_APP_ID", app_id)
new_data = set_env(new_data, "FEISHU_APP_SECRET", app_secret)
if new_data != data:
    path.write_text(new_data, encoding="utf-8")
    os.chmod(path, 0o600)
    print("updated")
else:
    os.chmod(path, 0o600)
    print("unchanged")
PY
}

setup_platform() {
  local platform="$1" desc="$2"
  if [ "$(has_platform "$platform")" = "yes" ]; then
    if [ "$NON_INTERACTIVE" = "1" ]; then
      info "$desc 已配，跳过"
      [ "$platform" = "feishu" ] && [ "$(normalize_platform_options)" = "updated" ] && CC_CONNECT_CHANGED=1
      CC_CONNECT_CHANGED=1
      return 0
    fi
    if ! confirm "$desc 已绑定，是否解绑并重新扫码？" n; then
      info "$desc 已配，跳过"
      [ "$platform" = "feishu" ] && [ "$(normalize_platform_options)" = "updated" ] && CC_CONNECT_CHANGED=1
      return 0
    fi
    if [ "$(remove_platform_binding "$platform")" = "removed" ]; then
      CC_CONNECT_CHANGED=1
      warn "$desc 已解绑，开始重新扫码..."
    else
      warn "$desc 解绑失败，跳过重新扫码"
      return 1
    fi
  fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    dim "未配 $desc — 手动跑：cc-connect $platform setup --project $AGENT_ID"
    return 0
  fi
  echo
  warn "$desc 未配置，开始 QR onboarding..."
  dim "扫码完成后 cc-connect 会把凭据写进 config.toml，无需手动复制。"
  setup_args=("$platform" setup --project "$AGENT_ID" --timeout 600)
  [ "$platform" = "weixin" ] && setup_args+=(--set-allow-from-empty)
  if cc-connect "${setup_args[@]}"; then
    CC_CONNECT_CHANGED=1
    [ "$platform" = "feishu" ] && normalize_platform_options >/dev/null
    ensure_cc_connect_running "$desc onboarding 完成"
  else
    warn "$desc onboarding 失败/超时（不影响其他流程）"
  fi
}

step "3. 平台 QR onboarding"
if [ "$WITH_FEISHU" = "1" ]; then
  setup_platform feishu "飞书"
fi
if [ "$WITH_WEIXIN" = "1" ]; then
  setup_platform weixin "微信"
fi
if [ "$WITH_FEISHU" = "0" ] && [ "$WITH_WEIXIN" = "0" ]; then
  if [ "$NON_INTERACTIVE" = "1" ]; then
    dim "未指定 --with-feishu / --with-weixin — 跳过 onboarding"
  else
    echo
    if confirm "现在 QR onboarding 飞书？" n; then setup_platform feishu "飞书"; fi
    if confirm "现在 QR onboarding 微信（个人 ilink）？" n; then setup_platform weixin "微信"; fi
  fi
fi

echo
if [ "$(normalize_platform_options)" = "updated" ]; then
  CC_CONNECT_CHANGED=1
fi
SYNC_HERMES_FEISHU_ENV="$(sync_hermes_feishu_env_from_cc_config)"
case "$SYNC_HERMES_FEISHU_ENV" in
  updated) info "已同步 Hermes workspace 飞书凭据镜像（来自 cc-connect QR 绑定）" ;;
  missing) dim "Hermes workspace 飞书凭据镜像未更新：cc-connect 中还没有可同步的飞书 App 凭据" ;;
esac
# ── 4. 启动 cc-connect (daemon 优先，fallback 后台 nohup) ────────────────
step "4. 启动 cc-connect"
ensure_cc_connect_running "cc-connect 配置或二进制已更新"
echo
info "全部就绪 — 在已绑定的平台里 @ $AGENT_ID 找她"
