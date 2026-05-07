# 排错

## 安装器

**`~/.openclaw 不存在`**
→ 先装 openclaw：`npm i -g openclaw`，然后 `openclaw setup` 走一遍。

**`jq required`**
→ macOS `brew install jq` / Debian `apt install jq` / Windows `choco install jq`。

**`未在 openclaw.json 中找到任何可用模型`**
→ `openclaw.json` 里 `agents.defaults.models` 为空。去 [models.md](models.md) 看怎么加。

**安装过程被 Ctrl+C 了**
→ 重跑即可。已备份的 `openclaw.json.bak-*` 保留在原位。要完全回滚 `cp` 那个备份覆盖就行。

## 飞书

**「Bot can NOT be out of chat」**
→ 用错 App。每个 agent 要用自己的 `FEISHU_APP_ID` / `SECRET`。在 `<workspace>/skills/.env` 里配的应该是该 agent 的，不是别的。

**消息发不出**
→ 飞书 token 失效（App Secret 填错）或权限不够。检查：
  - `im:resource` 权限（上传文件需要）
  - 应用是否「发布版本」审批通过
  - `tenant_access_token` 的接口能不能正常拿到 token（用 curl 手动试）

**语音/图片发到群里不响**
→ 机器人没在群里。群设置 → 群机器人 → 添加。

## voice / sing

**`invalid api key`**
→ MiniMax key 对不上 endpoint。音乐 API 走 `api.minimaxi.com`（国内），TTS 也在这。国际版 `api.minimax.io` 暂不支持。

**`MINIMAX_API_KEY and MINIMAX_GROUP_ID required`**
→ 两者都要填，优先配置在 `~/.openclaw/openclaw.json -> skills.entries.voice.env`。旧安装也兼容 `~/.openclaw/skills/.env`。Group ID 在 MiniMax 控制台账户页。

**生成成功但飞书上听不见**
→ 上传时 `duration` 没传或为 0。脚本里 `ffprobe` 没装时火山引擎 TTS 会返回 0。装 ffmpeg 就好。

**sing 生成太慢**
→ MiniMax music 本来就 10–60 秒。长一点的歌词更久。免费版 `music-2.6-free` 慢且有配额限。

## hearing / STT

**`whisper not found`**
→ `brew install openai-whisper` 或 `pip install openai-whisper`。装完 `which whisper` 确认。

**首次运行卡在下载模型**
→ whisper 去 HuggingFace 拉 `.pt` 文件。`tiny` 72MB，`turbo` 1.5GB。国内网络慢可配 `HF_ENDPOINT=https://hf-mirror.com`。

**转写结果是空**
→ 音频太短 / 静音 / 纯噪声。告诉用户「没听清能再说一遍吗」。

**中英混杂转写错乱**
→ 设 `WHISPER_LANGUAGE=zh`（或 `en`）强制，或升级到 `medium`/`large-v3` 模型。

## vision

**`Key not found in gateway log`**
→ image_key 日志被轮转或截断。回退：`resolve.sh --latest` 取最近一张。

**图片文件存在但 agent 没看懂**
→ primary 模型不支持多模态。换多模态模型（见 [models.md](models.md)），或在 custom.md 里明确指示 agent 只报告路径不做解读。

## selfie

**`No reference image found`**
→ 优先检查 `openclaw.json -> skills.entries.selfie.env.SELFIE_REFERENCE_IMAGE`，旧安装也兼容 `<workspace>/skills/.env`。重跑最新版安装/同步脚本会在已有 fal/kie key 时补默认角色参考图。

**fal.ai 超时**
→ fal 某些时段不稳。降级到 `KIE_API_KEY` + `provider=kie`。

## dokidoki

**`doki: command not found`**
→ `npm install -g @tryjoy/dokidoki`。macOS 下可能还需要 `npm config set unsafe-perm true`。

**扫描不到设备**
→ 开蓝牙。macOS 给终端 `Bluetooth` 权限（系统设置 → 隐私与安全性 → 蓝牙）。

## 通用

**所有 skill 都挂**
→ gateway 没起来。`launchctl list | grep openclaw`。

