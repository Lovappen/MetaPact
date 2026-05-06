#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"' "$ROOT/install.sh"
grep -Fq 'QClaw runtime 使用 QClaw 自带模型路由，跳过 OpenClaw provider preset' "$ROOT/install.sh"
grep -Fq 'AGENT_WORKSPACE="$QCLAW_HOME/workspace-$AGENT_ID"' "$ROOT/install.sh"
grep -Fq 'name = identity.get("name") or agent_id' "$ROOT/install.sh"
grep -Fq '"avatar": "assets/nako-avatar.svg"' "$ROOT/install.sh"
grep -Fq 'NAKO_OVERWRITE_DEFAULT_WORKSPACE_TEMPLATES=1' "$ROOT/install.sh"
grep -Fq 'BOOTSTRAP.md.bak-qclaw-template-' "$ROOT/install.sh"
grep -Fq '[string]$CcConnectSource = "lazycat"' "$ROOT/install.ps1"
grep -Fq '[ValidateSet("openclaw","hermes","qclaw")]' "$ROOT/install.ps1"
grep -Fq '[switch]$UninstallAllCcConnect' "$ROOT/install.ps1"
grep -Fq '@("--agent-id", $AgentId, "--uninstall-all")' "$ROOT/install.ps1"
grep -Fq 'Sync-QClawRuntime' "$ROOT/install.ps1"
grep -Fq 'Complete-PreseededWorkspace' "$ROOT/install.ps1"
grep -Fq 'Test-DefaultWorkspaceTemplate' "$ROOT/install.ps1"
grep -Fq '@("--agent-id", $AgentId, "--runtime", $Runtime)' "$ROOT/install.ps1"
grep -Fq 'QClaw 主模型继承' "$ROOT/install.ps1"
grep -Fq 'name = identity.get("name") or agent_id' "$ROOT/install.ps1"
grep -Fq '"avatar": "assets/nako-avatar.svg"' "$ROOT/install.ps1"
grep -Fq 'OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/openclaw.json}"' "$ROOT/nako/scripts/lib.sh"
grep -Fq 'CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/openclaw.json}"' "$ROOT/nako/scripts/detect-models.sh"
grep -Fq 'CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'elif [ "$CC_CONNECT_SOURCE" = "lazycat" ] || [ "$CC_CONNECT_SOURCE" = "auto" ]; then' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CC_CONNECT_GO_DOWNLOAD_VERSION="${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'https://dl.google.com/go/go${CC_CONNECT_GO_DOWNLOAD_VERSION:-1.25.0}.linux-${arch}.tar.gz' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CodeEagle/cc-connect 安装失败；请修复网络/Go 环境后重跑' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'should_npm_fallback' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq -- '--uninstall' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq -- '--uninstall-all' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'remove_cc_connect_project' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'uninstall_cc_connect_all' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'uninstall_agent_runtime_data' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'remove_agent_from_openclaw_config' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '.nako-agent.bak-uninstall-all-' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '.cc-connect.bak-uninstall-all-' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ps -eo pid=,args=' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'looks_like_cc_connect_main(args)' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'kill -9 $old_pids' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'cc-connect daemon install --work-dir "$HOME/.cc-connect" --force' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'cc-connect daemon start --work-dir "$HOME/.cc-connect"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'nohup cc-connect </dev/null >"$HOME/.cc-connect/cc-connect.log" 2>&1 &' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'warn "${reason}，重启旧 cc-connect 进程: $old_pids"' "$ROOT/scripts/cc-connect-setup.sh"
! grep -Fq 'warn "$reason，重启旧 cc-connect 进程: $old_pids"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_cc_connect_running "$desc onboarding 完成"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CC_CONNECT_CHANGED=1' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'info "$desc 已配，跳过"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'openclaw|hermes|qclaw)' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_OPENCLAW_MJS' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'resolve_qclaw_layout' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '"OPENCLAW_CONFIG_PATH": qclaw_config_path' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_CC_SESSION_SUFFIX="${QCLAW_CC_SESSION_SUFFIX:-session-cc-connect}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_qclaw_cc_session' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_qclaw_nako_persona' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_qclaw_agent_registration' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '"avatar": "assets/nako-avatar.svg"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'f"agent:{agent_id}:{qclaw_session_suffix}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'sync_qclaw_runtime' "$ROOT/install.sh"
grep -Fq 'f"  - name: {yaml_quote(name)}"' "$ROOT/install.sh"
! grep -Fq 'f"  {name}:"' "$ROOT/install.sh"
grep -Fq -- '- Avatar: assets/nako-avatar.svg' "$ROOT/nako/agent/IDENTITY.md"
test -f "$ROOT/nako/agent/assets/nako-avatar.svg"
grep -Fq 'https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@${AGENTS_REF}/install.sh' "$ROOT/scripts/nako-agent-factory/install.sh"
grep -Fq 'https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@{AGENTS_REF}/install.sh' "$ROOT/scripts/nako-agent-factory/nako-server.py"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
envfile="$tmp/bash_env"
cat > "$envfile" <<'EOF'
cc-connect() { return 127; }
ps() { return 0; }
kill() { return 0; }
sudo() { return 1; }
EOF
mkdir -p "$tmp/.cc-connect" \
  "$tmp/.openclaw/workspace/agent-test" "$tmp/.openclaw/agents/agent-test" \
  "$tmp/.hermes/workspace/agent-test" "$tmp/.hermes/skills/openclaw-imports" \
  "$tmp/.qclaw" "$tmp/.qclaw-state/workspace-agent-test" "$tmp/.qclaw-state/agents/agent-test"
