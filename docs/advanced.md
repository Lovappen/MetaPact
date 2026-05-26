# 进阶玩法：Agent 通用自定义与调优

这份文档面向整个 Agents 仓库，不绑定某一个 agent。所有 agent 都建议遵循同一套结构：通用玩法放在根目录 `docs/`，某个 agent 的特色玩法放在 `docs/<agent-name>/`。

如果你正在调 nako，先读这里，再看 [docs/nako/advanced.md](nako/advanced.md)。

## 推荐目录结构

```text
Agents/
├── docs/
│   ├── advanced.md              # 所有 agent 共用的进阶玩法
│   └── <agent-name>/
│       ├── install.md           # 该 agent 的安装说明
│       ├── skills.md            # 该 agent 的技能说明
│       ├── customization.md     # 该 agent 的快速定制
│       └── advanced.md          # 该 agent 的特色玩法
└── <agent-name>/
    ├── install.sh
    ├── install.ps1
    ├── README.md
    ├── agent/
    ├── skills/
    ├── config/
    └── scripts/
```

原则：

- 根 `docs/` 写所有 agent 都能复用的规则。
- `docs/<agent-name>/` 写角色设定、专属 skill、默认模型、渠道限制等差异。
- agent pack 目录保留安装器、人设、skill 和脚本，不再把用户文档散落在各 pack 内。

## 先理解配置层级

一个 agent 的行为通常由几层文件叠加出来。

从低到高：

```text
<agent-name>/agent/*.md                         # 仓库里的默认人设模板
~/.openclaw/workspace/<agent-id>/*.md            # 安装后的 workspace 文件
~/.openclaw/workspace/<agent-id>/custom.md       # 用户覆盖规则
~/.openclaw/workspace/<agent-id>/MEMORY.md       # 长期记忆
~/.openclaw/workspace/<agent-id>/memory/*.md     # 日常记忆
```

常见文件分工：

| 文件 | 适合放什么 | 建议 |
|---|---|---|
| `SOUL.md` | 核心人设、价值观、语言风格、世界观 | 发布新 agent 时改 |
| `IDENTITY.md` | 身份卡、称呼、定位摘要 | 发布新 agent 时改 |
| `USER.md` | 初始用户画像和更新规则 | 可按 agent 场景改 |
| `AGENTS.md` | 启动流程、记忆规则、平台行为 | 谨慎改 |
| `custom.md` | 用户覆盖规则、偏好、SOP | 最推荐给用户改 |
| `MEMORY.md` | 长期事实、关系状态、用户信息库 | 通过 `<workspace>/scripts/memory-write.sh --category <kind>` 持续维护 |
| `HEARTBEAT.md` | 主动联系规则 | 有主动行为的 agent 才需要 |
| `TOOLS.md` | 本地工具、skill 入口、脚本约定 | 安装器生成，必要时补说明 |

升级策略也按这个分层设计：安装器可以更新默认人设和 skill，但必须保护 `custom.md`、`memory/`、`MEMORY.md`、`sessions/` 和认证文件。

## 该改哪里

| 目标 | 优先改哪里 |
|---|---|
| 改称呼、语气、回复长度、禁用表达 | `custom.md` |
| 增加私人知识、长期偏好、项目背景 | `<workspace>/scripts/memory-write.sh --category preference --summary ... --long ...` |
| 调主动问候频率、静默时段 | `HEARTBEAT.md` |
| 调主动行为数值或副作用 | `<workspace>/scripts/*.sh` |
| 改默认音色、语速、图片参考图、Whisper 模型 | `openclaw.json -> skills.entries.*.env`；agent 私有项用 `<workspace>/skills/.env` |
| 调 skill 触发倾向 | `custom.md`，必要时改对应 `SKILL.md` 的 `description` |
| 换主模型 | `~/.openclaw/openclaw.json` |
| 让安装器以后优先选某模型 | `<agent-name>/config/model-map.yaml` |
| 做全新 agent | 复制或 fork 一个 pack，改 `agent/`、`config/`、`docs/<agent-name>/` |

经验规则：用户个人偏好放 `custom.md`；长期事实用 `memory-write.sh --category <kind>` 写入 `MEMORY.md`；要给所有用户复用的底层行为才放进 agent pack。

## 写好 custom.md

`custom.md` 是最高优先级覆盖层，适合写明确、可执行的规则。不要写抽象愿望，写触发条件和行为。

推荐结构：

