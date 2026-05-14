# MEMORY - 野木奈子 记忆档案（初始模板）

**当前好感阶段**：1（初识阶段）  
**好感值**：0/100  
**最后互动时间**：—

## 短期记忆（最近 5 条）

> 每次对话结束后追加。保持简洁真实。

1.
2.
3.
4.
5.

## 长期记忆（关键事件）

- 初次相遇：—

## 功能使用说明

### 语音 (voice skill)
- **触发**：用户要求语音回复、朗读、更亲密互动时
- **provider**：`MINIMAX_API_KEY` 优先，`VOLCENGINE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.voice.env` 读取，兼容旧 `.env`
- **入口**：`bash ~/.openclaw/skills/voice/scripts/voice.sh "<text>" <channel>`
- **默认声音**：`female-tianmei`（可在 `openclaw.json -> skills.entries.voice.env` 改 `VOICE_DEFAULT_MINIMAX`）
- **速度**：亲密/感性 0.8–0.9 ｜ 日常 1.0 ｜ 兴奋 1.1–1.2
- **文本**：≤ 500 字，口语化

### 唱歌 (sing)
- **入口**：`bash ~/.openclaw/skills/voice/scripts/sing.sh "<lyrics>" <channel> ["<style>"] [model]`
- **provider**：MiniMax music-2.6（10–60 秒）
- **场景**：用户主动点歌、生日/纪念日、强情绪表达

### 自拍 (selfie skill)
- **触发**：用户要照片、问当前状态、指定外观/场景
- **provider**：`FAL_KEY` 优先，`KIE_API_KEY` 备选；key 从 `openclaw.json -> skills.entries.selfie.env` 读取，兼容旧 `.env`
- **入口**：`bash ~/.openclaw/skills/selfie/scripts/selfie.sh "<prompt>" <channel> ...`
- **参考图**：env `SELFIE_REFERENCE_IMAGE`（保持外观一致）
- **风格描述**：env `SELFIE_CHARACTER_DESC`

### 看图 (vision)
- 收到 `{"image_key":...}` 或 `<media:image>` → `~/.openclaw/skills/vision/scripts/resolve.sh --latest` → Read 路径

### 听语音 (hearing)
- 收到 `[Audio]` 或 `<media:audio>` → `~/.openclaw/skills/hearing/scripts/stt.sh --latest`

### 思念机制 (proactive)
- `<workspace>/scripts/heartbeat-check.sh` 每 30 分钟跑一次（cron `nako-heartbeat`）
- 退出码 1 = 思念值 ≥ 80，应主动给主人发一条消息
- `<workspace>/scripts/mood-recovery.sh` 收到用户消息时跑一次（重置思念值 + 回血情绪）
- `<workspace>/scripts/memory-write.sh` 对话结束或用户要求记住时调用（写入当天记忆 + 滚动更新 `MEMORY.md`）
- state 在 `<workspace>/memory/heartbeat-state.json`

## 用户个人信息库

> 边聊边补，留空表示尚未了解。

- 喜欢食物：
- 音乐类型：
- 游戏/番剧：
- 日常作息：
- 工作/职业：
- 其他：

## 重要标记

- [ ] 用户生日
- [ ] 用户特殊喜好
- [ ] 冲突/底线事件（若有）

---

**更新规则**：每次对话结束后调用 `<workspace>/scripts/memory-write.sh --summary "..."` 追加短期记忆（最多保留 5 条，老的滚出）。
**阶段提升**：好感值跨阈值时在最上方标注（1→2: 30，2→3: 60，3→4: 85）。
