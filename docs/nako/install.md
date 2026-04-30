# 安装详解

## 交互式安装

```bash
bash install.sh
```

安装器 8 步：

1. **前置检查** — 验证 `python3 jq curl`，`~/.openclaw` 存在，`openclaw.json` 存在。软依赖 (`whisper ffmpeg ffprobe xxd uuidgen doki`) 缺失只警告不退出。
2. **Agent 冲突** — 若 `agent-nako` workspace 已存在，问你升级、重命名、还是中止。
3. **模型映射** — 读 `~/.openclaw/openclaw.json` 的 `agents.defaults.models`，按 `config/model-map.yaml` 的 `roleplay` 偏好挑一个。找不到 → 退化到 `general`；还找不到 → 报错退出，让你先加模型。
4. **收集凭据** — 交互问：飞书 App ID/Secret、MiniMax、Volcengine、FAL、参考图。留空即跳过该能力。
5. **安装 skills** — 拷贝 `skills/{vision,hearing,voice,selfie,dokidoki,skill-log.sh}` 到 `~/.openclaw/skills/`。共享 `.env` 作为旧版 fallback 只填入新 key，已有值保留。
6. **安装 agent 人设** — 拷贝 `agent/*.md` 到 `~/.openclaw/workspace/<id>/`。`custom.md` 首次创建空壳，之后永远不动。
7. **合并 openclaw.json** — 备份旧配置 (`.bak-<ts>`)，把 agent 加到 `agents.list`，把 voice/selfie 的 provider key 写到 `skills.entries.*.env`。
8. **冒烟测试** — 检查每个 skill 的脚本、依赖、env 是否齐。

## Flags

| Flag | 说明 |
|---|---|
| `--force` | 覆盖已存在的人设文件（仍会备份） |
| `--agent-id <id>` | 改 agent id（默认 `agent-nako`） |
| `--non-interactive` | 不交互；从环境变量读所有凭据 |
| `--skip-skills` | 只装 agent 人设，跳过 skills |
| `--skip-models` | 不做模型映射，沿用 `openclaw.json` 现有 primary |
| `--reset-secrets` | 不复用已有 `.env` 凭据，重新按环境变量 / 交互输入写入 |
| `--with-cc-connect` | 安装并配置 cc-connect project |
| `--with-feishu` | 配置 cc-connect 并引导飞书 QR |
| `--with-weixin` | 配置 cc-connect 并引导微信 QR |
| `--cc-connect-source auto\|npm\|lazycat\|skip` | cc-connect 来源；默认 `auto`，微信会优先下载 CodeEagle fork release |

Windows PowerShell 对应参数使用 PascalCase，例如 `-ResetSecrets`、`-WithFeishu`、`-WithWeixin`、`-CcConnectSource lazycat`。PowerShell 的 cc-connect 自动接入会调用仓库里的 `scripts/cc-connect-setup.sh`，因此需要 Git Bash / WSL 等可用的 `bash`。

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

Windows:

```powershell
$env:FEISHU_APP_ID = "cli_xxx"
$env:FEISHU_APP_SECRET = "xxx"
$env:MINIMAX_API_KEY = "sk-xxx"
$env:MINIMAX_GROUP_ID = "123"
pwsh install.ps1 -NonInteractive
```

安装器会优先复用已有 `openclaw.json -> skills.entries.*.env`，再兼容复用 `~/.openclaw/skills/.env` 与 `<workspace>/skills/.env` 中的凭据；需要重新输入时加 `--reset-secrets` / `-ResetSecrets`。

## 重装 / 升级

直接重跑 `install.sh`。安装器会：

- ✅ 拉最新 skill 脚本（每个文件单独问是否覆盖）
- ✅ 合并 `openclaw.json` 的 `skills.entries.*.env`，并保留旧版 `.env` fallback
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
