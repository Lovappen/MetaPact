#!/usr/bin/env bash
set -euo pipefail

case "$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')" in
  mingw*|msys*|cygwin*)
    echo "Nako Agent Factory requires Linux/systemd; Windows local install uses pwsh install.ps1." >&2
    exit 1
    ;;
esac

APP_NAME="nako-agent-factory"
INSTALL_DIR="${NAKO_INSTALL_DIR:-/opt/${APP_NAME}}"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash uninstall.sh" >&2
  exit 1
fi

systemctl disable --now "${APP_NAME}.service" 2>/dev/null || true
rm -f "${SERVICE_FILE}"
systemctl daemon-reload
rm -rf "${INSTALL_DIR}"

cat <<EOF
Removed ${APP_NAME}.

Runtime data was kept:
  /root/.nako-jobs
  /root/.nako-counter
  /root/.cc-connect
  /root/.openclaw

Delete those manually only if you also want to remove generated agents,
QR state, cc-connect bindings, and OpenClaw data.
EOF
