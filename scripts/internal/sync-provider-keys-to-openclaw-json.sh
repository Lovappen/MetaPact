#!/usr/bin/env bash
# Internal helper: sync provider keys from env/.env into openclaw.json for testing.

set -euo pipefail

CONFIG=""
ENV_FILE=""
RUNTIME="${NAKO_AGENT_RUNTIME:-}"
AGENT_ID="${AGENT_ID:-agent-nako}"
BACKUP=1

usage() {
  cat <<'HELP'
sync-provider-keys-to-openclaw-json.sh

Internal test helper. Reads supported keys from the process environment and an
optional env file, then writes them into openclaw.json:

  voice:  MINIMAX_API_KEY, MINIMAX_GROUP_ID
  selfie: FAL_KEY, SELFIE_REFERENCE_IMAGE, SELFIE_CHARACTER_DESC

Usage:
  FAL_KEY=... MINIMAX_API_KEY=... MINIMAX_GROUP_ID=... \
    scripts/internal/sync-provider-keys-to-openclaw-json.sh

Options:
  --config <path>        Explicit openclaw.json path.
  --runtime <name>       openclaw|qclaw. Default: $NAKO_AGENT_RUNTIME, otherwise
                         auto-detect QClaw when only ~/.qclaw exists.
  --agent-id <id>        Agent id for workspace env discovery. Default: agent-nako.
  --env-file <path|->    Read KEY=VALUE lines before applying process env.
  --no-backup            Do not create a .bak file.
  -h, --help             Show this help.
HELP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --config=*) CONFIG="${1#*=}"; shift ;;
    --runtime|--backend) RUNTIME="$2"; shift 2 ;;
    --runtime=*|--backend=*) RUNTIME="${1#*=}"; shift ;;
    --agent-id) AGENT_ID="$2"; shift 2 ;;
    --agent-id=*) AGENT_ID="${1#*=}"; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --env-file=*) ENV_FILE="${1#*=}"; shift ;;
    --no-backup) BACKUP=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$RUNTIME" ]; then
  openclaw_probe="${OPENCLAW_HOME:-$HOME/.openclaw}"
  qclaw_probe="${QCLAW_HOME:-$HOME/.qclaw}"
  if [ -n "${QCLAW_HOME:-}" ] && { [ -f "$qclaw_probe/qclaw.json" ] || [ -f "$qclaw_probe/openclaw.json" ]; }; then
    RUNTIME="qclaw"
  elif [ ! -f "$openclaw_probe/openclaw.json" ] && { [ -f "$qclaw_probe/qclaw.json" ] || [ -f "$qclaw_probe/openclaw.json" ]; }; then
    RUNTIME="qclaw"
  else
    RUNTIME="openclaw"
  fi
fi

case "$RUNTIME" in
  openclaw|qclaw) ;;
  *) echo "--runtime only supports openclaw|qclaw" >&2; exit 2 ;;
esac

STDIN_ENV_FILE=""
cleanup_stdin_env_file() {
  if [ -n "${STDIN_ENV_FILE:-}" ] && [ -f "$STDIN_ENV_FILE" ]; then
    rm -f "$STDIN_ENV_FILE"
  fi
}

if [ "$ENV_FILE" = "-" ]; then
  STDIN_ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-provider-keys.XXXXXX")"
  chmod 600 "$STDIN_ENV_FILE"
  trap cleanup_stdin_env_file EXIT
  cat > "$STDIN_ENV_FILE"
fi

SYNC_PROVIDER_KEYS_STDIN_FILE="$STDIN_ENV_FILE" \
python3 - "$CONFIG" "$RUNTIME" "$ENV_FILE" "$BACKUP" "$AGENT_ID" <<'PY'
import json
import os
import re
import sys
import time
from pathlib import Path

config_arg, runtime, env_file, backup_enabled, agent_id = sys.argv[1:6]

voice_keys = ("MINIMAX_API_KEY", "MINIMAX_GROUP_ID")
selfie_keys = ("FAL_KEY", "KIE_API_KEY", "SELFIE_REFERENCE_IMAGE", "SELFIE_CHARACTER_DESC")
allowed = set(voice_keys + selfie_keys)
default_selfie_reference_image = "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png"

def resolve(path):
    return Path(os.path.expanduser(path)).resolve()

