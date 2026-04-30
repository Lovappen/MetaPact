# Nako Agent Factory

This package deploys the current Nako web manager on a Linux host.

It starts a LAN HTTP service on port `8088`. The page creates one `agent-nako-N`
per client IP, runs the upstream OpenClaw agent install script, generates Feishu
and Weixin QR codes, and streams install / QR logs in the page.

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
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --agent-id agent-nako-N --non-interactive --force --with-cc-connect
```

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
- OpenClaw gateway log: `/tmp/openclaw/openclaw-gateway.log`

## Operations

```bash
systemctl status nako-agent-factory.service
journalctl -u nako-agent-factory.service -f
tail -f /root/.cc-connect/cc-connect.log
tail -f /tmp/openclaw/openclaw-gateway.log
```

## Environment

These can be set before running `install.sh`; they are written into the systemd
service:

- `NAKO_SERVER_PORT`, default `8088`
- `OPENCLAW_GATEWAY_PORT`, default `18789`
- `OPENCLAW_GATEWAY_HEAP_MB`, default `2048`
- `NAKO_GATEWAY_WATCHDOG_INTERVAL`, default `10`
- `NAKO_TRUSTED_PROXY_CIDRS`, default `127.0.0.0/8,::1/128,172.16.0.0/12`

## Included Fixes

- One client IP maps to one agent only.
- QR generation is refreshable when not yet bound.
- Bound platforms can be explicitly unbound and rebound from the QR card.
- The page updates only QR/status areas, so logs are not hidden by polling.
- Feishu and Weixin QR cards are shown at the top with placeholders.
- Install logs and runtime info are collapsed at the bottom.
- OpenClaw gateway is started with a larger Node heap and watched.
- cc-connect restarts are deduplicated per bound platform set.
- Stale OpenClaw ACP client processes are cleaned before cc-connect restart.

## Uninstall

```bash
sudo bash uninstall.sh
```

The uninstall script keeps runtime data under `/root/.nako-jobs`,
`/root/.cc-connect`, and `/root/.openclaw`.
