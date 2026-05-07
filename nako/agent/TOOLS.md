# TOOLS.md - 本地工具速查

此文件列 agent 会用到的技能与它们的脚本入口。安装器会按你的环境填充可用项；缺少依赖的技能行会自动标注 `⚠️ 未启用`。

## 已启用（安装器会按实际环境自动调整）

```
🎤 voice   — 发语音 / 唱歌
   - ${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/voice/scripts/voice.sh "<文本>" <channel> [provider] [voice_id] [speed]
   - ${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/voice/scripts/sing.sh  "<歌词>" <channel> ["<风格>"] [model]

👀 vision  — 看图
   - ~/.openclaw/skills/vision/scripts/resolve.sh <image_key|--latest>
   - 拿到路径后用 Read 工具直接看图

👂 hearing — 听语音消息
   - ~/.openclaw/skills/hearing/scripts/stt.sh <file_key|--latest|/abs/path>

📸 selfie  — 生成自拍照片和图生视频
   - ${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/selfie/scripts/selfie.sh "<prompt>" <channel> [caption] [aspect_ratio] [format] [provider]
   - ${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/selfie/scripts/video.sh  "<image_url>" "<prompt>" <channel> ...

🎮 dokidoki — BLE 互动设备
   - doki scan / connect / action / player ...
```

## 技能选型

- **说话 vs 唱歌**：纯朗读用 `voice.sh`（快、稳）；用户要求唱歌/写歌用 `sing.sh`（MiniMax music-2.6，10–60 秒）
- **看图**：收到 `{"image_key":"..."}` 或 `<media:image>` 先 `resolve.sh` 拿路径，再 `Read` 看
- **听语音**：收到 `[Audio]` / `<media:audio>` 先 `stt.sh --latest` 转写
- **cc-connect 媒体强制规则**：用户来自飞书/微信/ACP 时，自拍、语音、唱歌、视频都必须调用上面的 Nako bash 脚本发送；不要调用 OpenClaw 原生 `image_generate` / `tts` / `video_generate`，这些只会生成 webchat 媒体，飞书/微信收不到。即使会话里出现 `messageProvider=webchat`，只要 `NAKO_OUTPUT_MODE=acp` 或 `OPENCLAW_OUTPUT_MODE=acp`，仍按 cc-connect 处理。
- **全能力展示**：用户要求“展示能力 / 自拍 / 语音 / 唱歌 / 视频”时，按脚本顺序逐项执行：`selfie.sh` 发自拍，`voice.sh` 发语音，`sing.sh` 发唱歌，最后用自拍返回的 `image_url` 调 `video.sh` 发视频。某一项失败只说明该项失败，不要把已成功的媒体漏发。

cc-connect / ACP 示例：

```bash
NAKO_OUTPUT_MODE=acp bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/selfie/scripts/selfie.sh" "<自拍英文 prompt>" "cc-connect" "<caption>" "3:4"
NAKO_OUTPUT_MODE=acp bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/voice/scripts/voice.sh" "<要说的话>" "cc-connect" auto female-tianmei 1.0
NAKO_OUTPUT_MODE=acp bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/voice/scripts/sing.sh" "<歌词>" "cc-connect" "<English music style>"
NAKO_OUTPUT_MODE=acp bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/selfie/scripts/video.sh" "<selfie.sh 返回的 image_url 或本地图片路径>" "<English motion prompt>" "cc-connect" "<caption>"
```

## 输出模式（重要）

skill 脚本支持两种产物投递方式，由环境变量 `NAKO_OUTPUT_MODE`（旧版兼容 `OPENCLAW_OUTPUT_MODE`）选择：

- **`feishu`（OpenClaw 原生直连飞书）**：脚本生成文件后自己上传到飞书并 send。需要 `FEISHU_APP_ID/SECRET` + `<channel>` 是真实飞书 chat_id。
- **`acp`（cc-connect / 多平台 host 接管）**：脚本生成文件后交给 host 按当前会话投递。Hermes/cc-connect 飞书绑定的 App ID 在 `~/.cc-connect/config.toml`，不要仅凭 `<workspace>/skills/.env` 里的 `FEISHU_APP_ID` 判断缺失。
  - 此时 `<channel>` 优先填 `cc-connect`，也兼容 `acp` / `feishu` 旧别名；脚本会自动使用当前 cc-connect 活跃会话。
  - 脚本会优先直接调用 `cc-connect send` 投递附件；收到 JSON 后只需简短说明结果，不要再改用 OpenClaw 原生媒体工具补发。

## 环境

- voice / sing 的 API key 和默认音色优先从运行时 skill env 读取；Hermes/cc-connect 同时读取 `$NAKO_SKILLS_DIR/.env`、`~/.hermes/.env` 和本 agent 的 `skills/.env`。
- selfie / video 的共享生成 key 同样从运行时 skill env 读取。
- 脚本仍兼容旧安装的共享 `skills/.env`；本 agent 私有 env（角色标识 + 可选原生飞书凭据）在 `<workspace>/skills/.env`，会覆盖共享默认值。
- 如果用户问语音/唱歌 key 在哪，先回答 `openclaw.json -> skills.entries.voice.env`，不要只提示去 `.env`。
- 判断 key 是否缺失前必须先真实检测，不要凭记忆推断。可运行 `bash <repo>/nako/scripts/smoke-test.sh`，或用 `jq` 只查看 `skills.entries.voice.env` / `skills.entries.selfie.env` 的 key 名称，不能打印密钥值。
- `NAKO_OUTPUT_MODE` / `OPENCLAW_OUTPUT_MODE`：`feishu`（OpenClaw 原生直连）或 `acp`（cc-connect 集成时设此值）

## 主动行为脚本（workspace/scripts/）

奈子有一套"思念机制"，由 openclaw cron 驱动 + 用户消息触发。脚本骨架已装到 `<workspace>/scripts/`。

| 脚本 | 谁来调 | 干什么 |
|---|---|---|
| `heartbeat-check.sh` | cron `nako-heartbeat`（每 30 分钟）— agent 在被唤起时 `Bash` 调用 | 更新思念值/情绪值。退出码 1 = 达阈值，agent 应主动生成一条消息 |
| `send-active-message.sh` | cron / agent 需要主动发文字时调用 | 通过 cc-connect 发送到当前最近活跃会话；不要依赖 openclaw cron delivery |
| `daily-missing-reminder.sh` | cron `nako-missing-reminder`（每天 16:50） | 发送默认思念提醒或只触发 doki 振动（`NAKO_REMINDER_SKIP_SEND=1`） |
| `mood-recovery.sh` | **agent 在每次收到用户消息时主动调用** | 思念值清零、情绪回血。务必在每个 turn 开头跑一次 |

调用约定：
```bash
bash <workspace>/scripts/heartbeat-check.sh   # 退出码 1 = 触发
bash <workspace>/scripts/send-active-message.sh "主人大人～..."  # 主动发文字
bash <workspace>/scripts/mood-recovery.sh     # 用户来消息时
```

state 文件：`<workspace>/memory/heartbeat-state.json`（思念值 + 情绪值的 source of truth，所有脚本读写它）。

## 用户自定义

见 `custom.md`。
