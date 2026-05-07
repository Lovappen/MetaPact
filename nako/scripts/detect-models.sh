#!/bin/bash
# detect-models.sh — read user's openclaw.json and output available provider/model pairs
# Output format (tab-separated): <provider>/<modelId>\t<name>
#
# Usage: detect-models.sh [--json]

set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
CONFIG="${OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-$OPENCLAW_HOME/openclaw.json}}"

[ ! -f "$CONFIG" ] && { echo "ERROR: openclaw.json not found at $CONFIG" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 required" >&2; exit 1; }

FORMAT="${1:-text}"

python3 - "$CONFIG" "$FORMAT" <<'PY'
import json, sys, os
cfg = json.load(open(sys.argv[1]))
fmt = sys.argv[2]

# Openclaw stores models in agents.defaults.models as { "provider/modelId": { alias } }
# Also per-agent override at agents.list[].model.primary
defaults = cfg.get("agents", {}).get("defaults", {})
models_map = defaults.get("models", {}) or {}
primary = defaults.get("model", {}).get("primary", "")

# Also try to mine /Users/<u>/.openclaw/agents/<id>/agent/models.json for real provider/model inventory
# The above are just the enabled ones. The presence of auth-profiles.json indicates configured credentials.

entries = []
for key in sorted(models_map.keys()):
    alias = models_map[key].get("alias", "")
    entries.append((key, alias))

if fmt == "--json":
    out = {"primary": primary, "models": [{"id": k, "alias": a} for k,a in entries]}
    print(json.dumps(out, ensure_ascii=False))
else:
    # tab-separated: id\talias
    for k, a in entries:
        mark = " *" if k == primary else ""
        print(f"{k}\t{a}{mark}")
PY
