#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
mkdir -p "$home/.local/bin"
mkdir -p "$home/.hermes"

cat > "$home/.hermes/.env" <<'EOF'
SENSENOVA_API_KEY=test-sensenova-key
EOF

cat > "$home/.hermes/config.yaml" <<EOF
model:
  default: SenseChat-Character-Agt
  provider: sensenova
custom_providers:
  sensenova:
    base_url: https://api.sensenova.cn/compatible-mode/v2
skills:
  creation_nudge_interval: 15
  external_dirs:
  - $home/.hermes/skills/openclaw-imports
  - $home/.openclaw/skills
agent:
  max_turns: 60
EOF

cat > "$home/.local/bin/hermes" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  status) exit 0 ;;
  "acp") exit 0 ;;
  "claw migrate --help") exit 1 ;;
  *) exit 0 ;;
esac
EOF

cat > "$home/.local/bin/cc-connect" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) echo "cc-connect lazycat/v1.3.3"; exit 0 ;;
  daemon) exit 0 ;;
  *) exit 0 ;;
esac
EOF

for cmd in doki whisper ffmpeg ffprobe xxd uuidgen; do
  cat > "$home/.local/bin/$cmd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
done
chmod +x "$home/.local/bin/"*

HOME="$home" HERMES_HOME="$home/.hermes" PATH="$home/.local/bin:$PATH" \
  bash "$ROOT/install.sh" \
    --runtime hermes \
    --agent-id agent-test \
    --non-interactive \
    --skip-models \
    --with-cc-connect \
    --cc-connect-source skip >/tmp/nako-hermes-native-install.log

python3 - "$home" <<'PY'
import re
import sys
from pathlib import Path

home = Path(sys.argv[1])
hermes = home / ".hermes"
workspace = hermes / "workspace" / "agent-test"
skills = hermes / "skills" / "nako"

assert workspace.is_dir(), workspace
assert skills.is_dir(), skills
for name in ["voice", "selfie", "hearing", "vision", "dokidoki"]:
    assert (skills / name / "SKILL.md").exists(), name

assert not (home / ".openclaw").exists()
assert not (hermes / "skills" / "openclaw-imports").exists()

tools = (workspace / "TOOLS.md").read_text(encoding="utf-8")
assert "~/.hermes/skills/nako" in tools
assert "~/.openclaw" not in tools
assert "openclaw.json" not in tools

memory = (workspace / "MEMORY.md").read_text(encoding="utf-8")
assert "~/.hermes/skills/nako/.env" in memory
assert "openclaw.json" not in memory

cfg = (hermes / "config.yaml").read_text(encoding="utf-8")
managed = re.search(r"# BEGIN NAKO HERMES RUNTIME\n.*?# END NAKO HERMES RUNTIME", cfg, re.S).group(0)
assert str(skills) in managed
assert "SenseChat-Character-Agt" in managed
assert "provider: \"sensenova\"" in managed
assert "custom_providers:" in managed
assert "- name: \"sensenova\"" in managed
assert "key_env: \"SENSENOVA_API_KEY\"" in managed
assert "context_length: 198000" in managed
assert "glm-4.5-flash" not in managed
assert "openclaw-imports" not in managed
assert ".openclaw" not in managed
assert "openclaw-imports" not in cfg
assert ".openclaw" not in cfg
assert cfg.count("\nskills:") == 1 or cfg.startswith("skills:")
assert cfg.count("\nmodel:") == 1 or cfg.startswith("model:")
assert cfg.count("\ncustom_providers:") == 1 or cfg.startswith("custom_providers:")
assert "SenseChat-Character-Agt" in cfg
assert "sensenova" in cfg

cc = (home / ".cc-connect" / "config.toml").read_text(encoding="utf-8")
project = re.search(r"\[\[projects\]\].*", cc, re.S).group(0)
assert 'NAKO_AGENT_RUNTIME = "hermes"' in project
assert "OPENCLAW_OUTPUT_MODE" not in project
assert "OPENCLAW_CCCONNECT_PROJECT" not in project
assert ".openclaw" not in project
PY

echo "hermes native install checks passed"
