#!/bin/bash
# make-images.sh — README·가이드 이미지(docs/images)를 다시 만든다. 실제 캡처는 쓰지 않고 가상의 화면만 쓴다.
#   사용법: scripts/docs/make-images.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OUT="$ROOT/docs/images"
swift build -c release >/dev/null
swift scripts/docs/demo-base.swift "$TMP/base.png"

run() {  # 점검 모드는 PNG를 쓰고 스스로 끝난다. 15초 안에 안 끝나면 멈춘다.
  env KKOK_FONTS_DIR="$ROOT/Resources/Fonts" KKOK_ICON_PATH="$ROOT/Resources/AppIcon.icns" "$@" .build/release/Kkok &
  local pid=$!
  for _ in $(seq 1 30); do sleep 0.5; kill -0 "$pid" 2>/dev/null || break; done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
run KKOK_SNAPSHOT_DEMO=1 KKOK_SNAPSHOT_IN="$TMP/base.png" KKOK_SNAPSHOT_OUT="$OUT/editor.png"
run KKOK_SNAPSHOT_IN="$TMP/base.png" KKOK_SNAPSHOT_HOME_OUT="$OUT/home.png"
run KKOK_SNAPSHOT_CURSORS_OUT="$OUT/cursors.png"
run KKOK_SNAPSHOT_DEMO=1 KKOK_SNAPSHOT_SELECT_ROTATED=1 KKOK_SNAPSHOT_IN="$TMP/base.png" KKOK_SNAPSHOT_OUT="$TMP/rotate.png"
sips -c 520 760 --cropOffset 820 180 "$TMP/rotate.png" --out "$OUT/rotate.png" >/dev/null
# 하위 막대 4가지 (왼쪽 부분만)
for t in shape stamp text color; do
  run KKOK_SNAPSHOT_DEMO=1 KKOK_SNAPSHOT_TOOL=$t KKOK_SNAPSHOT_IN="$TMP/base.png" KKOK_SNAPSHOT_OUT="$TMP/sub-$t.png"
done
swift scripts/docs/combine.swift "$OUT/subpanel.png" 300 1180 "$TMP"/sub-shape.png "$TMP"/sub-stamp.png "$TMP"/sub-text.png "$TMP"/sub-color.png
echo "✔ $OUT"
