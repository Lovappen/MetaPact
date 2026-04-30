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
from pathlib import Path
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
OPENCLAW_GATEWAY_PORT = int(os.environ.get("OPENCLAW_GATEWAY_PORT", "18789"))
OPENCLAW_GATEWAY_HEAP_MB = os.environ.get("OPENCLAW_GATEWAY_HEAP_MB", "2048")
OPENCLAW_WATCHDOG_INTERVAL = int(os.environ.get("NAKO_GATEWAY_WATCHDOG_INTERVAL", "10"))
NPM_RENAME_TMP_RE = re.compile(r"^\.[^/]+-[A-Za-z0-9]{6,}$")
TRUSTED_PROXY_CIDRS = tuple(
    ipaddress.ip_network(c.strip())
    for c in os.environ.get("NAKO_TRUSTED_PROXY_CIDRS", "127.0.0.0/8,::1/128,172.16.0.0/12").split(",")
    if c.strip()
)

LOCK = threading.RLock()
QR_PROCS = {}
JOB_GENERATIONS = {}
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
            if ip:
                return ip

    for name in ("X-Real-IP", "CF-Connecting-IP", "True-Client-IP"):
        ip = parse_ip(headers.get(name))
        if ip:
            return ip

    forwarded = headers.get("Forwarded")
    if forwarded:
        for entry in forwarded.split(","):
            for part in entry.split(";"):
                key, sep, val = part.strip().partition("=")
                if sep and key.lower() == "for":
                    ip = parse_ip(val)
                    if ip:
                        return ip
    return None


def client_ip_from_request(handler) -> str:
    peer_ip = parse_ip(handler.client_address[0]) or handler.client_address[0]
    if trusted_proxy(peer_ip):
        return forwarded_header_ip(handler.headers) or peer_ip
    return peer_ip


def ensure_cc_connect_config():
    if CC_CONFIG.exists():
        return
    CC_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    CC_CONFIG.write_text('[log]\nlevel = "info"\n')
    os.chmod(CC_CONFIG, 0o600)


def agent_id_for(n: int) -> str:
    return f"agent-nako-{n}"


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


def status_payload(n: int) -> dict:
    state = job_state(n)
    aid = state.get("agent_id") or agent_id_for(n)
    if state.get("status") not in ("unknown", "corrupt"):
        state.setdefault("agent_id", aid)

    bound = bound_platforms_for_agent(aid)
    state["bound_platforms"] = sorted(bound)
    state["unbound_platforms"] = [plat for plat in QR_PLATFORMS if plat not in bound]
    state["openclaw_agent_configured"] = openclaw_agent_configured(aid)
    with LOCK:
        active_qr = any(proc.poll() is None for proc in QR_PROCS.get(n, []))
    if state.get("status") == "awaiting_scan" and not active_qr:
        next_status = "qr_expired" if state["unbound_platforms"] else "ready"
        state["status"] = next_status
        state["qr_refresh_in_progress"] = False
        write_state(n, status=next_status, qr_refresh_in_progress=False)
    requested = set(state.get("cc_reload_platforms") or [])
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


