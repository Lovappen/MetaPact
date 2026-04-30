# 野木奈子 Agent Pack

一个可一键部署的 openclaw agent 包 — 战斗女仆人设 `野木奈子`，自带看图/听语音/说话/唱歌/自拍/互动设备等能力。

## 快装

**macOS / Linux:**

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash
```

**Windows (PowerShell 7+):**

```powershell
iex (iwr -UseBasicParsing https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.ps1).Content

# cc-connect 飞书 QR
$installer = [scriptblock]::Create((iwr -UseBasicParsing https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.ps1).Content)
& $installer -WithFeishu
```

或者克隆仓库本地跑：

```bash
git clone https://github.com/Lovappen/MetaPact.git
bash MetaPact/install.sh
# Windows:
pwsh MetaPact\install.ps1
```

## 前置

- 已安装 [openclaw](https://www.npmjs.com/package/openclaw) 且 `~/.openclaw` 存在
- macOS / Linux: `jq curl python3`（安装器会检查）；`uuidgen` 用于多媒体文件名，缺失时脚本会自动 fallback
- Windows 10+: PowerShell 7+、`python`、`jq`、`curl`
- 一个飞书自建应用（[创建教程](../docs/nako/feishu-setup.md)）
- 至少一个对话模型已配在 `openclaw.json`（最好是 `sensenova/SenseChat-Character-Agt`，详见 [models.md](../docs/nako/models.md)）

## 功能一览

| Skill | 触发场景 | 依赖 |
|---|---|---|
| 🎤 voice  | 发语音 / 唱歌 | MiniMax 或 Volcengine Key + 飞书 |
| 👀 vision | 看用户发的图 | 主模型多模态 |
| 👂 hearing | 听用户发的语音 | 本地 whisper + ffmpeg |
| 📸 selfie | 生成自拍 / 图生视频 | FAL_KEY 或 KIE_API_KEY |
| 🎮 dokidoki | 蓝牙互动设备 | npm `@tryjoy/dokidoki` |

## 文档

- [install.md](../docs/nako/install.md) — 安装详解 / 非交互模式 / 排错
- [feishu-setup.md](../docs/nako/feishu-setup.md) — 建飞书机器人
- [models.md](../docs/nako/models.md) — 模型选型 / 多模型切换 / 加新模型
- [skills.md](../docs/nako/skills.md) — 每个 skill 用法 + 参数
- [customization.md](../docs/nako/customization.md) — 改人设 / 换音色 / custom.md
- [advanced.md](../docs/advanced.md) — 通用进阶玩法 / 深度调优 / 自定义 agent
- [nako/advanced.md](../docs/nako/advanced.md) — nako 特色玩法
- [troubleshooting.md](../docs/nako/troubleshooting.md) — 常见错误

## 升级不会吃掉你的数据

安装器升级时**永远不会覆盖**：

- `<workspace>/custom.md`（你的定制）
- `<workspace>/memory/`（agent 记忆）
- `<workspace>/MEMORY.md`（如你有）
- `~/.openclaw/agents/<id>/sessions/`（对话记录）
- `~/.openclaw/agents/<id>/agent/auth-*.json`（认证凭据）

人设文件（IDENTITY.md / SOUL.md 等）升级时会提示你是否覆盖，默认保留。想改人设请写进 `custom.md`。

## 目前限制

- MiniMax music 目前**仅支持国内版账号**（`api.minimaxi.com`）。国际版支持后续补。
- Whisper 首次运行下模型（tiny ~72MB / turbo ~1.5GB）。
- Windows 原生未经充分测试，推荐 WSL2。
- **微信渠道**（通过 [cc-connect](https://github.com/chenhg5/cc-connect)）：语音永远是文件附件而非原生气泡（iLink Bot API 限制）；`--with-weixin` 会优先安装支持 mp4 原生视频的 [`CodeEagle/cc-connect@v1.3.3`](https://github.com/CodeEagle/cc-connect/releases/tag/v1.3.3) release。详见 [docs/nako/troubleshooting.md](../docs/nako/troubleshooting.md#微信渠道cc-connect已知限制)。

## License

MIT（见仓库根 `LICENSE`）。野木奈子角色设定属于项目作者，转发/二次创作请保留 SOUL/IDENTITY 文件中的版权注释。
