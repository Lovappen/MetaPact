#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"' "$ROOT/install.sh"
grep -Fq '[string]$CcConnectSource = "lazycat"' "$ROOT/install.ps1"
grep -Fq 'CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'elif [ "$CC_CONNECT_SOURCE" = "lazycat" ] || [ "$CC_CONNECT_SOURCE" = "auto" ]; then' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CC_CONNECT_GO_DOWNLOAD_VERSION="${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'https://dl.google.com/go/go${CC_CONNECT_GO_DOWNLOAD_VERSION}.linux-${arch}.tar.gz' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CodeEagle/cc-connect 安装失败；请修复网络/Go 环境后重跑' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@${AGENTS_REF}/install.sh' "$ROOT/scripts/nako-agent-factory/install.sh"
grep -Fq 'https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@{AGENTS_REF}/install.sh' "$ROOT/scripts/nako-agent-factory/nako-server.py"

echo "cc-connect default source checks passed"