```bash
# 重启
launchctl kickstart -k gui/$(id -u)/ai.openclaw.gateway

# 看日志
tail -f ~/.openclaw/logs/gateway.log
tail -f ~/.openclaw/logs/gateway.err.log
```

**openclaw.json 被我改坏了**
→ 从备份恢复：

```bash
ls ~/.openclaw/openclaw.json.bak-*
cp ~/.openclaw/openclaw.json.bak-YYYYMMDD-HHMMSS ~/.openclaw/openclaw.json
launchctl kickstart -k gui/$(id -u)/ai.openclaw.gateway
```

## 微信渠道（cc-connect）已知限制

通过 [cc-connect](https://github.com/chenhg5/cc-connect) 接微信个人号（iLink Bot API）时：

| 类型 | 微信里显示 |
|---|---|
| 文本 | ✅ 原生 |
| 图片 | ✅ 原生气泡（turn 内 token 新鲜） |
| 视频 (mp4) | ✅ 原生视频卡片（turn 内 token 新鲜） |
| 文件 (其他) | ✅ 文件附件 |
| **语音 (mp3/wav)** | ❌ 永远是文件附件 |

### 为什么语音不能是原生气泡

iLink Bot 协议（`@tencent-weixin/openclaw-weixin@2.1.10`）的 `messaging/send.ts` **没有 `sendVoiceMessageWeixin` 函数** —— 腾讯只暴露了 text/image/video/file 四种 send。任何外部 bot 主动发 voice item 都会被 iLink server `ret=-2` 拒绝（见 [chenhg5/cc-connect#763](https://github.com/chenhg5/cc-connect/issues/763)）。这是腾讯协议级限制，不是 cc-connect bug，无法绕过。

**解决**：让 nako 把语音作为文件附件发出（点开能播）。或在飞书/Telegram/Discord 等没有此限制的渠道用语音。

### 视频要原生卡片需要 cc-connect fork

upstream cc-connect v1.3.2 把 mp4 当文件发。fork [`CodeEagle/cc-connect@lazycat/v1.3.3`](https://github.com/CodeEagle/cc-connect/tree/lazycat/v1.3.3) 加了按 MIME/扩展名自动分流（`SendFile` → `SendVideo`）。

```bash
bash scripts/cc-connect-setup.sh --agent-id agent-nako --with-weixin --cc-connect-source lazycat
```

安装脚本会优先下载 `CodeEagle/cc-connect` release 制品；没有对应平台制品时才尝试本机 Go 构建。需要 `ffmpeg` + AMR 编码器在 PATH，否则微信语音转码会报 `ffmpeg not found` 或 `Unknown encoder 'amr_nb'`。最新版 voice/sing 在转码失败时会明确提示缺少 ffmpeg/AMR 转码能力，并保留生成好的 MP3 文件路径；不会把音频改打成 zip。

### context_token TTL

每条 inbound 消息附带 `context_token`，被 cc-connect 缓存到 `~/.cc-connect/weixin/<project>/<bot>/context_tokens.json`。token 有较短 TTL（实测几分钟），过期后任何 outbound（含 text）都会 ret=-2。**只能在用户最近发消息后短窗口内主动推送** —— cron 触发的 daily-missing-reminder 等场景不保证送达。

## 定时任务报 `Channel is required`

如果 cron 状态里看到：

```text
Channel is required (no configured channels detected)
```

说明 job 还在使用 OpenClaw 原生 `delivery.channel=last`。通过 cc-connect / ACP 进入的微信、飞书会话不会被 OpenClaw 识别成原生 channel，所以主动消息要由 agent 调 `<workspace>/scripts/send-active-message.sh` 发送。

重跑最新版安装脚本会把已有 `nako-heartbeat`、`nako-daily-script`、`nako-missing-reminder` 改成 `--session isolated --no-deliver`。历史错误会留在 `jobs-state.json`，等下一次任务跑完才会刷新。

## 提 Issue

[github.com/Lovappen/MetaPact/issues](https://github.com/Lovappen/MetaPact/issues)

带上：

1. 出错命令 + 完整输出
2. `gateway.log` / `gateway.err.log` 相关片段
3. `openclaw --version`、OS、Node 版本
4. `bash nako/scripts/smoke-test.sh` 输出
