# nako 特色进阶玩法

这份文档只写野木奈子这个 agent 的特色玩法。通用的 agent 调优方法见 [../advanced.md](../advanced.md)。

## nako 的可调层级

nako 的核心设定在 `nako/agent/`：

| 文件 | 作用 |
|---|---|
| `SOUL.md` | 野木奈子的核心灵魂、世界观、语言风格、关系阶段 |
| `IDENTITY.md` | 身份卡、称呼、年龄外貌、阵营 |
| `USER.md` | 初始用户档案和关系状态 |
| `HEARTBEAT.md` | 奈子的主动联系规则 |
| `MEMORY.md` | 好感阶段、短期记忆、用户个人信息库 |
| `TOOLS.md` | voice、vision、hearing、selfie、dokidoki 的本地入口 |

日常定制优先写安装后的 `<workspace>/custom.md`。只有要维护自己的 nako fork，才建议改 `nako/agent/*.md`。

## 调奈子的语气

`SOUL.md` 默认是战斗女仆、元气少女、中二、亲密陪伴风格。想弱化或增强某个面，写进 `custom.md`：

```markdown
## 奈子语气微调
- 保留战斗女仆设定，但减少中二口癖。
- 技术问题先给结论，不要先撒娇。
- 日常聊天可以活泼，但不要每条都夸我。
- 我说「严肃模式」后，停止角色化口吻，直到我说「恢复」。
```

如果你想保留角色扮演，但减少打扰：

```markdown
## 陪伴边界
- 工作时间 09:30-18:30 默认简短直接。
- 只有我主动发起亲密互动时，才进入强角色扮演。
- 不要连续追问；一次回复最多问一个问题。
```

## 调称呼和关系阶段

nako 默认称呼是「主人大人」，关系阶段从阶段 1 开始。轻度修改写 `custom.md`：

```markdown
## 称呼
- 日常叫我「老板」。
- 只有角色扮演模式才叫「主人大人」。
```

长期状态通过安装后的记忆脚本写入，避免手工覆盖短期记忆或好感阶段：

```bash
bash <workspace>/scripts/memory-write.sh \
  --category preference \
  --summary "用户更喜欢轻松陪伴" \
  --long "用户更喜欢轻松陪伴，不喜欢频繁主动消息" \
  --affinity 35
```

脚本会同时更新 `memory/YYYY-MM-DD.md` 和 `MEMORY.md`：

```markdown
**当前好感阶段**：2（互有好感阶段）
**好感值**：35/100

## 长期记忆（关键事件）
- 用户更喜欢轻松陪伴，不喜欢频繁主动消息。
```

不建议在普通对话里频繁手动改阶段。阶段适合记录稳定关系状态，不适合当作每轮都变的临时变量。

## 调 voice / sing

nako 的 voice skill 支持：

- `voice.sh`：普通 TTS。
- `sing.sh`：MiniMax music-2.6 生成新歌。

常用配置优先放在 `~/.openclaw/openclaw.json` 的 `skills.entries.voice.env`；旧安装里的 `~/.openclaw/skills/.env` 和 `<workspace>/skills/.env` 仍兼容：

```bash
VOICE_DEFAULT_MINIMAX=female-tianmei
VOICE_DEFAULT_VOLCENGINE=zh_female_shuangkuaisisi_moon_bigtts
VOICE_DEFAULT_SPEED=1.0
MINIMAX_API_KEY=...
MINIMAX_GROUP_ID=...
VOLCENGINE_API_KEY=...
```

可以把音色策略写到 `custom.md`：

```markdown
## 奈子语音策略
- 日常语音用 `female-tianmei`，speed=1.0。
- 晚安语音用 `female-tianmei`，speed=0.85。
- 元气或庆祝场景用 `female-shaonv`，speed=1.12。
- 除非我明确说「唱」，否则不要调用 sing.sh。
```

sing 生成的是新歌，不会复刻已有歌曲原旋律。歌词建议带结构标签：

```text
[verse]
第一段
[chorus]
副歌
[outro]
收尾
```

## 调自拍

nako 的自拍一致性靠 per-agent env；生成 provider key 优先放在 `openclaw.json -> skills.entries.selfie.env`：

```bash
# <workspace>/skills/.env
SELFIE_REFERENCE_IMAGE=https://...
SELFIE_CHARACTER_DESC="golden shoulder-length hair, red eyes, maid outfit, youthful face"
# openclaw.json -> skills.entries.selfie.env
FAL_KEY=...
KIE_API_KEY=...
```

规则：

- `SELFIE_REFERENCE_IMAGE` 负责外观锚定。
- `SELFIE_CHARACTER_DESC` 要短、稳定、每次都能塞进 prompt。
- 服装、地点、构图放到用户当次 prompt 或 `custom.md`。

可在 `custom.md` 固定风格：

