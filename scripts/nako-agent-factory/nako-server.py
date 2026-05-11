#!/usr/bin/env python3
"""
Nako agent factory — LAN HTTP service to provision new nako agents on demand.

Endpoints:
  GET  /                  → simple HTML page
  POST /create            → alloc next agent-nako-N, install, return QR URLs
  GET  /status?id=N       → progress + QR + recent log for agent-nako-N
  GET  /log?id=N          → full text log for agent-nako-N
  GET  /qr?id=N&platform= → returns QR image file (feishu|weixin)

Deps: only Python 3 stdlib + the host's openclaw/cc-connect/curl/bash.

Listen: 0.0.0.0:8088 (override with NAKO_SERVER_PORT env).
"""
import http.server, socketserver, json, os, re, socket, subprocess, threading, time, urllib.parse, fcntl, ipaddress, shutil, shlex
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4
try:
    import tomllib
except ImportError:
    tomllib = None

PORT       = int(os.environ.get("NAKO_SERVER_PORT", 8088))
HOME       = Path(os.path.expanduser("~"))
COUNTER    = HOME / ".nako-counter"
AGENTS_REF = os.environ.get("NAKO_AGENTS_REF", "main")
DEFAULT_INSTALL_URLS = (
    f"https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@{AGENTS_REF}/install.sh",
    f"https://raw.githubusercontent.com/Lovappen/MetaPact/{AGENTS_REF}/install.sh",
)
INSTALL_URLS = tuple(
    item.strip()
    for item in os.environ.get(
        "NAKO_AGENT_INSTALL_URLS",
        os.environ.get("NAKO_AGENT_INSTALL_URL", " ".join(DEFAULT_INSTALL_URLS)),
    ).split()
    if item.strip()
)
INSTALL_URL= INSTALL_URLS[0] if INSTALL_URLS else DEFAULT_INSTALL_URLS[0]
JOB_DIR    = HOME / ".nako-jobs"
IP_INDEX   = JOB_DIR / "ip-index.json"
CC_CONFIG  = HOME / ".cc-connect/config.toml"
LOG_TAIL_BYTES = int(os.environ.get("NAKO_LOG_TAIL_BYTES", "30000"))
JOB_DIR.mkdir(exist_ok=True)
QR_PLATFORMS = ("feishu", "weixin")
RUNTIMES = ("openclaw", "hermes", "qclaw")
FACTORY_BINDING_RUNTIMES = ("openclaw", "hermes")
QCLAW_CC_SESSION_SUFFIX = "session-cc-connect"
DEFAULT_RUNTIME = os.environ.get("NAKO_AGENT_RUNTIME", "openclaw").strip().lower()
if DEFAULT_RUNTIME not in FACTORY_BINDING_RUNTIMES:
    DEFAULT_RUNTIME = "openclaw"
OPENCLAW_GATEWAY_PORT = int(os.environ.get("OPENCLAW_GATEWAY_PORT", "18789"))
OPENCLAW_GATEWAY_HEAP_MB = os.environ.get("OPENCLAW_GATEWAY_HEAP_MB", "2048")
OPENCLAW_WATCHDOG_INTERVAL = int(os.environ.get("NAKO_GATEWAY_WATCHDOG_INTERVAL", "10"))
NPM_RENAME_TMP_RE = re.compile(r"^\.[^/]+-[A-Za-z0-9]{6,}$")
DEFAULT_TRUSTED_PROXY_CIDRS = (
    "127.0.0.0/8,::1/128,"
    "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,"
    "169.254.0.0/16,fc00::/7,fe80::/10"
)
TRUSTED_PROXY_CIDRS = tuple(
    ipaddress.ip_network(c.strip())
    for c in os.environ.get("NAKO_TRUSTED_PROXY_CIDRS", DEFAULT_TRUSTED_PROXY_CIDRS).split(",")
    if c.strip()
)

LOCK = threading.RLock()
QR_PROCS = {}
JOB_GENERATIONS = {}
JOB_WORKER_LOCKS = {}
CC_RESTART_LOCK = threading.RLock()
CC_RESTART_TIMER = None
OPENCLAW_GATEWAY_LOCK = threading.RLock()


def alloc_id() -> int:
    """Atomic increment of the counter file."""
    with LOCK:
        n = 0
        if COUNTER.exists():
            try: n = int(COUNTER.read_text().strip() or "0")
            except: n = 0
        n += 1
        COUNTER.write_text(str(n))
        return n


def load_ip_index() -> dict:
    if not IP_INDEX.exists():
        return {}
    try:
        data = json.loads(IP_INDEX.read_text())
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_ip_index(index: dict):
    IP_INDEX.write_text(json.dumps(index, ensure_ascii=False, indent=2))


def parse_ip(value: str):
    if not value:
        return None
    value = value.strip().strip('"').strip("'")
    if value.lower() == "unknown" or value.startswith("_"):
        return None
    if value.startswith("[") and "]" in value:
        value = value[1:value.index("]")]
    elif value.count(":") == 1 and "." in value:
        value = value.split(":", 1)[0]
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        return None


def usable_client_ip(value: str) -> bool:
    try:
        ip = ipaddress.ip_address(value)
    except ValueError:
        return False
    return not (ip.is_unspecified or ip.is_loopback or ip.is_multicast)


def trusted_proxy(peer_ip: str) -> bool:
    try:
        ip = ipaddress.ip_address(peer_ip)
    except ValueError:
        return False
    return any(ip in net for net in TRUSTED_PROXY_CIDRS)


def forwarded_header_ip(headers):
    xff = headers.get("X-Forwarded-For")
    if xff:
        for part in xff.split(","):
            ip = parse_ip(part)
            if ip and usable_client_ip(ip):
                return ip

    for name in (
        "X-Real-IP",
        "X-Client-IP",
        "X-Forwarded",
        "X-Cluster-Client-IP",
        "X-Original-Forwarded-For",
        "X-Remote-IP",
        "X-Remote-Addr",
        "CF-Connecting-IP",
        "True-Client-IP",
    ):
        ip = parse_ip(headers.get(name))
        if ip and usable_client_ip(ip):
            return ip

    forwarded = headers.get("Forwarded")
    if forwarded:
        for entry in forwarded.split(","):
            for part in entry.split(";"):
                key, sep, val = part.strip().partition("=")
                if sep and key.lower() == "for":
                    ip = parse_ip(val)
                    if ip and usable_client_ip(ip):
                        return ip
    return None


def client_ip_from_request(handler) -> str:
    peer_ip = parse_ip(handler.client_address[0]) or handler.client_address[0]
    if trusted_proxy(peer_ip):
        return forwarded_header_ip(handler.headers) or peer_ip
    return peer_ip


def ensure_cc_connect_config():
    if CC_CONFIG.exists():
        normalize_cc_global_options()
        return
    CC_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CC_CONFIG.write_text(
        'language = "en"\n\n'
        '[stream_preview]\nenabled = true\n\n'
        '[display]\ntool_messages = false\n\n'
        '[log]\nlevel = "info"\n'
    )
    os.chmod(CC_CONFIG, 0o600)


def normalize_cc_global_options() -> bool:
    """Keep cc-connect global defaults consistent for chat channels."""
    if not CC_CONFIG.exists():
        return False
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return False

    project_match = re.search(r"(?m)^\[\[projects\]\]\s*$", text)
    prefix_end = project_match.start() if project_match else len(text)
    prefix = text[:prefix_end]
    rest = text[prefix_end:]

    def ensure_section_value(src: str, section: str, key: str, value: str) -> str:
        match = re.search(
            rf"(?ms)(^\[{re.escape(section)}\]\s*\n)(.*?)(?=^\[|\Z)",
            src,
        )
        if match:
            body = match.group(2)
            if re.search(rf"(?m)^{re.escape(key)}\s*=", body):
                body = re.sub(rf"(?m)^{re.escape(key)}\s*=.*$", f"{key} = {value}", body)
            else:
                body = f"{key} = {value}\n" + body
            return src[:match.start(2)] + body + src[match.end(2):]
        if src and not src.endswith("\n"):
            src += "\n"
        return src + f"\n[{section}]\n{key} = {value}\n"

    prefix = ensure_section_value(prefix, "stream_preview", "enabled", "true")
    prefix = ensure_section_value(prefix, "display", "tool_messages", "false")

    new_text = prefix + rest
    if new_text == text:
        return False
    try:
        backup = CC_CONFIG.parent / f"config.toml.bak-global-options-{time.strftime('%Y%m%d-%H%M%S')}"
        backup.write_text(text, encoding="utf-8")
        CC_CONFIG.write_text(new_text, encoding="utf-8")
        os.chmod(CC_CONFIG, 0o600)
        return True
    except Exception:
        return False


def agent_id_for(n: int) -> str:
    return f"agent-nako-{n}"


def normalize_runtime(value: str) -> str:
    value = (value or "").strip().lower()
    return value if value in RUNTIMES else DEFAULT_RUNTIME


def normalize_factory_runtime(value: str) -> str:
    value = (value or "").strip().lower()
    return value if value in FACTORY_BINDING_RUNTIMES else DEFAULT_RUNTIME


def qclaw_script_binding_error() -> dict:
    return {
        "error": "qclaw_script_binding_only",
        "message": (
            "QClaw 不能通过 Nako Agent Factory 网页绑定；"
            "请在同一 host/user 下运行 scripts/cc-connect-setup.sh --runtime qclaw 做脚本绑定。"
        ),
    }


def factory_runtime_or_error(value: str, fallback: str = None):
    requested = (value or "").strip().lower() or normalize_runtime(fallback or DEFAULT_RUNTIME)
    if requested == "qclaw":
        return "", qclaw_script_binding_error()
    if requested in FACTORY_BINDING_RUNTIMES:
        return requested, None
    return normalize_factory_runtime(DEFAULT_RUNTIME), None


def runtime_label(runtime: str) -> str:
    if runtime == "hermes":
        return "Hermes"
    if runtime == "qclaw":
        return "QClaw"
    return "OpenClaw"


def normalized_platform_runtimes(state: dict, bound: set, fallback_runtime: str) -> dict:
    fallback_runtime = normalize_runtime(fallback_runtime)
    return {
        plat: fallback_runtime
        for plat in sorted(bound)
        if plat in QR_PLATFORMS
    }


def hermes_home() -> Path:
    return Path(os.environ.get("HERMES_HOME", str(HOME / ".hermes"))).expanduser()


def hermes_workspace(aid: str) -> Path:
    return hermes_home() / "workspace" / aid


def openclaw_workspace(aid: str) -> Path:
    return HOME / ".openclaw" / "workspace" / aid


def hermes_agent_roots() -> list:
    roots = [hermes_home() / "hermes-agent", HOME / ".hermes/hermes-agent"]
    home_root = Path("/home")
    if home_root.exists():
        try:
            roots.extend(sorted(home_root.glob("*/.hermes/hermes-agent")))
        except Exception:
            pass
    seen = set()
    result = []
    for root in roots:
        key = str(root)
        if key in seen:
            continue
        seen.add(key)
        result.append(root)
    return result


def ensure_hermes_venv_launcher() -> str:
    for root in hermes_agent_roots():
        candidate = root / "venv/bin/hermes"
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
        python = root / "venv/bin/python"
        script = root / "hermes"
        if not (python.exists() and os.access(python, os.X_OK) and script.exists()):
            continue
        wrapper = hermes_home() / "bin/hermes"
        try:
            wrapper.parent.mkdir(parents=True, exist_ok=True)
            wrapper.write_text(f'#!/bin/sh\nexec "{python}" "{script}" "$@"\n', encoding="utf-8")
            wrapper.chmod(0o755)
            return str(wrapper)
        except Exception:
            continue
    return ""


def hermes_command(env: dict = None) -> str:
    configured = os.environ.get("HERMES_BIN")
    if configured:
        return configured
    candidate = HOME / ".local/bin/hermes"
    if candidate.exists():
        return str(candidate)
    found = shutil.which("hermes", path=(env or tool_env()).get("PATH"))
    if found:
        return found
    launcher = ensure_hermes_venv_launcher()
    return launcher or "hermes"


def resolve_path(value: str) -> Path:
    return Path(os.path.expanduser(str(value))).resolve()


def qclaw_base_home() -> Path:
    return resolve_path(os.environ.get("QCLAW_HOME", str(HOME / ".qclaw")))


