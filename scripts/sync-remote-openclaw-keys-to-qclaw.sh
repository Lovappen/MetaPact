#!/usr/bin/env bash
# Sync supported provider keys from a remote OpenClaw env file into local QClaw.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/internal/sync-provider-keys-to-openclaw-json.sh"

REMOTE="${REMOTE_PROVIDER_KEYS_HOST:-openclaw@192.168.31.213}"
REMOTE_ENV="${REMOTE_PROVIDER_KEYS_ENV:-~/.openclaw/skills/.env}"
AGENT_ID="${AGENT_ID:-agent-nako}"
CONFIG=""
QCLAW_HOME_OVERRIDE=""
SSH_BIN="${SSH_BIN:-ssh}"
BACKUP=1
SSH_ARGS=(-o BatchMode=yes -o ConnectTimeout=8)

usage() {
  cat <<'HELP'
sync-remote-openclaw-keys-to-qclaw.sh

Sync provider keys from a remote OpenClaw skills .env into local QClaw
openclaw.json. Secret values are piped directly into the local sync helper and
are not printed.

Default source:
  openclaw@192.168.31.213:~/.openclaw/skills/.env

Default target:
  local ~/.qclaw/openclaw.json, or QClaw's configured stateDir/configPath.

Usage:
  scripts/sync-remote-openclaw-keys-to-qclaw.sh

Options:
  --remote <user@host>       SSH target. Default: openclaw@192.168.31.213.
  --remote-env <path>        Remote env file. Default: ~/.openclaw/skills/.env.
  --agent-id <id>            Agent id for local QClaw env discovery. Default: agent-nako.
  --config <path>            Explicit local QClaw openclaw.json path.
  --qclaw-home <path>        Override local QCLAW_HOME.
  --ssh-bin <path>           SSH binary or test shim. Default: ssh.
  --ssh-option <option>      Extra ssh option. Repeatable.
  --no-backup                Do not create a local openclaw.json backup.
  -h, --help                 Show this help.

Environment overrides:
  REMOTE_PROVIDER_KEYS_HOST, REMOTE_PROVIDER_KEYS_ENV, AGENT_ID, QCLAW_HOME,
  SSH_BIN.
HELP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --remote) REMOTE="$2"; shift 2 ;;
    --remote=*) REMOTE="${1#*=}"; shift ;;
    --remote-env) REMOTE_ENV="$2"; shift 2 ;;
    --remote-env=*) REMOTE_ENV="${1#*=}"; shift ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --agent-id=*) AGENT_ID="${1#*=}"; shift ;;
    --config) CONFIG="$2"; shift 2 ;;
    --config=*) CONFIG="${1#*=}"; shift ;;
    --qclaw-home) QCLAW_HOME_OVERRIDE="$2"; shift 2 ;;
    --qclaw-home=*) QCLAW_HOME_OVERRIDE="${1#*=}"; shift ;;
    --ssh-bin) SSH_BIN="$2"; shift 2 ;;
    --ssh-bin=*) SSH_BIN="${1#*=}"; shift ;;
    --ssh-option) SSH_ARGS+=("$2"); shift 2 ;;
    --ssh-option=*) SSH_ARGS+=("${1#*=}"); shift ;;
    --no-backup) BACKUP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ ! -x "$HELPER" ]; then
  echo "sync helper not found or not executable: $HELPER" >&2
  exit 1
fi

HELPER_ARGS=(--runtime qclaw --agent-id "$AGENT_ID" --env-file -)
if [ -n "$CONFIG" ]; then
  HELPER_ARGS+=(--config "$CONFIG")
fi
if [ "$BACKUP" = "0" ]; then
  HELPER_ARGS+=(--no-backup)
fi

if [ -n "$QCLAW_HOME_OVERRIDE" ]; then
  export QCLAW_HOME="$QCLAW_HOME_OVERRIDE"
fi

"$SSH_BIN" "${SSH_ARGS[@]}" "$REMOTE" python3 - "$REMOTE_ENV" <<'PY' \
  | "$HELPER" "${HELPER_ARGS[@]}"
import os
import sys
from pathlib import Path

allowed = {
    "MINIMAX_API_KEY",
    "MINIMAX_GROUP_ID",
    "FAL_KEY",
    "KIE_API_KEY",
    "SELFIE_REFERENCE_IMAGE",
    "SELFIE_CHARACTER_DESC",
}

path = Path(os.path.expanduser(sys.argv[1]))
if not path.exists():
    raise SystemExit(f"remote env file not found: {path}")

count = 0
for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key = line.split("=", 1)[0].replace("export ", "").strip()
    if key in allowed:
        print(line)
        count += 1

if count == 0:
    raise SystemExit(f"no supported key names found in remote env file: {path}")
PY
