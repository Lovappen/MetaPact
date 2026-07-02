# MetaPact

可一键部署到 [openclaw](https://openclaw.ai) 的 agent 集合。每个子目录是一个独立的 agent pack，含人设 + skill + 安装器；通用文档在 `docs/`，各 agent 特色文档在 `docs/<agent-name>/`。

**适配设备：**[心跳元力2 Pro][device-yuanli-2] / [黑洞SE][device-blackhole-se]，点击设备名可跳转到京东旗舰店。

## 不会弄龙虾？

<table>
  <tr>
    <td>
      <h3>下载心跳元力，一步开始</h3>
      <p>如果你不会配置龙虾，可以直接下载 <strong>心跳元力</strong>，用更省心的方式体验 MetaPact。</p>
      <p><a href="https://metapact.app/r/?target=heartbeat-app-download&source=github-readme"><strong>前往下载心跳元力 →</strong></a></p>
    </td>
  </tr>
</table>

## 适配设备

MetaPact 当前适配以下设备，点击设备名可跳转到京东旗舰店查看规格与购买：

| 图片                                                                           | 设备                             | 说明                                                     | 购买入口                          |
| ------------------------------------------------------------------------------ | -------------------------------- | -------------------------------------------------------- | --------------------------------- |
| <img src="./docs/assets/devices/yuanli-2.png" alt="心跳元力2 Pro" width="180"> | [心跳元力2 Pro][device-yuanli-2] | 元力系列二代设备，适合作为 MetaPact 的主力接入硬件。     | [京东旗舰店][device-yuanli-2]     |
| <img src="./docs/assets/devices/black-hole-se.png" alt="黑洞SE" width="180">   | [黑洞SE][device-blackhole-se]    | 黑洞系列 SE 设备，适合偏好紧凑机身和入门配置的接入场景。 | [京东旗舰店][device-blackhole-se] |

[device-yuanli-2]: https://metapact.app/r/?target=yuanli-2&source=github-readme
[device-blackhole-se]: https://metapact.app/r/?target=blackhole-se&source=github-readme

## 一键安装

```bash
# 默认装 nako（目前唯一 agent），交互式问 cc-connect 接入
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash

# 非交互 + QR 飞书一气呵成
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --with-feishu

# 选别的 agent
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --agent <name>

# 看可用 agent
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/install.sh | bash -s -- --list
```

完整 flag：`bash install.sh --help`。

### 模型要求

OpenClaw 模式会从 `openclaw.json -> agents.defaults.models` 读取已配置模型，
优先看模型条目里的 `capabilities` / `tags` / `features` / `modalities`
等能力字段。Nako 本体优先需要 `roleplay` 能力，也就是稳定中文对话、
角色扮演和指令跟随；没有命中时会退到 `general`，只要求能完成日常对话、
工具意图理解、总结和代码/配置分析。没有能力字段的已配置模型会被视为可用的
`general` 文本模型。

`nako/config/model-map.yaml` 只是无能力字段时的偏好排序，不是固定支持列表。
常见可用模型已经写入其中，包括
`moonshot/kimi-k2.6`、`moonshot/kimi-k2.5`、`volcengine/kimi-k2-5-260127`、
`volcengine-plan/ark-code-latest`、`volcengine/deepseek-v3-2-251201` 等。
图片理解是可选的 `vision` 能力，只影响 vision skill，不影响安装和文字聊天。
语音/唱歌/自拍主要依赖对应外部 key 和本地工具，不靠主模型能力判断。
完整说明见 [安装详解：模型能力要求](docs/nako/install.md#模型能力要求)。

Windows PowerShell 建议直接走 GitHub raw，避免 `cdn.jsdelivr.net @main` 缓存到旧脚本：

```powershell
$u = "https://raw.githubusercontent.com/Lovappen/MetaPact/main/install.ps1?ts=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$p = Join-Path $env:TEMP "metapact-install.ps1"
iwr -UseBasicParsing $u -OutFile $p
pwsh -NoProfile -ExecutionPolicy Bypass -File $p -Runtime qclaw -AgentId agent-nako -WithWeixin
```

## 现有 Agents

| Agent         | 角色              | 渠道                                                                                                                                                                                                 |
| ------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [nako](nako/) | 战斗女仆 野木奈子 | 飞书 / 微信 / Telegram / Slack /...（via [cc-connect](https://github.com/chenhg5/cc-connect)，微信视频优先用 [CodeEagle fork release](https://github.com/CodeEagle/cc-connect/releases/tag/v1.3.3)） |

## 文档

- [进阶玩法：Agent 通用自定义与调优](docs/advanced.md)
- [nako 文档](docs/nako/README.md)

## 致谢

感谢以下用户帮助完善 MetaPact：

| 用户 | 贡献                                                                                    |
| ---- | --------------------------------------------------------------------------------------- |
| 久部 | 帮助排查并完善 Windows 安装流程，尤其是 PowerShell、cc-connect 启动与微信绑定相关问题。 |

## 与 agent 无关的工具

### `scripts/cc-connect-setup.sh` / `scripts/cc-connect-setup.ps1` — 给任意 agent 做 cc-connect 多平台接入

也支持 curl 一键，参数走 `bash -s --` 传：

```bash
# 交互问要不要装飞书/微信
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/cc-connect-setup.sh | bash

# 指定 agent + 自动 QR 飞书 + 微信
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/cc-connect-setup.sh \
  | bash -s -- --agent-id agent-foo --with-feishu --with-weixin

# 本地 clone 后跑
bash scripts/cc-connect-setup.sh --agent-id agent-foo --with-feishu --with-weixin

# Hermes ACP 后端（Hermes 需已安装）
bash scripts/cc-connect-setup.sh --agent-id agent-foo --runtime hermes --with-feishu

# QClaw ACP 后端（QClaw 需已安装并已生成 ~/.qclaw/qclaw.json）
bash scripts/cc-connect-setup.sh --agent-id agent-foo --runtime qclaw --with-feishu

# 从 0 直接安装 Nako 到 QClaw（不要求 ~/.openclaw/openclaw.json）
bash install.sh --runtime qclaw --agent-id agent-nako --non-interactive

# 卸载某个 agent 的 cc-connect 接入
bash scripts/cc-connect-setup.sh --agent-id agent-foo --uninstall

# 一键完整卸载 cc-connect，并移除指定 agent runtime 数据（不传则默认 agent-nako）
bash scripts/cc-connect-setup.sh --agent-id agent-nako --uninstall-all

# Windows PowerShell: 通过 QClaw 接入飞书/微信
pwsh install.ps1 -Runtime qclaw -WithFeishu -WithWeixin

# Windows PowerShell: 只配置 cc-connect 接入
pwsh scripts/cc-connect-setup.ps1 -AgentId agent-foo -Runtime qclaw -WithFeishu -WithWeixin
```

QClaw 后端需要和 `cc-connect` 跑在同一个 host/user 下；如果 `cc-connect`
在 Linux VM 里，不能直接执行宿主机 macOS 的 `QClaw.app`。
同一台机器同时接 OpenClaw 和 QClaw 时，cc-connect project 会自动隔离：
OpenClaw 默认使用 `<agent-id>`，QClaw 默认使用 `<agent-id>-qclaw`，
Hermes 默认使用 `<agent-id>-hermes`；需要手动指定时加 `--cc-project-id` /
`-CcProjectId`。接入后飞书/微信消息会写入 QClaw 的 `cc-connect 飞书/微信`
ACP 会话，对应 QClaw session key 为 `agent:<id>:session-cc-connect`。

完整 flag：`bash scripts/cc-connect-setup.sh --help`

### `scripts/nako-agent-factory/` — 局域网自助创建 Nako agent

给一台 host 部署 8088 管理页：每个客户端 IP 只分配一个 `agent-nako-N`，页面可选择 OpenClaw 或 Hermes 作为消息后端，生成 / 刷新飞书和微信二维码，并直接展示安装与 QR 日志。QClaw 只能通过上面的 `scripts/cc-connect-setup.sh --runtime qclaw` 脚本绑定。

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/Lovappen/MetaPact@main/scripts/nako-agent-factory/install.sh | sudo bash

# 或本地 clone 后跑
cd scripts/nako-agent-factory
sudo bash install.sh
```

打开 `http://<host-ip>:8088/` 后点击按钮即可创建或刷新当前 IP 对应的 agent。

## Roadmap

- [x] **多平台接入**：飞书原生 + 通过 [cc-connect](https://github.com/chenhg5/cc-connect) 接微信/Telegram/Slack/Discord/QQ/微博/钉钉/企微/LINE 等。详见 [`scripts/cc-connect-setup.sh`](scripts/cc-connect-setup.sh)
- [x] **一键 QR onboarding**：飞书 / 微信 ilink 都内置在安装脚本里
- [ ] **微信原生语音气泡**：iLink Bot API 协议级限制——`@tencent-weixin/openclaw-weixin` 不暴露 `sendVoiceMessageWeixin`，外部 bot 发 voice item 永远 `ret=-2`。等腾讯放开（[chenhg5/cc-connect#763](https://github.com/chenhg5/cc-connect/issues/763)）
- [ ] **微信 cron 主动推送**：`context_token` TTL 短，cron-driven daily-reminder 不保证送达。需要 cc-connect 实现 token 续期或换协议
- [ ] **MiniMax 国际版**（`api.minimax.io`）
- [ ] **更多 agent 模板**（办公助手、学习搭档…）
- [ ] **共享 skill 库**：把 `nako/skills/` 里通用的 vision/hearing/voice/selfie 提取到 root 让多 agent 复用

## 贡献

欢迎开 PR 加新 agent pack。格式参考 `nako/` 的目录结构：

```
your-agent/
├── install.sh           # 入口
├── install.ps1          # Windows
├── README.md            # 快装 + 定位
├── agent/               # 人设 md 文件 + custom.md 模板
├── skills/              # 本 agent 用到的 skill
├── config/
│   └── model-map.yaml   # 无能力字段时的模型偏好表
└── scripts/             # 安装器内部 helper

docs/
└── your-agent/          # 该 agent 的用户文档与特色玩法
```

新 pack 必须：

- 不把任何真实 key / secret 提交进仓库（`.env.*.example` 仅占位）
- 升级路径不破坏用户 `custom.md` / `memory/` / `sessions/`
- 有 `scripts/smoke-test.sh` 冒烟脚本
- 顶层 README 里加一行，并在 `docs/<agent-name>/` 放用户文档

## License

MIT, see [LICENSE](LICENSE).