def load_qclaw_app_config(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def qclaw_home() -> Path:
    base = qclaw_base_home()
    data = load_qclaw_app_config(base / "qclaw.json")
    state_dir = data.get("stateDir")
    if isinstance(state_dir, str) and state_dir:
        return resolve_path(state_dir)
    return base


def qclaw_config_path() -> Path:
    configured = os.environ.get("QCLAW_OPENCLAW_CONFIG") or os.environ.get("OPENCLAW_CONFIG_PATH")
    if configured:
        return resolve_path(configured)
    base = qclaw_base_home()
    data = load_qclaw_app_config(base / "qclaw.json")
    qhome = qclaw_home()
    if qhome != base:
        state_data = load_qclaw_app_config(qhome / "qclaw.json")
        data = state_data or data
    config_path = data.get("configPath")
    if isinstance(config_path, str) and config_path:
        return resolve_path(config_path)
    return qhome / "openclaw.json"


def gateway_auth_token(config_path: Path) -> str:
    try:
        data = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception:
        return ""
    gateway = data.get("gateway") if isinstance(data.get("gateway"), dict) else {}
    auth = gateway.get("auth") if isinstance(gateway.get("auth"), dict) else {}
    token = auth.get("token")
    return token if isinstance(token, str) and token else ""


def qclaw_app_config_path() -> Path:
    qhome = qclaw_home()
    path = qhome / "qclaw.json"
    if path.exists():
        return path
    return qclaw_base_home() / "qclaw.json"


def qclaw_workspace(aid: str) -> Path:
    return qclaw_home() / f"workspace-{aid}"


def qclaw_app_config() -> dict:
    return load_qclaw_app_config(qclaw_app_config_path())


def qclaw_node_binary(env: dict = None) -> str:
    configured = os.environ.get("QCLAW_NODE_BIN")
    if configured:
        return configured
    cli = qclaw_app_config().get("cli") or {}
    if isinstance(cli, dict) and cli.get("nodeBinary"):
        return str(cli["nodeBinary"])
    mac_node = Path("/Applications/QClaw.app/Contents/Resources/node/node")
    if mac_node.exists():
        return str(mac_node)
    found = shutil.which("node", path=(env or tool_env()).get("PATH"))
    return found or "node"


def qclaw_openclaw_mjs() -> str:
    configured = os.environ.get("QCLAW_OPENCLAW_MJS")
    if configured:
        return configured
    cli = qclaw_app_config().get("cli") or {}
    if isinstance(cli, dict) and cli.get("openclawMjs"):
        return str(cli["openclawMjs"])
    return str(HOME / "Library/Application Support/QClaw/openclaw/node_modules/openclaw/openclaw.mjs")


def toml_quote(value) -> str:
    return json.dumps(str(value), ensure_ascii=False)


def toml_array(values) -> str:
    return "[" + ", ".join(toml_quote(v) for v in values) + "]"


def toml_inline_table(items) -> str:
    return "{ " + ", ".join(f"{k} = {toml_quote(v)}" for k, v in items.items()) + " }"


def job_state(n: int) -> dict:
    p = JOB_DIR / f"agent-nako-{n}.json"
    if not p.exists(): return {"id": n, "status": "unknown"}
    try: return json.loads(p.read_text())
    except: return {"id": n, "status": "corrupt"}


def log_path_for(n: int) -> Path:
    aid = job_state(n).get("agent_id") or f"agent-nako-{n}"
    return JOB_DIR / f"{aid}.log"


def read_log_tail(n: int, max_bytes: int = LOG_TAIL_BYTES) -> str:
    p = log_path_for(n)
    if not p.exists():
        return ""
    with p.open("rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        f.seek(max(0, size - max_bytes), os.SEEK_SET)
        data = f.read()
    return data.decode("utf-8", errors="replace")


def yaml_unquote(value: str) -> str:
    value = (value or "").strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def read_yaml_top_map(path: Path, key: str) -> dict:
    if not path.exists():
        return {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except Exception:
        return {}

    block = {}
    in_block = False
    for line in lines:
        if not in_block:
            if line.strip() == f"{key}:" and not line.startswith((" ", "\t")):
                in_block = True
            continue
        if line and not line.startswith((" ", "\t")):
            break
        m = re.match(r"^\s+([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$", line)
        if m:
            block[m.group(1)] = yaml_unquote(m.group(2))
    return block


def env_file_values(path: Path) -> dict:
    if not path.exists():
        return {}
    values = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except Exception:
        return values
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = yaml_unquote(value.strip())
    return values


def hermes_model_info() -> dict:
    model = read_yaml_top_map(hermes_home() / "config.yaml", "model")
    provider = model.get("provider") or ""
    default = model.get("default") or model.get("model") or ""
    if not provider and not default:
        return {}

    provider_key = provider.upper().replace("-", "_") if provider else ""
    api_key_candidates = []
    if provider_key:
        api_key_candidates.append(f"{provider_key}_API_KEY")
    if provider == "zai":
        api_key_candidates.append("GLM_API_KEY")

    env_values = env_file_values(hermes_home() / ".env")
    api_key_env = next((k for k in api_key_candidates if env_values.get(k)), api_key_candidates[0] if api_key_candidates else "")
    return {
        "runtime": "hermes",
        "source": str(hermes_home() / "config.yaml"),
        "provider": provider,
        "model": default,
        "label": f"{provider}/{default}" if provider and default else (default or provider),
        "base_url": model.get("base_url") or model.get("baseUrl") or "",
        "api_mode": model.get("api_mode") or "",
        "api_key_env": api_key_env,
        "api_key_configured": bool(api_key_env and env_values.get(api_key_env)),
    }


def openclaw_model_info(aid: str) -> dict:
    cfg_path = HOME / ".openclaw/openclaw.json"
    if not cfg_path.exists():
        return {}
    try:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        return {}

    agents = cfg.get("agents") if isinstance(cfg.get("agents"), dict) else {}
    primary = ""
    for item in agents.get("list", []) or []:
        if not isinstance(item, dict) or item.get("id") != aid:
            continue
        model = item.get("model") if isinstance(item.get("model"), dict) else {}
        primary = model.get("primary") or ""
        break
    if not primary:
        defaults = agents.get("defaults") if isinstance(agents.get("defaults"), dict) else {}
        model = defaults.get("model") if isinstance(defaults.get("model"), dict) else {}
        primary = model.get("primary") or ""
    if not primary:
        return {}

    provider, _, model = primary.partition("/")
    if not model:
        provider, model = "", provider

    providers = ((cfg.get("models") or {}).get("providers") or {}) if isinstance(cfg.get("models"), dict) else {}
    provider_cfg = providers.get(provider) if provider else {}
    provider_cfg = provider_cfg if isinstance(provider_cfg, dict) else {}
    return {
        "runtime": "openclaw",
        "source": str(cfg_path),
        "provider": provider,
        "model": model,
        "label": primary,
        "base_url": provider_cfg.get("baseUrl") or provider_cfg.get("base_url") or "",
        "api_mode": provider_cfg.get("api") or "",
        "api_key_env": "",
        "api_key_configured": False,
    }


def runtime_model_state_fields(aid: str, runtime: str) -> dict:
    runtime = normalize_runtime(runtime)
    info = hermes_model_info() if runtime == "hermes" else openclaw_model_info(aid) if runtime == "openclaw" else {}
    return {
        "model_info": info,
        "model_provider": info.get("provider") or "",
        "model_default": info.get("model") or "",
        "model_base_url": info.get("base_url") or "",
        "model_api_mode": info.get("api_mode") or "",
        "model_label": info.get("label") or "",
        "model_source": info.get("source") or "",
        "model_api_key_env": info.get("api_key_env") or "",
        "model_api_key_configured": bool(info.get("api_key_configured")),
    }


def status_payload(n: int) -> dict:
    state = job_state(n)
    persisted_state = dict(state)
    aid = state.get("agent_id") or agent_id_for(n)
    stored_runtime = normalize_runtime(state.get("runtime"))
    runtime = stored_runtime
    configured_runtime = cc_project_runtime(aid)
    if configured_runtime in RUNTIMES and state.get("status") not in ("queued", "installing", "generating_qr"):
        runtime = configured_runtime
    if state.get("status") not in ("unknown", "corrupt"):
        state.setdefault("agent_id", aid)
        state.setdefault("runtime", runtime)

    bound = bound_platforms_for_agent(aid)
    platform_runtimes = normalized_platform_runtimes(state, bound, runtime)
    state["bound_platforms"] = sorted(bound)
    state["unbound_platforms"] = [plat for plat in QR_PLATFORMS if plat not in bound]
    state["runtime"] = runtime
    state["runtime_label"] = runtime_label(runtime)
    state["platform_runtimes"] = platform_runtimes
    state["platform_runtime_labels"] = {
        plat: runtime_label(value) for plat, value in platform_runtimes.items()
    }
    state["openclaw_agent_configured"] = openclaw_agent_configured(aid)
    state["hermes_agent_configured"] = hermes_agent_configured(aid)
    state["qclaw_agent_configured"] = qclaw_agent_configured(aid)
    state["active_runtime_configured"] = {
        "hermes": state["hermes_agent_configured"],
        "qclaw": state["qclaw_agent_configured"],
    }.get(runtime, state["openclaw_agent_configured"])
    model_fields = runtime_model_state_fields(aid, runtime)
    state.update(model_fields)
    with LOCK:
        active_qr = any(proc.poll() is None for proc in QR_PROCS.get(n, []))
    if state.get("status") == "awaiting_scan" and not active_qr:
        next_status = "qr_expired" if state["unbound_platforms"] else "ready"
        state["status"] = next_status
        state["qr_refresh_in_progress"] = False
        write_state(n, status=next_status, qr_refresh_in_progress=False)
    requested = set(state.get("cc_reload_platforms") or [])
    state_updates = {}
    if state.get("status") not in ("unknown", "corrupt") and persisted_state.get("runtime") != runtime:
        state_updates["runtime"] = runtime
    if bound and persisted_state.get("platform_runtimes") != platform_runtimes:
        state_updates["platform_runtimes"] = platform_runtimes
    for key, value in model_fields.items():
        if persisted_state.get(key) != value:
            state_updates[key] = value
    if state_updates:
        write_state(n, **state_updates)
    if bound and bound != requested:
        schedule_reload_for_bound_platforms(
            n, bound, tool_env(), reason=f"{aid}:status-bound-{','.join(sorted(bound))}"
        )

    for plat in QR_PLATFORMS:
        p = JOB_DIR / f"{aid}-{plat}.png"
        if p.exists():
            state[f"{plat}_qr_image"] = f"/qr?id={n}&platform={plat}&v={int(p.stat().st_mtime)}"

    p = log_path_for(n)
    if p.exists():
        state["log_url"] = f"/log?id={n}"
        state["log_tail"] = read_log_tail(n)
    return state


def write_state(n: int, **kv):
    with LOCK:
        JOB_DIR.mkdir(exist_ok=True)
        p = JOB_DIR / f"agent-nako-{n}.json"
        cur = job_state(n)
        cur.update(kv)
        cur["id"] = n
        p.write_text(json.dumps(cur, ensure_ascii=False, indent=2))


def valid_secret(value) -> bool:
    if not isinstance(value, str):
        return bool(value)
    value = value.strip()
    return bool(value) and not value.startswith("your-")


def cc_project_names(prefix: str = "agent-nako-") -> list:
    if not CC_CONFIG.exists():
        return []
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return []

    names = []
    for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
        if not part.startswith("[[projects]]"):
            continue
        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        name = name_match.group(1) if name_match else ""
        if name and (not prefix or name.startswith(prefix)):
            names.append(name)
    return names


def cc_project_has_platforms(part: str) -> bool:
    return re.search(r"(?m)^\[\[projects\.platforms\]\]\s*$", part) is not None


def bound_platforms_for_agent(aid: str) -> set:
    if tomllib is None or not CC_CONFIG.exists():
        return set()
    try:
        data = tomllib.loads(CC_CONFIG.read_text(encoding="utf-8"))
    except Exception:
        return set()

    bound = set()
    for project in data.get("projects", []) or []:
        if project.get("name") != aid:
            continue
        for platform in project.get("platforms", []) or []:
            ptype = platform.get("type")
            opts = platform.get("options", {}) or {}
            if ptype in ("feishu", "lark"):
                if valid_secret(opts.get("app_id")) and valid_secret(opts.get("app_secret")):
                    bound.add("feishu")
            elif ptype == "weixin":
                if valid_secret(opts.get("token")):
                    bound.add("weixin")
    return bound


def unbound_platforms_for_agent(aid: str) -> list:
    bound = bound_platforms_for_agent(aid)
    return [plat for plat in QR_PLATFORMS if plat not in bound]


def cc_platform_types(platform: str) -> set:
    if platform == "feishu":
        return {"feishu", "lark"}
    return {platform}


def remove_platform_binding_for_agent(aid: str, platform: str) -> bool:
    """Remove one cc-connect platform binding from one project.

    This is used for explicit rebinds only. The normal refresh path must not
    drop working credentials for platforms that are already bound.
    """
    if platform not in QR_PLATFORMS or not CC_CONFIG.exists():
        return False

    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return False

    parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
    if len(parts) <= 1:
        return False

    target_types = cc_platform_types(platform)
    changed = False
    kept_projects = []

    for part in parts:
        if not part.startswith("[[projects]]"):
            kept_projects.append(part)
            continue

        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        if (name_match.group(1) if name_match else "") != aid:
            kept_projects.append(part)
            continue

        blocks = re.split(r"(?m)(?=^\[\[projects\.platforms\]\]\s*$)", part)
        if len(blocks) <= 1:
            kept_projects.append(part)
            continue

        kept_blocks = [blocks[0]]
        for block in blocks[1:]:
            type_match = re.search(r'(?m)^type\s*=\s*"([^"]+)"\s*$', block)
            ptype = type_match.group(1) if type_match else ""
            if ptype in target_types:
                changed = True
                continue
            kept_blocks.append(block)
        kept_projects.append("".join(kept_blocks))

    if not changed:
        return False

    backup = CC_CONFIG.parent / f"config.toml.bak-rebind-{platform}-{time.strftime('%Y%m%d-%H%M%S')}"
    try:
        backup.write_text(text, encoding="utf-8")
        CC_CONFIG.write_text("".join(kept_projects), encoding="utf-8")
        os.chmod(CC_CONFIG, 0o600)
    except Exception:
        return False
    return True


def normalize_cc_platform_options(aid: str) -> bool:
    """Keep cc-connect platform defaults aligned after QR onboarding rewrites.

    `cc-connect feishu new` owns the credential block and can recreate it
    without Nako's text-reply defaults. Normalize just the Nako project before
    every managed cc-connect restart so reinstall/rebind does not regress.
    """
    if not CC_CONFIG.exists():
        return False
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return False

    parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
    changed = False
    kept_projects = []

    for part in parts:
        if not part.startswith("[[projects]]"):
            kept_projects.append(part)
            continue

        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        if (name_match.group(1) if name_match else "") != aid:
            kept_projects.append(part)
            continue

        blocks = re.split(r"(?m)(?=^\[\[projects\.platforms\]\]\s*$)", part)
        if len(blocks) <= 1:
            kept_projects.append(part)
            continue

        fixed_blocks = [blocks[0]]
        for block in blocks[1:]:
            type_match = re.search(r'(?m)^type\s*=\s*"([^"]+)"\s*$', block)
            ptype = type_match.group(1) if type_match else ""
            if ptype in ("feishu", "lark"):
                new_block = re.sub(
                    r"(?m)^(enable_feishu_card|reply_to_trigger)\s*=.*\n?",
                    "",
                    block,
                ).rstrip()
                if "[projects.platforms.options]" not in new_block:
                    new_block += "\n\n[projects.platforms.options]"
                new_block += "\nenable_feishu_card = false\nreply_to_trigger = false\n"
                if new_block != block:
                    changed = True
                block = new_block
            fixed_blocks.append(block)
        kept_projects.append("".join(fixed_blocks))

    if not changed:
        return False

    backup = CC_CONFIG.parent / f"config.toml.bak-platform-options-{aid}-{time.strftime('%Y%m%d-%H%M%S')}"
    try:
        backup.write_text(text, encoding="utf-8")
        CC_CONFIG.write_text("".join(kept_projects), encoding="utf-8")
        os.chmod(CC_CONFIG, 0o600)
    except Exception:
        return False
    return True


def cc_project_platform_options(aid: str, platform_types: set) -> dict:
    if not CC_CONFIG.exists():
        return {}
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return {}

    if tomllib is not None:
        try:
            data = tomllib.loads(text)
            for project in data.get("projects", []):
                if project.get("name") != aid:
                    continue
                for platform in project.get("platforms", []):
                    if platform.get("type") in platform_types:
                        options = platform.get("options", {})
                        return options if isinstance(options, dict) else {}
        except Exception:
            pass

    for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
        if not part.startswith("[[projects]]"):
            continue
        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        if (name_match.group(1) if name_match else "") != aid:
            continue
        for block in re.split(r"(?m)(?=^\[\[projects\.platforms\]\]\s*$)", part)[1:]:
            type_match = re.search(r'(?m)^type\s*=\s*"([^"]+)"\s*$', block)
            if (type_match.group(1) if type_match else "") not in platform_types:
                continue
            options = {}
            for key, value in re.findall(r'(?m)^([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"\s*$', block):
                options[key] = value
            return options
    return {}


def write_env_values(path: Path, values: dict) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        text = path.read_text(encoding="utf-8") if path.exists() else ""
    except Exception:
        text = ""

    new_text = text
    for key, value in values.items():
        if not value:
            continue
        line = f"{key}={value}"
        pattern = rf"(?m)^#?\s*{re.escape(key)}=.*$"
        if re.search(pattern, new_text):
            new_text = re.sub(pattern, line, new_text)
        else:
            if new_text and not new_text.endswith("\n"):
                new_text += "\n"
            new_text += line + "\n"

    if new_text == text:
        try:
            os.chmod(path, 0o600)
        except Exception:
            pass
        return False
    try:
        path.write_text(new_text, encoding="utf-8")
        os.chmod(path, 0o600)
        return True
    except Exception:
        return False


def sync_hermes_feishu_env_for_project(aid: str) -> bool:
    """Mirror cc-connect QR Feishu credentials into Hermes workspace env.

    Hermes skills can read cc-connect config directly for delivery, but the
    agent also inspects <workspace>/skills/.env during self-checks. Keeping
    this mirror non-empty prevents stale template blanks from being reported
    as a missing Feishu binding.
    """
    if cc_project_runtime(aid) != "hermes":
        return False
    options = cc_project_platform_options(aid, {"feishu", "lark"})
    app_id = str(options.get("app_id") or "")
    app_secret = str(options.get("app_secret") or "")
    if not app_id or not app_secret:
        return False
    return write_env_values(
        hermes_workspace(aid) / "skills" / ".env",
        {"FEISHU_APP_ID": app_id, "FEISHU_APP_SECRET": app_secret},
    )


def reset_cc_connect_sessions_for_platform(aid: str, platform: str) -> list:
    if platform not in QR_PLATFORMS:
        return []
    sessions_dir = CC_CONFIG.parent / "sessions"
    if not sessions_dir.exists():
        return []

    prefixes = tuple(f"{ptype}:" for ptype in cc_platform_types(platform))
    removed = []
    ts = time.strftime("%Y%m%d-%H%M%S")

    for session_file in sessions_dir.glob(f"{aid}_*.json"):
        try:
            data = json.loads(session_file.read_text(encoding="utf-8"))
        except Exception:
            continue

        session_ids = set()
        for key, sid in list((data.get("active_session") or {}).items()):
            if key.startswith(prefixes):
                session_ids.add(sid)
        for key, ids in list((data.get("user_sessions") or {}).items()):
            if key.startswith(prefixes):
                session_ids.update(ids or [])

        if not session_ids:
            continue

        backup = session_file.with_name(f"{session_file.name}.bak-rebind-{platform}-{ts}")
        try:
            backup.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            continue

        for key in list((data.get("active_session") or {}).keys()):
            if key.startswith(prefixes):
                data["active_session"].pop(key, None)
        for key in list((data.get("user_sessions") or {}).keys()):
            if key.startswith(prefixes):
                data["user_sessions"].pop(key, None)
        for key in list((data.get("user_meta") or {}).keys()):
            if key.startswith(prefixes):
                data["user_meta"].pop(key, None)
        for sid in session_ids:
            (data.get("sessions") or {}).pop(sid, None)
            removed.append(sid)

        try:
            session_file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
            os.chmod(session_file, 0o600)
        except Exception:
            pass

    return sorted(removed)


def reset_openclaw_main_session(aid: str) -> str:
    sessions_file = HOME / ".openclaw" / "agents" / aid / "sessions" / "sessions.json"
    if not sessions_file.exists():
        return ""
    key = f"agent:{aid}:main"
    try:
        data = json.loads(sessions_file.read_text(encoding="utf-8"))
    except Exception:
        return ""
    entry = data.get(key)
    if not entry:
        return ""
    old_session = entry.get("sessionId") or ""
    backup = sessions_file.with_name(f"sessions.json.bak-rebind-main-{time.strftime('%Y%m%d-%H%M%S')}")
    try:
        backup.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        data.pop(key, None)
        sessions_file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        os.chmod(sessions_file, 0o600)
    except Exception:
        return ""
    return old_session


def remove_platform_bindings_for_runtime_switch(n: int, aid: str, runtime: str) -> dict:
    """Prevent existing platform credentials from silently moving runtimes.

    cc-connect has one agent backend per project. If a project is switched from
    OpenClaw/QClaw to Hermes, every platform block under that project would
    immediately route to Hermes. Clear the old platform bindings first so each
    platform must be explicitly scanned for the new runtime.
    """
    runtime = normalize_factory_runtime(runtime)
    old_runtime = cc_project_runtime(aid)
    if old_runtime not in RUNTIMES or old_runtime == runtime:
        return {"old_runtime": old_runtime, "removed_platforms": []}

    bound = bound_platforms_for_agent(aid)
    if not bound:
        return {"old_runtime": old_runtime, "removed_platforms": []}

    removed = []
    removed_sessions = {}
    clear_qr = {}
    platform_runtimes = job_state(n).get("platform_runtimes")
    platform_runtimes = platform_runtimes if isinstance(platform_runtimes, dict) else {}

    for plat in QR_PLATFORMS:
        if plat not in bound:
            continue
        if remove_platform_binding_for_agent(aid, plat):
            removed.append(plat)
        removed_sessions[plat] = reset_cc_connect_sessions_for_platform(aid, plat)
        platform_runtimes.pop(plat, None)
        try:
            (JOB_DIR / f"{aid}-{plat}.png").unlink()
        except FileNotFoundError:
            pass
        clear_qr[f"{plat}_qr_url"] = None
        clear_qr[f"{plat}_qr_image"] = None
        clear_qr[f"{plat}_rc"] = None

    bound_now = bound_platforms_for_agent(aid)
    write_state(
        n,
        bound_platforms=sorted(bound_now),
        unbound_platforms=[plat for plat in QR_PLATFORMS if plat not in bound_now],
        cc_reload_platforms=sorted(bound_now),
        platform_runtimes=platform_runtimes,
        **clear_qr,
    )
    return {
        "old_runtime": old_runtime,
        "removed_platforms": sorted(removed),
        "removed_sessions": removed_sessions,
    }


def should_refresh_qr(n: int) -> bool:
    state = job_state(n)
    if state.get("status") in ("queued", "installing"):
        return False
    aid = state.get("agent_id") or agent_id_for(n)
    return bool(unbound_platforms_for_agent(aid))


def next_generation(n: int) -> int:
    with LOCK:
        cur = JOB_GENERATIONS.get(n)
        if cur is None:
            try:
                cur = int(job_state(n).get("qr_generation") or 0)
            except Exception:
                cur = 0
        cur += 1
        JOB_GENERATIONS[n] = cur
        write_state(n, qr_generation=cur)
        return cur


def generation_current(n: int, generation: int) -> bool:
    with LOCK:
        cur = JOB_GENERATIONS.get(n)
    if cur is None:
        try:
            cur = int(job_state(n).get("qr_generation") or 0)
        except Exception:
            cur = 0
    return cur == generation


def register_qr_proc(n: int, proc):
    with LOCK:
        QR_PROCS.setdefault(n, []).append(proc)


def unregister_qr_proc(n: int, proc):
    with LOCK:
        procs = QR_PROCS.get(n, [])
        if proc in procs:
            procs.remove(proc)
        if not procs:
            QR_PROCS.pop(n, None)


def stop_qr_processes(n: int):
    with LOCK:
        procs = list(QR_PROCS.pop(n, []))
    for proc in procs:
        if proc.poll() is None:
            proc.terminate()
    deadline = time.time() + 3
    for proc in procs:
        while proc.poll() is None and time.time() < deadline:
            time.sleep(0.05)
        if proc.poll() is None:
            proc.kill()


def job_worker_lock(n: int):
    with LOCK:
        lock = JOB_WORKER_LOCKS.get(n)
        if lock is None:
            lock = threading.Lock()
            JOB_WORKER_LOCKS[n] = lock
        return lock


def tool_env() -> dict:
    env = os.environ.copy()
    home = os.path.expanduser("~")
    extra = ["/opt/homebrew/bin", "/usr/local/bin"]
    nvm = Path(home) / ".nvm/versions/node"
    if nvm.exists():
        latest = sorted(nvm.iterdir(), key=lambda p: p.name)[-1]
        extra.insert(0, str(latest / "bin"))
    env["PATH"] = ":".join(extra) + ":" + env.get("PATH", "")
    return env


def agent_install_command(aid: str, runtime: str = None) -> str:
    runtime = normalize_runtime(runtime)
    urls = " ".join(shlex.quote(url) for url in (INSTALL_URLS or DEFAULT_INSTALL_URLS))
    agent = shlex.quote(aid)
    runtime_arg = shlex.quote(runtime)
    return (
        "set -o pipefail; rc=1; "
        f"for url in {urls}; do "
        'echo "=== running installer: $url ==="; '
        f"if case \"$url\" in "
        f"file://*) installer_path=\"${{url#file://}}\"; bash \"$installer_path\" --agent-id {agent} --runtime {runtime_arg} --non-interactive --force --with-cc-connect ;; "
        f"/*) bash \"$url\" --agent-id {agent} --runtime {runtime_arg} --non-interactive --force --with-cc-connect ;; "
        f"*) curl --retry 3 --connect-timeout 20 -fsSL \"$url\" | bash -s -- --agent-id {agent} --runtime {runtime_arg} --non-interactive --force --with-cc-connect ;; "
        f"esac; then "
        "exit 0; "
        "else "
        "rc=$?; "
        'echo "=== installer failed rc=$rc url=$url ==="; '
        "fi; "
        "done; "
        "exit $rc"
    )


def openclaw_agent_configured(aid: str) -> bool:
    cfg_path = HOME / ".openclaw/openclaw.json"
    try:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        return False

    agents = cfg.get("agents", {})
    items = agents.get("list", []) if isinstance(agents, dict) else []
    if not isinstance(items, list):
        return False

    expected_workspace = str(HOME / ".openclaw/workspace" / aid)
    expected_agent_dir = str(HOME / ".openclaw/agents" / aid / "agent")
    for item in items:
        if not isinstance(item, dict) or item.get("id") != aid:
            continue
        return (
            item.get("workspace") == expected_workspace
            and item.get("agentDir") == expected_agent_dir
        )
    return False


def hermes_agent_configured(aid: str) -> bool:
    workspace = hermes_workspace(aid)
    return (
        workspace.is_dir()
        and (workspace / "AGENTS.md").exists()
        and (workspace / "SOUL.md").exists()
    )


def qclaw_agent_configured(aid: str) -> bool:
    cfg_path = qclaw_config_path()
    try:
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        return False

    agents = cfg.get("agents", {})
    items = agents.get("list", []) if isinstance(agents, dict) else []
    if not isinstance(items, list):
        return False

    expected_workspace = qclaw_workspace(aid)
    expected_agent_dir = qclaw_home() / "agents" / aid / "agent"
    for item in items:
        if not isinstance(item, dict) or item.get("id") != aid:
            continue
        workspace = resolve_path(item.get("workspace") or expected_workspace)
        agent_dir = resolve_path(item.get("agentDir") or expected_agent_dir)
        return (
            workspace == expected_workspace
            and agent_dir == expected_agent_dir
            and workspace.is_dir()
            and (workspace / "AGENTS.md").exists()
        )
    return False


def cc_project_runtime(aid: str) -> str:
    if not CC_CONFIG.exists():
        return ""
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return ""
    for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
        if not part.startswith("[[projects]]"):
            continue
        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        if (name_match.group(1) if name_match else "") != aid:
            continue
        return project_runtime_from_text(part)
    return ""


def agent_install_needed(aid: str, state: dict, runtime: str = None) -> bool:
    runtime = normalize_runtime(runtime or state.get("runtime"))
    if state.get("install_rc") != 0:
        return True
    if runtime == "qclaw":
        if not qclaw_agent_configured(aid):
            return True
    elif not openclaw_agent_configured(aid):
        return True
    if runtime == "hermes" and not hermes_agent_configured(aid):
        return True
    project_runtime = cc_project_runtime(aid)
    if not project_runtime or project_runtime != runtime:
        return True
    return False


def is_cc_connect_main_args(args: str) -> bool:
    return re.fullmatch(r"(?:node\s+)?(?:\S*/)?cc-connect(?:\s+--force)?", args.strip()) is not None


def is_openclaw_gateway_args(args: str) -> bool:
    return (
        "openclaw-gateway" in args
        or re.search(r"(^|\s)(?:node\s+)?\S*/?openclaw(?:\.mjs)?\s+gateway\s+run(\s|$)", args) is not None
    )


def cc_connect_main_pids() -> list:
    try:
        out = subprocess.run(["ps", "-eo", "pid=,args="], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, check=False).stdout
    except Exception:
        return []

    pids = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        pid_s, _, args = line.partition(" ")
        try:
            pid = int(pid_s)
        except ValueError:
            continue
        if "cc-connect" not in args:
            continue
        if is_cc_connect_main_args(args):
            pids.append(pid)
    return pids


def stop_cc_connect():
    pids = cc_connect_main_pids()
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass

    deadline = time.time() + 5
    while time.time() < deadline:
        live = [pid for pid in pids if Path(f"/proc/{pid}").exists()]
        if not live:
            return
        time.sleep(0.1)

    for pid in pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass


def openclaw_client_pids() -> list:
    try:
        out = subprocess.run(["ps", "-eo", "pid=,args="], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, check=False).stdout
    except Exception:
        return []

    pids = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        pid_s, _, args = line.partition(" ")
        try:
            pid = int(pid_s)
        except ValueError:
            continue
        if "openclaw" not in args:
            continue
        if is_openclaw_gateway_args(args):
            continue
        is_client = (
            re.search(r"(^|\s)openclaw-acp(\s|$)", args)
            or re.search(r"(^|\s)(?:node\s+)?\S*/?openclaw(?:\.mjs)?\s+acp(\s|$)", args)
        )
        if is_client:
            pids.append(pid)
    return pids


def stop_openclaw_clients() -> list:
    pids = openclaw_client_pids()
    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass

    deadline = time.time() + 3
    while time.time() < deadline:
        live = [pid for pid in pids if Path(f"/proc/{pid}").exists()]
        if not live:
            return pids
        time.sleep(0.1)

    for pid in pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
    return pids


def openclaw_gateway_pids() -> list:
    try:
        out = subprocess.run(["ps", "-eo", "pid=,args="], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, check=False).stdout
    except Exception:
        return []

    pids = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        pid_s, _, args = line.partition(" ")
        try:
            pid = int(pid_s)
        except ValueError:
            continue
        if "openclaw" not in args:
            continue
        if is_openclaw_gateway_args(args):
            pids.append(pid)
    return pids


def stop_openclaw_gateways() -> list:
    pids = openclaw_gateway_pids()
    if not pids:
        return []

    for pid in pids:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass

    deadline = time.time() + 10
    while time.time() < deadline:
        if not openclaw_gateway_pids():
            return pids
        time.sleep(0.5)

    for pid in pids:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
        except PermissionError:
            pass
    return pids


def restart_openclaw_gateway(env: dict) -> tuple:
    with OPENCLAW_GATEWAY_LOCK:
        clients = stop_openclaw_clients()
        gateways = stop_openclaw_gateways()
        deadline = time.time() + 10
        while time.time() < deadline and tcp_port_open("127.0.0.1", OPENCLAW_GATEWAY_PORT):
            time.sleep(0.5)
        ok = ensure_openclaw_gateway(env)
    return ok, clients, gateways


def cleanup_openclaw_npm_rename_temps() -> list:
    base = HOME / ".openclaw/plugin-runtime-deps"
    if not base.exists():
        return []

    removed = []
    for node_modules in base.glob("openclaw-*/node_modules"):
        targets = [node_modules]
        bin_dir = node_modules / ".bin"
        if bin_dir.is_dir():
            targets.append(bin_dir)
        try:
            scope_dirs = [
                child for child in node_modules.iterdir()
                if child.name.startswith("@") and child.is_dir() and not child.is_symlink()
            ]
            targets.extend(scope_dirs)
        except Exception:
            pass

        for directory in targets:
            try:
                children = list(directory.iterdir())
            except Exception:
                continue

            for child in children:
                name = child.name
                if name in {".bin", ".cache", ".package-lock.json"}:
                    continue
                if not NPM_RENAME_TMP_RE.match(name):
                    continue
                try:
                    if child.is_dir() and not child.is_symlink():
                        shutil.rmtree(child)
                    else:
                        child.unlink()
                    removed.append(str(child))
                except Exception:
                    pass
    return removed


def prewarm_openclaw_runtime_deps(env: dict) -> list:
    base = HOME / ".openclaw/plugin-runtime-deps"
    npm = shutil.which("npm", path=env.get("PATH"))
    if not npm or not base.exists():
        return []

    manifests = sorted(base.glob("openclaw-*/package.json"))
    if not manifests:
        return []

    lock_path = base / ".nako-runtime-deps.lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    results = []
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for manifest in manifests:
            root = manifest.parent
            cleanup_openclaw_npm_rename_temps()
            npm_env = env.copy()
            npm_env.update({
                "npm_config_cache": str(root / ".openclaw-npm-cache"),
                "npm_config_dry_run": "false",
                "npm_config_fund": "false",
                "npm_config_global": "false",
                "npm_config_location": "project",
                "npm_config_package_lock": "false",
                "npm_config_save": "false",
            })
            try:
                res = subprocess.run(
                    [npm, "install", "--package-lock=false", "--save=false", "--no-audit", "--fund=false"],
                    cwd=root,
                    env=npm_env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=180,
                    check=False,
                )
                if res.returncode == 0:
                    results.append(f"{root.name}:ok")
                else:
                    tail = " ".join((res.stdout or "").splitlines()[-3:])
                    results.append(f"{root.name}:rc={res.returncode} {tail[:240]}")
            except Exception as exc:
                results.append(f"{root.name}:error={str(exc)[:240]}")
            cleanup_openclaw_npm_rename_temps()
    return results


def parse_first_json_object(text: str):
    decoder = json.JSONDecoder()
    for idx, char in enumerate(text or ""):
        if char != "{":
            continue
        try:
            obj, _ = decoder.raw_decode(text[idx:])
        except Exception:
            continue
        if isinstance(obj, dict):
            return obj
    return None


def openclaw_device_id() -> str:
    try:
        data = json.loads((HOME / ".openclaw/identity/device.json").read_text(encoding="utf-8"))
    except Exception:
        return ""
    value = data.get("deviceId")
    return value if isinstance(value, str) else ""


def select_local_openclaw_device_repair_requests(device_list: dict, device_id: str) -> list:
    pending = device_list.get("pending")
    if not isinstance(pending, list):
        return []

    selected = []
    for item in pending:
        if not isinstance(item, dict):
            continue
        request_id = item.get("requestId")
        if not isinstance(request_id, str) or not request_id:
            continue
        if item.get("isRepair") is not True:
            continue
        if item.get("clientId") != "cli" or item.get("clientMode") != "cli":
            continue
        if device_id and item.get("deviceId") != device_id:
            continue
        selected.append(request_id)
    return selected


def approve_local_openclaw_device_repairs(env: dict) -> list:
    openclaw = shutil.which("openclaw", path=env.get("PATH"))
    if not openclaw or not (HOME / ".openclaw/devices").exists():
        return []

    device_id = openclaw_device_id()
    try:
        res = subprocess.run(
            [openclaw, "devices", "list", "--json"],
            cwd=HOME,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
            check=False,
        )
    except Exception:
        return []

    device_list = parse_first_json_object(res.stdout or "")
    if not isinstance(device_list, dict):
        return []

    approved = []
    for request_id in select_local_openclaw_device_repair_requests(device_list, device_id):
        try:
            approve = subprocess.run(
                [openclaw, "devices", "approve", request_id],
                cwd=HOME,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=30,
                check=False,
            )
        except Exception:
            continue
        if approve.returncode == 0:
            approved.append(request_id)
    return approved


def prune_empty_cc_projects() -> list:
    if not CC_CONFIG.exists():
        return []

    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return []

    parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
    if len(parts) <= 1:
        return []

    kept = []
    removed = []
    for part in parts:
        if not part.startswith("[[projects]]"):
            kept.append(part)
            continue
        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        name = name_match.group(1) if name_match else ""
        has_platform = re.search(r"(?m)^\[\[projects\.platforms\]\]\s*$", part) is not None
        if name.startswith("agent-nako-") and not has_platform:
            removed.append(name)
            continue
        kept.append(part)

    if not removed:
        return []

    backup = CC_CONFIG.parent / f"config.toml.bak-prune-{time.strftime('%Y%m%d-%H%M%S')}"
    try:
        backup.write_text(text, encoding="utf-8")
        CC_CONFIG.write_text("".join(kept), encoding="utf-8")
        os.chmod(CC_CONFIG, 0o600)
    except Exception:
        return []
    return removed


def project_runtime_from_text(part: str) -> str:
    env_match = re.search(r'NAKO_AGENT_RUNTIME\s*=\s*"?(hermes|qclaw|openclaw)"?', part)
    if env_match:
        return env_match.group(1)
    command_match = re.search(r'(?m)^command\s*=\s*"([^"]+)"\s*$', part)
    command = command_match.group(1).lower() if command_match else ""
    if "QCLAW_HOME" in part or ("OPENCLAW_STATE_DIR" in part and ".qclaw" in part):
        return "qclaw"
    if "hermes" in command:
        return "hermes"
    if "qclaw" in command:
        return "qclaw"
    if "openclaw" in command:
        return "openclaw"
    if "HERMES_HOME" in part:
        return "hermes"
    return "openclaw"


def cc_agent_options_for_runtime(name: str, runtime: str, env: dict = None) -> dict:
    runtime = normalize_runtime(runtime)
    env = env or tool_env()
    cc_data_dir = HOME / ".cc-connect"
    cc_api_data_dir = cc_data_dir
    cc_env = {
        "CC_CONNECT_DATA_DIR": str(cc_data_dir),
        "CC_CONNECT_API_DATA_DIR": str(cc_api_data_dir),
        "CC_CONNECT_SESSION_DIR": str(cc_api_data_dir / "sessions"),
        "CC_CONNECT_CONFIG": str(cc_data_dir / "config.toml"),
    }
    if runtime == "hermes":
        hhome = hermes_home()
        hermes_env = {
            "HOME": str(HOME),
            "HERMES_HOME": str(hhome),
            "PATH": env.get("PATH", ""),
            **cc_env,
            "NAKO_OUTPUT_MODE": "acp",
            "NAKO_CCCONNECT_PROJECT": name,
            "NAKO_AGENT_WORKSPACE": str(hermes_workspace(name)),
            "NAKO_SKILLS_DIR": str(hhome / "skills" / "nako"),
            "NAKO_MEDIA_HOME": str(hhome / "media"),
            "NAKO_AGENT_RUNTIME": "hermes",
        }
        return {
            "work_dir": str(hermes_workspace(name)),
            "command": hermes_command(env),
            "args": ["acp"],
            "display_name": f"Hermes {name}",
            "env": hermes_env,
        }
    if runtime == "qclaw":
        ensure_qclaw_cc_session(name)
        qhome = qclaw_home()
        qclaw_env = {
            "HOME": str(HOME),
            "QCLAW_HOME": str(qhome),
            "OPENCLAW_STATE_DIR": str(qhome),
            "OPENCLAW_CONFIG_PATH": str(qclaw_config_path()),
            "PATH": env.get("PATH", ""),
            **cc_env,
            "OPENCLAW_OUTPUT_MODE": "acp",
            "OPENCLAW_CCCONNECT_PROJECT": name,
            "NAKO_OUTPUT_MODE": "acp",
            "NAKO_CCCONNECT_PROJECT": name,
            "NAKO_AGENT_WORKSPACE": str(qclaw_workspace(name)),
            "NAKO_SKILLS_DIR": str(qhome / "skills"),
            "NAKO_MEDIA_HOME": str(qhome / "media"),
            "NAKO_AGENT_RUNTIME": "qclaw",
        }
        token = gateway_auth_token(qclaw_config_path())
        if token:
            qclaw_env["OPENCLAW_GATEWAY_TOKEN"] = token
        return {
            "work_dir": str(qclaw_workspace(name)),
            "command": qclaw_node_binary(env),
            "args": [qclaw_openclaw_mjs(), "acp", "--session", f"agent:{name}:{QCLAW_CC_SESSION_SUFFIX}"],
            "display_name": f"QClaw {name}",
            "env": qclaw_env,
        }

    ohome = HOME / ".openclaw"
    options = {
        "work_dir": str(ohome),
        "command": "openclaw",
        "args": ["acp", "--session", f"agent:{name}:main"],
        "display_name": f"OpenClaw {name}",
        "env": {
            "HOME": str(HOME),
            "OPENCLAW_HOME": str(ohome),
            "PATH": env.get("PATH", ""),
            **cc_env,
            "OPENCLAW_OUTPUT_MODE": "acp",
            "OPENCLAW_CCCONNECT_PROJECT": name,
            "NAKO_OUTPUT_MODE": "acp",
            "NAKO_CCCONNECT_PROJECT": name,
            "NAKO_AGENT_WORKSPACE": str(openclaw_workspace(name)),
            "NAKO_SKILLS_DIR": str(ohome / "skills"),
            "NAKO_MEDIA_HOME": str(ohome / "media"),
            "NAKO_AGENT_RUNTIME": "openclaw",
        },
    }
    token = gateway_auth_token(ohome / "openclaw.json")
    if token:
        options["env"]["OPENCLAW_GATEWAY_TOKEN"] = token
    return options


def ensure_qclaw_cc_session(aid: str) -> bool:
    session_dir = qclaw_home() / "agents" / aid / "sessions"
    session_dir.mkdir(parents=True, exist_ok=True)
    sessions_file = session_dir / "sessions.json"
    try:
        sessions = json.loads(sessions_file.read_text(encoding="utf-8")) if sessions_file.exists() else {}
        if not isinstance(sessions, dict):
            sessions = {}
    except Exception:
        sessions = {}

    key = f"agent:{aid}:{QCLAW_CC_SESSION_SUFFIX}"
    now_ms = int(time.time() * 1000)
    entry = sessions.get(key)
    if not isinstance(entry, dict):
        entry = {}

    for other_key, other_entry in list(sessions.items()):
        if other_key == key or not other_key.startswith(f"agent:{aid}:"):
            continue
        if not isinstance(other_entry, dict):
            continue
        origin = other_entry.get("origin") if isinstance(other_entry.get("origin"), dict) else {}
        delivery = other_entry.get("deliveryContext") if isinstance(other_entry.get("deliveryContext"), dict) else {}
        stale_cc = (
            other_entry.get("label") in ("ACP", "cc-connect", "cc-connect 飞书/微信")
            or origin.get("provider") == "acp"
            or origin.get("surface") == "cc-connect"
            or delivery.get("channel") == "cc-connect"
            or other_entry.get("lastChannel") == "cc-connect"
        )
        if stale_cc:
            sessions.pop(other_key, None)

    session_id = str(entry.get("sessionId") or uuid4())
    session_file = entry.get("sessionFile")
    if not isinstance(session_file, str) or not session_file:
        session_file = str(session_dir / f"{session_id}.jsonl")
    try:
        updated_at = int(entry.get("updatedAt") or now_ms)
    except Exception:
        updated_at = now_ms

    entry.update({
        "sessionId": session_id,
        "updatedAt": updated_at,
        "label": "cc-connect 飞书/微信",
        "systemSent": bool(entry.get("systemSent", False)),
        "abortedLastRun": bool(entry.get("abortedLastRun", False)),
        "chatType": entry.get("chatType") or "direct",
        "deliveryContext": {"channel": "webchat"},
        "lastChannel": "webchat",
        "origin": {
            "label": "cc-connect 飞书/微信",
            "provider": "webchat",
            "surface": "webchat",
            "chatType": "direct",
        },
        "sessionFile": session_file,
    })
    sessions[key] = entry

    path = resolve_path(session_file)
    path.parent.mkdir(parents=True, exist_ok=True)
    changed = False
    if not path.exists():
        header = {
            "type": "session",
            "version": 3,
            "id": session_id,
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "cwd": str(qclaw_workspace(aid)),
        }
        path.write_text(json.dumps(header, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        changed = True

    serialized = json.dumps(sessions, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    old = sessions_file.read_text(encoding="utf-8") if sessions_file.exists() else ""
    if old != serialized:
        if sessions_file.exists():
            backup = sessions_file.with_name(f"sessions.json.bak-cc-connect-{time.strftime('%Y%m%d-%H%M%S')}")
            backup.write_text(old, encoding="utf-8")
        sessions_file.write_text(serialized, encoding="utf-8")
        changed = True
    return changed


def ensure_qclaw_cc_sessions_for_projects() -> list:
    if not CC_CONFIG.exists():
        return []
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return []

    ensured = []
    for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
        if not part.startswith("[[projects]]") or project_runtime_from_text(part) != "qclaw":
            continue
        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        name = name_match.group(1) if name_match else ""
        if name and ensure_qclaw_cc_session(name):
            ensured.append(name)
    return ensured


def cc_agent_option_lines(options: dict) -> dict:
    return {
        "work_dir": f"work_dir = {toml_quote(options['work_dir'])}",
        "command": f"command = {toml_quote(options['command'])}",
        "args": f"args = {toml_array(options['args'])}",
        "display_name": f"display_name = {toml_quote(options['display_name'])}",
        "env": f"env = {toml_inline_table(options['env'])}",
    }


def repair_nako_cc_projects() -> list:
    if not CC_CONFIG.exists():
        return []

    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return []

    parts = re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text)
    if len(parts) <= 1:
        return []

    kept = []
    repaired = []
    for part in parts:
        if not part.startswith("[[projects]]"):
            kept.append(part)
            continue

        name_match = re.search(r'(?m)^name\s*=\s*"([^"]+)"\s*$', part)
        name = name_match.group(1) if name_match else ""
        if not name.startswith("agent-nako-") or "[[projects.platforms]]" not in part:
            kept.append(part)
            continue

        original = part
        runtime = project_runtime_from_text(part)
        if "[projects.agent]" not in part:
            insert = '\n[projects.agent]\ntype = "acp"\n\n[projects.agent.options]\n'
            marker = "\n[[projects.platforms]]"
            if marker in part:
                part = part.replace(marker, insert + marker, 1)
            else:
                part = part.rstrip() + insert
        elif "[projects.agent.options]" not in part:
            insert = '\n[projects.agent.options]\n'
            marker = "\n[[projects.platforms]]"
            if marker in part:
                part = part.replace(marker, insert + marker, 1)
            else:
                part = part.rstrip() + insert

        agent_match = re.search(
            r"(?ms)(^\[projects\.agent\]\s*\n)(.*?)(?=^\[)",
            part,
        )
        if agent_match:
            agent_body = agent_match.group(2)
            if re.search(r'(?m)^type\s*=', agent_body):
                agent_body = re.sub(r'(?m)^type\s*=.*$', 'type = "acp"', agent_body)
            else:
                agent_body = 'type = "acp"\n' + agent_body
            part = part[:agent_match.start(2)] + agent_body + part[agent_match.end(2):]

        opt = part.index("[projects.agent.options]")
        rest_start = opt + len("[projects.agent.options]")
        next_table = re.search(r"(?m)^\[", part[rest_start:])
        insert_at = len(part) if next_table is None else rest_start + next_table.start()
        section = part[opt:insert_at]
        options = cc_agent_options_for_runtime(name, runtime)
        if runtime == "hermes":
            existing_command = re.search(r'(?m)^command\s*=\s*"([^"]*hermes[^"]*)"\s*$', part)
            if existing_command and existing_command.group(1) != "hermes":
                options["command"] = existing_command.group(1)
        needed = cc_agent_option_lines(options)
        additions = []
        for key, line in needed.items():
            if re.search(rf"(?m)^{key}\s*=", section):
                section = re.sub(rf"(?m)^{key}\s*=.*$", line, section)
            else:
                additions.append(line)
        part = part[:opt] + section + part[insert_at:]
        insert_at = opt + len(section)
        if additions:
            part = part[:insert_at].rstrip() + "\n" + "\n".join(additions) + "\n" + part[insert_at:]

        if part != original:
            repaired.append(name)
        kept.append(part)

    if not repaired:
        return []

    backup = CC_CONFIG.parent / f"config.toml.bak-repair-{time.strftime('%Y%m%d-%H%M%S')}"
    try:
        backup.write_text(text, encoding="utf-8")
        CC_CONFIG.write_text("".join(kept), encoding="utf-8")
        os.chmod(CC_CONFIG, 0o600)
    except Exception:
        return []
    return repaired


def tcp_port_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except OSError:
        return False


def openclaw_gateway_env(env: dict) -> dict:
    gw_env = env.copy()
    gw_env.setdefault("NODE_COMPILE_CACHE", "/var/tmp/openclaw-compile-cache")
    gw_env.setdefault("OPENCLAW_NO_RESPAWN", "1")
    node_options = gw_env.get("NODE_OPTIONS", "")
    heap_option = f"--max-old-space-size={OPENCLAW_GATEWAY_HEAP_MB}"
    if "--max-old-space-size" not in node_options:
        gw_env["NODE_OPTIONS"] = (node_options + " " + heap_option).strip()
    Path(gw_env["NODE_COMPILE_CACHE"]).mkdir(parents=True, exist_ok=True)
    return gw_env


def ensure_openclaw_gateway(env: dict) -> bool:
    port = OPENCLAW_GATEWAY_PORT
    if tcp_port_open("127.0.0.1", port):
        return True

    with OPENCLAW_GATEWAY_LOCK:
        if tcp_port_open("127.0.0.1", port):
            return True

        gw_env = openclaw_gateway_env(env)
        if shutil.which("openclaw", path=gw_env.get("PATH")) is None:
            return False
        gw_log = Path("/tmp/openclaw/openclaw-gateway.log")
        gw_log.parent.mkdir(parents=True, exist_ok=True)

        existing = openclaw_gateway_pids()
        if existing:
            deadline = time.time() + 10
            while time.time() < deadline:
                if tcp_port_open("127.0.0.1", port):
                    return True
                if not openclaw_gateway_pids():
                    break
                time.sleep(1)
            if openclaw_gateway_pids():
                return False

        for attempt in range(2):
            removed = cleanup_openclaw_npm_rename_temps()
            prewarm = prewarm_openclaw_runtime_deps(gw_env)
            with gw_log.open("ab") as f:
                if removed:
                    note = (
                        f"\n=== nako cleaned npm rename temps before gateway start "
                        f"attempt={attempt + 1}: {len(removed)} entries ===\n"
                    )
                    f.write(note.encode("utf-8"))
                if prewarm:
                    note = f"\n=== nako prewarmed runtime deps attempt={attempt + 1}: {'; '.join(prewarm)} ===\n"
                    f.write(note.encode("utf-8"))
                proc = subprocess.Popen(["openclaw", "gateway", "run", "--port", str(port), "--bind", "loopback"],
                                        stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                        env=gw_env, start_new_session=True)

            deadline = time.time() + 45
            while time.time() < deadline:
                if tcp_port_open("127.0.0.1", port):
                    return True
                if proc.poll() is not None:
                    break
                time.sleep(1)

            if tcp_port_open("127.0.0.1", port):
                return True
            if proc.poll() is None:
                return False
            if attempt == 0:
                time.sleep(1)
    return False


def gateway_watchdog():
    while True:
        port = OPENCLAW_GATEWAY_PORT
        if has_openclaw_cc_projects():
            was_up = tcp_port_open("127.0.0.1", port)
            if not was_up:
                stop_openclaw_clients()
            ok = ensure_openclaw_gateway(tool_env())
            if ok and not was_up:
                schedule_cc_connect_restart(tool_env(), reason="gateway-watchdog", delay=35.0)
            elif ok and has_cc_projects() and not cc_connect_main_pids():
                schedule_cc_connect_restart(tool_env(), reason="cc-connect-watchdog", delay=2.0)
        elif has_cc_projects() and not cc_connect_main_pids():
            schedule_cc_connect_restart(tool_env(), reason="cc-connect-watchdog", delay=2.0)
        time.sleep(OPENCLAW_WATCHDOG_INTERVAL)


def ensure_cc_connect_api_socket_compat(work_dir: Path) -> bool:
    """Expose the daemon socket at the default cc-connect send data-dir path."""
    public_run = work_dir / "run"
    nested_run = work_dir / ".cc-connect" / "run"
    public_sock = public_run / "api.sock"
    nested_sock = nested_run / "api.sock"

    deadline = time.time() + 3
    while time.time() < deadline:
        if public_sock.exists():
            return False
        if nested_sock.exists():
            break
        time.sleep(0.2)

    if not nested_sock.exists():
        return False

    try:
        if public_run.is_symlink():
            public_run.unlink()
        elif public_run.exists():
            if public_sock.exists():
                return False
            if public_run.is_dir() and not any(public_run.iterdir()):
                public_run.rmdir()
            else:
                return False
        public_run.symlink_to(Path(".cc-connect") / "run")
        return True
    except OSError:
        return False


def start_cc_connect(env: dict, reason: str = ""):
    with CC_RESTART_LOCK:
        log = HOME / ".cc-connect/cc-connect.log"
        work_dir = HOME / ".cc-connect"
        log.parent.mkdir(parents=True, exist_ok=True)
        removed = []
        repaired = repair_nako_cc_projects()
        normalized_global = normalize_cc_global_options()
        normalized = []
        synced_hermes_feishu = []
        for aid in sorted(cc_project_names()):
            if normalize_cc_platform_options(aid):
                normalized.append(aid)
            if sync_hermes_feishu_env_for_project(aid):
                synced_hermes_feishu.append(aid)
        ensured_qclaw_sessions = ensure_qclaw_cc_sessions_for_projects()
        startable = has_cc_projects()
        needs_gateway = has_openclaw_cc_projects()
        gateway_ok = ensure_openclaw_gateway(env) if needs_gateway else True
        approved_devices = approve_local_openclaw_device_repairs(env) if needs_gateway and gateway_ok else []

        stop_cc_connect()
        stopped_openclaw = stop_openclaw_clients()
        with log.open("ab") as f:
            note = f"\n=== nako restart cc-connect reason={reason or 'reload'} gateway_ok={gateway_ok} ===\n"
            f.write(note.encode("utf-8"))
            if stopped_openclaw:
                f.write(("=== stopped stale openclaw clients: " + ", ".join(map(str, stopped_openclaw)) + " ===\n").encode("utf-8"))
            if removed:
                f.write(("=== pruned empty projects: " + ", ".join(removed) + " ===\n").encode("utf-8"))
            if repaired:
                f.write(("=== repaired projects: " + ", ".join(repaired) + " ===\n").encode("utf-8"))
            if normalized_global:
                f.write(b"=== normalized global options: stream_preview.enabled=true display.tool_messages=false ===\n")
            if normalized:
                f.write(("=== normalized platform options: " + ", ".join(normalized) + " ===\n").encode("utf-8"))
            if synced_hermes_feishu:
                f.write(("=== synced hermes feishu env: " + ", ".join(synced_hermes_feishu) + " ===\n").encode("utf-8"))
            if ensured_qclaw_sessions:
                f.write(("=== ensured qclaw sessions: " + ", ".join(ensured_qclaw_sessions) + " ===\n").encode("utf-8"))
            if approved_devices:
                f.write(("=== approved local openclaw device repairs: " + ", ".join(approved_devices) + " ===\n").encode("utf-8"))
            daemon_ok = False
            cc_bin = shutil.which("cc-connect", path=env.get("PATH")) or "cc-connect"
            subprocess.run([cc_bin, "daemon", "stop", "--work-dir", str(work_dir)],
                           stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                           env=env, check=False)
            stop_cc_connect()
            if not startable:
                f.write(b"=== cc-connect start skipped: no project platforms configured ===\n")
                return
            install_rc = subprocess.run(
                [cc_bin, "daemon", "install", "--work-dir", str(work_dir), "--force"],
                stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                env=env, check=False,
            ).returncode
            if install_rc == 0:
                start_rc = subprocess.run(
                    [cc_bin, "daemon", "start", "--work-dir", str(work_dir)],
                    stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                    env=env, check=False,
                ).returncode
                daemon_ok = start_rc == 0
                f.write(f"=== cc-connect daemon start rc={start_rc} ===\n".encode("utf-8"))
            else:
                f.write(f"=== cc-connect daemon install rc={install_rc} ===\n".encode("utf-8"))
            if not daemon_ok:
                subprocess.Popen([cc_bin], stdout=f, stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, cwd=str(work_dir),
                                 env=env, start_new_session=True)
                f.write(b"=== cc-connect fallback process started ===\n")
            if ensure_cc_connect_api_socket_compat(work_dir):
                f.write(b"=== cc-connect api socket compat link ready ===\n")


def schedule_cc_connect_restart(env: dict, reason: str = "", delay: float = 2.0):
    global CC_RESTART_TIMER
    env_copy = env.copy()
    with CC_RESTART_LOCK:
        if CC_RESTART_TIMER is not None:
            CC_RESTART_TIMER.cancel()
        CC_RESTART_TIMER = threading.Timer(delay, start_cc_connect, args=(env_copy, reason))
        CC_RESTART_TIMER.daemon = True
        CC_RESTART_TIMER.start()


def schedule_reload_for_bound_platforms(n: int, bound: set, env: dict, reason: str, force: bool = False) -> bool:
    if not bound:
        return False
    desired = set(bound)
    current = set(job_state(n).get("cc_reload_platforms") or [])
    if desired == current and not force:
        return False
    write_state(n, cc_reload_platforms=sorted(desired))
    schedule_cc_connect_restart(env, reason=reason)
    return True


def has_cc_projects() -> bool:
    if not CC_CONFIG.exists():
        return False
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return False
    for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
        if part.startswith("[[projects]]") and cc_project_has_platforms(part):
            return True
    return False


def cc_project_runtimes() -> set:
    if not CC_CONFIG.exists():
        return set()
    try:
        text = CC_CONFIG.read_text(encoding="utf-8")
    except Exception:
        return set()

    runtimes = set()
    for part in re.split(r"(?m)(?=^\[\[projects\]\]\s*$)", text):
        if not part.startswith("[[projects]]"):
            continue
        if not cc_project_has_platforms(part):
            continue
        if "[projects.agent]" not in part:
            continue
        runtimes.add(project_runtime_from_text(part))
    return runtimes


def has_openclaw_cc_projects() -> bool:
    return "openclaw" in cc_project_runtimes()


def existing_job_for_ip(client_ip: str, index: dict):
    raw = index.get(client_ip)
    if raw is None:
        return None
    try:
        n = int(raw)
    except Exception:
        index.pop(client_ip, None)
        return None
    if (JOB_DIR / f"agent-nako-{n}.json").exists():
        return n
    index.pop(client_ip, None)
    return None


def create_or_get_job_for_ip(client_ip: str, runtime: str):
    client_ip = client_ip or "unknown"
    runtime = normalize_runtime(runtime)
    with LOCK:
        index = load_ip_index()
        n = existing_job_for_ip(client_ip, index)
        if n is not None:
            state = job_state(n)
            aid = state.get("agent_id") or agent_id_for(n)
            bound = bound_platforms_for_agent(aid)
            configured_runtime = cc_project_runtime(aid)
            current_runtime = configured_runtime if configured_runtime in RUNTIMES else normalize_runtime(state.get("runtime"))
            platform_runtimes = normalized_platform_runtimes(
                state, bound, current_runtime
            )
            update = {"platform_runtimes": platform_runtimes}
            if not bound:
                update["runtime"] = runtime
            write_state(n, **update)
            return n, True, client_ip

        n = alloc_id()
        aid = f"agent-nako-{n}"
        write_state(n, status="queued", agent_id=aid, client_ip=client_ip, runtime=runtime)
        index[client_ip] = n
        save_ip_index(index)
        return n, False, client_ip


def current_job_payload_for_ip(client_ip: str) -> dict:
    client_ip = client_ip or "unknown"
    with LOCK:
        index = load_ip_index()
        n = existing_job_for_ip(client_ip, index)
    if n is None:
        return {
            "existing": False,
            "client_ip": client_ip,
            "status": "none",
            "runtime": DEFAULT_RUNTIME,
            "runtime_label": runtime_label(DEFAULT_RUNTIME),
        }
    payload = status_payload(n)
    payload.update({
        "existing": True,
        "id": n,
        "agent_id": agent_id_for(n),
        "client_ip": client_ip,
        "status_url": f"/status?id={n}",
        "log_url": f"/log?id={n}",
    })
    return payload


def run_install_and_qr(n: int, force_qr: bool = False, generation: int = None, target_platforms=None, runtime: str = None):
    with job_worker_lock(n):
        if generation is not None and not generation_current(n, generation):
            return
        return run_install_and_qr_locked(n, force_qr, generation, target_platforms, runtime)


def run_install_and_qr_locked(n: int, force_qr: bool = False, generation: int = None, target_platforms=None, runtime: str = None):
    """Background worker: install agent when needed, then run QR onboarding."""
    aid = agent_id_for(n)
    log = JOB_DIR / f"{aid}.log"
    env = tool_env()
    runtime = normalize_runtime(runtime or job_state(n).get("runtime"))
    if generation is None:
        generation = next_generation(n)
    target_platforms = [p for p in (target_platforms or []) if p in QR_PLATFORMS]
    ensure_cc_connect_config()

    switch_cleanup = remove_platform_bindings_for_runtime_switch(n, aid, runtime)
    if switch_cleanup.get("removed_platforms"):
        with log.open("a") as f:
            f.write(
                f"\n=== runtime switch cleanup old_runtime={switch_cleanup.get('old_runtime') or '-'} "
                f"new_runtime={runtime} removed_platforms={','.join(switch_cleanup['removed_platforms'])} ===\n"
            )

    state = job_state(n)
    install_needed = agent_install_needed(aid, state, runtime)
    if install_needed:
        write_state(n, status="installing", agent_id=aid, runtime=runtime, qr_generation=generation)
        with log.open("w") as f:
            # Install (idempotent)
            rc = subprocess.run(
                ["bash", "-c", agent_install_command(aid, runtime)],
                stdout=f, stderr=subprocess.STDOUT, env=env).returncode
            f.write(f"\n=== install rc={rc} ===\n")

        if rc != 0:
            if generation_current(n, generation):
                write_state(n, status="install_failed", install_rc=rc)
            return

        if runtime == "openclaw":
            gateway_ok, stopped_clients, stopped_gateways = restart_openclaw_gateway(env)
        else:
            gateway_ok, stopped_clients, stopped_gateways = True, [], []
        with log.open("a") as f:
            f.write(
                f"\n=== runtime={runtime} post-install: "
                f"gateway_ok={gateway_ok} clients={stopped_clients} gateways={stopped_gateways} ===\n"
            )
        write_state(n, status="installed", runtime=runtime, install_rc=rc,
                    **runtime_model_state_fields(aid, runtime))

    if not generation_current(n, generation):
        return

    platforms = target_platforms or unbound_platforms_for_agent(aid)
    if not platforms:
        bound = bound_platforms_for_agent(aid)
        platform_runtimes = job_state(n).get("platform_runtimes")
        platform_runtimes = platform_runtimes if isinstance(platform_runtimes, dict) else {}
        write_state(n, status="ready", runtime=runtime, qr_refresh_in_progress=False,
                    bound_platforms=sorted(bound),
                    unbound_platforms=[],
                    platform_runtimes=platform_runtimes,
                    **runtime_model_state_fields(aid, runtime))
        schedule_reload_for_bound_platforms(n, bound, env, reason=f"{aid}:already-bound")
        return

    with log.open("a") as f:
        f.write(
            f"\n=== qr generation {generation} force={force_qr} "
            f"platforms={','.join(platforms)} ===\n"
        )

    clear_qr = {}
    platform_runtimes = job_state(n).get("platform_runtimes")
    platform_runtimes = platform_runtimes if isinstance(platform_runtimes, dict) else {}
    for plat in platforms:
        qr_path = JOB_DIR / f"{aid}-{plat}.png"
        try:
            qr_path.unlink()
        except FileNotFoundError:
            pass
        platform_runtimes.pop(plat, None)
        clear_qr[f"{plat}_qr_url"] = None
        clear_qr[f"{plat}_qr_image"] = None
        clear_qr[f"{plat}_rc"] = None
    write_state(n, status="generating_qr", agent_id=aid, runtime=runtime, qr_generation=generation,
                qr_refresh_in_progress=True, platform_runtimes=platform_runtimes, **clear_qr)

    procs = []
    url_patterns = {
        "feishu": r"https://open\.feishu\.cn/[^\s]+",
        "weixin": r"https://(?:liteapp|weixin)\.weixin\.qq\.com/[^\s]+",
    }

    for plat in platforms:
        if not generation_current(n, generation):
            return
        qr_path = JOB_DIR / f"{aid}-{plat}.png"
        proc = subprocess.Popen(
            ["bash", "-c",
             f"cc-connect {plat} new --project {aid} --qr-image {qr_path} --timeout 480"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, text=True)
        register_qr_proc(n, proc)
        procs.append((plat, proc))

        qr_url = None
        deadline = time.time() + 20
        while time.time() < deadline and qr_url is None:
            line = proc.stdout.readline()
            if not line:
                break
            with log.open("a") as f:
                f.write(f"[{plat}] " + line)
            m = re.search(url_patterns[plat], line)
            if m:
                qr_url = m.group(0)

        write_state(n, **{
            f"{plat}_qr_url": qr_url,
            f"{plat}_qr_image": str(qr_path) if qr_path.exists() else None,
        })

    if not generation_current(n, generation):
        return

    write_state(n, status="awaiting_scan", runtime=runtime,
                **runtime_model_state_fields(aid, runtime))

    rc_updates = {}
    remaining = {plat: proc for plat, proc in procs}
    last_bound = set()
    while remaining:
        if not generation_current(n, generation):
            return

        for plat, proc in list(remaining.items()):
            rc = proc.poll()
            if rc is None:
                continue
            rc_updates[f"{plat}_rc"] = rc
            try:
                rest = proc.stdout.read()
            except Exception:
                rest = ""
            if rest:
                with log.open("a") as f:
                    for line in rest.splitlines(True):
                        f.write(f"[{plat}] " + line)
            unregister_qr_proc(n, proc)
            remaining.pop(plat, None)

        bound_now = bound_platforms_for_agent(aid)
        unbound_now = [plat for plat in QR_PLATFORMS if plat not in bound_now]
        platform_runtimes = job_state(n).get("platform_runtimes")
        platform_runtimes = platform_runtimes if isinstance(platform_runtimes, dict) else {}
        for plat in platforms:
            if plat in bound_now:
                platform_runtimes[plat] = runtime
        write_state(n, bound_platforms=sorted(bound_now), unbound_platforms=unbound_now,
                    platform_runtimes=platform_runtimes,
                    **rc_updates)
        if bound_now and bound_now != last_bound:
            with log.open("a") as f:
                f.write(f"\n=== detected bound platforms: {', '.join(sorted(bound_now))}; scheduling cc-connect reload ===\n")
            schedule_reload_for_bound_platforms(
                n, bound_now, env, reason=f"{aid}:bound-{','.join(sorted(bound_now))}", force=True
            )
            last_bound = set(bound_now)

        if remaining:
            time.sleep(2)

    if not generation_current(n, generation):
        return

    bound = bound_platforms_for_agent(aid)
    unbound = [plat for plat in QR_PLATFORMS if plat not in bound]
    platform_runtimes = job_state(n).get("platform_runtimes")
    platform_runtimes = platform_runtimes if isinstance(platform_runtimes, dict) else {}
    for plat in platforms:
        if plat in bound:
            platform_runtimes[plat] = runtime
    write_state(n, status="ready" if not unbound else "qr_expired",
                runtime=runtime,
                qr_refresh_in_progress=False,
                bound_platforms=sorted(bound),
                unbound_platforms=unbound,
                platform_runtimes=platform_runtimes,
                **runtime_model_state_fields(aid, runtime),
                **rc_updates)
    if bound:
        schedule_reload_for_bound_platforms(n, bound, env, reason=f"{aid}:qr-finished", force=True)


def start_worker(n: int, force_qr: bool = False, reason: str = "", target_platforms=None, runtime: str = None) -> bool:
    generation = next_generation(n)
    runtime = normalize_runtime(runtime or job_state(n).get("runtime"))
    target_platforms = [p for p in (target_platforms or []) if p in QR_PLATFORMS]
    stop_qr_processes(n)
    if force_qr:
        state = job_state(n)
        aid = state.get("agent_id") or agent_id_for(n)
        clear_qr = {}
        platforms = target_platforms or unbound_platforms_for_agent(aid)
        for plat in platforms:
            try:
                (JOB_DIR / f"{aid}-{plat}.png").unlink()
            except FileNotFoundError:
                pass
            clear_qr[f"{plat}_qr_url"] = None
            clear_qr[f"{plat}_qr_image"] = None
            clear_qr[f"{plat}_rc"] = None
        write_state(n, status="generating_qr", runtime=runtime, qr_refresh_in_progress=True, **clear_qr)
    t = threading.Thread(
        target=run_install_and_qr,
        args=(n, force_qr, generation, target_platforms, runtime),
        daemon=True,
    )
    t.start()
    return True


class Handler(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.end_headers()
        self.wfile.write(json.dumps(obj, ensure_ascii=False).encode())

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/":
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8"); self.send_header("Cache-Control", "no-store, max-age=0"); self.end_headers()
            self.wfile.write("""<!doctype html><html lang="zh-CN"><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><title>Nako Factory</title>
<style>
:root{color-scheme:light;--bg:#f6f7f9;--panel:#fff;--text:#17202a;--muted:#687385;--line:#dde3ea;--accent:#2563eb;--accent-dark:#1d4ed8;--ok:#0f8a5f;--warn:#a16207;--bad:#b42318;--shadow:0 14px 36px rgba(20,30,45,.08)}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,"PingFang SC","Microsoft YaHei",sans-serif}.page{width:min(1120px,100%);margin:0 auto;padding:28px 18px 36px}.topbar{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:18px}.brand h1{margin:0;font-size:26px;line-height:1.2;letter-spacing:0}.brand p{margin:6px 0 0;color:var(--muted)}.actions{display:grid;gap:10px;min-width:360px}.runtime-switch{display:grid;grid-template-columns:repeat(2,1fr);gap:4px;border:1px solid var(--line);border-radius:8px;background:#fff;padding:4px}.runtime-switch input{position:absolute;opacity:0;pointer-events:none}.runtime-switch span{display:block;border-radius:6px;padding:8px 10px;text-align:center;font-weight:800;color:var(--muted);cursor:pointer}.runtime-switch input:checked+span{background:#e8f0ff;color:#1d4ed8}button{border:0;border-radius:8px;background:var(--accent);color:#fff;padding:11px 16px;font-weight:700;font-size:15px;cursor:pointer;white-space:nowrap;box-shadow:0 8px 18px rgba(37,99,235,.18)}button:hover{background:var(--accent-dark)}button:disabled{cursor:wait;opacity:.72}.small-btn{width:100%;margin-top:12px;background:#fff;color:var(--accent);border:1px solid #bfd0ff;box-shadow:none;padding:9px 12px;font-size:14px}.small-btn:hover{background:#eef4ff}.summary{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0 18px}.pill{display:inline-flex;align-items:center;min-height:30px;border:1px solid var(--line);border-radius:999px;background:#fff;padding:4px 10px;color:var(--muted);font-size:13px}.pill strong{color:var(--text);font-weight:700}.status-ready{color:var(--ok)}.status-working{color:var(--accent)}.status-warn{color:var(--warn)}.status-bad{color:var(--bad)}.qr-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;margin-bottom:18px}.qr-card{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:18px}.qr-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:14px}.qr-title{font-size:18px;font-weight:800}.qr-state{font-size:13px;color:var(--muted);white-space:nowrap}.qr-wrap{display:grid;place-items:center;min-height:286px;border:1px dashed #cbd5e1;border-radius:8px;background:#f8fafc}.qr{width:min(260px,78vw);height:min(260px,78vw);image-rendering:pixelated}.qr-placeholder{display:flex;min-height:260px;align-items:center;justify-content:center;flex-direction:column;text-align:center;color:var(--muted);padding:22px}.qr-placeholder strong{display:block;color:var(--text);font-size:18px;margin-top:12px}.qr-placeholder span{display:block;margin-top:4px}.spinner{width:34px;height:34px;border-radius:999px;border:3px solid #dbe4ef;border-top-color:var(--accent);animation:spin 1s linear infinite}.check{display:grid;place-items:center;width:42px;height:42px;border-radius:999px;background:#e7f7ef;color:var(--ok);font-size:26px;font-weight:900}.qr-link{margin:12px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.qr-link a{color:var(--accent);text-decoration:none}.qr-link a:hover{text-decoration:underline}.hint{margin:0 0 18px;color:var(--muted)}.details{display:grid;gap:10px;margin-top:10px}details{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow)}summary{cursor:pointer;padding:13px 16px;font-weight:800}pre{margin:0;border-top:1px solid var(--line);background:#0f172a;color:#dbeafe;padding:14px 16px;max-height:340px;overflow:auto;white-space:pre-wrap;font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}.empty{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:26px;color:var(--muted)}@keyframes spin{to{transform:rotate(360deg)}}@media(max-width:760px){.page{padding:20px 12px 28px}.topbar{display:block}.actions{min-width:0}.topbar button{width:100%}.qr-grid{grid-template-columns:1fr}.qr-wrap{min-height:240px}.qr-placeholder{min-height:220px}.brand h1{font-size:23px}}
</style></head>
<body><main class=page><div class=topbar><div class=brand><h1>Nako Agent Factory</h1><p>同一个客户端 IP 只会分配一个 agent；可选择 OpenClaw 或 Hermes 作为消息后端，已绑定平台可在卡片里解绑重扫。</p></div><div class=actions><div class=runtime-switch aria-label="Agent runtime"><label><input type=radio name=runtime value=openclaw checked><span>OpenClaw</span></label><label><input type=radio name=runtime value=hermes><span>Hermes</span></label></div><button id=createBtn onclick="create()" disabled>载入中...</button></div></div><div id=out><div class=empty>正在载入当前 agent...</div></div></main>
<script>
let timer=null;
let lastState=null;
let runtimeTouched=false;
let desiredRuntime=null;
const platforms=[
  {key:'feishu',name:'飞书',desc:'使用飞书 / Lark 手机 App 扫码绑定'},
  {key:'weixin',name:'微信',desc:'使用微信扫码连接 ilink 机器人'}
];
const finalStatuses=['ready','qr_expired','install_failed','unknown','corrupt'];
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function validRuntime(s){return s==='hermes'?'hermes':'openclaw';}
function selectedRuntime(){return validRuntime(desiredRuntime||document.querySelector('input[name=runtime]:checked')?.value||'openclaw');}
function runtimeName(s){return s==='hermes'?'Hermes':(s==='qclaw'?'QClaw':'OpenClaw');}
function currentRuntime(j){return j.runtime||'openclaw';}
function updateActionText(){const btn=document.getElementById('createBtn');if(btn&&!btn.disabled)btn.textContent='切换到 '+runtimeName(selectedRuntime())+' / 刷新二维码';}
function setRuntimeControl(value,touched=false){const v=validRuntime(value);desiredRuntime=v;if(touched)runtimeTouched=true;const input=document.querySelector('input[name=runtime][value="'+v+'"]');if(input)input.checked=true;updateActionText();}
function initializeRuntimeControl(j){if(!runtimeTouched)setRuntimeControl(currentRuntime(j));}
function statusLabel(s){return ({queued:'排队中',installing:'安装中',installed:'已安装',generating_qr:'生成二维码中',awaiting_scan:'等待扫码',ready:'就绪',qr_expired:'二维码已过期',install_failed:'安装失败',unknown:'未知',corrupt:'状态损坏'})[s]||s||'未知';}
function statusClass(s){if(s==='ready')return'status-ready';if(s==='install_failed'||s==='corrupt')return'status-bad';if(s==='qr_expired'||s==='unknown')return'status-warn';return'status-working';}
function isBound(j,key){return (j.bound_platforms||[]).includes(key);}
function isUnbound(j,key){return (j.unbound_platforms||[]).includes(key);}
function platformRuntime(j,key){return (j.platform_runtimes||{})[key]||j.runtime||'openclaw';}
function summaryHTML(j){
  const current=currentRuntime(j);
  const selected=selectedRuntime();
  const pills=[
    '<span class="pill '+statusClass(j.status)+'"><strong>状态：</strong>'+esc(statusLabel(j.status))+'</span>',
    '<span class=pill><strong>Agent：</strong>'+esc(j.agent_id||'-')+'</span>',
    '<span class=pill><strong>当前后端：</strong>'+esc(runtimeName(current))+'</span>'
  ];
  if(j.model_label){
    pills.push('<span class=pill><strong>模型：</strong>'+esc(j.model_label)+'</span>');
  }
  if(selected!==current){
    pills.push('<span class=pill><strong>已选择：</strong>'+esc(runtimeName(selected))+'</span>');
  }
  pills.push('<span class=pill><strong>IP：</strong>'+esc(j.client_ip||'-')+'</span>');
  return pills.join('');
}
function hintText(j){
  const unbound=(j.unbound_platforms||[]).map(x=>platforms.find(p=>p.key===x)?.name||x).join('、');
  const current=currentRuntime(j);
  const backend=runtimeName(current);
  const target=selectedRuntime()!==current?('已选择：'+runtimeName(selectedRuntime())+'；点击上方按钮后会切换并生成二维码。'):'';
  return unbound?('当前后端：'+backend+'。'+target+'未绑定：'+unbound+'。二维码超时后再次点击上方按钮即可刷新。'):'当前后端：'+backend+'。'+target+'飞书和微信均已绑定；如需换绑，点击对应卡片的“解绑并重扫”。';
}
function qrHTML(j){return platforms.map(p=>renderQR(j,p)).join('');}
function renderQR(j,p){
  const img=j[p.key+'_qr_image'];
  const url=j[p.key+'_qr_url'];
  const bound=isBound(j,p.key);
  const working=['queued','installing','installed','generating_qr','awaiting_scan'].includes(j.status)||j.qr_refresh_in_progress;
  let body='';
  const backend=runtimeName(platformRuntime(j,p.key));
  let state=bound?('已绑定到 '+backend):(working?'正在生成':'待生成');
  if(img&&!bound){
    body='<img class=qr src="'+esc(img)+'" alt="'+esc(p.name)+'二维码">';
    state='待扫码';
  }else if(bound){
    body='<div class=qr-placeholder><div class=check>✓</div><strong>扫码绑定到 '+esc(backend)+'</strong><span>当前消息后端：'+esc(runtimeName(currentRuntime(j)))+'</span></div>';
  }else{
    body='<div class=qr-placeholder><div class=spinner></div><strong>正在生成二维码</strong><span>'+esc(p.desc)+'</span></div>';
  }
  const link=url&&!bound?'<p class=qr-link><a href="'+esc(url)+'" target="_blank" rel="noreferrer">'+esc(url)+'</a></p>':'<p class=qr-link><span class=muted>链接生成后会显示在这里</span></p>';
  const action=bound&&!working?'<button class=small-btn onclick="rebind('+Number(j.id)+',\\''+esc(p.key)+'\\',\\''+esc(p.name)+'\\')">解绑并重扫</button>':'';
  return '<section class=qr-card><div class=qr-head><div class=qr-title>'+esc(p.name)+'</div><div class=qr-state>'+esc(state)+'</div></div><div class=qr-wrap>'+body+'</div>'+link+action+'</section>';
}
function render(j){
  lastState=j;
  document.getElementById('out').innerHTML='<div id=qrGrid class=qr-grid>'+qrHTML(j)+'</div><div id=summary class=summary>'+summaryHTML(j)+'</div><p id=hint class=hint>'+esc(hintText(j))+'</p><div class=details><details id=infoDetails><summary>运行信息</summary><pre id=info></pre></details><details id=logDetails><summary>安装 / 二维码日志</summary><pre id=log></pre></details></div>';
  updateDetails(j,true);
}
function updateDetails(j,forceScroll){
  const info=document.getElementById('info');
  if(info) info.textContent=JSON.stringify(j,null,2);
  const log=document.getElementById('log');
  if(log){
    const atBottom=log.scrollTop+log.clientHeight>=log.scrollHeight-24;
    log.textContent=j.log_tail||'暂无日志';
    if(forceScroll||atBottom) log.scrollTop=log.scrollHeight;
  }
}
function updateLive(j){
  lastState=j;
  const qr=document.getElementById('qrGrid');
  if(!qr){render(j);return;}
  qr.innerHTML=qrHTML(j);
  const summary=document.getElementById('summary');
  if(summary) summary.innerHTML=summaryHTML(j);
  const hint=document.getElementById('hint');
  if(hint) hint.textContent=hintText(j);
  updateDetails(j,false);
}
async function create(){
  const btn=document.getElementById('createBtn');
  const runtime=selectedRuntime();
  btn.disabled=true;btn.textContent='处理中...';
  try{
    const r=await fetch('/create?runtime='+encodeURIComponent(runtime),{method:'POST'});const j=await r.json();
    render(j);
    poll(j.id);
  }finally{
    btn.disabled=false;updateActionText();
  }
}
async function rebind(id,platform,name){
  const runtime=selectedRuntime();
  const backend=runtimeName(runtime);
  if(!confirm('解绑 '+name+' 并重新绑定到 '+backend+'？')) return;
  const btn=document.getElementById('createBtn');
  btn.disabled=true;btn.textContent='处理中...';
  try{
    const r=await fetch('/rebind?id='+encodeURIComponent(id)+'&platform='+encodeURIComponent(platform)+'&runtime='+encodeURIComponent(runtime),{method:'POST'});
    const j=await r.json();
    render(j);
    poll(j.id);
  }finally{
    btn.disabled=false;updateActionText();
  }
}
async function poll(id){
  if(timer) clearTimeout(timer);
  const r=await fetch('/status?id='+id);const j=await r.json();
  updateLive(j);
  if(!finalStatuses.includes(j.status)){
    timer=setTimeout(()=>poll(id),2000);
  }
}
function setCreateButton(enabled,text){
  const btn=document.getElementById('createBtn');
  if(!btn)return;
  btn.disabled=!enabled;
  btn.textContent=text||'生成 / 刷新二维码';
}
async function loadCurrent(){
  try{
    const r=await fetch('/current');
    const j=await r.json();
    if(j.existing){
      initializeRuntimeControl(j);
      render(j);
      if(!finalStatuses.includes(j.status))poll(j.id);
    }else{
      setRuntimeControl(j.runtime||selectedRuntime());
      document.getElementById('out').innerHTML='<div class=empty>选择后端并点击按钮，开始安装 agent 并生成飞书、微信二维码。</div>';
    }
  }finally{
    setCreateButton(true);
    updateActionText();
  }
}
document.querySelectorAll('input[name=runtime]').forEach(input=>{
  input.addEventListener('change',()=>{setRuntimeControl(input.value,true);if(lastState)updateLive(lastState);});
});
loadCurrent();
</script></body></html>""".encode("utf-8"))
            return
        if u.path == "/current":
            client_ip = client_ip_from_request(self)
            return self._json(200, current_job_payload_for_ip(client_ip))
        if u.path == "/status":
            try: n = int(q.get("id", ["0"])[0])
            except: return self._json(400, {"error": "bad id"})
            return self._json(200, status_payload(n))
        if u.path == "/log":
            try: n = int(q.get("id", ["0"])[0])
            except: return self._json(400, {"error": "bad id"})
            p = log_path_for(n)
            if not p.exists(): return self._json(404, {"error": "log not ready"})
            self.send_response(200); self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store, max-age=0")
            self.end_headers()
            self.wfile.write(p.read_text(errors="replace").encode("utf-8"))
            return
        if u.path == "/qr":
            try: n = int(q.get("id", ["0"])[0])
            except: return self._json(400, {"error": "bad id"})
            plat = q.get("platform", ["feishu"])[0]
            if plat not in QR_PLATFORMS: return self._json(400, {"error": "bad platform"})
            p = JOB_DIR / f"agent-nako-{n}-{plat}.png"
            if not p.exists(): return self._json(404, {"error": "qr not ready"})
            self.send_response(200); self.send_header("Content-Type", "image/png"); self.end_headers()
            self.wfile.write(p.read_bytes())
            return
        return self._json(404, {"error": "not found"})

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/create":
            client_ip = client_ip_from_request(self)
            runtime, runtime_error = factory_runtime_or_error(q.get("runtime", [DEFAULT_RUNTIME])[0])
            if runtime_error:
                return self._json(400, runtime_error)
            n, existing, client_ip = create_or_get_job_for_ip(client_ip, runtime)
            refresh_started = False
            aid = agent_id_for(n)
            bound_now = bound_platforms_for_agent(aid)
            if not existing:
                refresh_started = start_worker(n, force_qr=False, reason="new", runtime=runtime)
            elif agent_install_needed(aid, job_state(n), runtime):
                refresh_started = start_worker(n, force_qr=False, reason="repair", runtime=runtime)
            elif should_refresh_qr(n):
                refresh_started = start_worker(n, force_qr=True, reason="refresh", runtime=runtime)
            code = 200 if existing else 202
            payload = status_payload(n)
            payload.update({"id": n, "agent_id": agent_id_for(n),
                            "client_ip": client_ip,
                            "existing": existing,
                            "qr_refresh_started": refresh_started,
                            "status_url": f"/status?id={n}",
                            "log_url": f"/log?id={n}",
                            "next": "GET /status?id={} 查看状态和日志".format(n)})
            return self._json(code, payload)
        if u.path == "/rebind":
            try:
                n = int(q.get("id", ["0"])[0])
            except Exception:
                return self._json(400, {"error": "bad id"})
            plat = q.get("platform", [""])[0]
            if plat not in QR_PLATFORMS:
                return self._json(400, {"error": "bad platform"})
            state = job_state(n)
            if state.get("status") in ("unknown", "corrupt"):
                return self._json(404, {"error": "job not found"})

            aid = state.get("agent_id") or agent_id_for(n)
            runtime, runtime_error = factory_runtime_or_error(
                q.get("runtime", [""])[0],
                state.get("runtime") or DEFAULT_RUNTIME,
            )
            if runtime_error:
                return self._json(400, runtime_error)
            current_runtime = cc_project_runtime(aid)
            old_platform_runtime = normalized_platform_runtimes(
                state,
                {plat},
                current_runtime if current_runtime in RUNTIMES else normalize_runtime(state.get("runtime")),
            ).get(plat)
            removed = remove_platform_binding_for_agent(aid, plat)
            removed_sessions = reset_cc_connect_sessions_for_platform(aid, plat)
            old_openclaw_session = reset_openclaw_main_session(aid) if old_platform_runtime == "openclaw" else ""
            platform_runtimes = state.get("platform_runtimes")
            platform_runtimes = platform_runtimes if isinstance(platform_runtimes, dict) else {}
            platform_runtimes.pop(plat, None)
            log = log_path_for(n)
            log.parent.mkdir(exist_ok=True)
            with log.open("a") as f:
                f.write(
                    f"\n=== rebind requested old_runtime={old_platform_runtime or '-'} runtime={runtime} platform={plat} removed={removed} "
                    f"cc_sessions={','.join(removed_sessions) or '-'} "
                    f"openclaw_main={old_openclaw_session or '-'} ===\n"
                )
            write_state(
                n,
                status="generating_qr",
                agent_id=aid,
                runtime=runtime,
                qr_refresh_in_progress=True,
                cc_reload_platforms=sorted(bound_platforms_for_agent(aid)),
                platform_runtimes=platform_runtimes,
            )
            refresh_started = start_worker(n, force_qr=True, reason=f"rebind-{plat}", target_platforms=[plat], runtime=runtime)
            payload = status_payload(n)
            payload.update({
                "id": n,
                "agent_id": aid,
                "rebind_platform": plat,
                "binding_removed": removed,
                "cc_sessions_removed": removed_sessions,
                "openclaw_main_session_reset": bool(old_openclaw_session),
                "qr_refresh_started": refresh_started,
                "status_url": f"/status?id={n}",
                "log_url": f"/log?id={n}",
            })
            return self._json(202, payload)
        return self._json(404, {"error": "not found"})

    def log_message(self, fmt, *a):
        print(f"[{self.address_string()}] {fmt%a}")


class ReusableTCP(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    print(f"Nako factory listening on 0.0.0.0:{PORT}")
    print(f"Open: http://<this-host>:{PORT}/")
    threading.Thread(target=gateway_watchdog, daemon=True).start()
    ReusableTCP(("0.0.0.0", PORT), Handler).serve_forever()
