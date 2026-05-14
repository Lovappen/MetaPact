# 模型选型与切换

## 安装器怎么挑模型

安装器从用户已经配置好的 `openclaw.json` 中挑 primary model。判断顺序是：

```
1. 读你的 ~/.openclaw/openclaw.json，拿到 agents.defaults.models 下所有 provider/model
2. 优先看模型条目声明的 capabilities / tags / features / modalities
3. 能力字段命中 roleplay，就按用户已配置模型顺序选择；多个命中时交互让你选
4. 没有能力字段或字段不明确时，再参考 config/model-map.yaml 的 preferred 顺序
5. roleplay 没命中会退到 general；general 允许任意已配置文本模型兜底
6. 只有 openclaw.json 里完全没有模型时才报错
```

所以 `config/model-map.yaml` 不是固定支持列表，只是旧配置没有能力字段时的
偏好排序。新 provider 如果在模型条目里声明了能力，不需要先改表也能被识别。

## 推荐模型（按 nako 角色扮演的契合度）

| 模型 | 提供商 | 评价 |
|---|---|---|
| `sensenova/SenseChat-Character-Agt` | 商汤日日新 | **最佳** — 角色一致性强，中文口语化，情感拿捏到位 |
| `zhipu/glm-4-plus` | 智谱 | 次优 — 综合好，角色稍淡 |
| `zai/glm-5` | Z.ai | 可用 — 综合模型，角色 flavor 弱 |
| `anthropic/claude-sonnet-4` | Anthropic | 可用 — 英文强，中文角色一般 |
| `openai/gpt-4o` | OpenAI | 可用 — 视觉强，角色需大量 prompt |

## 查当前已配模型

```bash
bash nako/scripts/detect-models.sh
```

输出：

```
sensenova/SenseChat-Character-Agt    
zai/glm-4.7                           
zai/glm-5                    GLM
zai/glm-4.7                 * (primary)
```

`*` 表示当前 `agents.defaults.model.primary`。

## 手动切换 agent 的主模型

编辑 `~/.openclaw/openclaw.json`，找到 `agents.list` 里你的 agent：

```json
{
  "id": "agent-nako",
  "model": { "primary": "sensenova/SenseChat-Character-Agt" }
}
```

改完重启 gateway。

或重跑 `install.sh` 让它重新交互选。

## 加新模型到 openclaw

先在 `openclaw.json` 的 `agents.defaults.models` 下加：

```json
"agents": {
  "defaults": {
    "models": {
      "sensenova/SenseChat-Character-Agt": {}
    }
  }
}
```

再到 `agents.defaults` 补 provider 定义（走 `openclaw setup` 交互式添加最省事），或去 `~/.openclaw/agents/<id>/agent/models.json` 和 `auth-profiles.json` 加 API key。

详见 openclaw 官方文档的 provider 设置。

## 给模型声明能力

推荐在 `openclaw.json` 的模型条目里声明能力，例如：

```json
"agents": {
  "defaults": {
    "models": {
      "your_provider/your_model": {
        "capabilities": ["roleplay", "text"]
      }
    }
  }
}
```

安装器会读取这些字段：`capabilities`、`capability`、`tags`、`features`、
`modalities`、`inputModalities`、`input_modalities`。

当前能力含义：

| 能力 | 要求 |
|---|---|
| `roleplay` | 中文对话稳定、角色一致、能跟随工具和人设指令 |
| `general` | 日常对话、总结、代码/配置分析、基础工具意图理解 |
| `vision` | 能直接理解图片输入；只影响 vision skill |

## 调整 model-map.yaml 偏好

如果模型本身没有能力字段，但你想让安装器优先选择它，可以编辑
`config/model-map.yaml`：

```yaml
capabilities:
  roleplay:
    preferred:
      - sensenova/SenseChat-Character-Agt
      - your_provider/your_model      # ← 加到偏好顺序
      - zhipu/glm-4-plus
```

往 preferred 列表靠前加 = 无能力字段时优先级高。

## 不同 skill 对模型的要求

| Skill | 模型需求 | 不满足时 |
|---|---|---|
| voice / sing | 无（跟 LLM 无关） | — |
| hearing | 无（本地 whisper） | — |
| vision | primary 必须多模态 | 路径能拿到，但 agent 无法理解图像内容 |
| selfie | 无 | — |
| dokidoki | 无 | — |

若 primary 不多模态、你又想 agent 看图，换个多模态 primary，或者在 `custom.md` 里说明「遇到图片时只报告路径，不做解读」。

## 上下文窗口

角色扮演类 agent 对话往往很长。推荐 primary 至少 128K 上下文。nako 默认 `sensenova/SenseChat-Character-Agt` 是 198K。

如果用小上下文模型（< 32K），必要时调 openclaw 的 compaction：

```json
"agents": {
  "defaults": {
    "compaction": {
      "mode": "safeguard",
      "reserveTokensFloor": 30000
    }
  }
}
```