printf 'fake cc-connect\n' > "$tmp/cc-connect"
printf 'cc config\n' > "$tmp/.cc-connect/config.toml"
printf 'openclaw workspace\n' > "$tmp/.openclaw/workspace/agent-test/file.txt"
printf 'openclaw agent\n' > "$tmp/.openclaw/agents/agent-test/data.txt"
printf 'hermes workspace\n' > "$tmp/.hermes/workspace/agent-test/file.txt"
printf 'hermes env\n' > "$tmp/.hermes/skills/openclaw-imports/.env.agent-test"
printf 'qclaw workspace\n' > "$tmp/.qclaw-state/workspace-agent-test/file.txt"
printf 'qclaw agent\n' > "$tmp/.qclaw-state/agents/agent-test/data.txt"
python3 - "$tmp" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
(root / ".openclaw" / "openclaw.json").write_text(
    json.dumps({"agents": {"list": [{"id": "agent-test"}, {"id": "other"}]}}),
    encoding="utf-8",
)
(root / ".qclaw" / "qclaw.json").write_text(
    json.dumps({"stateDir": str(root / ".qclaw-state")}),
    encoding="utf-8",
)
(root / ".qclaw-state" / "qclaw.json").write_text(
    json.dumps({"configPath": str(root / ".qclaw-state" / "openclaw.json")}),
    encoding="utf-8",
)
(root / ".qclaw-state" / "openclaw.json").write_text(
    json.dumps({"agents": {"list": [{"id": "agent-test"}, {"id": "other"}]}}),
    encoding="utf-8",
)
PY
(
  cd "$tmp"
  HOME="$tmp" BASH_ENV="$envfile" bash "$ROOT/scripts/cc-connect-setup.sh" --agent-id agent-test --uninstall-all >/dev/null
)
python3 - "$tmp" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
removed = [
    ".openclaw/workspace/agent-test",
    ".openclaw/agents/agent-test",
    ".hermes/workspace/agent-test",
    ".hermes/skills/openclaw-imports/.env.agent-test",
    ".qclaw-state/workspace-agent-test",
    ".qclaw-state/agents/agent-test",
    ".cc-connect",
    "cc-connect",
]
for rel in removed:
    assert not (root / rel).exists(), rel
