#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

config="$tmp/openclaw.json"
envfile="$tmp/provider.env"
mkdir -p "$tmp/.openclaw/skills" "$tmp/.openclaw/workspace/agent-nako/skills"
python3 - "$config" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps(
        {
            "skills": {
                "entries": {
                    "voice": {
                        "enabled": True,
                        "env": {
                            "MINIMAX_API_KEY": "old-minimax",
                            "VOLCENGINE_API_KEY": "keep-volc",
                        },
                    }
                }
            }
        },
        ensure_ascii=False,
    ),
    encoding="utf-8",
)
PY

cat > "$envfile" <<'EOF'
MINIMAX_API_KEY=envfile-minimax
MINIMAX_GROUP_ID=envfile-group
FAL_KEY=envfile-fal
SELFIE_REFERENCE_IMAGE=https://example.test/ref.png
IGNORED_SECRET=must-not-copy
EOF
cat > "$tmp/.openclaw/skills/.env" <<'EOF'
MINIMAX_API_KEY=default-minimax
MINIMAX_GROUP_ID=default-group
FAL_KEY=default-fal
SELFIE_REFERENCE_IMAGE=https://example.test/default-ref.png
EOF
cat > "$tmp/.openclaw/workspace/agent-nako/skills/.env" <<'EOF'
FAL_KEY=workspace-fal
SELFIE_REFERENCE_IMAGE=https://example.test/workspace-ref.png
EOF

output="$(
  HOME="$tmp" MINIMAX_API_KEY=process-minimax \
    "$ROOT/scripts/internal/sync-provider-keys-to-openclaw-json.sh" \
      --config "$config" --env-file "$envfile"
)"

case "$output" in
  *process-minimax*|*envfile-group*|*envfile-fal*|*example.test*|*default-minimax*|*workspace-fal*|*old-minimax*|*keep-volc*)
    echo "script output leaked secret values" >&2
    exit 1
    ;;
esac

python3 - "$config" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
entries = data["skills"]["entries"]
voice = entries["voice"]["env"]
selfie = entries["selfie"]["env"]
assert voice["MINIMAX_API_KEY"] == "process-minimax"
assert voice["MINIMAX_GROUP_ID"] == "envfile-group"
assert voice["VOLCENGINE_API_KEY"] == "keep-volc"
assert selfie["FAL_KEY"] == "envfile-fal"
assert selfie["SELFIE_REFERENCE_IMAGE"] == "https://example.test/ref.png"
assert "IGNORED_SECRET" not in voice
assert "IGNORED_SECRET" not in selfie
PY

ls "$tmp"/openclaw.json.bak-sync-provider-keys-* >/dev/null

python3 - "$config" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({"skills": {"entries": {}}}), encoding="utf-8")
PY

output="$(
  HOME="$tmp" "$ROOT/scripts/internal/sync-provider-keys-to-openclaw-json.sh" \
    --config "$config" --no-backup
)"
case "$output" in
  *default-minimax*|*default-group*|*workspace-fal*|*example.test*)
    echo "default env discovery output leaked secret values" >&2
    exit 1
    ;;
esac
python3 - "$config" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
entries = data["skills"]["entries"]
assert entries["voice"]["env"]["MINIMAX_API_KEY"] == "default-minimax"
assert entries["voice"]["env"]["MINIMAX_GROUP_ID"] == "default-group"
assert entries["selfie"]["env"]["FAL_KEY"] == "workspace-fal"
assert entries["selfie"]["env"]["SELFIE_REFERENCE_IMAGE"] == "https://example.test/workspace-ref.png"
PY

python3 - "$config" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({"skills": {"entries": {}}}), encoding="utf-8")
PY
output="$(
  printf 'MINIMAX_API_KEY=stdin-minimax\nMINIMAX_GROUP_ID=stdin-group\nFAL_KEY=stdin-fal\n' \
    | HOME="$tmp/empty-home" "$ROOT/scripts/internal/sync-provider-keys-to-openclaw-json.sh" \
        --config "$config" --env-file - --no-backup
)"
case "$output" in
  *stdin-minimax*|*stdin-group*|*stdin-fal*)
    echo "stdin env sync output leaked secret values" >&2
    exit 1
    ;;
esac
python3 - "$config" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
entries = data["skills"]["entries"]
assert entries["voice"]["env"]["MINIMAX_API_KEY"] == "stdin-minimax"
assert entries["voice"]["env"]["MINIMAX_GROUP_ID"] == "stdin-group"
assert entries["selfie"]["env"]["FAL_KEY"] == "stdin-fal"
assert entries["selfie"]["env"]["SELFIE_REFERENCE_IMAGE"] == "https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png"
PY

echo "sync provider keys checks passed"
