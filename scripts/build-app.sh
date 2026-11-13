#!/bin/bash
# build-app.sh — SwiftPM 릴리스 빌드 후 Kkok.app 번들을 조립하고 서명한다. (SageBar 스크립트에서 가져옴)
#   사용법: scripts/build-app.sh [--version 0.1.0] [--universal] [--install]
#   --install: /Applications/Kkok.app 으로 복사하고 다시 실행한다.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${KKOK_VERSION:-0.1.0}"
UNIVERSAL=0
INSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --universal) UNIVERSAL=1; shift ;;
    --install) INSTALL=1; shift ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 2 ;;
  esac
done
BUILD_NUM="$(date +%Y%m%d%H%M)"

echo "▶ swift build (release, version $VERSION)"
if [[ "$UNIVERSAL" -eq 1 ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Kkok"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/Kkok"
fi

APP="$ROOT/dist/Kkok.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kkok"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUM/" scripts/Info.plist > "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
[[ -f Resources/AppIcon.icns ]] || scripts/generate-icons.sh
cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"

# ad-hoc 서명이지만 "지정 요구 사항"을 번들 ID로 고정한다.
# 그래야 다시 빌드해도 화면 기록 권한(TCC)이 풀리지 않는다.
echo "▶ codesign (ad-hoc, 고정 요구 사항)"
codesign --force --sign - --timestamp=none \
  -r='designated => identifier "io.github.reentakim.kkok"' "$APP"
codesign --verify --strict "$APP" && echo "✔ $APP"

if [[ "$INSTALL" -eq 1 ]]; then
  echo "▶ /Applications 에 설치"
  # 정상 종료(편집 중인 내용 저장) → 안 되면 강제 종료
  if pgrep -x Kkok >/dev/null; then
    osascript -e 'tell application id "io.github.reentakim.kkok" to quit' 2>/dev/null || true
    for _ in 1 2 3 4 5 6; do pgrep -x Kkok >/dev/null || break; sleep 0.5; done
    pkill -x Kkok 2>/dev/null || true
    sleep 0.3
  fi
  rm -rf /Applications/Kkok.app
  cp -R "$APP" /Applications/Kkok.app
  open /Applications/Kkok.app
  echo "✔ /Applications/Kkok.app 실행"
fi
