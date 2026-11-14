#!/bin/bash
# test-update.sh — 자체 업데이트를 끝까지 시험한다 (실제 GitHub·설치된 앱은 건드리지 않음)
#   임시 폴더에 옛 버전(0.0.1) 앱을 두고, 이 Mac 안에서만 도는 가짜 릴리스 서버(9.9.9)를 띄운 뒤
#   KKOK_UPDATE_AUTOINSTALL 모드로 확인 → 받기 → SHA-256·번들 ID·버전·서명 검증 → 교체까지 돌린다.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
T="$(mktemp -d)"
PORT=$((20000 + RANDOM % 20000))
cleanup() { [[ -n "${SRV:-}" ]] && kill "$SRV" 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT

echo "▶ 새 버전(9.9.9)과 옛 버전(0.0.1) 빌드"
mkdir -p "$T/rel" "$T/install"
scripts/build-app.sh --version 9.9.9 >/dev/null
ditto -c -k --keepParent dist/Kkok.app "$T/rel/Kkok-9.9.9.zip"
scripts/build-app.sh --version 0.0.1 >/dev/null
ditto dist/Kkok.app "$T/install/Kkok.app"
SHA="$(shasum -a 256 "$T/rel/Kkok-9.9.9.zip" | cut -d' ' -f1)"
cat > "$T/rel/latest.json" <<JSON
{"tag_name":"v9.9.9","html_url":"http://127.0.0.1:$PORT/","body":"test",
 "assets":[{"name":"Kkok-9.9.9.zip","browser_download_url":"http://127.0.0.1:$PORT/Kkok-9.9.9.zip","digest":"sha256:$SHA"}]}
JSON

echo "▶ 가짜 릴리스 서버 127.0.0.1:$PORT"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$T/rel" >/dev/null 2>&1 &
SRV=$!
sleep 1

echo "▶ 옛 버전 실행 → 자동 업데이트"
KKOK_UPDATE_API="http://127.0.0.1:$PORT/latest.json" KKOK_UPDATE_AUTOINSTALL=1 KKOK_UPDATE_RESULT="$T/result.json" \
  "$T/install/Kkok.app/Contents/MacOS/Kkok" >/dev/null 2>&1 &
APP=$!
for _ in $(seq 1 60); do sleep 0.5; kill -0 "$APP" 2>/dev/null || break; done
kill -0 "$APP" 2>/dev/null && { kill "$APP"; echo "✘ 앱이 30초 안에 끝나지 않음"; exit 1; }
for _ in $(seq 1 40); do [[ -f "$T/result.json" ]] && break; sleep 0.25; done

V="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$T/install/Kkok.app/Contents/Info.plist")"
echo "  결과 파일: $(cat "$T/result.json" 2>/dev/null || echo 없음)"
echo "  설치된 버전: $V"
codesign --verify --strict "$T/install/Kkok.app" && echo "  서명 정상"
[[ "$V" == "9.9.9" ]] && grep -q '"ok":true' "$T/result.json" && echo "✔ 업데이트 성공" || { echo "✘ 업데이트 실패"; exit 1; }

echo "▶ 손상된 파일은 거부하는지 (SHA-256 불일치)"
ditto dist/Kkok.app "$T/install2/Kkok.app"
sed -i '' "s/$SHA/$(printf '0%.0s' {1..64})/" "$T/rel/latest.json"
set +e
KKOK_UPDATE_API="http://127.0.0.1:$PORT/latest.json" KKOK_UPDATE_AUTOINSTALL=1 KKOK_UPDATE_RESULT="$T/result2.json" \
  "$T/install2/Kkok.app/Contents/MacOS/Kkok" >/dev/null 2>&1
CODE=$?
set -e
V2="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$T/install2/Kkok.app/Contents/Info.plist")"
[[ "$CODE" == 2 && "$V2" == "0.0.1" ]] && echo "✔ 손상된 파일 거부, 기존 앱 유지" || { echo "✘ 거부 시험 실패 (종료 코드 $CODE, 버전 $V2)"; exit 1; }
