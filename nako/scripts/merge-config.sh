#!/bin/bash
# merge-config.sh — merge agent + skills entries into user's openclaw.json.
# Preserves all user fields; only adds or updates the keys this pack owns.
#
# Usage: merge-config.sh <agent_id> <primary_model>
# Env inputs (passed to preserve secrets in this process, not CLI args):
#   FEISHU_APP_ID, FEISHU_APP_SECRET
#   MINIMAX_API_KEY, MINIMAX_GROUP_ID   (empty → skip voice music)
#   VOLCENGINE_API_KEY, VOLCENGINE_RESOURCE_ID  (optional)
#   FAL_KEY, KIE_API_KEY (optional, selfie)
#   OPENCLAW_GATEWAY_TOKEN (optional)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

AGENT_ID="${1:-agent-nako}"
PRIMARY="${2:-}"
[ -z "$PRIMARY" ] && { err "usage: $0 <agent_id> <primary_model>"; exit 1; }

CONFIG="$OPENCLAW_CONFIG"
[ ! -f "$CONFIG" ] && { err "openclaw.json not found"; exit 1; }

backup_file "$CONFIG"

WORKSPACE="${AGENT_WORKSPACE:-$OPENCLAW_WORKSPACES/$AGENT_ID}"
AGENT_DIR="${NAKO_AGENT_CONFIG_DIR:-$OPENCLAW_HOME/agents/$AGENT_ID/agent}"
mkdir -p "$WORKSPACE" "$AGENT_DIR"

python3 - "$CONFIG" "$AGENT_ID" "$PRIMARY" "$WORKSPACE" "$AGENT_DIR" "$OPENCLAW_SKILLS_DIR" <<'PY'
import json, sys, os
path, agent_id, primary, workspace, agent_dir, skills_dir = sys.argv[1:]
cfg = json.load(open(path))

# ── agents.list: upsert the agent entry
agents = cfg.setdefault("agents", {})
lst = agents.setdefault("list", [])
found = False
for a in lst:
    if a.get("id") == agent_id:
        a["workspace"] = workspace
        a["agentDir"] = agent_dir
        model = a.get("model")
        if not isinstance(model, dict):
            model = {}
            a["model"] = model
        model["primary"] = primary
        found = True
        break
if not found:
    lst.append({
        "id": agent_id,
        "name": agent_id,
        "workspace": workspace,
        "agentDir": agent_dir,
        "model": {"primary": primary},
    })

# ── skills.entries: publish skill configuration for scripts to read directly.
# The bash skills also keep the runtime skills/.env compatibility, but
# openclaw.json is now the canonical shared config for voice/selfie providers.
skills = cfg.setdefault("skills", {})
entries = skills.setdefault("entries", {})

def set_env(entry_name, env_keys):
    entry = entries.setdefault(entry_name, {"enabled": True, "env": {}})
    entry.setdefault("enabled", True)
    env = entry.setdefault("env", {})
    for k in env_keys:
        v = os.environ.get(k, "")
        if v:
            env[k] = v

set_env("voice", [
    "MINIMAX_API_KEY", "MINIMAX_GROUP_ID",
    "VOLCENGINE_API_KEY", "VOLCENGINE_RESOURCE_ID",
    "VOICE_DEFAULT_MINIMAX", "VOICE_DEFAULT_VOLCENGINE", "VOICE_DEFAULT_SPEED",
    "OPENCLAW_GATEWAY_TOKEN",
])
set_env("selfie", ["FAL_KEY", "KIE_API_KEY", "OPENCLAW_GATEWAY_TOKEN"])

# ── skills.load.extraDirs: ensure the runtime skills dir is present
load = skills.setdefault("load", {})
extras = load.setdefault("extraDirs", [])
global_skills = os.path.expanduser(skills_dir)
if global_skills not in extras:
    extras.append(global_skills)

# ── write back with stable formatting
with open(path, "w") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"merged: agent={agent_id}, primary={primary}")
PY

info "openclaw.json 已合并 (备份 ${CONFIG}.bak-*)"
