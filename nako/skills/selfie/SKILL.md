---
name: selfie
description: Generate character-consistent selfie images and videos, send via the active Nako messaging channel. Character reference image and description come from per-agent env.
allowed-tools: Bash(*/selfie.sh:*) Bash(*/video.sh:*) Bash(curl:*) Bash(jq:*) Bash(sleep:*) Read Write WebFetch
---

# Selfie

Generate a selfie-style image (and optionally a short video) that preserves the agent's character identity, then send it back through the active Nako messaging channel.

## Character Identity

The character reference image URL and description are **injected via env vars** — not hardcoded in this file.

| Env var | Source | Purpose |
|---------|--------|---------|
| `SELFIE_REFERENCE_IMAGE` | per-agent `skills/.env` | Identity anchor image URL passed to image-to-image models |
| `SELFIE_CHARACTER_DESC` | per-agent `skills/.env` | Short textual traits; include in every prompt you build |

Each agent has its own `<workspace>/skills/.env`. Do not attempt to override these.

## When to Use

Trigger on: `"发张照片"` / `"自拍一张"` / `"send a pic"` / `"show me what you look like"` / `"穿...拍一张"` / `"发一张你在…的照片"`.

Skip for pure text replies.

In Feishu/Weixin/ACP sessions, always use `selfie.sh` / `video.sh` with channel `cc-connect`. Do not use OpenClaw native `image_generate` or `video_generate` there because those outputs stay in webchat media and are not delivered to Feishu/Weixin.

Native video red line: never call OpenClaw native `video_generate` in Feishu/Weixin/ACP sessions, even if it appears in the available tool list. For video requests, call `video.sh`; if it fails or times out, respond with a text failure notice instead of saying the native background job will send later.

ACP is not webchat: when running under cc-connect/ACP, ignore `messageProvider=webchat`. Do not set `NAKO_OUTPUT_MODE=webchat` and do not pass channel `webchat`; use `NAKO_OUTPUT_MODE=acp` and channel `cc-connect` so media is delivered to the active Feishu/Weixin session.

## Invocation

All scripts live in the shared install. In Hermes/cc-connect sessions, prefer `$NAKO_SKILLS_DIR`; only fall back to `~/.openclaw/skills` in an OpenClaw runtime.

```bash
bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/selfie/scripts/selfie.sh" "<prompt>" "<channel>" [caption] [aspect_ratio] [format] [provider]
```

| Arg | Required | Default | Notes |
|-----|----------|---------|-------|
| prompt | yes | — | Include `$SELFIE_CHARACTER_DESC` traits. |
| channel | yes | — | Feishu `oc_*` / `ou_*` chat id, or `cc-connect` in Hermes/cc-connect/ACP sessions for active-session routing (`feishu` remains a legacy alias). |
| caption | no | `Generated with Grok Imagine` | |
| aspect_ratio | no | `1:1` | |
| format | no | `jpeg` | fal only |
| provider | no | `auto` | `fal` / `kie` / `auto` — auto prefers `fal`, falls back to `kie`. |

### Video (two-step)

```bash
IMAGE_URL=$(bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/selfie/scripts/selfie.sh" "<prompt>" "<channel>" | jq -r '.image_url')
bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/selfie/scripts/video.sh" "$IMAGE_URL" "<motion prompt in English>" "<channel>" [caption] [fal|kie]
```

Video generation: 30–120s. Warn user before starting.

## Prompt Modes

### Mirror Selfie
Use for: outfit, fashion, full-body shots.
```
Create a mirror selfie. She is <USER_CONTEXT>.
<SELFIE_CHARACTER_DESC>.
Mirror composition, handheld phone visible, casual candid pose.
```

### Direct Selfie
Use for: cafe, beach, park, close-up, portrait, expression.
```
Create a close-up selfie. She is at <USER_CONTEXT>.
<SELFIE_CHARACTER_DESC>.
Direct eye contact, phone at arm's length, face fully visible.
```

## Prompting Rules

- Always include the traits from `$SELFIE_CHARACTER_DESC` verbatim.
- Do not describe other characters or let the model drift away from the reference identity.
- Prefer English prompts — the model handles English more consistently.

## Environment Variables

Shared (`$NAKO_SKILLS_DIR/.env`, `~/.hermes/.env`, or OpenClaw `openclaw.json → skills.entries.selfie.env`):

| Variable | Purpose |
|----------|---------|
| `FAL_KEY` | fal.ai API key |
| `KIE_API_KEY` | kie.ai API key |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway token (optional) |

Per-agent (`<workspace>/skills/.env`):

| Variable | Purpose |
|----------|---------|
| `SELFIE_REFERENCE_IMAGE` | Character reference image URL |
| `SELFIE_CHARACTER_DESC` | Character traits, included in prompts |
| `FEISHU_APP_ID` / `FEISHU_APP_SECRET` | Optional native Feishu credentials. In Hermes/cc-connect, QR binding credentials live in `~/.cc-connect/config.toml` and may be mirrored here after binding. Do not report Feishu missing just because this env file has empty placeholders. |

Per-agent values override shared when both define the same key.
