#!/usr/bin/env bash
set -euo pipefail

APP_NAME="nako-agent-factory"
INSTALL_DIR="${NAKO_INSTALL_DIR:-/opt/${APP_NAME}}"
SERVER_FILE="${INSTALL_DIR}/nako-server.py"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
PORT="${NAKO_SERVER_PORT:-8088}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_HEAP_MB="${OPENCLAW_GATEWAY_HEAP_MB:-2048}"
WATCHDOG_INTERVAL="${NAKO_GATEWAY_WATCHDOG_INTERVAL:-10}"
TRUSTED_PROXY_CIDRS="${NAKO_TRUSTED_PROXY_CIDRS:-127.0.0.0/8,::1/128,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.0.0/16,fc00::/7,fe80::/10}"
DEFAULT_RUNTIME="${NAKO_AGENT_RUNTIME:-openclaw}"
AGENTS_REF="${NAKO_AGENTS_REF:-main}"
INSTALL_URL="${NAKO_AGENT_INSTALL_URL:-https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@${AGENTS_REF}/install.sh}"
INSTALL_URLS="${NAKO_AGENT_INSTALL_URLS:-${INSTALL_URL} https://raw.githubusercontent.com/Lovappen/MetaPact/${AGENTS_REF}/install.sh}"
FACTORY_BASE_URL="${NAKO_FACTORY_BASE_URL:-https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@${AGENTS_REF}/scripts/nako-agent-factory}"
FACTORY_BASE_URLS="${NAKO_FACTORY_BASE_URLS:-${FACTORY_BASE_URL} https://raw.githubusercontent.com/Lovappen/MetaPact/${AGENTS_REF}/scripts/nako-agent-factory}"
PREINSTALL="${NAKO_PREINSTALL_OPENCLAW:-0}"
BOOTSTRAP_AGENT_ID="${NAKO_BOOTSTRAP_AGENT_ID:-agent-nako-bootstrap}"

case "${DEFAULT_RUNTIME}" in
  openclaw|hermes|qclaw) ;;
  *) echo "NAKO_AGENT_RUNTIME must be openclaw, hermes, or qclaw" >&2; exit 1 ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash install.sh" >&2
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_factory_host_ip() {
  if [ -n "${NAKO_FACTORY_HOST_IP:-}" ]; then
    printf '%s\n' "${NAKO_FACTORY_HOST_IP}"
    return 0
  fi

  if need_cmd ip; then
    local route_ip
    route_ip="$(
      { ip -o -4 route get "${NAKO_FACTORY_IP_PROBE:-1.1.1.1}" 2>/dev/null || true; } \
        | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}'
    )"
    if [ -n "${route_ip}" ] && [ "${route_ip}" != "127.0.0.1" ]; then
      printf '%s\n' "${route_ip}"
      return 0
    fi

    { ip -o -4 addr show scope global up 2>/dev/null || true; } | awk '
      {
        iface=$2
        split($4, addr, "/")
        ip=addr[1]
        if (iface ~ /^(lo|docker|br-|veth|virbr|zt|tailscale|tun|tap|wg)/) next
        if (ip ~ /^127\./ || ip ~ /^169\.254\./) next
        print ip
        exit
      }
    '
    return 0
  fi

  { hostname -I 2>/dev/null || true; } | awk '
    {
      for (i=1; i<=NF; i++) {
        if ($i !~ /^127\./ && $i !~ /^169\.254\./) {
          print $i
          exit
        }
      }
    }
  '
}

install_base_packages() {
  local missing=()
  for cmd in bash curl python3; do
    if ! need_cmd "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    return
  fi

  if need_cmd apt-get; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl python3 bash
  elif need_cmd dnf; then
    dnf install -y ca-certificates curl python3 bash
  elif need_cmd yum; then
    yum install -y ca-certificates curl python3 bash
  elif need_cmd apk; then
    apk add --no-cache ca-certificates curl python3 bash
  else
    echo "Missing commands: ${missing[*]}; install them first." >&2
    exit 1
  fi
}