openclaw = json.loads((root / ".openclaw/openclaw.json").read_text(encoding="utf-8"))
qclaw = json.loads((root / ".qclaw-state/openclaw.json").read_text(encoding="utf-8"))
assert [x["id"] for x in openclaw["agents"]["list"]] == ["other"]
assert [x["id"] for x in qclaw["agents"]["list"]] == ["other"]
agent_baks = list(root.glob(".nako-agent.bak-uninstall-all-agent-test-*"))
cc_baks = list(root.glob(".cc-connect.bak-uninstall-all-*"))
assert len(agent_baks) == 1, agent_baks
assert len(cc_baks) == 1, cc_baks
expected = {
    "openclaw-workspace-agent-test/file.txt",
    "openclaw-agent-agent-test/data.txt",
    "hermes-workspace-agent-test/file.txt",
    "hermes-env-agent-test",
    "qclaw-workspace-agent-test/file.txt",
    "qclaw-agent-agent-test/data.txt",
}
found = {str(p.relative_to(agent_baks[0])) for p in agent_baks[0].rglob("*") if p.is_file()}
missing = expected - found
assert not missing, missing
PY

tmp2="$(mktemp -d)"
trap 'rm -rf "$tmp" "$tmp2"' EXIT
envfile2="$tmp2/bash_env"
cat > "$envfile2" <<'EOF'
cc-connect() {
  case "$1" in
    --version) echo "cc-connect lazycat/v1.3.3"; return 0 ;;
    daemon) return 0 ;;
    *) return 0 ;;
  esac
}
ps() { return 0; }
kill() { return 0; }
sudo() { return 1; }
EOF
python3 - "$tmp2" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
app = root / ".qclaw-app"
state = root / ".qclaw-state"
app.mkdir(parents=True)
state.mkdir(parents=True)
(app / "qclaw.json").write_text(
    json.dumps(
        {
            "stateDir": str(state),
            "cli": {
                "nodeBinary": "/bin/echo",
                "openclawMjs": "/tmp/fake-openclaw.mjs",
            },
        }
    ),
    encoding="utf-8",
)
(state / "qclaw.json").write_text(
    json.dumps({"configPath": str(state / "custom-openclaw.json")}),
    encoding="utf-8",
)
PY
(
  cd "$tmp2"
  HOME="$tmp2" QCLAW_HOME="$tmp2/.qclaw-app" BASH_ENV="$envfile2" \
    bash "$ROOT/scripts/cc-connect-setup.sh" \
      --agent-id agent-test --runtime qclaw --with-feishu --with-weixin \
      --cc-connect-source skip --non-interactive >/dev/null
)
python3 - "$tmp2" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
state = (root / ".qclaw-state").resolve()
cfg = (root / ".cc-connect" / "config.toml").read_text(encoding="utf-8")
assert f'work_dir = "{state / "workspace-agent-test"}"' in cfg
assert 'command = "/bin/echo"' in cfg
assert 'args = ["/tmp/fake-openclaw.mjs", "acp", "--session", "agent:agent-test:session-cc-connect"]' in cfg
assert f'QCLAW_HOME = "{state}"' in cfg
assert f'OPENCLAW_STATE_DIR = "{state}"' in cfg
assert f'OPENCLAW_CONFIG_PATH = "{state / "custom-openclaw.json"}"' in cfg
project = re.search(r'\[\[projects\]\].*', cfg, re.S).group(0)
assert ".openclaw" not in project, project
sessions = state / "agents" / "agent-test" / "sessions" / "sessions.json"
assert sessions.exists()
data = json.loads(sessions.read_text(encoding="utf-8"))
key = "agent:agent-test:session-cc-connect"
assert list(data) == [key]
assert data[key]["sessionFile"].startswith(str(state / "agents" / "agent-test" / "sessions"))
qclaw_config = json.loads((state / "custom-openclaw.json").read_text(encoding="utf-8"))
registered = [
    item for item in qclaw_config["agents"]["list"]
    if isinstance(item, dict) and item.get("id") == "agent-test"
]
assert len(registered) == 1
assert registered[0]["workspace"] == str(state / "workspace-agent-test")
assert registered[0]["agentDir"] == str(state / "agents" / "agent-test" / "agent")
PY