def read_json(path):
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"openclaw.json not found: {path}")
    except Exception as exc:
        raise SystemExit(f"Failed to read JSON {path}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"openclaw.json must contain an object: {path}")
    return data

def qclaw_home():
    base = resolve(os.environ.get("QCLAW_HOME", "~/.qclaw"))
    app_config = base / "qclaw.json"
    app = {}
    if app_config.exists():
        try:
            app = json.loads(app_config.read_text(encoding="utf-8"))
        except Exception:
            app = {}
    state_dir = app.get("stateDir")
    if isinstance(state_dir, str) and state_dir:
        base = resolve(state_dir)
    return base

def qclaw_config_path():
    base = resolve(os.environ.get("QCLAW_HOME", "~/.qclaw"))
    app_config = base / "qclaw.json"
    app = {}
    if app_config.exists():
        try:
            app = json.loads(app_config.read_text(encoding="utf-8"))
        except Exception:
            app = {}
    state_dir = app.get("stateDir")
    if isinstance(state_dir, str) and state_dir:
        base = resolve(state_dir)
        state_config = base / "qclaw.json"
        if state_config.exists():
            try:
                app = json.loads(state_config.read_text(encoding="utf-8")) or app
            except Exception:
                pass
    config_path = os.environ.get("QCLAW_OPENCLAW_CONFIG") or os.environ.get("OPENCLAW_CONFIG_PATH")
    if not config_path and isinstance(app.get("configPath"), str):
        config_path = app["configPath"]
    return resolve(config_path) if config_path else base / "openclaw.json"

def default_config_path():
    if config_arg:
        return resolve(config_arg)
    if runtime == "qclaw":
        return qclaw_config_path()
    config_path = os.environ.get("OPENCLAW_CONFIG")
    if config_path:
        return resolve(config_path)
    home = resolve(os.environ.get("OPENCLAW_HOME", "~/.openclaw"))
    return home / "openclaw.json"

def openclaw_home():
    return resolve(os.environ.get("OPENCLAW_HOME", "~/.openclaw"))

def parse_env_file(path):
    values = {}
    empty = []
    if not path:
        return values, "", empty
    if path == "-":
        stdin_file = os.environ.get("SYNC_PROVIDER_KEYS_STDIN_FILE")
        if stdin_file:
            p = resolve(stdin_file)
            text = p.read_text(encoding="utf-8")
        else:
            text = sys.stdin.read()
        label = "stdin"
    else:
        p = resolve(path)
        if not p.exists():
            raise SystemExit(f"env file not found: {p}")
        text = p.read_text(encoding="utf-8")
        label = str(p)
    line_re = re.compile(r"^(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = line_re.match(line)
        if not match:
            continue
        key, value = match.groups()
        if key not in allowed:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
            value = value[1:-1]
        if value:
            values[key] = value
        else:
            empty.append(key)
    return values, label, empty

config_path = default_config_path()
cfg = read_json(config_path)
default_env_files = [
    openclaw_home() / "skills" / ".env",
    openclaw_home() / "workspace" / agent_id / "skills" / ".env",
]
if runtime == "qclaw":
    qhome = qclaw_home()
    default_env_files.extend([
        qhome / "skills" / ".env",
        qhome / f"workspace-{agent_id}" / "skills" / ".env",
    ])

values = {}
read_files = []
empty_keys = []
for candidate in default_env_files:
    if candidate.exists():
        file_values, label, file_empty_keys = parse_env_file(str(candidate))
        values.update(file_values)
        empty_keys.extend(file_empty_keys)
        read_files.append(str(candidate))
if env_file:
    file_values, label, file_empty_keys = parse_env_file(env_file)
    values.update(file_values)
    empty_keys.extend(file_empty_keys)
    read_files.append(label)
for key in allowed:
    value = os.environ.get(key)
    if value:
        values[key] = value

if (values.get("FAL_KEY") or values.get("KIE_API_KEY")) and not values.get("SELFIE_REFERENCE_IMAGE"):
    values["SELFIE_REFERENCE_IMAGE"] = default_selfie_reference_image

if not values:
    message = [
        "No supported non-empty keys found in env or env file",
        "Supported keys: " + ", ".join(sorted(allowed)),
        f"Config target: {config_path}",
    ]
    if read_files:
        message.append("Checked env files: " + ", ".join(read_files))
    if empty_keys:
        message.append("Supported keys present but empty: " + ", ".join(sorted(set(empty_keys))))
    raise SystemExit("\n".join(message))

skills = cfg.setdefault("skills", {})
entries = skills.setdefault("entries", {})

changed = []

def sync_entry(entry_name, keys):
    entry = entries.setdefault(entry_name, {"enabled": True, "env": {}})
    if not isinstance(entry, dict):
        entry = {"enabled": True, "env": {}}
        entries[entry_name] = entry
    entry["enabled"] = True
    env = entry.setdefault("env", {})
    if not isinstance(env, dict):
        env = {}
        entry["env"] = env
    for key in keys:
        value = values.get(key)
        if value and env.get(key) != value:
            env[key] = value
            changed.append(f"{entry_name}.{key}")

sync_entry("voice", voice_keys)
sync_entry("selfie", selfie_keys)

if not changed:
    print(f"No changes needed: {config_path}")
    raise SystemExit(0)

old = config_path.read_text(encoding="utf-8")
if backup_enabled == "1":
    backup = config_path.with_name(f"{config_path.name}.bak-sync-provider-keys-{time.strftime('%Y%m%d-%H%M%S')}")
    backup.write_text(old, encoding="utf-8")
    print(f"Backup: {backup}")

config_path.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Updated: {config_path}")
print("Synced keys: " + ", ".join(changed))
if read_files:
    print("Read env files: " + ", ".join(read_files))
PY
