#!/bin/bash
# cc-connect-setup.sh — 把 openclaw 上任意 agent 接到 cc-connect 多平台 host
#
# 这个脚本与具体 agent 无关，可独立使用：
#   1. 装/复用 cc-connect
#   2. 在 ~/.cc-connect/config.toml idempotent 写入指向
#      `openclaw acp --session agent:<id>:main` 的 project
#   3. 引导 QR-onboarding 飞书/微信等平台
#
# Usage:
#   bash scripts/cc-connect-setup.sh [options]
#
# Flags:
#   --agent-id <id>      openclaw agent id (默认 agent-nako)
#   --display-name <n>   cc-connect 内显示名 (默认 OpenClaw <id>)
#   --with-feishu        自动跑 feishu QR 引导（若未配 feishu）
#   --with-weixin        自动跑 weixin QR 引导（若未配 weixin）
#   --cc-connect-source  auto|npm|lazycat|skip (默认 lazycat；CodeEagle fork)
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
confirm(){
  local q="$1" def="${2:-n}" reply hint="[y/N]"
  [ "$def" = "y" ] && hint="[Y/n]"
  echo -en "${C_CYAN}?${C_NC} $q $hint: "
  read -r reply </dev/tty || reply=""
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
DISPLAY_NAME=""
CC_CONNECT_CHANGED=0
GO_FOR_CC_CONNECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --with-feishu) WITH_FEISHU=1; shift ;;
    --with-weixin) WITH_WEIXIN=1; shift ;;
    --cc-connect-source) CC_CONNECT_SOURCE="$2"; shift 2 ;;
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --display-name) DISPLAY_NAME="$2"; shift 2 ;;
    -h|--help)
      cat <<'HELP'
cc-connect-setup.sh — 把 openclaw 上任意 agent 接到 cc-connect 多平台 host

Usage:
  curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/cc-connect-setup.sh | bash
  curl -fsSL ... | bash -s -- --agent-id agent-foo --with-feishu --with-weixin
  bash scripts/cc-connect-setup.sh [options]

Flags:
  --agent-id <id>      openclaw agent id (默认 agent-nako)
  --display-name <n>   cc-connect 内显示名 (默认 "OpenClaw <id>")
  --with-feishu        自动跑 feishu QR 引导（若未配 feishu）
  --with-weixin        自动跑 weixin QR 引导（若未配 weixin）
  --cc-connect-source  auto|npm|lazycat|skip (默认 lazycat；CodeEagle fork)
  --non-interactive    不询问，缺什么就跳过
  -h, --help           本帮助
HELP
      exit 0 ;;
    *) err "Unknown flag: $1"; exit 1 ;;
  esac
done
: ${DISPLAY_NAME:="OpenClaw $AGENT_ID"}

case "$CC_CONNECT_SOURCE" in
  auto|npm|lazycat|skip) ;;
  *) err "--cc-connect-source 只支持 auto|npm|lazycat|skip"; exit 1 ;;
esac

CC_CONFIG="$HOME/.cc-connect/config.toml"
WORKSPACE="$HOME/.openclaw/workspace/$AGENT_ID"

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
  [ -n "$v" ] && version_ge "$v" "$CC_CONNECT_GO_MIN_VERSION"
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
  has_bin curl || { warn "缺少 curl，无法下载 Go $CC_CONNECT_GO_DOWNLOAD_VERSION"; return 1; }
  has_bin tar || { warn "缺少 tar，无法安装 Go $CC_CONNECT_GO_DOWNLOAD_VERSION"; return 1; }
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) warn "不支持自动安装 Go 的架构: $arch"; return 1 ;;
  esac

  url="https://dl.google.com/go/go${CC_CONNECT_GO_DOWNLOAD_VERSION}.linux-${arch}.tar.gz"
  tmp="$(mktemp -d)"
  archive="$tmp/go.tgz"
  info "下载 Go ${CC_CONNECT_GO_DOWNLOAD_VERSION} (${arch}) ..."
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
    install_root="$HOME/.local/go-${CC_CONNECT_GO_DOWNLOAD_VERSION}"
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
        info "安装 Go（CodeEagle/cc-connect 构建需要 >= $CC_CONNECT_GO_MIN_VERSION）..."
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

install_cc_connect_binary() {
  local src="$1" dest="${CC_CONNECT_BIN:-}"
  if [ -z "$dest" ]; then
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
      dest="/usr/local/bin/cc-connect"
    elif [ -d /usr/local/bin ] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
      dest="/usr/local/bin/cc-connect"
    else
      mkdir -p "$HOME/.local/bin"
      dest="$HOME/.local/bin/cc-connect"
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  if [ -w "$(dirname "$dest")" ]; then
    install -m 0755 "$src" "$dest"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo install -m 0755 "$src" "$dest"
  else
    err "无法写入 $dest；请用 sudo 运行，或设置 CC_CONNECT_BIN=$HOME/.local/bin/cc-connect"
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
  bin="$tmp/cc-connect-$platform"
  if [ ! -x "$bin" ]; then
    bin="$(find "$tmp" -type f -perm -111 -name 'cc-connect*' | head -1 || true)"
  fi
  [ -n "$bin" ] || { rm -rf "$tmp"; return 1; }
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
    warn "缺少 Go >= $CC_CONNECT_GO_MIN_VERSION，无法构建 CodeEagle/cc-connect fork"
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
  pgrep -af "cc-connect" 2>/dev/null \
    | awk '!/cc-connect-setup\.sh/ && !/cc-connect (feishu|weixin) setup/ {print $1}'
}