```markdown
# custom.md

## 语气
- 技术问题先给结论，再补步骤。
- 日常聊天保持轻松，但单条回复不超过 120 字。
- 不使用颜文字。

## 称呼
- 默认叫我「老板」。
- 只有我明确要求角色扮演时才使用角色化称呼。

## 边界
- 工作时间 09:30-18:30 少闲聊，多给行动建议。
- 我说「严肃模式」后，停止玩梗和角色化语气，直到我说「恢复」。

## Skill 使用规则
- 只有我明确说「发语音」「读出来」时才调用语音 skill。
- 收到图片时先描述画面，再回答我的具体问题。
- 用户发语音时，必须先转写，再按转写内容回答。

## 工作 SOP
我说「开始工作」时：
1. 先问今天最重要的一个目标是什么。
2. 帮我拆成 3 个以内的下一步。
3. 如果我拖延，只提醒一次，不连续催。
```

反例：

```markdown
- 更懂我一点。
- 更可爱。
- 不要太烦。
```

这些太模糊，模型每次理解可能不同。改成「什么场景、做什么、不做什么」。

## 调人设

轻度调优用 `custom.md`：

```markdown
## 人设微调
- 保留当前角色设定，但减少口癖。
- 面对代码、文档、排错任务时，优先像工程助手一样工作。
- 亲密互动只在我主动开启时进入，默认保持日常陪伴。
```

中度调优用 `MEMORY.md`：

```markdown
## 长期记忆
- 用户更喜欢直接、短句、可执行建议。
- 用户晚上 23:30 后不希望收到主动消息。
- 用户正在维护 Agents 仓库，偏好文档先解释配置层级。
```

深度调优才改 `SOUL.md` / `IDENTITY.md`：

1. fork 这个仓库，或复制一个现有 agent pack。
2. 改 `<agent-name>/agent/SOUL.md`、`IDENTITY.md`、`USER.md`。
3. 改 `<agent-name>/README.md` 和 `docs/<agent-name>/`。
4. 用新的 `--agent-id` 安装，避免覆盖已有 agent。

```bash
bash <agent-name>/install.sh --agent-id agent-yourname
```

## 调模型

运行时真正生效的是 `~/.openclaw/openclaw.json` 里的 agent 配置：

```json
{
  "id": "agent-example",
  "model": {
    "primary": "provider/model-name"
  }
}
```

改完后重启 gateway。

安装器会优先看 `openclaw.json -> agents.defaults.models` 里模型条目声明的能力字段
（例如 `capabilities`、`tags`、`features`、`modalities`）。如果模型没有能力字段，
才会参考 `<agent-name>/config/model-map.yaml`。想让安装器以后优先选择自己的模型，
可以给模型声明能力：

```json
"models": {
  "your_provider/your_roleplay_model": {
    "capabilities": ["roleplay", "text"]
  }
}
```

也可以把它加到对应能力的 `preferred` 列表前面作为偏好排序：

```yaml
capabilities:
  roleplay:
    preferred:
      - your_provider/your_roleplay_model
      - provider/default_model
```

选择建议：

| 目标 | 建议 |
|---|---|
| 角色一致性 | 优先角色扮演模型 |
| 看图 | primary 必须是多模态模型 |
| 长对话 | 选大上下文模型，或配置 openclaw compaction |
| 技术任务 | 可在 `custom.md` 要求技术问题更直接；自动切模型取决于 openclaw 当前能力 |

上下文不够时，可以调 compaction：

```json
"agents": {
  "defaults": {
    "compaction": {
      "mode": "safeguard",
      "reserveTokensFloor": 30000
    }
  }
}
```

## 调 Skill

每个 skill 通常由两部分组成：

- `SKILL.md`：告诉 agent 什么时候用、怎么用。
- `scripts/`：真正执行 TTS、转写、图片生成、设备控制等动作。

低风险做法是在 `custom.md` 覆盖触发规则：

```markdown
## Skill 触发规则
- 不确定要不要发语音时，默认不发。
- 用户只说「看看」且带图片时，必须先用看图 skill。
- 用户发语音时，必须先转写，再回答。
```

高风险做法是直接改全局 skill：

```bash
vi ~/.openclaw/skills/<skill>/SKILL.md
```

直接改全局 skill 会影响所有使用同名 skill 的 agent，也可能被升级覆盖。要长期维护，建议复制成新 skill 名称，例如 `voice-work`、`selfie-agentname`，再改 description 和脚本。

## 调 Env

常见配置分三处：

```text
~/.openclaw/openclaw.json                # skills.entries.voice/selfie.env：共享 provider key
~/.openclaw/skills/.env                  # 旧安装 fallback：TTS、图像生成、Whisper 等通用 key
~/.openclaw/workspace/<agent-id>/skills/.env  # 单 agent 私有：渠道凭据、角色参考图
```

