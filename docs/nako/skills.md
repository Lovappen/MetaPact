# Skills 参考

每个 skill 有自己的 SKILL.md（装在 `~/.openclaw/skills/<skill>/SKILL.md`），这里汇总高层用法。

## 🎤 voice — 说话 & 唱歌

两个脚本：

- `voice.sh` — 纯 TTS，秒级生成
- `sing.sh` — MiniMax music-2.6，10–60 秒生成完整歌曲（含伴奏+旋律+唱腔）

### voice.sh

```bash
~/.openclaw/skills/voice/scripts/voice.sh "<text>" "<channel>" [provider] [voice_id] [speed]
```

| 参数 | 默认 | 说明 |
|---|---|---|
| text | — | 要朗读的文本，建议 <500 字 |
| channel | — | 飞书 chat_id (`oc_xxx`) 或 open_id (`ou_xxx`) |
| provider | auto | `minimax` / `volcengine` / `auto`（按 key 优先 minimax） |
| voice_id | 引擎默认 | 音色 ID，见 SKILL.md 音色表 |
| speed | 1.0 | 0.5–2.0 |

MiniMax 默认音色：`female-tianmei`（甜美女声）、`female-shaonv`（少女声）、`female-yujie`（御姐）、`female-chengshu`（成熟）。

火山引擎更多音色见 [volcengine 音色列表](https://www.volcengine.com/docs/6561/1257544)。

### sing.sh

```bash
~/.openclaw/skills/voice/scripts/sing.sh "<lyrics>" "<channel>" ["<style>"] [model]
```

歌词支持结构标签 `[verse]` `[chorus]` `[bridge]` `[intro]` `[outro]`，用 `\n` 换行。

```bash
# 示例
./sing.sh "[verse]\n月色洒在窗台\n思念像潮水\n[chorus]\n想你的夜 数着星光" \
  "ou_xxx" \
  "Chinese ballad, soft piano, warm female vocal" \
  music-2.6
```

**注意**：
- `music-2.6` 免费版叫 `music-2.6-free`，配额受限
- 生成耗时 10–60 秒，先告诉用户「稍等我写一首」
- 风格 prompt 用英文更精确
- **无法复现已有歌曲的原旋律**（每次都是新创作），真翻唱需 `music-cover` + 上传原曲片段（本 skill 暂不支持）
- 音色**不能**和 voice.sh 的 TTS 音色共用 — 两个系统独立

voice / sing 会先读 `~/.openclaw/skills/.env`，再从 `openclaw.json -> skills.entries.voice.env` 补齐未设置的 key，最后叠加当前 agent 的 `skills/.env`。

## 👀 vision — 看图

```bash
~/.openclaw/skills/vision/scripts/resolve.sh <image_key|--latest>
```

输出本地路径，然后 agent 用 `Read` 工具读图。Claude 类多模态模型原生看懂。

| 输入 | 行为 |
|---|---|
| `img_v3_0210u_xxx` | 查 `gateway.log` 定位到下载文件 |
| `--latest` | 取 inbound 目录里最新一张 `.jpg/.png/.webp` |

退出码：`0`=成功；`2`=日志里找不到 key；`3`=文件已清理。

## 👂 hearing — 听语音

```bash
~/.openclaw/skills/hearing/scripts/stt.sh <file_key|--latest|/abs/path>
```

调本地 whisper 转写，stdout 是文本。

env:

| 变量 | 默认 | 说明 |
|---|---|---|
| `WHISPER_BIN` | `/opt/homebrew/bin/whisper` | whisper 路径 |
| `WHISPER_MODEL` | `turbo` | `tiny`/`base`/`small`/`medium`/`large-v3`/`turbo` |
| `WHISPER_LANGUAGE` | auto | 强制指定语言可提速并降低错识 |

首次用某 model 会去 HuggingFace 下载权重，可能十几秒到几分钟。

## 📸 selfie — 自拍 & 图生视频

```bash
# 自拍
~/.openclaw/skills/selfie/scripts/selfie.sh "<prompt>" "<channel>" [caption] [aspect] [format] [provider]

# 图生视频
~/.openclaw/skills/selfie/scripts/video.sh "<image_url>" "<prompt>" "<channel>" ...
```

依赖 `FAL_KEY`（推荐）或 `KIE_API_KEY`。脚本会先读 `~/.openclaw/skills/.env`，再从 `openclaw.json -> skills.entries.selfie.env` 补齐未设置的 key，最后叠加当前 agent 的 `skills/.env`。参考图由同一 env 里的 `SELFIE_REFERENCE_IMAGE` 给出，用来保持角色相貌一致。

## 🎮 dokidoki — 互动设备

```bash
doki scan
doki connect DK-META2
doki action linear 50       # 0–100
doki action rotary -30       # -100–100
doki action vibration 80
doki player play audio.mp3 timeline.json
```

详见 `~/.openclaw/skills/dokidoki/SKILL.md`。

## Skill 触发逻辑（agent 怎么知道用哪个）

每个 SKILL.md 前面的 YAML frontmatter 的 `description` 是 agent 看到的摘要。openclaw 把全部 skill 的摘要塞进系统提示，agent 根据对话自己决定调哪个。

想调节触发倾向：改对应 SKILL.md 的 description 或在 `custom.md` 里写 `## skill 使用原则` 覆盖默认判断。
