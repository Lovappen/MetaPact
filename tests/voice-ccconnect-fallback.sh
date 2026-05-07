#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for script in "$ROOT/nako/skills/voice/scripts/voice.sh" "$ROOT/nako/skills/voice/scripts/sing.sh"; do
  ! grep -Fq '_ccconnect_send_attachment_fallback' "$script"
  ! grep -Fq 'zipfile.ZipFile' "$script"
  ! grep -Fq '.mp3.zip' "$script"
  grep -Fq '_explain_ccconnect_audio_failure' "$script"
  grep -Fq '缺少 ffmpeg 或 AMR 编码器' "$script"
  grep -Fq 'MP3 文件已保留' "$script"
done

grep -Fq '需要语音/视频转码（ffmpeg）吗？现在安装' "$ROOT/install.sh"
grep -Fq 'brew install ffmpeg' "$ROOT/install.sh"
grep -Fq 'sudo apt-get install -y ffmpeg libavcodec-extra' "$ROOT/install.sh"
grep -Fq '需要语音/视频转码（ffmpeg）吗？现在安装' "$ROOT/install.ps1"

echo "voice cc-connect fallback checks passed"
