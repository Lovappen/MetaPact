#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'CC_CONNECT_SOURCE="${CC_CONNECT_SOURCE:-lazycat}"' "$ROOT/install.sh"
grep -Fq 'QClaw runtime 使用 QClaw 自带模型路由，跳过 OpenClaw provider preset' "$ROOT/install.sh"
grep -Fq 'AGENT_WORKSPACE="$QCLAW_HOME/workspace-$AGENT_ID"' "$ROOT/install.sh"
grep -Fq 'name = identity.get("name") or agent_id' "$ROOT/install.sh"
grep -Fq '"avatar": "assets/nako-avatar-head.png"' "$ROOT/install.sh"
grep -Fq 'legacy_default_avatars = {' "$ROOT/install.sh"
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
grep -Fq '"avatar": "assets/nako-avatar-head.png"' "$ROOT/install.ps1"
grep -Fq 'legacy_default_avatars = {' "$ROOT/install.ps1"
grep -Fq 'for tool_name in ("image_generate", "video_generate", "tts"):' "$ROOT/install.ps1"
grep -Fq 'OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-$OPENCLAW_HOME/openclaw.json}}"' "$ROOT/nako/scripts/lib.sh"
grep -Fq 'safe_install_pack_file()' "$ROOT/nako/scripts/lib.sh"
grep -Fq 'non-interactive; use --force to overwrite' "$ROOT/nako/scripts/lib.sh"
grep -Fq 'CONFIG="${OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-$OPENCLAW_HOME/openclaw.json}}"' "$ROOT/nako/scripts/detect-models.sh"
grep -Fq 'local _cfg="${NAKO_CONFIG:-${OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}}}"' "$ROOT/nako/skills/voice/scripts/voice.sh"
grep -Fq 'local _cfg="${NAKO_CONFIG:-${OPENCLAW_CONFIG:-${OPENCLAW_CONFIG_PATH:-$HOME/.openclaw/openclaw.json}}}"' "$ROOT/nako/skills/selfie/scripts/selfie.sh"
grep -Fq 'SELFIE_REFERENCE_IMAGE' "$ROOT/scripts/internal/sync-provider-keys-to-openclaw-json.sh"
grep -Fq 'send --data-dir "$data_dir" --image' "$ROOT/nako/skills/selfie/scripts/selfie.sh"
grep -Fq '_feishu_send_image_file "$temp_file"' "$ROOT/nako/skills/selfie/scripts/selfie.sh"
grep -Fq 'send --data-dir "$data_dir" --file' "$ROOT/nako/skills/selfie/scripts/video.sh"
grep -Fq '_feishu_send_video_file "$VIDEO_FILE"' "$ROOT/nako/skills/selfie/scripts/video.sh"
grep -Fq 'send --data-dir "$data_dir" --file' "$ROOT/nako/skills/voice/scripts/voice.sh"
grep -Fq 'send --data-dir "$data_dir" --file' "$ROOT/nako/skills/voice/scripts/sing.sh"
grep -Fq 'cc-connect media rule' "$ROOT/nako/agent/AGENTS.md"
grep -Fq 'Skill script path rule' "$ROOT/nako/agent/AGENTS.md"
grep -Fq '$HOME/.qclaw/skills' "$ROOT/nako/agent/TOOLS.md"
grep -Fq '不要调用 OpenClaw 原生 `image_generate` / `tts` / `video_generate`' "$ROOT/nako/agent/TOOLS.md"
grep -Fq 'never call OpenClaw native `video_generate` under any circumstance' "$ROOT/nako/agent/AGENTS.md"
grep -Fq 'Never set `NAKO_OUTPUT_MODE=webchat`' "$ROOT/nako/agent/AGENTS.md"
grep -Fq '即使工具列表里出现 `video_generate`，也绝对不要调用' "$ROOT/nako/agent/TOOLS.md"
grep -Fq '不要写 `NAKO_OUTPUT_MODE=webchat`' "$ROOT/nako/agent/TOOLS.md"
grep -Fq '全能力展示' "$ROOT/nako/agent/TOOLS.md"
grep -Fq 'Do not use OpenClaw native `image_generate`' "$ROOT/nako/skills/selfie/SKILL.md"
grep -Fq 'never call OpenClaw native `video_generate` in Feishu/Weixin/ACP sessions' "$ROOT/nako/skills/selfie/SKILL.md"
grep -Fq 'Do not set `NAKO_OUTPUT_MODE=webchat`' "$ROOT/nako/skills/selfie/SKILL.md"
grep -Fq '不要调用 OpenClaw 原生 `tts`' "$ROOT/nako/skills/voice/SKILL.md"
grep -Fq '不要设置 `NAKO_OUTPUT_MODE=webchat`' "$ROOT/nako/skills/voice/SKILL.md"
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
grep -Fq 'cc_connect_has_startable_projects()' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'cc-connect 还没有平台绑定，跳过启动；扫码完成后 Nako Factory 会自动重启' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_cc_connect_api_socket_compat()' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_cc_connect_api_socket_compat(work_dir)' "$ROOT/scripts/nako-agent-factory/nako-server.py"
grep -Fq 'sync_hermes_feishu_env_from_cc_config()' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'sync_hermes_feishu_env_for_project(aid)' "$ROOT/scripts/nako-agent-factory/nako-server.py"
grep -Fq 'stream_preview' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'tool_messages = false' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'stream_preview.enabled=true display.tool_messages=false' "$ROOT/scripts/nako-agent-factory/nako-server.py"
grep -Fq 'openclaw|hermes)' "$ROOT/scripts/nako-agent-factory/install.sh"
grep -Fq 'QClaw 不能通过 Nako Agent Factory 网页绑定' "$ROOT/scripts/nako-agent-factory/nako-server.py"
! grep -Fq 'openclaw|hermes|qclaw)' "$ROOT/scripts/nako-agent-factory/install.sh"
grep -Fq 'nohup cc-connect </dev/null >"$HOME/.cc-connect/cc-connect.log" 2>&1 &' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'warn "${reason}，重启旧 cc-connect 进程: $old_pids"' "$ROOT/scripts/cc-connect-setup.sh"
! grep -Fq 'warn "$reason，重启旧 cc-connect 进程: $old_pids"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_cc_connect_running "$desc onboarding 完成"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'CC_CONNECT_CHANGED=1' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'info "$desc 已配，跳过"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'openclaw|hermes|qclaw)' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_OPENCLAW_MJS' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'resolve_qclaw_layout' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'NAKO_OUTPUT_MODE' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'NAKO_CCCONNECT_PROJECT' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'OPENCLAW_GATEWAY_TOKEN' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'gateway_auth_token' "$ROOT/scripts/nako-agent-factory/nako-server.py"
grep -Fq '"NAKO_SKILLS_DIR": str(Path(openclaw_home) / "skills")' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '"NAKO_MEDIA_HOME": str(Path(openclaw_home) / "media")' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '"OPENCLAW_CONFIG": qclaw_config_path' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '"OPENCLAW_CONFIG_PATH": qclaw_config_path' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_CC_SESSION_SUFFIX="${QCLAW_CC_SESSION_SUFFIX:-session-cc-connect}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_PERSONA_CHANGED="${QCLAW_PERSONA_CHANGED:-0}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'for tool_name in ("image_generate", "video_generate", "tts"):' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'QCLAW_AGENT_REGISTRATION_STATUS="$(ensure_qclaw_agent_registration)"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_qclaw_cc_session' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_qclaw_nako_persona' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'ensure_qclaw_agent_registration' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq '"avatar": "assets/nako-avatar-head.png"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'f"agent:{agent_id}:{qclaw_session_suffix}"' "$ROOT/scripts/cc-connect-setup.sh"
grep -Fq 'sync_qclaw_runtime' "$ROOT/install.sh"
grep -Fq 'QCLAW_STATUS_TIMEOUT' "$ROOT/install.sh"
grep -Fq 'QClaw 状态检查超时' "$ROOT/install.sh"
grep -Fq 'QCLAW_PERSONA_CHANGED=1 bash "$CC_SETUP"' "$ROOT/install.sh"
grep -Fq 'for tool_name in ("image_generate", "video_generate", "tts"):' "$ROOT/install.sh"
grep -Fq 'safe_install_pack_file "$PACK_ROOT/skills/skill-log.sh" "$OPENCLAW_SKILLS_DIR/skill-log.sh"' "$ROOT/install.sh"
grep -Fq 'safe_install_pack_file "$s" "$dst/scripts/$(basename "$s")"' "$ROOT/install.sh"
grep -Fq '"selfie": ["FAL_KEY", "KIE_API_KEY", "SELFIE_REFERENCE_IMAGE", "SELFIE_CHARACTER_DESC", "OPENCLAW_GATEWAY_TOKEN"]' "$ROOT/install.sh"
grep -Fq "set_env('selfie', ['FAL_KEY','KIE_API_KEY','SELFIE_REFERENCE_IMAGE','SELFIE_CHARACTER_DESC','OPENCLAW_GATEWAY_TOKEN'])" "$ROOT/install.ps1"
grep -Fq 'set_env("selfie", ["FAL_KEY", "KIE_API_KEY", "SELFIE_REFERENCE_IMAGE", "SELFIE_CHARACTER_DESC", "OPENCLAW_GATEWAY_TOKEN"])' "$ROOT/nako/scripts/merge-config.sh"
grep -Fq 'f"  - name: {yaml_quote(name)}"' "$ROOT/install.sh"
! grep -Fq 'f"  {name}:"' "$ROOT/install.sh"
grep -Fq -- '- Avatar: assets/nako-avatar-head.png' "$ROOT/nako/agent/IDENTITY.md"
test -f "$ROOT/nako/agent/assets/nako-avatar.svg"
test -f "$ROOT/nako/agent/assets/nako-avatar-head.png"
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
assert f'OPENCLAW_CONFIG = "{state / "custom-openclaw.json"}"' in cfg
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
assert "- Avatar: assets/nako-avatar-head.png" in identity_text
assert (workspace / "assets" / "nako-avatar.svg").exists()
assert (workspace / "assets" / "nako-avatar-head.png").exists()
qclaw_config = json.loads((state / "openclaw.json").read_text(encoding="utf-8"))
registered = [
    item for item in qclaw_config["agents"]["list"]
    if isinstance(item, dict) and item.get("id") == "agent-nako"
]
assert len(registered) == 1
assert registered[0]["identity"]["avatar"] == "assets/nako-avatar-head.png"
assert "vibe" not in registered[0]["identity"]
assert registered[0]["identity"]["theme"] == "核战后赛博世界专属战斗女仆"
assert registered[0]["tools"]["deny"] == ["image_generate", "video_generate", "tts"]
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
    "# IDENTITY - custom\n\n**姓名**：野木奈子\n- Avatar: https://pulseact.lovappen.cn/test/act_ci_build/dlc-promotion/act-gengen/images/e.png\n\ncustom line\n",
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
assert "- Avatar: assets/nako-avatar-head.png" in identity_text
assert (workspace / "assets" / "nako-avatar.svg").exists()
assert (workspace / "assets" / "nako-avatar-head.png").exists()
qclaw_config = json.loads((state / "openclaw.json").read_text(encoding="utf-8"))
registered = [
    item for item in qclaw_config["agents"]["list"]
    if isinstance(item, dict) and item.get("id") == "agent-nako"
]
assert len(registered) == 1
assert registered[0]["identity"]["avatar"] == "assets/nako-avatar-head.png"
assert "vibe" not in registered[0]["identity"]
assert registered[0]["identity"]["theme"] == "核战后赛博世界专属战斗女仆"
assert registered[0]["tools"]["deny"] == ["image_generate", "video_generate", "tts"]
PY
python3 - "$tmp4" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
state = root / ".qclaw-state"
session_dir = state / "agents" / "agent-nako" / "sessions"
session_dir.mkdir(parents=True, exist_ok=True)
old_session = session_dir / "env-force-session.jsonl"
old_session.write_text(
    '{"type":"session","id":"env-force-session","cwd":"test"}\n'
    '{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"old clean session"}]}}\n',
    encoding="utf-8",
)
(session_dir / "sessions.json").write_text(
    json.dumps(
        {
            "agent:agent-nako:session-cc-connect": {
                "sessionId": "env-force-session",
                "updatedAt": 1,
                "label": "cc-connect 飞书/微信",
                "systemSent": True,
                "sessionFile": str(old_session),
            }
        }
    ),
    encoding="utf-8",
)
PY
(
  cd "$tmp4"
  HOME="$tmp4" QCLAW_HOME="$tmp4/.qclaw-app" QCLAW_PERSONA_CHANGED=1 BASH_ENV="$envfile4" \
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
sessions_file = state / "agents" / "agent-nako" / "sessions" / "sessions.json"
sessions = json.loads(sessions_file.read_text(encoding="utf-8"))
entry = sessions["agent:agent-nako:session-cc-connect"]
assert entry["sessionId"] != "env-force-session"
assert entry["systemSent"] is False
assert list((state / "agents" / "agent-nako" / "sessions").glob("env-force-session.jsonl.bak-cc-connect-stale-*"))
PY

tmp5="$(mktemp -d)"
trap 'rm -rf "$tmp" "$tmp2" "$tmp3" "$tmp4" "$tmp5"' EXIT
envfile5="$tmp5/bash_env"
cat > "$envfile5" <<'EOF'
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
mkdir -p "$tmp5/bin"
cat > "$tmp5/bin/hermes" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  status) exit 0 ;;
  "acp") exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp5/bin/hermes"
