<div align="center">

# MetaPact

元力 AI 女友，专属赛博伴侣养成计划：把可定义人设、长期记忆、语音/视觉能力和多平台聊天接入，打包成可一键部署的 Agent Pack。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/runtime-OpenClaw-111827)](https://github.com/openclaw/openclaw)
[![QClaw](https://img.shields.io/badge/runtime-QClaw-7c3aed)](https://qclaw.qq.com/)
[![HermesAgent](https://img.shields.io/badge/runtime-HermesAgent-f59e0b)](https://github.com/NousResearch/hermes-agent)
[![MetaPact](https://img.shields.io/badge/site-metapact.app-ff4d8d)](https://www.metapact.app/)

[官网](https://www.metapact.app/) · [一键安装](#一键安装) · [Nako 文档](docs/nako/README.md) · [进阶玩法](docs/advanced.md)

</div>

> 愿你拥有一个会记得、会说话、会看见、会在常用工具里陪你生活的 AI 伴侣。

MetaPact 是一套开源 AI 伴侣 Agent 集合。每个子目录都是一个独立的 agent pack，包含角色设定、skills、安装器和文档；目前主力角色是 **野木奈子 Nako**，一个可部署到 OpenClaw / QClaw / HermesAgent 的战斗女仆 Agent。

它不是只有 prompt 的聊天模板，而是把「人设」「记忆」「多模态能力」「渠道接入」「硬件互动」放到同一个可 fork、可升级、可自定义的仓库里。你可以直接安装 Nako，也可以把这里当成创建自己 AI 女友 / AI 伴侣 / 角色 Agent 的骨架。

> [!TIP]
> 不会配置 OpenClaw / QClaw / HermesAgent？可以直接下载 **心跳元力**，用更省心的方式体验 MetaPact。
>
> <a href="https://metapact.app/r/?target=heartbeat-app-download&source=github-readme"><strong>前往下载心跳元力 →</strong></a>

## 为什么是 MetaPact？

很多 AI 伴侣产品能聊天，但你很难真正拥有它：人设不透明、记忆不可迁移、渠道被平台锁住、能力也不能自由改。MetaPact 想提供另一种可能：**把你的角色设定和能力栈留在你自己的环境里**。

- **可拥有的人设**：角色设定、灵魂文件、custom.md、memory 都在本地，可读、可改、可版本化。
- **可部署的伴侣**：一条命令安装 agent pack，支持 OpenClaw / QClaw / HermesAgent，能接入飞书、微信、Telegram、Slack 等渠道。
- **可扩展的能力**：看图、听语音、说话、唱歌、自拍、互动设备等能力以 skill 形式组织。
- **可升级的骨架**：安装器会保护你的 custom、memory、session 和认证文件，升级不会吃掉个人数据。
- **可 fork 的生态**：你可以基于 Nako 做二创，也可以新增完全不同的人格模板和 agent pack。

## 一键安装

**macOS / Linux**

```bash
# 默认安装 nako，安装器会交互式完成 agent 配置
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash

# 非交互 + QR 飞书一气呵成
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --with-feishu

# 选择其他 agent
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --agent <name>

# 查看可用 agent
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --list
```

**Windows PowerShell 7+**

Windows PowerShell 建议直接走 GitHub raw，避免 `cdn.jsdelivr.net @main` 缓存到旧脚本：

```powershell
$u = "https://raw.githubusercontent.com/Lovappen/MetaPact/main/install.ps1?ts=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$p = Join-Path $env:TEMP "metapact-install.ps1"
iwr -UseBasicParsing $u -OutFile $p
pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Runtime qclaw -AgentId agent-nako -WithWeixin
```

完整 flag：

```bash
bash install.sh --help
```

## 模型要求

OpenClaw 模式会从 `openclaw.json -> agents.defaults.models` 读取已配置模型，并优先看模型条目里的 `capabilities` / `tags` / `features` / `modalities` 等能力字段。

Nako 本体优先需要 `roleplay` 能力，也就是稳定中文对话、角色扮演和指令跟随；没有命中时会退到 `general`，只要求能完成日常对话、工具意图理解、总结和代码/配置分析。没有能力字段的已配置模型会被视为可用的 `general` 文本模型。

`nako/config/model-map.yaml` 只是无能力字段时的偏好排序，不是固定支持列表。常见可用模型已经写入其中，包括 `moonshot/kimi-k2.6`、`moonshot/kimi-k2.5`、`volcengine/kimi-k2-5-260127`、`volcengine-plan/ark-code-latest`、`volcengine/deepseek-v3-2-251201` 等。

图片理解是可选的 `vision` 能力，只影响 vision skill，不影响安装和文字聊天。语音/唱歌/自拍主要依赖对应外部 key 和本地工具，不靠主模型能力判断。完整说明见 [安装详解：模型能力要求](docs/nako/install.md#模型能力要求)。

## 现有 Agents

| Agent | 角色 | 能力 | 渠道 |
| --- | --- | --- | --- |
| [nako](nako/) | 战斗女仆 野木奈子 | 看图 / 听语音 / 说话 / 唱歌 / 自拍 / 互动设备 | 飞书 / 微信 / Telegram / Slack / Discord / QQ / 微博 / 钉钉 / 企微 / LINE 等 |

微信、Telegram、Slack 等多平台接入由 [cc-connect](https://github.com/chenhg5/cc-connect) 提供；微信视频优先使用 [CodeEagle fork release](https://github.com/CodeEagle/cc-connect/releases/tag/v1.3.3)。

## 适配设备

MetaPact 当前适配以下设备，点击设备名可跳转到京东旗舰店查看规格与购买：

| 图片 | 设备 | 说明 | 购买入口 |
| --- | --- | --- | --- |
| <img src="./docs/assets/devices/yuanli-2.png" alt="元力2" width="180"> | [元力2][device-yuanli-2] | 元力系列二代设备，适合作为 MetaPact 的主力接入硬件。 | [京东旗舰店][device-yuanli-2] |
| <img src="./docs/assets/devices/black-hole-se.png" alt="黑洞SE" width="180"> | [黑洞SE][device-blackhole-se] | 黑洞系列 SE 设备，适合偏好紧凑机身和入门配置的接入场景。 | [京东旗舰店][device-blackhole-se] |

[device-yuanli-2]: https://metapact.app/r/?target=yuanli-2&source=github-readme
[device-blackhole-se]: https://metapact.app/r/?target=blackhole-se&source=github-readme

## 文档

- [安装详解](docs/nako/install.md)：安装参数、非交互模式、模型能力要求与排错。
- [飞书接入](docs/nako/feishu-setup.md)：创建飞书机器人并接入 Nako。
- [模型选型](docs/nako/models.md)：多模型切换、能力字段与新增模型。
- [Skills 参考](docs/nako/skills.md)：voice、vision、hearing、selfie、dokidoki 的使用方式。
- [人设定制](docs/nako/customization.md)：改人设、换音色、维护 `custom.md`。
- [进阶玩法](docs/advanced.md)：Agent 通用自定义与调优。
- [Nako 特色玩法](docs/nako/advanced.md)：Nako 专属高级用法。
- [常见错误](docs/nako/troubleshooting.md)：安装、渠道、依赖与平台限制。

## 与 Agent 无关的工具

### `scripts/cc-connect-setup.sh` / `scripts/cc-connect-setup.ps1`

给任意 agent 做 cc-connect 多平台接入，也支持 curl 一键安装：

```bash
# 交互询问是否安装飞书/微信
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/cc-connect-setup.sh | bash

# 指定 agent + 自动 QR 飞书 + 微信
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/cc-connect-setup.sh \
  | bash -s -- --agent-id agent-foo --with-feishu --with-weixin

# 本地 clone 后运行
bash scripts/cc-connect-setup.sh --agent-id agent-foo --with-feishu --with-weixin

# HermesAgent ACP 后端，HermesAgent 需已安装
bash scripts/cc-connect-setup.sh --agent-id agent-foo --runtime hermes --with-feishu

# QClaw ACP 后端，QClaw 需已安装并已生成 ~/.qclaw/qclaw.json
bash scripts/cc-connect-setup.sh --agent-id agent-foo --runtime qclaw --with-feishu

# 从 0 直接安装 Nako 到 QClaw，不要求 ~/.openclaw/openclaw.json
bash install.sh --runtime qclaw --agent-id agent-nako --non-interactive

# 卸载某个 agent 的 cc-connect 接入
bash scripts/cc-connect-setup.sh --agent-id agent-foo --uninstall

# 一键完整卸载 cc-connect，并移除指定 agent runtime 数据；不传则默认 agent-nako
bash scripts/cc-connect-setup.sh --agent-id agent-nako --uninstall-all
```

Windows PowerShell：

```powershell
# 通过 QClaw 接入飞书/微信
pwsh install.ps1 -Runtime qclaw -WithFeishu -WithWeixin

# 只配置 cc-connect 接入
pwsh scripts/cc-connect-setup.ps1 -AgentId agent-foo -Runtime qclaw -WithFeishu -WithWeixin
```

QClaw 后端需要和 `cc-connect` 跑在同一个 host/user 下；如果 `cc-connect` 在 Linux VM 里，不能直接执行宿主机 macOS 的 `QClaw.app`。

同一台机器同时接 OpenClaw、QClaw 和 HermesAgent 时，cc-connect project 会自动隔离：OpenClaw 默认使用 `<agent-id>`，QClaw 默认使用 `<agent-id>-qclaw`，HermesAgent 默认使用 `<agent-id>-hermes`；需要手动指定时加 `--cc-project-id` / `-CcProjectId`。接入后飞书/微信消息会写入 QClaw 的 `cc-connect 飞书/微信` ACP 会话，对应 QClaw session key 为 `agent:<id>:session-cc-connect`。

完整 flag：

```bash
bash scripts/cc-connect-setup.sh --help
```

### `scripts/nako-agent-factory/`

局域网自助创建 Nako agent。它会给一台 host 部署 8088 管理页，每个客户端 IP 只分配一个 `agent-nako-N`，页面可选择 OpenClaw 或 HermesAgent 作为消息后端，生成 / 刷新飞书和微信二维码，并直接展示安装与 QR 日志。

QClaw 只能通过上面的 `scripts/cc-connect-setup.sh --runtime qclaw` 脚本绑定。

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/nako-agent-factory/install.sh | sudo bash

# 或本地 clone 后运行
cd scripts/nako-agent-factory
sudo bash install.sh
```

打开 `http://<host-ip>:8088/` 后点击按钮即可创建或刷新当前 IP 对应的 agent。

## 当前进展

Capable of:

- [x] **Brain**
  - [x] Nako 战斗女仆人设
  - [x] 本地 custom.md 人设覆盖
  - [x] 长期记忆与对话 session 保留
  - [x] OpenClaw / QClaw / HermesAgent runtime 安装路径
- [x] **Channels**
  - [x] 飞书原生接入
  - [x] 微信 / Telegram / Slack / Discord / QQ / 微博 / 钉钉 / 企微 / LINE 等 via [cc-connect](https://github.com/chenhg5/cc-connect)
  - [x] 一键 QR onboarding
- [x] **Ears & Eyes**
  - [x] 图片理解 via vision skill
  - [x] 语音转写 via hearing skill
- [x] **Mouth**
  - [x] TTS 语音回复
  - [x] MiniMax music 唱歌
- [x] **Body**
  - [x] 自拍 / 图生视频
  - [x] 元力2 / 黑洞SE 等互动设备适配

## 下一步计划

- [ ] **微信原生语音气泡**：iLink Bot API 协议级限制，`@tencent-weixin/openclaw-weixin` 不暴露 `sendVoiceMessageWeixin`，外部 bot 发 voice item 永远 `ret=-2`。等待腾讯放开，见 [chenhg5/cc-connect#763](https://github.com/chenhg5/cc-connect/issues/763)。
- [ ] **微信 cron 主动推送**：`context_token` TTL 短，cron-driven daily-reminder 不保证送达。需要 cc-connect 实现 token 续期或更换协议。
- [ ] **MiniMax 国际版**：支持 `api.minimax.io`。
- [ ] **更多 agent 模板**：办公助手、学习搭档、不同人格模板等。
- [ ] **共享 skill 库**：把 `nako/skills/` 里的 vision、hearing、voice、selfie 等通用能力提取到 root 让多 agent 复用。
- [ ] **人设库与社区作品流**：整理更多可直接 fork 的人格模板、示例对话和用户作品展示。

## 贡献

欢迎开 PR 加新 agent pack。格式参考 `nako/` 的目录结构：

```text
your-agent/
├── install.sh
├── install.ps1
├── README.md
├── agent/
├── skills/
├── config/
│   └── model-map.yaml
└── scripts/

docs/
└── your-agent/
```

新 pack 必须：

- 不把任何真实 key / secret 提交进仓库，`.env.*.example` 仅占位。
- 升级路径不破坏用户 `custom.md` / `memory/` / `sessions/`。
- 有 `scripts/smoke-test.sh` 冒烟脚本。
- 顶层 README 里加一行，并在 `docs/<agent-name>/` 放用户文档。

## 致谢

感谢以下用户帮助完善 MetaPact：

| 用户 | 贡献 |
| --- | --- |
| 久部 | 帮助排查并完善 Windows 安装流程，尤其是 PowerShell、cc-connect 启动与微信绑定相关问题。 |

## License

MIT, see [LICENSE](LICENSE).
