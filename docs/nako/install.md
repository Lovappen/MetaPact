# 安装详解

## 交互式安装

```bash
bash install.sh
```

安装器 8 步：

1. **前置检查** — 验证 `python3 jq curl`。默认 OpenClaw 模式要求 `~/.openclaw/openclaw.json` 存在；`--runtime hermes` 只要求 `hermes` 命令可用，并使用 `~/.hermes`；`--runtime qclaw` 会直接使用 `~/.qclaw/openclaw.json`，不要求 `~/.openclaw`。软依赖 (`whisper ffmpeg ffprobe xxd uuidgen doki`) 缺失只警告不退出。
2. **Agent 冲突** — 若 `agent-nako` workspace 已存在，问你升级、重命名、还是中止。
3. **模型映射** — OpenClaw 会读 `~/.openclaw/openclaw.json` 的 `agents.defaults.models`，按 `config/model-map.yaml` 的 `roleplay` 偏好挑一个；Hermes 会沿用现有 `~/.hermes/config.yaml` 或 `HERMES_MODEL=provider/model`，其中 `sensenova/SenseChat-Character-Agt` 会被写成 Hermes `custom_providers` 的 OpenAI-compatible endpoint；没有可沿用模型时默认 `zai/glm-4.5-flash`；QClaw 继承 QClaw 模型路由。
4. **收集凭据** — 交互问：飞书 App ID/Secret、MiniMax、Volcengine、FAL、参考图。留空即跳过该能力。
5. **安装 skills** — OpenClaw/QClaw 拷贝到对应 runtime 的 `skills/`；Hermes 拷贝到 `~/.hermes/skills/nako/`。共享 `.env` 只填入新 key，已有值保留。
6. **安装 agent 人设** — OpenClaw 使用 `~/.openclaw/workspace/<id>/`；Hermes 使用 `~/.hermes/workspace/<id>/`；QClaw 使用 `~/.qclaw/workspace-<id>/`。`custom.md` 首次创建空壳，之后永远不动。
7. **合并 runtime 配置** — OpenClaw/QClaw 会备份并合并 `openclaw.json`；Hermes 不依赖 `~/.openclaw`，会重写 `~/.hermes/config.yaml` 中的顶层 `model` / `custom_providers` / `skills` Nako managed block。OpenAI-compatible 模型会按 Hermes schema 写入 `custom_providers` 列表，避免旧 OpenClaw skills 路径或错误 provider 格式在重装后继续生效，并读取 `~/.hermes/skills/nako/.env` / `~/.hermes/.env`。
8. **runtime 接入** — 默认使用 OpenClaw；`--runtime hermes` 会让 cc-connect 调 `hermes acp`，并注入 `NAKO_*` 环境变量；`--runtime qclaw` 会把 agent 写入 `~/.qclaw/workspace-<id>` 和 QClaw 的 `openclaw.json`，并让 cc-connect 调 QClaw 自带的 OpenClaw ACP。QClaw 的飞书/微信消息固定进入 `agent:<id>:session-cc-connect`，在 QClaw 里显示为 `cc-connect 飞书/微信` 会话。
9. **冒烟测试** — 检查每个 skill 的脚本、依赖、env 是否齐。

## Flags

| Flag | 说明 |
|---|---|
| `--force` | 覆盖已存在的人设文件（仍会备份） |
| `--agent-id <id>` | 改 agent id（默认 `agent-nako`） |
| `--runtime openclaw\|hermes\|qclaw` | 选择运行时和 cc-connect 消息后端；默认 `openclaw`。Hermes 模式要求已安装 `hermes`，直接使用 `~/.hermes`，不要求 `~/.openclaw`；QClaw 模式要求在同一 host/user 下已安装并启动过 QClaw 以生成 `~/.qclaw/qclaw.json`，但不要求 `~/.openclaw/openclaw.json` |
| `--non-interactive` | 不交互；从环境变量读所有凭据 |
| `--skip-skills` | 只装 agent 人设，跳过 skills |
| `--skip-models` | 不做 OpenClaw 模型映射；OpenClaw/QClaw 沿用现有 primary，Hermes 沿用 `HERMES_MODEL`、现有 `~/.hermes/config.yaml` 或默认 Hermes 主模型 |
| `--reset-secrets` | 不复用已有 `.env` 凭据，重新按环境变量 / 交互输入写入 |
| `--with-cc-connect` | 安装并配置 cc-connect project |
| `--with-feishu` | 配置 cc-connect 并引导飞书 QR |
| `--with-weixin` | 配置 cc-connect 并引导微信 QR |
| `--cc-connect-source auto\|npm\|lazycat\|skip` | cc-connect 来源；默认 `auto`，微信会优先下载 CodeEagle fork release |

卸载某个 agent 的 cc-connect 接入：