agent 私有 `.env` 覆盖共享默认值。推荐：

- voice/sing/selfie/video provider key 放本机 `openclaw.json` 的对应 `skills.entries.*.env`，不要提交进仓库。
- 权限设为 `0600`。
- agent 私有角色信息放 workspace 的 `skills/.env`。
- 旧版 `.env` 只作为兼容 fallback。

## 调多平台输出

skill 脚本可以支持两种输出模式：

```bash
OPENCLAW_OUTPUT_MODE=feishu
OPENCLAW_OUTPUT_MODE=acp
```

| 模式 | 适合场景 | 行为 |
|---|---|---|
| `feishu` | 飞书原生 bot | 脚本自己上传并发送 |
| `acp` | cc-connect 多平台 | 脚本输出文件 JSON，由 host 投递 |

接微信、QQ、Telegram、Slack 等渠道时，优先用 `acp`。agent 收到文件 JSON 后，把文件路径按 host 约定贴到回复正文里，由 host 替换成附件。

## 调主动行为

有主动行为的 agent 建议统一拆成三层：

| 层 | 文件或任务 | 作用 |
|---|---|---|
| 规则 | `HEARTBEAT.md` | 什么时候能主动说话、说多长、什么语气 |
| 状态 | `memory/*.json` | 数值、冷却、上次触发时间 |
| 脚本 | `<workspace>/scripts/*.sh` | 计算状态、触发副作用、写日志 |

想少打扰，优先改 `HEARTBEAT.md`：

```markdown
## 主动联系规则
- 每天最多主动 1 次。
- 23:00-09:00 永远不主动发消息。
- 工作日 09:30-18:30 只在有明确待办或重要提醒时发。
- 没有具体内容时回复 HEARTBEAT_OK。
```

想改阈值、随机增长、设备副作用，再改安装后的 `<workspace>/scripts/*.sh`。脚本改动属于高级玩法，升级前要备份。

## 做一个自己的 agent pack

最稳的路径是复制现有 pack：

```bash
cp -R nako your-agent
```

至少改这些地方：

| 文件 | 要改什么 |
|---|---|
| `your-agent/README.md` | 名称、定位、功能、安装命令 |
| `your-agent/agent/SOUL.md` | 核心人设 |
| `your-agent/agent/IDENTITY.md` | 身份卡 |
| `your-agent/agent/USER.md` | 初始用户档案 |
| `your-agent/agent/HEARTBEAT.md` | 主动联系规则 |
| `your-agent/agent/custom.md.example` | 给用户的定制示例 |
| `your-agent/config/model-map.yaml` | 默认 agent id 和模型偏好 |
| `your-agent/install.sh` / `install.ps1` | 默认 `AgentId`、安装器标题、默认描述、cron 名称和消息 |
| `docs/your-agent/*.md` | 安装、技能、定制、特色玩法 |
| 根 `README.md` | Agents 表格新增一行 |

安装时换 agent id：

```bash
bash your-agent/install.sh --agent-id agent-your-agent
```

## 验证与排错

改完以后按这个顺序查：

```bash
# 看安装器能识别哪些模型
bash <agent-name>/scripts/detect-models.sh

# 跑 skill 冒烟测试
bash <agent-name>/scripts/smoke-test.sh

# 看 cron 是否注册
openclaw cron list

# 看 skill 调用日志
tail -f ~/.openclaw/skills/<skill>/logs/skill.jsonl | jq .
```

常见判断：

| 现象 | 先查 |
|---|---|
| 人设不听 custom.md | `AGENTS.md` 是否引用了 `custom.md` |
| skill 不触发 | `custom.md` 触发规则、`SKILL.md` description |
| 语音或图片不发 | provider key、渠道权限、`OPENCLAW_OUTPUT_MODE` |
| 看不了图 | primary 是否多模态，本地媒体路径是否可解析 |
| 主动消息太频繁 | `HEARTBEAT.md`、cron 列表、状态 JSON |
| 升级后行为变了 | 对比安装器备份文件和当前 `custom.md` |

## 升级策略

推荐三层维护：

1. 日常偏好写 `custom.md`。
2. 长期事实用 `<workspace>/scripts/memory-write.sh --category <kind>` 写入 `MEMORY.md`；只写明确有长期价值的信息，不写寒暄、临时输出或完整对话。
3. 要发布给别人用的底层改动，放到你的 fork 或 agent pack 里。

不要把 API key、真实 token、私密聊天记录提交进仓库。
