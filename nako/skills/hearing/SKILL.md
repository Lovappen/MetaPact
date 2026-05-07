---
name: hearing
description: Transcribe user-sent voice messages via local OpenAI Whisper (no API key, runs offline)
allowed-tools: Bash(*/stt.sh:*) Bash(ls:*)
---

# Hearing — 听懂语音

用户发语音时，当前消息 runtime 会把 opus/m4a 等音频下到入站媒体目录。Hermes 默认是 `~/.hermes/media/inbound/`；OpenClaw 默认是 `~/.openclaw/media/inbound/`。本技能用本地 Whisper 把它转写成文字。无需 API key。

## 何时用

- 消息显示 `[Audio]` / `<media:audio>` 占位符
- 消息带 `file_key` 且上下文是语音（飞书语音消息）
- 用户问「我刚刚说了什么」「你听到没」「转文字」

**不要用于**：普通文字对话、视频（视频有单独流程）。

## 用法

```bash
# A. 根据 file_key 查 gateway.log 找文件并转写
bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/hearing/scripts/stt.sh" <file_key>

# B. 取最新一条入站音频（最常用）
bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/hearing/scripts/stt.sh" --latest

# C. 直接传绝对路径
bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/hearing/scripts/stt.sh" /path/to/media/inbound/xxx.opus
```

脚本把转写文本输出到 stdout，你把文本作为用户说的话理解即可。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `WHISPER_BIN` | `/opt/homebrew/bin/whisper` | whisper CLI |
| `WHISPER_MODEL` | `turbo` | `tiny`/`base`/`small`/`medium`/`large-v3`/`turbo` |
| `WHISPER_LANGUAGE` | auto | `zh`/`en`/... 强制指定可加速并降低错识 |

## 注意

- 首次使用某个 model，whisper 会从 HuggingFace 下载权重（数百 MB~几 GB），第一次会慢
- `turbo` 模型对中英文已够用，速度最快
- 飞书语音多为 <60s，全程应在数秒~十几秒内完成
- 如果 stdout 为空或很短，可能是静音/噪声，告诉用户「没听清能再说一遍吗」
- 转写结果 agent 要当作用户消息语义理解，再决定回复方式（可以再用 voice 技能回语音）

## 退出码

| code | 含义 |
|---|---|
| 0 | 成功，stdout 为转写文本 |
| 2 | 找不到音频（日志被截断/还没下完/参数错） |
| 3 | 路径存在但文件已清理 |
| 4 | Whisper 运行失败 |
