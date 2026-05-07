# Nako Agent Factory

This package deploys the current Nako web manager on a Linux host.

It starts a LAN HTTP service on port `8088`. The page creates one `agent-nako-N`
per client IP, lets the user choose OpenClaw or Hermes as the messaging runtime,
generates Feishu and Weixin QR codes, and streams install / QR logs in the page.

## Install

```bash
sudo bash install.sh
```

Or install directly from GitHub:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/nako-agent-factory/install.sh | sudo bash
```

Open:

```text
http://<server-ip>:8088/
```

The first click on the page runs:

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --agent-id agent-nako-N --runtime openclaw --non-interactive --force --with-cc-connect
```

Selecting Hermes uses `--runtime hermes`. QClaw binding is intentionally not
available from the web page; run `scripts/cc-connect-setup.sh --runtime qclaw`
from the same host/user that has QClaw installed.

If you want to preinstall OpenClaw and cc-connect while installing the web
manager, run:

```bash
sudo NAKO_PREINSTALL_OPENCLAW=1 bash install.sh
```

## Runtime Paths

- App code: `/opt/nako-agent-factory/nako-server.py`
- Service: `/etc/systemd/system/nako-agent-factory.service`
- Job state and QR images: `/root/.nako-jobs`
- cc-connect config and logs: `/root/.cc-connect`
- OpenClaw data: `/root/.openclaw`
- Hermes data: `/root/.hermes`
- QClaw data: `/root/.qclaw` (or `QCLAW_HOME`), only for script-created QClaw projects
- OpenClaw gateway log: `/tmp/openclaw/openclaw-gateway.log`

## Operations

```bash
systemctl status nako-agent-factory.service
journalctl -u nako-agent-factory.service -f
tail -f /root/.cc-connect/cc-connect.log
tail -f /tmp/openclaw/openclaw-gateway.log
```

To remove one agent's cc-connect binding:

```bash
bash scripts/cc-connect-setup.sh --agent-id agent-nako-N --uninstall
```

To remove cc-connect and the default agent runtime data completely:

```bash
bash scripts/cc-connect-setup.sh --agent-id agent-nako --uninstall-all
```

## Environment

These can be set before running `install.sh`; they are written into the systemd
service:

- `NAKO_SERVER_PORT`, default `8088`
- `OPENCLAW_GATEWAY_PORT`, default `18789`
- `OPENCLAW_GATEWAY_HEAP_MB`, default `2048`
- `NAKO_GATEWAY_WATCHDOG_INTERVAL`, default `10`
- `NAKO_AGENT_RUNTIME`, default `openclaw`; set `hermes` to make the page and
  preinstall flow default to Hermes
- `QCLAW_HOME`, default `/root/.qclaw`
- `QCLAW_NODE_BIN` / `QCLAW_OPENCLAW_MJS`, optional overrides for existing
  script-created QClaw projects
- `NAKO_TRUSTED_PROXY_CIDRS`, default trusts loopback, RFC1918 LAN ranges,
  link-local ranges, and ULA IPv6 ranges for forwarded client IP headers
- `NAKO_FACTORY_HOST_IP`, optional override for the URL printed by `install.sh`

## Included Fixes

- One client IP maps to one agent only.
- QR generation is refreshable when not yet bound.
- Bound platforms can be explicitly unbound and rebound from the QR card.
- The page updates only QR/status areas, so logs are not hidden by polling.
- Feishu and Weixin QR cards are shown at the top with placeholders.
- Install logs and runtime info are collapsed at the bottom.
- OpenClaw gateway is started with a larger Node heap and watched.
- Hermes projects are not rewritten back to OpenClaw by the repair watchdog.
- QClaw projects are kept script-only; the Factory page does not create or
  rebind QClaw QR onboarding.
- cc-connect restarts are deduplicated per bound platform set.
- Stale OpenClaw ACP client processes are cleaned before cc-connect restart.

## Uninstall

```bash
sudo bash uninstall.sh
```

The uninstall script keeps runtime data under `/root/.nako-jobs`,
`/root/.cc-connect`, `/root/.openclaw`, and `/root/.hermes`.
