---
name: voice
description: Send voice/song audio to Feishu — voice.sh does plain TTS (MiniMax or Volcengine); sing.sh generates a full song with melody via MiniMax music-2.6
allowed-tools: Bash(curl:*) Bash(jq:*) Bash(xxd:*) Bash(base64:*) Bash(uuidgen:*) Bash(sleep:*) Bash(ffprobe:*) Bash(*/voice.sh:*) Bash(*/sing.sh:*) Bash(*/setup.sh:*) Read Write
---

# Voice — 语音消息

将文本转为语音，以飞书语音消息形式发送。支持 MiniMax 和火山引擎两个 TTS 引擎。

## 何时使用

用户说以下内容时触发：

- "发个语音" / "说句话给我听" / "用语音回复"
- "send a voice message" / "speak to me"
- "我想听你的声音" / "语音消息"
- 讲故事、读诗、晚安问候等适合用声音表达的场景

**不要用于**：普通文字对话、技术说明、超长文本（>500 字请分段）

## 说话 vs 唱歌：选对脚本

| 场景 | 用 | 说明 |
|---|---|---|
| 说话（朗读、问候、讲故事、撒娇） | `voice.sh` | 纯 TTS，秒级合成 |
| 唱歌（有旋律的歌曲、写歌送给用户、生日快乐歌） | `sing.sh` | MiniMax music-2.6，带伴奏和旋律，10–60 秒生成 |

判断要点：
- 用户说「唱一首/给我唱/写首歌/来段 rap/唱给我听/生日歌」→ `sing.sh`
- 用户说「读一下/发语音/说一句/念给我听」→ `voice.sh`
- 内容含 `[verse]` `[chorus]` 等结构标签或明显是歌词格式 → `sing.sh`
- 犹豫时默认 `voice.sh`（更快、更便宜）

## 快速使用

```bash
~/.openclaw/skills/voice/scripts/voice.sh "<文本>" "<频道ID>" [provider] [voice_id] [speed]
```

| 参数 | 必须 | 默认值 | 说明 |
|------|------|--------|------|
| text | 是 | — | 要合成的文本，建议 500 字以内 |
| channel | 是 | — | 飞书 chat_id（`oc_xxx`）或 open_id（`ou_xxx`） |
| provider | 否 | auto | `minimax` / `volcengine` / `auto`（按 key 自动选择） |
| voice_id | 否 | 按引擎默认 | 音色 ID，见下方音色表 |
| speed | 否 | 1.0 | 语速倍率 0.5–2.0 |

### 示例

```bash
# MiniMax 甜美女声
./voice.sh "主人大人早上好呀！" "oc_xxx" minimax female-tianmei 1.0

# 火山引擎 爽快女声
./voice.sh "今天天气真不错呢！" "oc_xxx" volcengine zh_female_shuangkuaisisi_moon_bigtts 1.0

# 慢速温柔语音（适合晚安）
./voice.sh "晚安，做个好梦哦……" "oc_xxx" minimax female-tianmei 0.85
```

## TTS 引擎

### MiniMax（推荐）

