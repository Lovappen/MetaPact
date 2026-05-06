#!/usr/bin/env python3
import importlib.util
import json
import os
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
server_path = root / "scripts" / "nako-agent-factory" / "nako-server.py"

with tempfile.TemporaryDirectory() as tmp:
    os.environ["HOME"] = tmp
    spec = importlib.util.spec_from_file_location("nako_server", server_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)

    server_source = server_path.read_text(encoding="utf-8")
    assert "syncRuntimeControl" not in server_source
    assert "let lastState=null;" in server_source
    assert "<strong>当前后端：</strong>" in server_source
    assert "<strong>已选择：</strong>" in server_source
    assert 'Cache-Control", "no-store, max-age=0"' in server_source
    assert "def current_job_payload_for_ip" in server_source
    assert "fetch('/current')" in server_source
    assert "initializeRuntimeControl(j)" in server_source
    assert "let runtimeTouched=false;" in server_source
    assert "let desiredRuntime=null;" in server_source
    assert "const runtime=selectedRuntime();" in server_source
    assert "扫码绑定到 " in server_source
    assert "当前消息后端：" in server_source
    assert "QClaw" in server_source
    assert "qclaw_agent_configured" in server_source
    assert "消息将进入 " not in server_source
    assert "JOB_WORKER_LOCKS" in server_source
    assert "with job_worker_lock(n):" in server_source
    assert "stop_qr_processes(n)" in server_source
    assert "bound_after_install" not in server_source

    class Headers(dict):
        def get(self, name, default=None):
            for key, value in self.items():
                if key.lower() == name.lower():
                    return value
            return default

    class FakeHandler:
        def __init__(self, peer_ip, headers=None):
            self.client_address = (peer_ip, 49152)
            self.headers = Headers(headers or {})

    old_proxy_cidrs = module.TRUSTED_PROXY_CIDRS
    try:
        module.TRUSTED_PROXY_CIDRS = (
            module.ipaddress.ip_network("127.0.0.0/8"),
            module.ipaddress.ip_network("192.168.0.0/16"),
        )
        assert module.client_ip_from_request(
            FakeHandler("192.168.31.1", {"X-Forwarded-For": "192.168.31.42"})
        ) == "192.168.31.42"
        assert module.client_ip_from_request(
            FakeHandler("192.168.31.1", {"X-Forwarded-For": "127.0.0.1, 192.168.31.43"})
        ) == "192.168.31.43"
        assert module.client_ip_from_request(
            FakeHandler("192.168.31.1", {"X-Client-IP": "192.168.31.44"})
        ) == "192.168.31.44"
        assert module.client_ip_from_request(FakeHandler("203.0.113.10")) == "203.0.113.10"
    finally:
        module.TRUSTED_PROXY_CIDRS = old_proxy_cidrs

    cfg = Path(tmp) / ".cc-connect" / "config.toml"
    cfg.parent.mkdir(parents=True, exist_ok=True)
    cfg.write_text(
        """[log]
level = "info"

[[projects]]
name = "agent-nako-1"

[projects.agent]
type = "codex"

[projects.agent.options]
work_dir = "/root"
command = "codex"
args = ["exec"]
display_name = "Wrong"
env = { OPENCLAW_OUTPUT_MODE = "bad" }

[[projects.platforms]]
type = "feishu"

[projects.platforms.options]
app_id = "x"
app_secret = "y"
""",
        encoding="utf-8",
    )

    repaired = module.repair_nako_cc_projects()
    assert repaired == ["agent-nako-1"], repaired
    text = cfg.read_text(encoding="utf-8")
    assert 'type = "acp"' in text
    assert 'type = "codex"' not in text
    assert f'work_dir = "{Path(tmp) / ".openclaw"}"' in text
    assert 'command = "openclaw"' in text
    assert 'args = ["acp", "--session", "agent:agent-nako-1:main"]' in text
    assert 'display_name = "OpenClaw agent-nako-1"' in text
    assert 'OPENCLAW_CCCONNECT_PROJECT = "agent-nako-1"' in text
    assert 'NAKO_AGENT_RUNTIME = "openclaw"' in text
    openclaw_text = text

    cfg.write_text(
        """[log]
level = "info"

[[projects]]
name = "agent-nako-3"

[projects.agent]
type = "codex"

[projects.agent.options]
work_dir = "/wrong"
command = "hermes"
args = ["bad"]
display_name = "Wrong"
env = { HERMES_HOME = "/tmp/hermes", NAKO_AGENT_RUNTIME = "hermes" }

[[projects.platforms]]
type = "feishu"

[projects.platforms.options]
app_id = "x"
app_secret = "y"
""",
        encoding="utf-8",
    )
    repaired = module.repair_nako_cc_projects()
    assert repaired == ["agent-nako-3"], repaired
    text = cfg.read_text(encoding="utf-8")
    assert 'command = "openclaw"' not in text
    assert 'args = ["acp"]' in text
    assert 'display_name = "Hermes agent-nako-3"' in text
    assert 'HERMES_HOME' in text
    assert 'NAKO_AGENT_RUNTIME = "hermes"' in text

    old_qclaw_node = os.environ.get("QCLAW_NODE_BIN")
    old_qclaw_mjs = os.environ.get("QCLAW_OPENCLAW_MJS")
    os.environ["QCLAW_NODE_BIN"] = "/opt/QClaw/node"
    os.environ["QCLAW_OPENCLAW_MJS"] = "/opt/QClaw/openclaw.mjs"
    try:
        cfg.write_text(
            """[log]
level = "info"

[[projects]]
name = "agent-nako-5"

[projects.agent]
type = "codex"

[projects.agent.options]
work_dir = "/wrong"
command = "openclaw"
args = ["bad"]
display_name = "Wrong"
env = { NAKO_AGENT_RUNTIME = "qclaw" }

[[projects.platforms]]
type = "feishu"

[projects.platforms.options]
app_id = "x"
app_secret = "y"
""",
            encoding="utf-8",
        )
        repaired = module.repair_nako_cc_projects()
        assert repaired == ["agent-nako-5"], repaired
        text = cfg.read_text(encoding="utf-8")
        assert 'command = "/opt/QClaw/node"' in text
        assert 'args = ["/opt/QClaw/openclaw.mjs", "acp", "--session", "agent:agent-nako-5:session-cc-connect"]' in text
        assert 'display_name = "QClaw agent-nako-5"' in text
        assert f'work_dir = "{Path(tmp) / ".qclaw" / "workspace-agent-nako-5"}"' in text
        assert 'OPENCLAW_STATE_DIR' in text
        assert 'OPENCLAW_CONFIG_PATH' in text
        assert 'NAKO_AGENT_RUNTIME = "qclaw"' in text
    finally:
        if old_qclaw_node is None:
            os.environ.pop("QCLAW_NODE_BIN", None)
        else:
            os.environ["QCLAW_NODE_BIN"] = old_qclaw_node
        if old_qclaw_mjs is None:
            os.environ.pop("QCLAW_OPENCLAW_MJS", None)
        else:
            os.environ["QCLAW_OPENCLAW_MJS"] = old_qclaw_mjs

    cfg.write_text(
        """[log]
level = "info"

[[projects]]
name = "agent-nako-4"

[projects.agent]
type = "acp"

[projects.agent.options]
work_dir = "/root/.hermes/workspace/agent-nako-4"
command = "/home/openclaw.linux/.local/bin/hermes"
args = ["acp"]
display_name = "Hermes agent-nako-4"
env = { HERMES_HOME = "/root/.hermes", NAKO_AGENT_RUNTIME = "hermes" }

[[projects.platforms]]
type = "feishu"

[projects.platforms.options]
app_id = "x"
app_secret = "y"
""",
        encoding="utf-8",
    )
    (module.JOB_DIR / "agent-nako-4.json").write_text(
        json.dumps(
            {
                "id": 4,
                "status": "ready",
                "agent_id": "agent-nako-4",
                "runtime": "openclaw",
                "cc_reload_platforms": ["feishu"],
            }
        ),
        encoding="utf-8",
    )
    payload = module.status_payload(4)
    assert payload["runtime"] == "hermes"
    assert payload["platform_runtimes"]["feishu"] == "openclaw"
    assert payload["platform_runtime_labels"]["feishu"] == "OpenClaw"
    module.save_ip_index({"198.51.100.4": 4})
    n, existing, _ = module.create_or_get_job_for_ip("198.51.100.4", "hermes")
    assert (n, existing) == (4, True)
    preserved = module.job_state(4)
    assert preserved["runtime"] == "openclaw"
    assert preserved["platform_runtimes"]["feishu"] == "openclaw"

    cfg.write_text(
        openclaw_text
        + """

[[projects.platforms]]
type = "weixin"

[projects.platforms.options]
token = "token"
base_url = "https://ilinkai.weixin.qq.com"

[[projects]]
name = "agent-nako-2"

[projects.agent]
type = "acp"

[[projects.platforms]]
type = "weixin"

[projects.platforms.options]
token = "keep-other"
""",
        encoding="utf-8",
    )
    assert module.remove_platform_binding_for_agent("agent-nako-1", "feishu")
    text = cfg.read_text(encoding="utf-8")
    agent_1 = text.split('[[projects]]\nname = "agent-nako-2"', 1)[0]
    assert 'type = "feishu"' not in agent_1
    assert 'type = "weixin"' in agent_1
    assert 'keep-other' in text
    assert not module.remove_platform_binding_for_agent("agent-nako-1", "feishu")

    cc_sessions = cfg.parent / "sessions" / "agent-nako-1_abc.json"
    cc_sessions.parent.mkdir(parents=True, exist_ok=True)
    cc_sessions.write_text(
        """{
  "sessions": {
    "s1": {"id": "s1"},
    "s2": {"id": "s2"}
  },
  "active_session": {
    "feishu:chat:user": "s1",
    "weixin:dm:user": "s2"
  },
  "user_sessions": {
    "feishu:chat:user": ["s1"],
    "weixin:dm:user": ["s2"]
  },
  "user_meta": {
    "feishu:chat:user": {"name": "feishu"},
    "weixin:dm:user": {"name": "weixin"}
  }
}
""",
        encoding="utf-8",
    )
    removed_sessions = module.reset_cc_connect_sessions_for_platform("agent-nako-1", "feishu")
    assert removed_sessions == ["s1"], removed_sessions
    data = json.loads(cc_sessions.read_text(encoding="utf-8"))
    assert "s1" not in data["sessions"]
    assert "s2" in data["sessions"]
    assert "feishu:chat:user" not in data["active_session"]
    assert data["active_session"]["weixin:dm:user"] == "s2"

    node_modules = Path(tmp) / ".openclaw" / "plugin-runtime-deps" / "openclaw-test" / "node_modules"
    stale = node_modules / ".semver-8C7644GC"
    keep_bin = node_modules / ".bin"
    keep_pkg_lock = node_modules / ".package-lock.json"
    stale_bin = keep_bin / ".semver-7WrXNAsk"
    scoped = node_modules / "@larksuiteoapi"
    stale_scoped = scoped / ".node-sdk-cLSqwXE4"
    stale.mkdir(parents=True)
    keep_bin.mkdir()
    scoped.mkdir()
    stale_scoped.mkdir()
    stale_bin.write_text("stale", encoding="utf-8")
    keep_pkg_lock.write_text("{}", encoding="utf-8")

    removed = module.cleanup_openclaw_npm_rename_temps()
    assert str(stale) in removed
    assert str(stale_bin) in removed
    assert str(stale_scoped) in removed
    assert not stale.exists()
    assert not stale_bin.exists()
    assert not stale_scoped.exists()
    assert keep_bin.exists()
    assert scoped.exists()
    assert keep_pkg_lock.exists()

    assert module.is_cc_connect_main_args("cc-connect")
    assert module.is_cc_connect_main_args("/usr/local/bin/cc-connect")
    assert module.is_cc_connect_main_args("node /usr/local/bin/cc-connect")
    assert module.is_cc_connect_main_args("/usr/local/bin/cc-connect --force")
    assert not module.is_cc_connect_main_args("grep cc-connect")

    assert module.is_openclaw_gateway_args("openclaw gateway run --port 18789")
    assert module.is_openclaw_gateway_args("node /usr/lib/node_modules/openclaw/openclaw.mjs gateway run --port 18789")
    assert not module.is_openclaw_gateway_args("openclaw acp --session agent:agent-nako-1:main")

    fake_bin = Path(tmp) / "bin"
    fake_bin.mkdir()
    fake_curl = fake_bin / "curl"
    fake_curl.write_text("#!/bin/sh\nprintf 'exit 7\\n'\n", encoding="utf-8")
    fake_curl.chmod(0o755)
    old_urls = module.INSTALL_URLS
    try:
        module.INSTALL_URLS = ("https://example.test/install.sh",)
        env = os.environ.copy()
        env["PATH"] = f"{fake_bin}:{env.get('PATH', '')}"
        rc = subprocess.run(
            ["bash", "-c", module.agent_install_command("agent-nako-1")],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        ).returncode
        assert rc == 7, rc
    finally:
        module.INSTALL_URLS = old_urls

    local_installer = Path(tmp) / "installer.sh"
    local_args = Path(tmp) / "installer.args"
    local_installer.write_text(
        f"#!/bin/sh\nprintf '%s\\n' \"$*\" > {local_args}\nexit 0\n",
        encoding="utf-8",
    )
    local_installer.chmod(0o755)
    try:
        module.INSTALL_URLS = (f"file://{local_installer}",)
        rc = subprocess.run(
            ["bash", "-c", module.agent_install_command("agent-nako-9", "hermes")],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        ).returncode
        assert rc == 0, rc
        assert "--runtime hermes" in local_args.read_text(encoding="utf-8")
    finally:
        module.INSTALL_URLS = old_urls

    openclaw_cfg = Path(tmp) / ".openclaw" / "openclaw.json"
    openclaw_cfg.parent.mkdir(parents=True, exist_ok=True)
    openclaw_cfg.write_text(
        """{
  "agents": {
    "list": [
      {
        "id": "agent-nako-1",
        "name": "agent-nako-1",
        "workspace": "/Users/openclaw/.openclaw/workspace/agent-nako-1",
        "agentDir": "/Users/openclaw/.openclaw/agents/agent-nako-1/agent"
      }
    ]
  }
}
""",
        encoding="utf-8",
    )
    assert not module.openclaw_agent_configured("agent-nako-1")
    assert module.agent_install_needed("agent-nako-1", {"install_rc": 0})
    openclaw_cfg.write_text(
        """{
  "agents": {
    "list": [
      {
        "id": "agent-nako-1",
        "name": "agent-nako-1",
        "workspace": "%s",
        "agentDir": "%s"
      }
    ]
  }
}
"""
        % (
            Path(tmp) / ".openclaw" / "workspace" / "agent-nako-1",
            Path(tmp) / ".openclaw" / "agents" / "agent-nako-1" / "agent",
        ),
        encoding="utf-8",
    )
    assert module.openclaw_agent_configured("agent-nako-1")
    assert not module.agent_install_needed("agent-nako-1", {"install_rc": 0})

    qclaw_cfg = Path(tmp) / ".qclaw" / "openclaw.json"
    qclaw_workspace = Path(tmp) / ".qclaw" / "workspace-agent-nako-1"
    qclaw_agent_dir = Path(tmp) / ".qclaw" / "agents" / "agent-nako-1" / "agent"
    qclaw_workspace.mkdir(parents=True, exist_ok=True)
    qclaw_agent_dir.mkdir(parents=True, exist_ok=True)
    (qclaw_workspace / "AGENTS.md").write_text("agent", encoding="utf-8")
    qclaw_cfg.write_text(
        json.dumps(
            {
                "agents": {
                    "list": [
                        {
                            "id": "agent-nako-1",
                            "workspace": str(qclaw_workspace),
                            "agentDir": str(qclaw_agent_dir),
                        }
                    ]
                }
            }
        ),
        encoding="utf-8",
    )
    assert module.qclaw_agent_configured("agent-nako-1")

    sessions_file = Path(tmp) / ".openclaw" / "agents" / "agent-nako-1" / "sessions" / "sessions.json"
    sessions_file.parent.mkdir(parents=True, exist_ok=True)
    sessions_file.write_text(
        """{
  "agent:agent-nako-1:main": {"sessionId": "main-session"},
  "agent:agent-nako-1:cron:x": {"sessionId": "cron-session"}
}
""",
        encoding="utf-8",
    )
    assert module.reset_openclaw_main_session("agent-nako-1") == "main-session"
    data = json.loads(sessions_file.read_text(encoding="utf-8"))
    assert "agent:agent-nako-1:main" not in data
    assert "agent:agent-nako-1:cron:x" in data

    parsed = module.parse_first_json_object("warning before json\n{\"pending\": []}\n")
    assert parsed == {"pending": []}

    requests = module.select_local_openclaw_device_repair_requests(
        {
            "pending": [
                {
                    "requestId": "repair-1",
                    "deviceId": "device-1",
                    "isRepair": True,
                    "clientId": "cli",
                    "clientMode": "cli",
                },
                {
                    "requestId": "new-device",
                    "deviceId": "device-2",
                    "isRepair": False,
                    "clientId": "cli",
                    "clientMode": "cli",
                },
                {
                    "requestId": "webchat",
                    "deviceId": "device-1",
                    "isRepair": True,
                    "clientId": "openclaw-control-ui",
                    "clientMode": "webchat",
                },
            ]
        },
        "device-1",
    )
    assert requests == ["repair-1"], requests

print("nako factory repair checks passed")
