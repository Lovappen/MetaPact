#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/media-path-resolution.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

runtime="$TMP_DIR/runtime home"
mkdir -p "$runtime/logs" "$runtime/media/inbound" "$TMP_DIR/bin"

image_path="$runtime/media/inbound/image with spaces.jpg"
audio_path="$runtime/media/inbound/audio with spaces.mp3"
: > "$image_path"
: > "$audio_path"

cat > "$runtime/logs/gateway.log" <<LOG
time=2026-05-14 level=INFO msg="message received" image_key=img-key-1
time=2026-05-14 level=INFO msg="downloaded image media, saved to $image_path"
time=2026-05-14 level=INFO msg="message received" file_key=aud-key-1
time=2026-05-14 level=INFO msg="downloaded audio media, saved to $audio_path"
LOG

resolved_image="$(
  NAKO_RUNTIME_HOME="$runtime" \
  bash "$ROOT/nako/skills/vision/scripts/resolve.sh" img-key-1
)"
test "$resolved_image" = "$image_path"

cat > "$TMP_DIR/bin/whisper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
audio="$1"
outdir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output_dir)
      shift
      outdir="$1"
      ;;
  esac
  shift || true
done
[ -n "$outdir" ] || exit 9
mkdir -p "$outdir"
base="$(basename "$audio")"
printf 'transcribed %s\n' "$audio" > "$outdir/${base%.*}.txt"
SH
chmod +x "$TMP_DIR/bin/whisper"

transcript="$(
  NAKO_RUNTIME_HOME="$runtime" \
  SKILL_LOG_FILE="$TMP_DIR/skill.jsonl" \
  WHISPER_BIN="$TMP_DIR/bin/whisper" \
  bash "$ROOT/nako/skills/hearing/scripts/stt.sh" aud-key-1
)"
test "$transcript" = "transcribed $audio_path"

echo "media path resolution checks passed"