install_base_packages

download_factory_file() {
  local name="$1" dest="$2" base last_rc=1
  for base in ${FACTORY_BASE_URLS}; do
    echo "Downloading ${name} from ${base}/${name}"
    if curl --retry 3 --connect-timeout 20 -fsSL "${base}/${name}" -o "${dest}"; then
      return 0
    else
      last_rc=$?
    fi
  done
  return "${last_rc}"
}

run_agent_installer() {
  local agent_id="$1" url last_rc=1
  for url in ${INSTALL_URLS}; do
    echo "Running Nako installer from ${url}"
    if curl --retry 3 --connect-timeout 20 -fsSL "${url}" | bash -s -- \
      --agent-id "${agent_id}" \
      --runtime "${DEFAULT_RUNTIME}" \
      --non-interactive \
      --force \
      --with-cc-connect; then
      return 0
    else
      last_rc=$?
    fi
  done
  return "${last_rc}"
}

TMP_DIR=""
cleanup() {
  [ -n "${TMP_DIR}" ] && rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
SERVER_SRC="${SCRIPT_DIR}/nako-server.py"
if [ ! -f "${SERVER_SRC}" ]; then
  TMP_DIR="$(mktemp -d)"
  SERVER_SRC="${TMP_DIR}/nako-server.py"
  download_factory_file "nako-server.py" "${SERVER_SRC}"
fi

mkdir -p "${INSTALL_DIR}" /root/.cc-connect /root/.nako-jobs /tmp/openclaw /var/tmp/openclaw-compile-cache
install -m 0755 "${SERVER_SRC}" "${SERVER_FILE}"

if [ ! -f /root/.cc-connect/config.toml ]; then
  cat > /root/.cc-connect/config.toml <<'EOF'
[log]
level = "info"
EOF
  chmod 0600 /root/.cc-connect/config.toml
fi

if [ "${PREINSTALL}" = "1" ]; then
  echo "Preinstalling OpenClaw and cc-connect with ${INSTALL_URL}"
  run_agent_installer "${BOOTSTRAP_AGENT_ID}"
fi

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Nako Agent Factory
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment=HOME=/root
Environment=NAKO_SERVER_PORT=${PORT}
Environment=OPENCLAW_GATEWAY_PORT=${GATEWAY_PORT}
Environment=OPENCLAW_GATEWAY_HEAP_MB=${GATEWAY_HEAP_MB}
Environment=NAKO_GATEWAY_WATCHDOG_INTERVAL=${WATCHDOG_INTERVAL}
Environment=NAKO_TRUSTED_PROXY_CIDRS=${TRUSTED_PROXY_CIDRS}
Environment=NAKO_AGENT_RUNTIME=${DEFAULT_RUNTIME}
Environment=QCLAW_HOME=${QCLAW_HOME:-/root/.qclaw}
Environment=QCLAW_NODE_BIN=${QCLAW_NODE_BIN:-}
Environment=QCLAW_OPENCLAW_MJS=${QCLAW_OPENCLAW_MJS:-}
ExecStart=/usr/bin/env python3 ${SERVER_FILE}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "${APP_NAME}.service"

FACTORY_HOST_IP="$(detect_factory_host_ip)"

echo
echo "Installed ${APP_NAME}"
echo "Service: systemctl status ${APP_NAME}.service"
echo "Logs:    journalctl -u ${APP_NAME}.service -f"
if [ -n "${FACTORY_HOST_IP}" ]; then
  echo "URL:     http://${FACTORY_HOST_IP}:${PORT}/"
else
  echo "URL:     http://<host-ip>:${PORT}/"
fi
echo "Override URL IP with: sudo NAKO_FACTORY_HOST_IP=<ip> bash install.sh"
echo
echo "Note: first agent creation runs:"
echo "  curl -fsSL ${INSTALL_URL} | bash -s -- --agent-id agent-nako-N --runtime ${DEFAULT_RUNTIME} --non-interactive --force --with-cc-connect"
echo "Fallback URLs: ${INSTALL_URLS}"