```bash
bash scripts/cc-connect-setup.sh --agent-id agent-nako --uninstall
```

如果要同时卸载 cc-connect daemon 并删除二进制，追加 `--purge-cc-connect`。

一键完整卸载 cc-connect 和当前 agent：

```bash
bash scripts/cc-connect-setup.sh --agent-id agent-nako --uninstall-all
```

完整卸载会停止 daemon/进程、移除二进制，把 `~/.cc-connect` 移到
`~/.cc-connect.bak-uninstall-all-*`，并从 OpenClaw/QClaw 配置中移除当前 `--agent-id`
（默认 `agent-nako`）。对应 workspace、agent 数据目录会移到
`~/.nako-agent.bak-uninstall-all-<agent-id>-*` 备份目录。

Windows PowerShell 对应参数使用 PascalCase，例如 `-Runtime qclaw`、`-ResetSecrets`、`-WithFeishu`、`-WithWeixin`、`-CcConnectSource lazycat`。PowerShell 的 cc-connect 自动接入会优先调用仓库里的 `scripts/cc-connect-setup.ps1`，不需要 Git Bash / WSL；只有旧包缺少 `.ps1` 时才会回退到 Bash 脚本。

PowerShell 下接入 QClaw：

```powershell
pwsh install.ps1 -Runtime qclaw -WithFeishu -WithWeixin
```

PowerShell 下一键完整卸载 cc-connect 和当前 agent：

```powershell
pwsh install.ps1 -AgentId agent-nako -UninstallAllCcConnect
```

## 非交互模式

CI 或脚本场景：

```bash
export FEISHU_APP_ID=cli_xxx
export FEISHU_APP_SECRET=xxx
export MINIMAX_API_KEY=sk-xxx
export MINIMAX_GROUP_ID=123
export FAL_KEY=xxx
export SELFIE_REFERENCE_IMAGE="https://..."
bash install.sh --non-interactive
```

直接安装到 QClaw：

```bash
bash install.sh --runtime qclaw --agent-id agent-nako --non-interactive
```

Windows:

```powershell
$env:FEISHU_APP_ID = "cli_xxx"
$env:FEISHU_APP_SECRET = "xxx"
$env:MINIMAX_API_KEY = "sk-xxx"
$env:MINIMAX_GROUP_ID = "123"
pwsh install.ps1 -NonInteractive
```

OpenClaw/QClaw 会优先复用已有 `openclaw.json -> skills.entries.*.env`，再兼容复用 runtime `skills/.env` 与 `<workspace>/skills/.env` 中的凭据。Hermes 会复用 `~/.hermes/skills/nako/.env`、`~/.hermes/.env` 与 `<workspace>/skills/.env`。需要重新输入时加 `--reset-secrets` / `-ResetSecrets`。

## 重装 / 升级

直接重跑 `install.sh`。安装器会：

- ✅ 拉最新 skill 脚本（每个文件单独问是否覆盖）
- ✅ OpenClaw/QClaw 合并 `openclaw.json` 的 `skills.entries.*.env`；Hermes 更新 `~/.hermes/config.yaml` 的 Nako managed block，并保留 `.env` fallback
- ✅ 保留 `custom.md` / `memory/` / `sessions/`
- ❌ 不会动 `openclaw.json` 中其他 agent 的配置

若想强制覆盖所有人设文件：`--force`。但 `custom.md`、memory、sessions 仍不动。

## 回滚

每次合并 `openclaw.json` 前都会备份：`openclaw.json.bak-YYYYMMDD-HHMMSS`。想回滚：

```bash
cp ~/.openclaw/openclaw.json.bak-20260424-120000 ~/.openclaw/openclaw.json
# 重启 gateway
launchctl kickstart -k gui/$(id -u)/ai.openclaw.gateway
```

删除 agent：

```bash
# 1. 从 agents.list 里删该 entry（手动编辑）
# 2. 删 workspace 和数据
rm -rf ~/.openclaw/workspace/agent-nako
rm -rf ~/.openclaw/agents/agent-nako
```

## 目录影响总览

安装后改动的位置：

```
~/.openclaw/
├── openclaw.json                     # 合并 (备份保留)
├── skills/
│   ├── vision/ hearing/ voice/ selfie/ dokidoki/   # 新增或更新
│   ├── skill-log.sh                  # 新增或更新
│   └── .env                          # key merge (只加不删)
└── workspace/
    └── <agent-id>/
        ├── AGENTS.md IDENTITY.md SOUL.md USER.md HEARTBEAT.md TOOLS.md
        ├── custom.md                  # 首装创建空壳，之后不动
        ├── custom.md.example
        ├── skills/.env                # per-agent, 飞书凭据 + 角色描述
        ├── memory/                    # 不动
        └── MEMORY.md                  # 不动
```