```markdown
## 奈子自拍风格
- 展示穿搭时用 mirror selfie，全身构图。
- 表情、咖啡店、街景用 direct selfie。
- prompt 默认用英文，必须包含 SELFIE_CHARACTER_DESC 的特征。
```

图生视频通常 30-120 秒。触发前最好先回复用户会稍等。

## 调看图和听语音

看图：

```bash
~/.openclaw/skills/vision/scripts/resolve.sh --latest
```

vision 只把平台图片解析成本地路径，真正看图靠 primary 模型。如果 primary 不是多模态，奈子只能拿到路径，不能理解图片内容。

听语音：

```bash
WHISPER_MODEL=turbo
WHISPER_LANGUAGE=zh
```

建议：

- 中英文混合多，`WHISPER_LANGUAGE` 保持 `auto`。
- 主要中文语音，设 `zh` 会更快、更稳。
- 机器性能弱，改 `tiny` 或 `base`；准确率优先，改 `large-v3`。

## 调思念机制

nako 的主动行为由三层组成：

| 层 | 文件或任务 | 作用 |
|---|---|---|
| 规则 | `HEARTBEAT.md` | 什么阶段多久主动一次、什么语气 |
| 状态 | `memory/heartbeat-state.json` | 思念值、情绪值、是否触发 |
| 脚本 | `<workspace>/scripts/*.sh` | 计算数值、恢复情绪、每日提醒、副作用 |

安装器会注册三个 cron：

| 名称 | 时间 | 作用 |
|---|---|---|
| `nako-heartbeat` | 每 30 分钟 | 调 `heartbeat-check.sh`，到阈值后让 agent 主动生成消息，并用 `send-active-message.sh` 经 cc-connect 发送 |
| `nako-daily-script` | 每天 08:00 | 生成当天日常剧本 |
| `nako-missing-reminder` | 每天 16:50 | 生成思念提醒，经 cc-connect 发送，并可触发 doki |

这些 cron job 注册时使用 `--no-deliver`：OpenClaw 只负责唤醒 agent，不负责 fallback delivery。主动消息必须走 `<workspace>/scripts/send-active-message.sh`，否则通过 cc-connect/ACP 进入的微信或飞书会话不会被 OpenClaw 识别为 `delivery.channel=last`。

查看：

```bash
openclaw cron list
```

默认逻辑：

- 01:00-08:00 不增长思念值。
- 正常时段每次增加随机基础值、加速值和随机波动。
- 思念值到 `80` 后 `heartbeat-check.sh` 退出码为 `1`。
- 每次触发会降低情绪值。
- 用户发消息时，`mood-recovery.sh` 会清零思念值并恢复情绪。

想少打扰，优先改 `HEARTBEAT.md`：

```markdown
## 主动联系规则
- 每天最多主动 1 次。
- 23:00-09:00 永远不主动发消息。
- 工作日 09:30-18:30 只在有明确待办或重要提醒时发。
- 没有具体内容时回复 HEARTBEAT_OK。
```

想改阈值，改安装后的脚本：

```bash
vi ~/.openclaw/workspace/agent-nako/scripts/heartbeat-check.sh
```

升级时如果安装器提示覆盖这些脚本，先备份自己的版本。

每日提醒可用 env 调：

```bash
NAKO_DAILY_REMINDER_MSG="今天也记得喝水。"
NAKO_DAILY_REMINDER_CHANNEL=feishu
NAKO_DAILY_REMINDER_CHAT=oc_xxx
NAKO_DOKI_DEVICE=DK-META2
NAKO_DOKI_VIBRATION=25
```

## 调 dokidoki

nako 的 dokidoki skill 走 `doki` CLI：

```bash
doki scan
doki connect DK-META2
doki action vibration 50
doki action pause
```

高级联动用 timeline JSON：

```json
{
  "duration": 30,
  "actions": [
    {"timestamp": 0, "type": "VIBRATION", "value": 30},
    {"timestamp": 10, "type": "LINEAR", "value": 45},
    {"timestamp": 20, "type": "ROTARY", "value": -30}
  ]
}
```

播放：

```bash
doki player play audio.mp3 timeline.json
```

建议把设备名、强度上限和禁用时段写进 `custom.md` 或 `TOOLS.md`，避免奈子每次猜。

## nako 排错速查

```bash
bash nako/scripts/detect-models.sh
bash nako/scripts/smoke-test.sh
openclaw cron list
tail -f ~/.openclaw/skills/voice/logs/skill.jsonl | jq .
```

手动测：

```bash
~/.openclaw/skills/voice/scripts/voice.sh "测试语音" "oc_xxx" auto female-tianmei 1.0
~/.openclaw/skills/hearing/scripts/stt.sh --latest
~/.openclaw/skills/vision/scripts/resolve.sh --latest
bash ~/.openclaw/workspace/agent-nako/scripts/heartbeat-check.sh
```