tmp3="$(mktemp -d)"
trap 'rm -rf "$tmp" "$tmp2" "$tmp3"' EXIT
envfile3="$tmp3/bash_env"
cat > "$envfile3" <<'EOF'
cc-connect() {
  case "$1" in
    --version) echo "cc-connect lazycat/v1.3.3"; return 0 ;;
    daemon) return 0 ;;
    *) return 0 ;;
  esac
}
ps() { return 0; }
kill() { return 0; }
sudo() { return 1; }
EOF
python3 - "$tmp3" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
app = root / ".qclaw-app"
state = root / ".qclaw-state"
workspace = state / "workspace-agent-nako"
session_dir = state / "agents" / "agent-nako" / "sessions"
app.mkdir(parents=True)
state.mkdir(parents=True)
workspace.mkdir(parents=True)
session_dir.mkdir(parents=True)
(app / "qclaw.json").write_text(
    json.dumps(
        {
            "stateDir": str(state),
            "cli": {
                "nodeBinary": "/bin/echo",
                "openclawMjs": "/tmp/fake-openclaw.mjs",
            },
        }
    ),
    encoding="utf-8",
)
(state / "qclaw.json").write_text(
    json.dumps({"configPath": str(state / "openclaw.json")}),
    encoding="utf-8",
)
for name, text in {
    "AGENTS.md": "# AGENTS.md - Your Workspace\nIf `BOOTSTRAP.md` exists, follow it.\n",
    "IDENTITY.md": "# IDENTITY.md - Who Am I?\n_Fill this in during your first conversation._\n",
    "SOUL.md": "# SOUL.md - Who You Are\n_You're not a chatbot._\n",
    "USER.md": "# USER.md - About Your Human\n_Learn about the person you're helping._\n",
    "HEARTBEAT.md": "# HEARTBEAT.md Template\n",
    "TOOLS.md": "# TOOLS.md - Local Notes\n",
    "BOOTSTRAP.md": "# BOOTSTRAP.md - Hello, World\n_You just woke up._\n",
}.items():
    (workspace / name).write_text(text, encoding="utf-8")
old_session = session_dir / "old-session.jsonl"
old_session.write_text(
    '{"type":"session","id":"old-session","cwd":"' + str(workspace) + '"}\n'
    '{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"BOOTSTRAP.md says I have no name yet"}]}}\n',
    encoding="utf-8",
)
(session_dir / "sessions.json").write_text(
    json.dumps(
        {
            "agent:agent-nako:session-cc-connect": {
                "sessionId": "old-session",
                "updatedAt": 1,
                "label": "cc-connect 飞书/微信",
                "systemSent": True,
                "sessionFile": str(old_session),
            }
        }
    ),
    encoding="utf-8",
)
cc_sessions = root / ".cc-connect" / "sessions"
cc_sessions.mkdir(parents=True)
(cc_sessions / "agent-nako_stale.json").write_text("stale", encoding="utf-8")
PY
(
  cd "$tmp3"
  HOME="$tmp3" QCLAW_HOME="$tmp3/.qclaw-app" BASH_ENV="$envfile3" \
    bash "$ROOT/scripts/cc-connect-setup.sh" \
      --agent-id agent-nako --runtime qclaw \
      --cc-connect-source skip --non-interactive >/dev/null
)
python3 - "$tmp3" "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
repo = Path(sys.argv[2])
state = (root / ".qclaw-state").resolve()
workspace = state / "workspace-agent-nako"
source = repo / "nako" / "agent"
for name in ["AGENTS.md", "IDENTITY.md", "SOUL.md", "USER.md", "HEARTBEAT.md", "TOOLS.md"]:
    assert (workspace / name).read_text(encoding="utf-8") == (source / name).read_text(encoding="utf-8"), name
