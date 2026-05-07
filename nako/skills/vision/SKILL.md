---
name: vision
description: Resolve Feishu image_key to a local file path so the agent can Read the image natively
allowed-tools: Bash(*/resolve.sh:*) Bash(ls:*) Read
---

# Vision — 看懂图片

用户发图片时，消息体里出现 `{"image_key":"img_v3_..."}`。当前消息 runtime 会自动把图片下到本地入站媒体目录；Hermes 默认是 `~/.hermes/media/inbound/`，OpenClaw 默认是 `~/.openclaw/media/inbound/`。本技能把 image_key 反查到本地路径，之后你用 `Read` 工具直接读图（Claude 原生视觉）。

## 何时用

- 消息里出现 `image_key`
- 占位符 `<media:image>` 或 `[Image]`
- 用户问「这张图是什么」「看看这个」「分析一下图片」
- 也适用 `file_key`（图片以文件形式发送）

## 用法

```bash
# 1) image_key → 本地路径
bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/vision/scripts/resolve.sh" img_v3_0210u_xxx
# → /root/.hermes/media/inbound/d526ab00-xxx.jpg

# 2) 拿不到 key 时的回退：取最近一张图
bash "${NAKO_SKILLS_DIR:-$HOME/.openclaw/skills}/vision/scripts/resolve.sh" --latest

# 3) 之后用 Read 读文件
# Read tool 直接传上面输出的绝对路径即可
```

## 退出码

| code | 含义 |
|---|---|
| 0 | 成功，stdout 是绝对路径 |
| 2 | 日志里找不到 key（太老被截断，或下载还没完成） |
| 3 | 路径存在但文件已被清理 |

## 注意

- 不要自己去猜 inbound 目录里哪个文件 — 用本脚本
- 图片找不到就直接告诉用户「图片已过期或下载中」，别瞎编内容
