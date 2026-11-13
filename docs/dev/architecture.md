# Kkok v0.1 아키텍처

- 작성: 2026-11-13 · 역할: 개발
- 네이티브 Swift + AppKit, SwiftPM 실행 대상 하나 + 테스트 대상(`swift test`)

## 1. 폴더
| 폴더 | 내용 | 주요 FR |
|---|---|---|
| `Sources/Kkok/Model` | AppKit 없이 테스트 가능한 핵심. `Annotation`(주석 값), `DocumentState`(실행 취소 단위: 캔버스 범위+주석), `Geometry`(화살표 모양·범위·클릭 판정·손잡이·⇧ 고정), `Renderer`(그리기·평탄화·PNG), `HistoryStore`(보관함) | FR-10~18, 33·34 |
| `Sources/Kkok/Capture` | `ScreenCapturer`(ScreenCaptureKit), `SelectionOverlay`(영역·창 선택 오버레이, 카운트다운), `CaptureController`(방식별 흐름·권한) | FR-01~08, 43 |
| `Sources/Kkok/Canvas` | `EditorDocument`(상태·실행 취소·자동 저장), `CanvasView`(마우스·키보드·글자 편집), `EditorWindowController`(창 구성) | FR-10~22, 31·32 |
| `Sources/Kkok/Tools` | `ToolState`(현재 도구·색·굵기, 저장), `ToolPaletteView`(왼쪽 막대) | FR-19·20·22 |
| `Sources/Kkok/Export` | `DragTabView`(끌기 탭) | FR-30 |
| `Sources/Kkok/Settings` | `Preferences`(UserDefaults), 설정 창·단축키 입력 | FR-41·42 |
| `Sources/Kkok/App` | 진입점, `AppDelegate`(메뉴 막대·앱 메뉴·문서 열기), `HotKeyCenter`(Carbon 전역 단축키) | FR-07, 40~42 |

## 2. 좌표계
- 모든 주석은 **원본 이미지 픽셀, 왼쪽 위 원점(y 아래)** 좌표로 저장한다.
- `DocumentState.canvasRect`가 내보낼 범위다. 자르기는 줄이고(원본 유지), 넓히기는 이미지 밖으로 늘린다(흰 배경).
- 화면 표시: `k = zoom / scale`(화면 pt / 이미지 px). 100%면 Retina 캡처가 원래 크기로 보인다.
- 굵기는 이미지 px × `scale`이라 Retina 캡처와 일반 이미지에서 화면상 굵기가 같다.

## 3. 그리기
`Renderer.drawDocument`를 화면(`CanvasView.draw`)과 내보내기(`Renderer.flatten`)가 함께 쓴다. 그래서 보이는 것과 내보낸 PNG가 같다. 모자이크는 원본에서 잘라 작게 줄였다 보간 없이 키운다(원본 글자 복원 불가, 테스트 `testPixelateDestroysDetail`).

## 4. 실행 취소
`DocumentState`가 값 타입이라 한 동작 전 상태를 통째로 기록한다(`EditorDocument.commit(from:)`). 끄는 동안은 기록하지 않고 마우스를 놓을 때 한 번만 기록한다. 글자 입력 중의 실행 취소는 별도 UndoManager라 문서 기록과 섞이지 않는다.

## 5. 캡처 흐름
1. 단축키(Carbon) → `CaptureController.start(mode)` → 권한 확인
2. 영역: 모든 화면을 먼저 찍어(얼림) 오버레이에 보여 주고 고른 범위를 그 이미지에서 잘라 낸다 → 고르는 동안 화면이 바뀌어도 누른 순간이 찍힌다
3. 타이머·직전 영역: 고른 범위를 기억했다가 그때의 실제 화면을 찍어 자른다
4. 창: `CGWindowList`로 마우스 아래 창을 찾고 `SCContentFilter(desktopIndependentWindow:)`로 그림자 없이 찍는다
5. 결과 → `HistoryStore.create`(원본 저장) → 편집 창

## 6. 저장 위치
- `~/Library/Application Support/Kkok/history/<UUID>/` — `original.png`, `doc.json`(주석), `thumb.png`
- `~/Pictures/Kkok/<yyyy-MM-dd HH.mm.ss>.png` — 합친 결과(편집할 때마다 0.6초 뒤 갱신)

## 7. 빌드·설치
```
swift test                          # 모델 테스트
scripts/build-app.sh                # dist/Kkok.app
scripts/build-app.sh --install      # /Applications 설치 후 실행
scripts/generate-icons.sh           # 아이콘 다시 그리기
```
서명은 ad-hoc이지만 지정 요구 사항을 번들 ID로 고정해 재빌드해도 화면 기록 권한이 유지된다.

화면 점검: `KKOK_SNAPSHOT_IN=이미지 KKOK_SNAPSHOT_OUT=결과.png .build/release/Kkok` — 화면에 띄우지 않고 편집 창을 그려 PNG로 저장한다(사용자 작업 방해 없음).

## 8. 이후 추가 (2026-11-13, 사용자 피드백)
| 항목 | 위치 |
|---|---|
| 시작 창(FR-45): 직접 실행·아이콘 다시 누름 | `App/HomeWindowController.swift` |
| 글꼴 4개(OFL, 프로세스 안에서만 등록, FR-23) | `Model/FontRegistry.swift`, `Resources/Fonts`, `Resources/licenses` |
| 12색 격자 | `Tools/ToolPaletteView.swift` (`ColorGridView`) |
| 글자 회전·손잡이 커서(FR-24·25) | `Model/Geometry.swift`(textCorners·rotate·snapAngle), `Canvas/HandleCursor.swift` |
| 오버레이 종료 시 해제된 선택기 참조로 죽던 문제(BUG-14) | `Capture/SelectionOverlay.swift` (`weak owner`) |

화면 점검 모드(화면에 띄우지 않고 PNG로 저장): `KKOK_SNAPSHOT_IN/OUT`(편집 창), `KKOK_SNAPSHOT_HOME_OUT`(시작 창), `KKOK_SNAPSHOT_COLORS_OUT`(색 격자), `KKOK_SNAPSHOT_CURSORS_OUT`(커서). 번들 밖에서 실행할 때 글꼴은 `KKOK_FONTS_DIR=Resources/Fonts`, 아이콘은 `KKOK_ICON_PATH=Resources/AppIcon.icns`. README·가이드 이미지는 `KKOK_SNAPSHOT_DEMO=1`(가상의 "Team Board" 화면에 맞춘 주석, `KKOK_SNAPSHOT_SELECT_ROTATED=1`이면 회전 손잡이까지)로 만든다. 시작 창 점검은 실제 보관함 대신 임시 보관함을 쓴다.

## 9. 알려진 한계 (v0.1)
- 영역 선택은 한 화면 안에서만(화면 두 개에 걸친 영역 불가)
- 회전은 글자만(도형·스탬프 회전은 v0.2 후보). 돌린 글자를 고쳐 쓰는 동안은 입력 상자가 수평으로 보임
- 화살표 곡선 없음, 글자 배경 상자 없음
