#!/bin/bash
# lib.sh — shared installer helpers
# Source this from any scripts/*.sh inside the nako pack.

set -euo pipefail

# ───── Colors & logging ─────
if [ -t 1 ]; then
  C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'
  C_CYAN='\033[0;36m'; C_BOLD='\033[1m'; C_DIM='\033[2m'; C_NC='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_NC=''
fi

info()  { echo -e "${C_GREEN}[✓]${C_NC} $*"; }
warn()  { echo -e "${C_YELLOW}[!]${C_NC} $*"; }
err()   { echo -e "${C_RED}[✗]${C_NC} $*" >&2; }
step()  { echo -e "\n${C_BOLD}${C_CYAN}▸ $*${C_NC}"; }
dim()   { echo -e "${C_DIM}$*${C_NC}"; }

# ───── Prompt helpers ─────
# ask "question" [default]
# 注意：prompt 必须打到 stderr (>&2)，否则会被调用方 $(ask ...) 的命令替换吃掉，
# 用户屏幕上看不到任何提示，以为脚本卡死了。只有最终 reply 才走 stdout。
ask() {
  local question="$1"; local default="${2:-}"; local reply
  if [ -n "$default" ]; then
    echo -en "${C_CYAN}?${C_NC} $question ${C_DIM}[$default]${C_NC}: " >&2
  else
    echo -en "${C_CYAN}?${C_NC} $question: " >&2
  fi
  read -r reply </dev/tty
  echo "${reply:-$default}"
}

ask_secret() {
  # 每输入一字符 echo 一个 *，看得见进度但内容隐藏。回车结束。
  # backspace (0x7f) 删一个 *。结束后若长度 > 8，提示首4…末4 让用户对比是否粘贴正确。
  local question="$1" reply="" ch
  echo -en "${C_CYAN}?${C_NC} $question ${C_DIM}(直接回车跳过；粘贴时会逐字符显示 *)${C_NC}: " >&2
  while IFS= read -rs -n 1 ch </dev/tty; do
    case "$ch" in
      "")          break ;;                                              # Enter
      $'\x7f'|$'\b')                                                     # Backspace / DEL
        if [ -n "$reply" ]; then reply="${reply%?}"; echo -en "\b \b" >&2; fi
        ;;
      *)           reply+="$ch"; echo -n "*" >&2 ;;
    esac
  done
  echo >&2
  if [ "${#reply}" -gt 8 ]; then
    echo -e "${C_DIM}  ↳ ${reply:0:4}…${reply: -4} (${#reply} 字符)${C_NC}" >&2
  elif [ -n "$reply" ]; then
    echo -e "${C_DIM}  ↳ ${#reply} 字符${C_NC}" >&2
  fi
  echo "$reply"
}

confirm() {
  local question="$1"; local default="${2:-n}"; local reply
  local hint="[y/N]"; [ "$default" = "y" ] && hint="[Y/n]"
  echo -en "${C_CYAN}?${C_NC} $question $hint: "
  read -r reply </dev/tty
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ask_choice "prompt" "opt1" "opt2" ...
# echoes selected option text to stdout
ask_choice() {
  local prompt="$1"; shift
  local i=1
  echo -e "${C_CYAN}?${C_NC} $prompt" >&2
  for o in "$@"; do
    echo "  $i) $o" >&2
    i=$((i+1))
  done
  local count=$#
  while true; do
    echo -en "  选择 (1-$count): " >&2
    local n; read -r n </dev/tty
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "$count" ]; then
      echo "${!n}"
      return 0
    fi
    warn "无效选择"
  done
}

# ───── Requirement checks ─────
need_bin() {
  local bin="$1"
  if ! command -v "$bin" &>/dev/null; then
    err "缺少依赖：$bin"
    return 1
  fi
}

has_bin() { command -v "$1" &>/dev/null; }

# ───── Openclaw paths ─────
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/openclaw.json}"
OPENCLAW_SKILLS_DIR="${OPENCLAW_SKILLS_DIR:-$OPENCLAW_HOME/skills}"
OPENCLAW_WORKSPACES="${OPENCLAW_WORKSPACES:-$OPENCLAW_HOME/workspace}"

# Backup file with timestamp suffix
backup_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  cp -p "$f" "${f}.bak-${ts}"
  dim "  备份 → ${f}.bak-${ts}"
}

nako_is_default_workspace_template() {
  [ "${NAKO_OVERWRITE_DEFAULT_WORKSPACE_TEMPLATES:-0}" = "1" ] || return 1
  local f="$1" base
  [ -f "$f" ] || return 1
  base="$(basename "$f")"
  case "$base" in
    AGENTS.md)
      grep -Fq '# AGENTS.md - Your Workspace' "$f" \
        && ! grep -Fq '@custom.md' "$f"
      ;;
    IDENTITY.md)
      grep -Fq '# IDENTITY.md - Who Am I?' "$f"
      ;;
    SOUL.md)
      grep -Fq '# SOUL.md - Who You Are' "$f"
      ;;
    USER.md)
      grep -Fq '# USER.md - About Your Human' "$f"
      ;;
    HEARTBEAT.md)
      grep -Fq '# HEARTBEAT.md Template' "$f"
      ;;
    TOOLS.md)
      grep -Fq '# TOOLS.md - Local Notes' "$f"
      ;;
    *)
      return 1
      ;;
  esac
}

# ───── Safe install pattern ─────
# safe_install_file <src> <dst>
#   If dst doesn't exist: install
#   If dst exists and differs: prompt (unless FORCE=1)
safe_install_file() {
  local src="$1"; local dst="$2"
  if [ ! -f "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    dim "  + $dst"
    return 0
  fi
  if cmp -s "$src" "$dst"; then
    dim "  = $dst (unchanged)"
    return 0
  fi
  if nako_is_default_workspace_template "$dst"; then
    backup_file "$dst"
    cp "$src" "$dst"
    dim "  ± $dst (replaced default workspace template)"
    return 0
  fi
  if [ "${FORCE:-0}" = "1" ]; then
    backup_file "$dst"
    cp "$src" "$dst"
    dim "  ± $dst (overwritten with backup)"
    return 0
  fi
  if confirm "  $dst 已存在且不同。覆盖？（原文件会被备份）" n; then
    backup_file "$dst"
    cp "$src" "$dst"
    dim "  ± $dst"
  else
    warn "  跳过 $dst"
  fi
}

# ───── .env merge: only add missing keys, never overwrite user-set ─────
env_merge() {
  local src="$1"; local dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ ! -f "$dst" ]; then
    cp "$src" "$dst"
    chmod 600 "$dst"
    dim "  + $dst (new)"
    return 0
  fi
  local added=0
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    local key="${line%%=*}"
    [[ -z "$key" ]] && continue
    if ! grep -qE "^${key}=" "$dst" 2>/dev/null; then
      echo "$line" >> "$dst"
      added=$((added+1))
    fi
  done < "$src"
  chmod 600 "$dst"
  if [ "$added" -gt 0 ]; then
    dim "  ± $dst (+$added new keys, existing kept)"
  else
    dim "  = $dst (already complete)"
  fi
}

# ───── Determine pack root from any script location ─────
pack_root() {
  # Called from nako/scripts/*.sh or the root install.sh
  local dir; dir="$(cd "$(dirname "${BASH_SOURCE[1]:-$0}")" && pwd)"
  # if under scripts/ → go up one; if under nako root → itself
  if [ "$(basename "$dir")" = "scripts" ]; then
    dirname "$dir"
  else
    echo "$dir"
  fi
}