def agent_install_command(aid: str) -> str:
    urls = " ".join(shlex.quote(url) for url in (INSTALL_URLS or DEFAULT_INSTALL_URLS))
    agent = shlex.quote(aid)
    return (
        "set -o pipefail; rc=1; "
        f"for url in {urls}; do "
        'echo "=== downloading installer: $url ==="; '
        f"if curl --retry 3 --connect-timeout 20 -fsSL \"$url\" | bash -s -- --agent-id {agent} --non-interactive --force --with-cc-connect; then "
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


def agent_install_needed(aid: str, state: dict) -> bool:
    return state.get("install_rc") != 0 or not openclaw_agent_configured(aid)


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
        needed = {
            "work_dir": f'work_dir = "{HOME / ".openclaw"}"',
            "command": 'command = "openclaw"',
            "args": f'args = ["acp", "--session", "agent:{name}:main"]',
            "display_name": f'display_name = "OpenClaw {name}"',
            "env": f'env = {{ OPENCLAW_OUTPUT_MODE = "acp", OPENCLAW_CCCONNECT_PROJECT = "{name}" }}',
        }
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
        was_up = tcp_port_open("127.0.0.1", port)
        if not was_up:
            stop_openclaw_clients()
        ok = ensure_openclaw_gateway(tool_env())
        if ok and not was_up:
            schedule_cc_connect_restart(tool_env(), reason="gateway-watchdog", delay=35.0)
        elif ok and has_cc_projects() and not cc_connect_main_pids():
            schedule_cc_connect_restart(tool_env(), reason="cc-connect-watchdog", delay=2.0)
        time.sleep(OPENCLAW_WATCHDOG_INTERVAL)


def start_cc_connect(env: dict, reason: str = ""):
    with CC_RESTART_LOCK:
        log = HOME / ".cc-connect/cc-connect.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        removed = prune_empty_cc_projects()
        repaired = repair_nako_cc_projects()
        gateway_ok = ensure_openclaw_gateway(env)
        approved_devices = approve_local_openclaw_device_repairs(env) if gateway_ok else []

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
            if approved_devices:
                f.write(("=== approved local openclaw device repairs: " + ", ".join(approved_devices) + " ===\n").encode("utf-8"))
            subprocess.Popen(["cc-connect"], stdout=f, stderr=subprocess.STDOUT,
                             stdin=subprocess.DEVNULL, env=env, start_new_session=True)


def schedule_cc_connect_restart(env: dict, reason: str = "", delay: float = 2.0):
    global CC_RESTART_TIMER
    env_copy = env.copy()
    with CC_RESTART_LOCK:
        if CC_RESTART_TIMER is not None:
            CC_RESTART_TIMER.cancel()
        CC_RESTART_TIMER = threading.Timer(delay, start_cc_connect, args=(env_copy, reason))
        CC_RESTART_TIMER.daemon = True
        CC_RESTART_TIMER.start()


def schedule_reload_for_bound_platforms(n: int, bound: set, env: dict, reason: str) -> bool:
    if not bound:
        return False
    desired = set(bound)
    current = set(job_state(n).get("cc_reload_platforms") or [])
    if desired == current:
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
    return re.search(r"(?m)^\[\[projects\]\]\s*$", text) is not None


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


def create_or_get_job_for_ip(client_ip: str):
    client_ip = client_ip or "unknown"
    with LOCK:
        index = load_ip_index()
        n = existing_job_for_ip(client_ip, index)
        if n is not None:
            return n, True, client_ip

        n = alloc_id()
        aid = f"agent-nako-{n}"
        write_state(n, status="queued", agent_id=aid, client_ip=client_ip)
        index[client_ip] = n
        save_ip_index(index)
        return n, False, client_ip


def run_install_and_qr(n: int, force_qr: bool = False, generation: int = None, target_platforms=None):
    """Background worker: install agent when needed, then run QR onboarding."""
    aid = agent_id_for(n)
    log = JOB_DIR / f"{aid}.log"
    env = tool_env()
    if generation is None:
        generation = next_generation(n)
    target_platforms = [p for p in (target_platforms or []) if p in QR_PLATFORMS]
    ensure_cc_connect_config()

    state = job_state(n)
    install_needed = agent_install_needed(aid, state)
    if install_needed:
        write_state(n, status="installing", agent_id=aid, qr_generation=generation)
        with log.open("w") as f:
            # Install (idempotent)
            rc = subprocess.run(
                ["bash", "-c", agent_install_command(aid)],
                stdout=f, stderr=subprocess.STDOUT, env=env).returncode
            f.write(f"\n=== install rc={rc} ===\n")

        if rc != 0:
            if generation_current(n, generation):
                write_state(n, status="install_failed", install_rc=rc)
            return

        gateway_ok, stopped_clients, stopped_gateways = restart_openclaw_gateway(env)
        with log.open("a") as f:
            f.write(
                "\n=== restarted openclaw gateway after install: "
                f"ok={gateway_ok} clients={stopped_clients} gateways={stopped_gateways} ===\n"
            )
        write_state(n, status="installed", install_rc=rc)

    if not generation_current(n, generation):
        return

    platforms = target_platforms or unbound_platforms_for_agent(aid)
    if not platforms:
        bound = bound_platforms_for_agent(aid)
        write_state(n, status="ready", qr_refresh_in_progress=False,
                    bound_platforms=sorted(bound),
                    unbound_platforms=[])
        schedule_reload_for_bound_platforms(n, bound, env, reason=f"{aid}:already-bound")
        return

    with log.open("a") as f:
        f.write(
            f"\n=== qr generation {generation} force={force_qr} "
            f"platforms={','.join(platforms)} ===\n"
        )

    clear_qr = {}
    for plat in platforms:
        qr_path = JOB_DIR / f"{aid}-{plat}.png"
        try:
            qr_path.unlink()
        except FileNotFoundError:
            pass
        clear_qr[f"{plat}_qr_url"] = None
        clear_qr[f"{plat}_qr_image"] = None
        clear_qr[f"{plat}_rc"] = None
    write_state(n, status="generating_qr", agent_id=aid, qr_generation=generation,
                qr_refresh_in_progress=True, **clear_qr)

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

    write_state(n, status="awaiting_scan")

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
        write_state(n, bound_platforms=sorted(bound_now), unbound_platforms=unbound_now,
                    **rc_updates)
        if bound_now and bound_now != last_bound:
            with log.open("a") as f:
                f.write(f"\n=== detected bound platforms: {', '.join(sorted(bound_now))}; scheduling cc-connect reload ===\n")
            schedule_reload_for_bound_platforms(
                n, bound_now, env, reason=f"{aid}:bound-{','.join(sorted(bound_now))}"
            )
            last_bound = set(bound_now)

        if remaining:
            time.sleep(2)

    if not generation_current(n, generation):
        return

    bound = bound_platforms_for_agent(aid)
    unbound = [plat for plat in QR_PLATFORMS if plat not in bound]
    write_state(n, status="ready" if not unbound else "qr_expired",
                qr_refresh_in_progress=False,
                bound_platforms=sorted(bound),
                unbound_platforms=unbound,
                **rc_updates)
    if bound:
        schedule_reload_for_bound_platforms(n, bound, env, reason=f"{aid}:qr-finished")


def start_worker(n: int, force_qr: bool = False, reason: str = "", target_platforms=None) -> bool:
    generation = next_generation(n)
    target_platforms = [p for p in (target_platforms or []) if p in QR_PLATFORMS]
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
        write_state(n, status="generating_qr", qr_refresh_in_progress=True, **clear_qr)
        stop_qr_processes(n)
    t = threading.Thread(
        target=run_install_and_qr,
        args=(n, force_qr, generation, target_platforms),
        daemon=True,
    )
    t.start()
    return True


class Handler(http.server.BaseHTTPRequestHandler):
    def _json(self, code, obj):
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(obj, ensure_ascii=False).encode())

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/":
            self.send_response(200); self.send_header("Content-Type", "text/html; charset=utf-8"); self.end_headers()
            self.wfile.write("""<!doctype html><html lang="zh-CN"><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><title>Nako Factory</title>
<style>
:root{color-scheme:light;--bg:#f6f7f9;--panel:#fff;--text:#17202a;--muted:#687385;--line:#dde3ea;--accent:#2563eb;--accent-dark:#1d4ed8;--ok:#0f8a5f;--warn:#a16207;--bad:#b42318;--shadow:0 14px 36px rgba(20,30,45,.08)}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,"PingFang SC","Microsoft YaHei",sans-serif}.page{width:min(1120px,100%);margin:0 auto;padding:28px 18px 36px}.topbar{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:18px}.brand h1{margin:0;font-size:26px;line-height:1.2;letter-spacing:0}.brand p{margin:6px 0 0;color:var(--muted)}button{border:0;border-radius:8px;background:var(--accent);color:#fff;padding:11px 16px;font-weight:700;font-size:15px;cursor:pointer;white-space:nowrap;box-shadow:0 8px 18px rgba(37,99,235,.18)}button:hover{background:var(--accent-dark)}button:disabled{cursor:wait;opacity:.72}.small-btn{width:100%;margin-top:12px;background:#fff;color:var(--accent);border:1px solid #bfd0ff;box-shadow:none;padding:9px 12px;font-size:14px}.small-btn:hover{background:#eef4ff}.summary{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0 18px}.pill{display:inline-flex;align-items:center;min-height:30px;border:1px solid var(--line);border-radius:999px;background:#fff;padding:4px 10px;color:var(--muted);font-size:13px}.pill strong{color:var(--text);font-weight:700}.status-ready{color:var(--ok)}.status-working{color:var(--accent)}.status-warn{color:var(--warn)}.status-bad{color:var(--bad)}.qr-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;margin-bottom:18px}.qr-card{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:18px}.qr-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:14px}.qr-title{font-size:18px;font-weight:800}.qr-state{font-size:13px;color:var(--muted);white-space:nowrap}.qr-wrap{display:grid;place-items:center;min-height:286px;border:1px dashed #cbd5e1;border-radius:8px;background:#f8fafc}.qr{width:min(260px,78vw);height:min(260px,78vw);image-rendering:pixelated}.qr-placeholder{display:flex;min-height:260px;align-items:center;justify-content:center;flex-direction:column;text-align:center;color:var(--muted);padding:22px}.qr-placeholder strong{display:block;color:var(--text);font-size:18px;margin-top:12px}.qr-placeholder span{display:block;margin-top:4px}.spinner{width:34px;height:34px;border-radius:999px;border:3px solid #dbe4ef;border-top-color:var(--accent);animation:spin 1s linear infinite}.check{display:grid;place-items:center;width:42px;height:42px;border-radius:999px;background:#e7f7ef;color:var(--ok);font-size:26px;font-weight:900}.qr-link{margin:12px 0 0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.qr-link a{color:var(--accent);text-decoration:none}.qr-link a:hover{text-decoration:underline}.hint{margin:0 0 18px;color:var(--muted)}.details{display:grid;gap:10px;margin-top:10px}details{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow)}summary{cursor:pointer;padding:13px 16px;font-weight:800}pre{margin:0;border-top:1px solid var(--line);background:#0f172a;color:#dbeafe;padding:14px 16px;max-height:340px;overflow:auto;white-space:pre-wrap;font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}.empty{background:var(--panel);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:26px;color:var(--muted)}@keyframes spin{to{transform:rotate(360deg)}}@media(max-width:760px){.page{padding:20px 12px 28px}.topbar{display:block}.topbar button{width:100%;margin-top:14px}.qr-grid{grid-template-columns:1fr}.qr-wrap{min-height:240px}.qr-placeholder{min-height:220px}.brand h1{font-size:23px}}
</style></head>
<body><main class=page><div class=topbar><div class=brand><h1>Nako Agent Factory</h1><p>同一个客户端 IP 只会分配一个 agent；未绑定时再次点击会刷新二维码，已绑定平台可在卡片里解绑重扫。</p></div><button id=createBtn onclick="create()">生成 / 刷新二维码</button></div><div id=out><div class=empty>点击按钮后开始安装并生成飞书、微信二维码。</div></div></main>
<script>
let timer=null;
const platforms=[
  {key:'feishu',name:'飞书',desc:'使用飞书 / Lark 手机 App 扫码绑定'},
  {key:'weixin',name:'微信',desc:'使用微信扫码连接 ilink 机器人'}
];
const finalStatuses=['ready','qr_expired','install_failed','unknown','corrupt'];
function esc(s){return String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function statusLabel(s){return ({queued:'排队中',installing:'安装中',installed:'已安装',generating_qr:'生成二维码中',awaiting_scan:'等待扫码',ready:'就绪',qr_expired:'二维码已过期',install_failed:'安装失败',unknown:'未知',corrupt:'状态损坏'})[s]||s||'未知';}
function statusClass(s){if(s==='ready')return'status-ready';if(s==='install_failed'||s==='corrupt')return'status-bad';if(s==='qr_expired'||s==='unknown')return'status-warn';return'status-working';}
function isBound(j,key){return (j.bound_platforms||[]).includes(key);}
function isUnbound(j,key){return (j.unbound_platforms||[]).includes(key);}
function summaryHTML(j){
  return [
    '<span class="pill '+statusClass(j.status)+'"><strong>状态：</strong>'+esc(statusLabel(j.status))+'</span>',
    '<span class=pill><strong>Agent：</strong>'+esc(j.agent_id||'-')+'</span>',
    '<span class=pill><strong>IP：</strong>'+esc(j.client_ip||'-')+'</span>'
  ].join('');
}
function hintText(j){
  const unbound=(j.unbound_platforms||[]).map(x=>platforms.find(p=>p.key===x)?.name||x).join('、');
  return unbound?('未绑定：'+unbound+'。二维码超时后再次点击上方按钮即可刷新。'):'飞书和微信均已绑定；如需换绑，点击对应卡片的“解绑并重扫”。';
}
function qrHTML(j){return platforms.map(p=>renderQR(j,p)).join('');}
function renderQR(j,p){
  const img=j[p.key+'_qr_image'];
  const url=j[p.key+'_qr_url'];
  const bound=isBound(j,p.key);
  const working=['queued','installing','installed','generating_qr','awaiting_scan'].includes(j.status)||j.qr_refresh_in_progress;
  let body='';
  let state=bound?'已绑定':(working?'正在生成':'待生成');
  if(img&&!bound){
    body='<img class=qr src="'+esc(img)+'" alt="'+esc(p.name)+'二维码">';
    state='待扫码';
  }else if(bound){
    body='<div class=qr-placeholder><div class=check>✓</div><strong>已绑定</strong><span>'+esc(p.name)+' 已可使用</span></div>';
  }else{
    body='<div class=qr-placeholder><div class=spinner></div><strong>正在生成二维码</strong><span>'+esc(p.desc)+'</span></div>';
  }
  const link=url&&!bound?'<p class=qr-link><a href="'+esc(url)+'" target="_blank" rel="noreferrer">'+esc(url)+'</a></p>':'<p class=qr-link><span class=muted>链接生成后会显示在这里</span></p>';
  const action=bound&&!working?'<button class=small-btn onclick="rebind('+Number(j.id)+',\\''+esc(p.key)+'\\',\\''+esc(p.name)+'\\')">解绑并重扫</button>':'';
  return '<section class=qr-card><div class=qr-head><div class=qr-title>'+esc(p.name)+'</div><div class=qr-state>'+esc(state)+'</div></div><div class=qr-wrap>'+body+'</div>'+link+action+'</section>';
}
function render(j){
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
  btn.disabled=true;btn.textContent='处理中...';
  try{
    const r=await fetch('/create',{method:'POST'});const j=await r.json();
    render(j);
    poll(j.id);
  }finally{
    btn.disabled=false;btn.textContent='生成 / 刷新二维码';
  }
}
async function rebind(id,platform,name){
  if(!confirm('解绑 '+name+' 并重新生成二维码？')) return;
  const btn=document.getElementById('createBtn');
  btn.disabled=true;btn.textContent='处理中...';
  try{
    const r=await fetch('/rebind?id='+encodeURIComponent(id)+'&platform='+encodeURIComponent(platform),{method:'POST'});
    const j=await r.json();
    render(j);
    poll(j.id);
  }finally{
    btn.disabled=false;btn.textContent='生成 / 刷新二维码';
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
</script></body></html>""".encode("utf-8"))
            return
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
            n, existing, client_ip = create_or_get_job_for_ip(client_ip)
            refresh_started = False
            if not existing:
                refresh_started = start_worker(n, force_qr=False, reason="new")
            elif agent_install_needed(agent_id_for(n), job_state(n)):
                refresh_started = start_worker(n, force_qr=False, reason="repair")
            elif should_refresh_qr(n):
                refresh_started = start_worker(n, force_qr=True, reason="refresh")
            code = 200 if existing else 202
            payload = status_payload(n)
            payload.update({"id": n, "agent_id": agent_id_for(n),
                            "client_ip": client_ip, "existing": existing,
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
            removed = remove_platform_binding_for_agent(aid, plat)
            log = log_path_for(n)
            log.parent.mkdir(exist_ok=True)
            with log.open("a") as f:
                f.write(f"\n=== rebind requested platform={plat} removed={removed} ===\n")
            write_state(
                n,
                status="generating_qr",
                agent_id=aid,
                qr_refresh_in_progress=True,
                cc_reload_platforms=sorted(bound_platforms_for_agent(aid)),
            )
            refresh_started = start_worker(n, force_qr=True, reason=f"rebind-{plat}", target_platforms=[plat])
            payload = status_payload(n)
            payload.update({
                "id": n,
                "agent_id": aid,
                "rebind_platform": plat,
                "binding_removed": removed,
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