# ── 1. 装 cc-connect ──────────────────────────────────────────────────
# 既然你跑了这个脚本，说明你想用 cc-connect — 默认直接装，不再问。
step "1. 检查 cc-connect"
if [ "$CC_CONNECT_SOURCE" = "skip" ]; then
  has_bin cc-connect || { err "--cc-connect-source skip 但系统里找不到 cc-connect"; exit 1; }
elif [ "$CC_CONNECT_SOURCE" = "lazycat" ] || [ "$CC_CONNECT_SOURCE" = "auto" ]; then
  if cc_connect_has_native_video; then
    info "当前 cc-connect 已支持微信原生视频"
  elif ! install_cc_connect_lazycat_release && ! install_cc_connect_lazycat; then
    if [ "${CC_CONNECT_ALLOW_NPM_FALLBACK:-0}" = "1" ]; then
      warn "CodeEagle/cc-connect 安装失败，按 CC_CONNECT_ALLOW_NPM_FALLBACK=1 回退 npm"
      install_cc_connect_npm || exit 1
    else
      err "CodeEagle/cc-connect 安装失败；请修复网络/Go 环境后重跑，或显式设置 --cc-connect-source npm"
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

if [ ! -f "$CC_CONFIG" ]; then
  cat > "$CC_CONFIG" <<EOF
[server]
data_dir = "$HOME/.cc-connect/data"
log_level = "info"

[[projects]]
name = "$AGENT_ID"

[projects.agent]
type = "acp"

[projects.agent.options]
work_dir = "$HOME/.openclaw"
command = "openclaw"
args = ["acp", "--session", "agent:$AGENT_ID:main"]
display_name = "$DISPLAY_NAME"
env = { OPENCLAW_OUTPUT_MODE = "acp", OPENCLAW_CCCONNECT_PROJECT = "$AGENT_ID" }
EOF
  info "新建 $CC_CONFIG"
else
  if grep -q "name = \"$AGENT_ID\"" "$CC_CONFIG"; then
    info "已存在 $AGENT_ID project，跳过 config 写入"
  else
    cat >> "$CC_CONFIG" <<EOF

[[projects]]
name = "$AGENT_ID"

[projects.agent]
type = "acp"

[projects.agent.options]
work_dir = "$HOME/.openclaw"
command = "openclaw"
args = ["acp", "--session", "agent:$AGENT_ID:main"]
display_name = "$DISPLAY_NAME"
env = { OPENCLAW_OUTPUT_MODE = "acp", OPENCLAW_CCCONNECT_PROJECT = "$AGENT_ID" }
EOF
    info "追加 $AGENT_ID project 到 $CC_CONFIG"
  fi
fi

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

setup_platform() {
  local platform="$1" desc="$2"
  if [ "$(has_platform "$platform")" = "yes" ]; then
    info "$desc 已配，跳过"
    return 0
  fi
  if [ "$NON_INTERACTIVE" = "1" ]; then
    dim "未配 $desc — 手动跑：cc-connect $platform setup --project $AGENT_ID"
    return 0
  fi
  echo
  warn "$desc 未配置，开始 QR onboarding..."
  dim "扫码完成后 cc-connect 会把凭据写进 config.toml，无需手动复制。"
  cc-connect "$platform" setup --project "$AGENT_ID" --timeout 600 || warn "$desc onboarding 失败/超时（不影响其他流程）"
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
# ── 4. 启动 cc-connect (daemon 优先，fallback 后台 nohup) ────────────────
step "4. 启动 cc-connect"
if [ "$CC_CONNECT_CHANGED" = "1" ]; then
  old_pids="$(cc_connect_running_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ -n "${old_pids:-}" ]; then
    warn "cc-connect 已更新，重启旧进程: $old_pids"
    kill $old_pids 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      [ -z "$(cc_connect_running_pids)" ] && break
      sleep 1
    done
  fi
fi

if [ -n "$(cc_connect_running_pids)" ]; then
  info "cc-connect 已在跑，跳过"
else
  if cc-connect daemon install --force >/dev/null 2>&1 && cc-connect daemon start >/dev/null 2>&1; then
    info "cc-connect daemon 已启动 (launchd/systemd)"
    dim "  状态: cc-connect daemon status   日志: cc-connect daemon logs -f"
  else
    nohup cc-connect >"$HOME/.cc-connect/cc-connect.log" 2>&1 &
    disown 2>/dev/null || true
    info "cc-connect 后台已启 (PID $!)，日志: ~/.cc-connect/cc-connect.log"
  fi
  sleep 2
fi
echo
info "全部就绪 — 在已绑定的平台里 @ $AGENT_ID 找她"