identity_text = (workspace / "IDENTITY.md").read_text(encoding="utf-8")
assert "- Avatar: assets/nako-avatar.svg" in identity_text
assert (workspace / "assets" / "nako-avatar.svg").exists()
qclaw_config = json.loads((state / "openclaw.json").read_text(encoding="utf-8"))
registered = [
    item for item in qclaw_config["agents"]["list"]
    if isinstance(item, dict) and item.get("id") == "agent-nako"
]
assert len(registered) == 1
assert registered[0]["identity"]["avatar"] == "assets/nako-avatar.svg"
assert not (workspace / "BOOTSTRAP.md").exists()
state_file = workspace / ".openclaw" / "workspace-state.json"
setup_state = json.loads(state_file.read_text(encoding="utf-8"))
assert setup_state.get("setupCompletedAt"), setup_state
sessions_file = state / "agents" / "agent-nako" / "sessions" / "sessions.json"
sessions = json.loads(sessions_file.read_text(encoding="utf-8"))
entry = sessions["agent:agent-nako:session-cc-connect"]
assert entry["sessionId"] != "old-session"
assert entry["systemSent"] is False
assert Path(entry["sessionFile"]).exists()
assert not (root / ".cc-connect" / "sessions" / "agent-nako_stale.json").exists()
PY

tmp4="$(mktemp -d)"
trap 'rm -rf "$tmp" "$tmp2" "$tmp3" "$tmp4"' EXIT
envfile4="$tmp4/bash_env"
cat > "$envfile4" <<'EOF'
cc-connect() {
  case "$1" in
    --version) echo "cc-connect lazycat/v1.3.3"; return 0 ;;
    daemon) return 0 ;;
    *) return 0 ;;
  esac
}
ps() { return 0; }
kill() { return 0; }
sudo() { return 1; }
EOF
python3 - "$tmp4" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
app = root / ".qclaw-app"
state = root / ".qclaw-state"
workspace = state / "workspace-agent-nako"
app.mkdir(parents=True)
state.mkdir(parents=True)
workspace.mkdir(parents=True)
(app / "qclaw.json").write_text(
    json.dumps(
        {
            "stateDir": str(state),
            "cli": {
                "nodeBinary": "/bin/echo",
                "openclawMjs": "/tmp/fake-openclaw.mjs",
            },
        }
    ),
    encoding="utf-8",
)
(state / "qclaw.json").write_text(
    json.dumps({"configPath": str(state / "openclaw.json")}),
    encoding="utf-8",
)
(workspace / "IDENTITY.md").write_text(
    "# IDENTITY - custom\n\n**姓名**：野木奈子\n\ncustom line\n",
    encoding="utf-8",
)
PY
(
  cd "$tmp4"
  HOME="$tmp4" QCLAW_HOME="$tmp4/.qclaw-app" BASH_ENV="$envfile4" \
    bash "$ROOT/scripts/cc-connect-setup.sh" \
      --agent-id agent-nako --runtime qclaw \
      --cc-connect-source skip --non-interactive >/dev/null
)
python3 - "$tmp4" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
state = (root / ".qclaw-state").resolve()
workspace = state / "workspace-agent-nako"
identity_text = (workspace / "IDENTITY.md").read_text(encoding="utf-8")
assert "# IDENTITY - custom" in identity_text
assert "custom line" in identity_text
assert "- Avatar: assets/nako-avatar.svg" in identity_text
assert (workspace / "assets" / "nako-avatar.svg").exists()
qclaw_config = json.loads((state / "openclaw.json").read_text(encoding="utf-8"))
registered = [
    item for item in qclaw_config["agents"]["list"]
    if isinstance(item, dict) and item.get("id") == "agent-nako"
]
assert len(registered) == 1
assert registered[0]["identity"]["avatar"] == "assets/nako-avatar.svg"
PY

echo "cc-connect default source checks passed"
