#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/.qclaw/skills"
cat > "$tmp/.qclaw/skills/skill-log.sh" <<'EOF'
: "${SKILL_LOG_MARKER:?}"
printf 'sourced\n' >> "$SKILL_LOG_MARKER"
skill_log_start() { :; }
skill_log_ok() { :; }
skill_log_fail() { :; }
EOF

scripts=(
  "selfie/scripts/selfie.sh"
  "selfie/scripts/video.sh"
  "voice/scripts/voice.sh"
  "voice/scripts/sing.sh"
  "hearing/scripts/stt.sh"
)

for rel in "${scripts[@]}"; do
  mkdir -p "$tmp/.qclaw/skills/$(dirname "$rel")"
  cp "$ROOT/nako/skills/$rel" "$tmp/.qclaw/skills/$rel"
done

for rel in "${scripts[@]}"; do
  marker="$tmp/${rel//\//_}.marker"
  : > "$marker"
  env -i HOME="$tmp" PATH="${PATH:-/usr/bin:/bin}" SKILL_LOG_MARKER="$marker" \
    bash "$tmp/.qclaw/skills/$rel" >/dev/null 2>&1 || true
  grep -Fq 'sourced' "$marker"
done

echo "skill-log path checks passed"