mkdir -p "$tmp5/.cc-connect"
cat > "$tmp5/.cc-connect/config.toml" <<EOF
language = "en"

[[projects]]
name = "agent-test"

[projects.agent]
type = "acp"

[projects.agent.options]
work_dir = "/old"
command = "old"
args = ["old"]
env = { NAKO_AGENT_RUNTIME = "hermes" }

[[projects.platforms]]
type = "feishu"

[projects.platforms.options]
app_id = "cli_x"
app_secret = "secret_x"
enable_feishu_card = true
reply_to_trigger = true
EOF
(
  cd "$tmp5"
  HOME="$tmp5" HERMES_HOME="$tmp5/.hermes" PATH="$tmp5/bin:$PATH" BASH_ENV="$envfile5" \
    bash "$ROOT/scripts/cc-connect-setup.sh" \
      --agent-id agent-test --runtime hermes \
      --cc-connect-source skip --non-interactive >/dev/null
)
python3 - "$tmp5" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
cfg = (root / ".cc-connect" / "config.toml").read_text(encoding="utf-8")
assert '[stream_preview]' in cfg
assert 'enabled = true' in cfg
assert '[display]' in cfg
assert 'tool_messages = false' in cfg
project = re.search(r'\[\[projects\]\].*', cfg, re.S).group(0)
assert f'work_dir = "{root / ".hermes" / "workspace" / "agent-test"}"' in project
assert 'command = "' in project and "/hermes" in project
assert 'args = ["acp"]' in project
assert 'HERMES_HOME = "' in project
assert f'CC_CONNECT_DATA_DIR = "{root / ".cc-connect"}"' in project
assert f'CC_CONNECT_API_DATA_DIR = "{root / ".cc-connect" / ".cc-connect"}"' in project
assert f'CC_CONNECT_SESSION_DIR = "{root / ".cc-connect" / ".cc-connect" / "sessions"}"' in project
assert f'CC_CONNECT_CONFIG = "{root / ".cc-connect" / "config.toml"}"' in project
assert 'NAKO_OUTPUT_MODE = "acp"' in project
assert 'NAKO_CCCONNECT_PROJECT = "agent-test"' in project
assert 'NAKO_AGENT_WORKSPACE = "' in project
assert 'NAKO_SKILLS_DIR = "' in project
assert 'NAKO_MEDIA_HOME = "' in project
assert 'NAKO_AGENT_RUNTIME = "hermes"' in project
assert 'enable_feishu_card = false' in project
assert 'reply_to_trigger = false' in project
assert 'enable_feishu_card = true' not in project
assert 'reply_to_trigger = true' not in project
assert "OPENCLAW_OUTPUT_MODE" not in project
assert "OPENCLAW_CCCONNECT_PROJECT" not in project
assert ".openclaw" not in project
env = (root / ".hermes" / "workspace" / "agent-test" / "skills" / ".env").read_text(encoding="utf-8")
assert "FEISHU_APP_ID=cli_x" in env
assert "FEISHU_APP_SECRET=secret_x" in env
PY

echo "cc-connect default source checks passed"
