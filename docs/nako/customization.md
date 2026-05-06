# 定制与调优

本页是 nako 的快速定制速查。所有 agent 通用的进阶玩法见 [../advanced.md](../advanced.md)，nako 特色玩法见 [advanced.md](advanced.md)。

## 覆盖层顺序（优先级从低到高）

```
SOUL.md / IDENTITY.md / USER.md    ← 安装器写入的默认人设
                ↓
           AGENTS.md                ← 汇总入口 + 引用 custom.md
                ↓
         custom.md                  ← 你写的东西，永不被覆盖
```

冲突时 custom.md 赢。升级 pack 只会动上面那几个文件，不动 custom.md。

## 常见定制配方

### 换称呼 / 语气

```markdown
# custom.md

## 称呼微调
- 不再用「主人大人」，改叫「老板」
- 禁用颜文字，只用 emoji
```

### 改默认 TTS 音色 / 语速

```markdown
## 默认音色
- voice.sh 第一选择 `female-shaonv`（少女）
- 晚安场景 `female-tianmei` + speed=0.85
- 生气时 `female-yujie`
```

Agent 读到后会照做。

### 改模型（某条消息走不同模型）

AGENTS.md 里 agent 主模型由 `openclaw.json` 定，但你可以在 `custom.md` 指示：

```markdown
## 模型选择
- 代码相关任务让我切换到 coding 模型再回答
```

Agent 会调 `openclaw` 的 model-switch API（如支持），或提示用户换会话。

### 改 QClaw 列表头像

QClaw 会监听 workspace 里的 `IDENTITY.md`，只解析英文 key：

```markdown
- Name: 野木奈子
- Emoji: 🎀
- Vibe: 核战后赛博世界专属战斗女仆
- Avatar: assets/nako-avatar.svg
```

`Avatar` 可以是 workspace 相对路径、HTTPS URL 或 data URI。默认头像文件随安装器复制到 `assets/nako-avatar.svg`。

### 新增私人知识

```markdown
## 我的家人
- 我妹妹叫阿玲，今年 17 岁，在读高三
- 别提「爸爸」这个词，我爸已故
```

### 新增工作 SOP

```markdown
## 早会 SOP
用户说「开始早会」时：
1. 查 Things 今日列表
2. 用 voice.sh 读三条最重要的
3. 等用户回复状态后，sing.sh 给一段打鸡血的开场歌
```

## 换人设底子（深度定制）

把 `SOUL.md` / `IDENTITY.md` 整个换掉即可。重跑 `install.sh --force` 会用仓库版本覆盖（会备份）。

推荐做法：fork 仓库，改 `nako/agent/*.md`，然后你自己维护。安装器指向你的 fork：

```bash
git clone https://github.com/YOU/Agents.git
bash Agents/install.sh
```

## 调 Skill 行为

每个 skill 有自己的 SKILL.md。可以直接编辑 `~/.openclaw/skills/<skill>/SKILL.md` — 但这会被升级覆盖。

推荐：在 `custom.md` 写「skill 使用规则」覆盖默认触发逻辑。

```markdown
## Skill 使用规则
- 除非用户明确说「唱」，否则用 voice.sh 不用 sing.sh
- vision 看图时，先描述场景再尝试识别人物
- 发语音前先用文字说明「给你录了条语音」
```

## 私有 env 放哪

voice/sing 和 selfie/video 的共享 key 优先在 `~/.openclaw/openclaw.json`：

- `skills.entries.voice.env` — 语音/唱歌 key 与默认音色
- `skills.entries.selfie.env` — 自拍/视频生成 key

旧安装仍兼容两层 `.env`：

- `~/.openclaw/skills/.env` — 旧安装共享 fallback（TTS、图像生成、Whisper 模型）
- `<workspace>/skills/.env` — 本 agent 私有（飞书凭据、角色参考图）

agent 私有 `.env` 覆盖共享默认值。手动改 `.env` 时权限用 `0600`。

## 日志与调试

- 共享 gateway 日志：`~/.openclaw/logs/gateway.log`
- 每个 skill 的执行日志：`~/.openclaw/skills/<skill>/logs/skill.jsonl`（JSONL，每行一次调用）

跟踪某次调用：

```bash
tail -f ~/.openclaw/skills/voice/logs/skill.jsonl | jq .
```

## 升级 pack 到新版

```bash
cd /path/to/Agents
git pull
bash install.sh    # 交互询问每个文件是否覆盖
# 或
bash install.sh --force  # 全部覆盖（仍备份）
```

你写的 `custom.md` / memory/ / sessions/ 永远不会被动。
