#!/bin/bash
# Compatibility shim. The canonical installer lives at repo root: ./install.sh.

set -euo pipefail

if [ -n "${BASH_SOURCE:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  command -v git >/dev/null || { echo "git required" >&2; exit 1; }
  TMPDL="$(mktemp -d)"
  trap 'rm -rf "$TMPDL"' EXIT
  echo "正在克隆 MetaPact 仓库 → $TMPDL ..."
  git clone --depth 1 https://github.com/Lovappen/MetaPact.git "$TMPDL" >/dev/null 2>&1
  REPO_ROOT="$TMPDL"
fi

exec bash "$REPO_ROOT/install.sh" "$@"