- 模型：speech-02-hd
- 音频：MP3 32kHz 128kbps
- 返回 duration，无需 ffprobe
- 获取 key：[platform.minimaxi.com](https://platform.minimaxi.com)

| 音色 ID | 描述 | 推荐场景 |
|---------|------|---------|
| `female-tianmei` | 甜美女声 **（默认）** | 日常、撒娇、问候 |
| `female-shaonv` | 少女声 | 元气、兴奋 |
| `female-yujie` | 御姐声 | 认真、冷酷 |
| `female-chengshu` | 成熟女声 | 沉稳、叙述 |

### 火山引擎（备选）

- API：V3 HTTP Chunked（openspeech.bytedance.com）
- 模型版本：seed-tts-1.0（默认），可切换 seed-tts-2.0
- 获取 key：[console.volcengine.com/speech/new](https://console.volcengine.com/speech/new)

| 音色 ID | 描述 |
|---------|------|
| `zh_female_shuangkuaisisi_moon_bigtts` | 爽快思思 **（默认）** |
| `zh_female_cancan_mars_bigtts` | 灿灿（活泼） |
| `zh_female_gaolengyujie_moon_bigtts` | 高冷御姐 |
| `zh_female_sajiaonvyou_moon_bigtts` | 撒娇女友 |
| `zh_female_tianmeixiaoyuan_moon_bigtts` | 甜美小源 |

更多音色见 [火山引擎音色列表](https://www.volcengine.com/docs/6561/1257544)

## 唱歌 — sing.sh

```bash
~/.openclaw/skills/voice/scripts/sing.sh "<歌词>" "<频道ID>" ["<风格描述>"] ["<model>"]
```

| 参数 | 必须 | 默认 | 说明 |
|---|---|---|---|
| lyrics | 是 | — | 歌词。支持段落标签 `[intro]` `[verse]` `[pre chorus]` `[chorus]` `[bridge]` `[outro]`，用 `\n` 换行 |
| channel | 是 | — | chat_id (`oc_xxx`) 或 open_id (`ou_xxx`) |
| style_prompt | 否 | `Indie pop, gentle, warm female vocal, acoustic guitar` | 风格描述：流派+情绪+乐器+人声性别 |
| model | 否 | `music-2.6` | `music-2.6` 或 `music-2.6-free`（免费版配额有限） |

### 歌词结构建议

```
[verse]
第一段主歌第一行
第一段主歌第二行
[chorus]
副歌高潮第一行
副歌高潮第二行
[bridge]
过桥段
[outro]
收尾
```

### 示例

```bash
# 中文抒情
./sing.sh "[verse]\n月色洒在窗台\n思念像潮水漫来\n[chorus]\n想你在每个夜晚\n想你在每次梦醒" "oc_xxx" "Chinese ballad, soft piano, female vocal, emotional"

# 英文流行
./sing.sh "[verse]\nStreetlights flicker, the night breeze sighs\n[chorus]\nPushing the wooden door, the aroma spreads" "ou_xxx" "Indie folk, acoustic guitar, melancholic"

# 生日歌（即兴写词）
./sing.sh "[verse]\n亲爱的小夜今天生日\n愿望写在蛋糕上\n[chorus]\n生日快乐生日快乐\n每一天都要笑开花" "oc_xxx" "Upbeat pop, cheerful, warm female voice"
```

### 注意

- 生成耗时 10–60 秒，发消息前可先说「稍等，我写一首给你～」安抚用户
- 歌词最好 30–400 字，太短模型会补白、太长会截断
- 风格描述用英文更精确（MiniMax 训练数据以英文 prompt 为主）
- 输出音频默认 44.1kHz / 256kbps MP3，比 TTS 音质高很多
- 失败时看 stderr 的 `status_msg`，常见 `lyrics_too_short` / `invalid_model` / 配额耗尽

## 环境变量

所有变量在 `openclaw.json` → `skills.entries.voice.env` 中配置。

### 必需

| 变量 | 来源 | 说明 |
|------|------|------|
| `FEISHU_APP_ID` | 飞书开放平台 | 飞书应用 App ID |
| `FEISHU_APP_SECRET` | 飞书开放平台 | 飞书应用 App Secret |

### MiniMax（至少配一组 TTS）

| 变量 | 说明 |
|------|------|
| `MINIMAX_API_KEY` | MiniMax API 密钥 |
| `MINIMAX_GROUP_ID` | MiniMax 分组 ID |

### 火山引擎（可选）

| 变量 | 说明 |
|------|------|
| `VOLCENGINE_API_KEY` | 火山引擎新版控制台 API Key |
| `VOLCENGINE_RESOURCE_ID` | 模型版本（默认 `seed-tts-1.0`） |

## 安装

首次安装运行安装脚本，交互式引导配置 API Key：

```bash
bash ~/.openclaw/skills/voice/scripts/setup.sh
```

脚本会：
1. 检查系统依赖（jq, curl, ffprobe）
2. 引导输入 TTS API Key
3. 自动从 openclaw.json 读取飞书凭据
4. 写入 openclaw.json 配置
5. 发送测试语音验证

## 工作原理

```
文本 → TTS API → MP3 音频
  → 飞书上传（file_type=opus, 含 duration）
  → 飞书发送（msg_type=audio）
  → 用户收到可播放的语音消息
```

关键细节：
- 上传时 `file_type` 必须设为 `opus`（即使文件是 mp3），飞书服务端转码
- 上传时必须传 `duration`（毫秒），否则语音无法播放
- MiniMax 返回十六进制编码音频（xxd 解码），火山引擎返回 base64
- 临时文件 10 分钟后自动清理

## 使用建议

- 文本口语化，短句为主，加逗号和省略号控制节奏
- 亲密/感性内容用慢速（0.8–0.9）
- 日常用正常速度（1.0）
- 兴奋场景可稍快（1.1–1.2）
- 语音消息前后配合文字，如"给你录了一段语音哦～"
- 不要每条消息都发语音，特殊场景才有仪式感

## 错误排查

| 问题 | 原因 | 解决 |
|------|------|------|
| MiniMax error | API key 或 Group ID 错误 | 检查 `openclaw.json -> skills.entries.voice.env` 里的 MINIMAX_API_KEY 和 MINIMAX_GROUP_ID |
| Volcengine resource mismatch | 音色和模型版本不匹配 | seed-tts-1.0 音色用 seed-tts-1.0，2.0 同理 |
| Upload failed | 飞书 token 过期或权限不足 | 检查 FEISHU_APP_ID/SECRET，确认 im:resource 权限 |
| 语音无法播放 | 未传 duration | 确认上传时 duration 参数正确传入 |
| Bot can NOT be out of chat | 飞书 App ID 和聊天不匹配 | 使用对应 agent 的飞书 App ID |
