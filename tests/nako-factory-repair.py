#!/usr/bin/env python3
import importlib.util
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
