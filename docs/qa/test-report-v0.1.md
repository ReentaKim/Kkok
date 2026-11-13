# Kkok v0.1 테스트 보고서

- 작성: 2026-11-13 · 역할: QA(독립, 코드를 쓰지 않은 사람)
- 대상: `Sources/Kkok/**` 현재 작업본, [테스트 계획](test-plan-v0.1.md)
- 범위 제한: 사용자가 Mac을 쓰는 중이라 GUI 조작·앱 실행·화면 캡처는 하지 않았다. 캡처·전역 단축키·끌어 놓기·IME는 "사용자 확인 필요"로 남겼다.

## 1. 요약

| 항목 | 결과 |
|---|---|
| `swift build`, `swift build -c release` | 성공 |
| `swift test` | 12개 중 11개 통과, 1개 건너뜀(`RenderSampleTests`, 환경 변수 있을 때만 실행 → 따로 실행해 견본 PNG 확인) |
| QA 추가 테스트(임시 복사본, 저장소에 넣지 않음) | 4개 중 3개 통과, 1개 실패(BUG-04 재현) |
| 점검 모드 화면(1배·2배 이미지) | 2배(작은) 이미지에서 왼쪽 막대 잘림·툴바 버튼 숨음 확인(BUG-01·02) |
| 결함 | 13건: 높음 1, 중간 7(그중 추정 3), 낮음 5 |

판정: **핵심 흐름(캡처→주석→끌기)은 코드상 성립하지만, 작은 캡처에서 색·굵기 조절이 보이지 않는 BUG-01은 v0.1 사용 전에 고쳐야 한다.** 중간 결함(BUG-02~05)도 함께 고치는 것을 권한다.

## 2. 실행한 것

1. `swift test` — ModelTests 11개 통과(자르기, 넓히기, ⇧ 고정, 클릭 판정, 모서리 손잡이, 모자이크, 넓힘+자름 합치기, 모든 종류 그리기, 보관함 저장·불러오기·같은 초 이름, JSON 왕복).
2. `KKOK_SAMPLE_OUT=… swift test --filter RenderSampleTests` — 모든 주석 견본 PNG를 그려 눈으로 확인: 화살표 굵어짐·흰 외곽선, 글자 외곽선, 도형, 형광펜, 펜, 스탬프 6종 정상.
3. 점검 모드 `KKOK_SNAPSHOT_IN/OUT .build/release/Kkok`
   - 900×600 이미지(72dpi, 배율 1): 편집 창 정상, 툴바·왼쪽 막대·아래 탭 모두 보임.
   - 같은 이미지를 144dpi(배율 2, 화면상 450×300pt)로: 창이 최소 크기 근처(약 586×488pt)로 열리며 **왼쪽 막대가 자르기 버튼 중간에서 잘려 색 원·굵기 점이 보이지 않고**, **툴바의 "복사·저장" 버튼이 넘침(»)으로 숨는다.**
4. QA 추가 테스트(임시 복사본 `QAExtraTests.swift`(임시 복사본, 저장소에 넣지 않음))
   - `testUndoRedo` 통과: 그리기→자르기→넓히기를 ⌘Z 3번, ⇧⌘Z 3번으로 정확히 왕복.
   - `testHighlighterSelfOverlap` 통과: 한 획 안 겹친 곳과 한 겹인 곳의 색이 같다.
   - `testTextBaselineMatch`: 48px 글자에서 편집 중 NSTextView 기준선 49.0px, 그린 결과 기준선 43.2px → 약 5.8px(글자 크기의 12%) 차이(BUG-06).
   - `testColorChangeLeaksAcrossWindows` **실패**: 창 A에서 색을 바꾸자 창 B에서 선택돼 있던 주석 색이 바뀜(BUG-04).

## 3. FR별 결과

| FR | 결과 | 근거·비고 |
|---|---|---|
| FR-01 영역 캡처 | 사용자 확인 필요 | 코드상 모든 화면을 먼저 찍고(얼림) 화면별 오버레이·십자선·크기 표시·Esc 취소 구현. 다른 앱 사용 중 Esc가 먹는지(앱 활성화)는 수동 확인 M-01 |
| FR-02 영역 다듬기 | 사용자 확인 필요 | ⌥ 놓기 → 손잡이·이동·"캡처"·"N초 후"·Enter 구현 확인 |
| FR-03 직전 영역 | 사용자 확인 필요 | 화면 ID + 화면 안 pt 좌표 저장, 화면이 없으면 영역 선택으로 대체. 논리 이상 없음 |
| FR-04 창 캡처 | 사용자 확인 필요 | CGWindowList 강조 + `desktopIndependentWindow` + `ignoreShadowsSingleWindow`. 좌표 변환(주 화면 높이 기준) 맞음 |
| FR-05 전체 화면 | 사용자 확인 필요 | 마우스 아래 화면을 `backingScaleFactor` 해상도로 캡처 |
| FR-06 타이머 | 사용자 확인 필요 | 카운트다운·테두리 창은 Kkok 앱 제외 필터로 결과에 안 찍힘. 설정 1~15초 반영 |
| FR-07 다른 경로로 열기 | 사용자 확인 필요 | ⌘O·⌘N·⌘⇧V·캔버스 끌어 놓기·Dock 놓기(Info.plist 문서 형식 있음) 구현. 단 평소 LSUIElement라 Dock 놓기는 편집 창이 열려 있을 때만 가능 |
| FR-08 픽셀 정확도 | 통과(코드) + 사용자 확인 필요 | 화면별 배율로 찍고 pt 범위를 정수로 맞춘 뒤 ×배율로 자름 → 경계 어긋남 없음. 여러 모니터 좌표 변환 맞음. 실제 모니터 조합은 M-08 |
| FR-10 화살표 | 통과 | 견본·점검 모드에서 모양·외곽선 확인. 손잡이·⇧ 45°는 코드 확인 |
| FR-11 글자 | 결함 | BUG-06(편집 끝낼 때 글자 위치가 튐), BUG-05(입력 중 종료 시 유실). 한글 IME 조합 중 바깥 클릭은 M-11로 확인 필요 |
| FR-12 도형 | 통과 | 테스트 + 코드. 둥근 사각 반경이 명세(굵기×2)와 달리 선 두께×2.4(참고 4장) |
| FR-13 펜 | 통과 | 중점 이차 곡선 보정 |
| FR-14 형광펜 | 통과 | QA 테스트로 한 획 겹침 불변 확인 |
| FR-15 모자이크 | 통과 | `testPixelateDestroysDetail` |
| FR-16 스탬프 | 통과 | 6종·자동 번호·크기 손잡이. ★ 색이 #FFCC00(명세 팔레트 노랑 #FFD60A와 다름, 참고) |
| FR-17 자르기 | 통과 | 테스트 + QA 실행 취소 테스트 |
| FR-18 캔버스 넓히기 | 통과(경미한 결함 있음) | BUG-12 |
| FR-19 선택·편집 | 결함 | BUG-04 |
| FR-20 색과 굵기 | 결함 | BUG-01(작은 캡처에서 색·굵기 조절이 안 보임). 기억(UserDefaults)은 코드상 정상 |
| FR-21 실행 취소 | 통과(경미한 결함 있음) | 모든 편집 경로가 `commit/apply`로 기록됨. BUG-07 |
| FR-22 단축키 도구 전환 | 결함 | BUG-03(O·L 없음), BUG-08(추정, 한국어 입력 상태) |
| FR-30 끌기 탭 | 사용자 확인 필요 | 끌 때 임시 PNG 파일 URL + PNG 데이터를 함께 넘김. 앱별 수용은 M-30 |
| FR-31 복사 | 통과(코드) + 사용자 확인 필요 | PNG + TIFF로 클립보드에 씀. 선택이 있어도 이미지를 복사(PRD 조건과 충돌하지 않음) |
| FR-32 저장 | 결함 | BUG-02(작은 창에서 저장 버튼 숨음, ⌘S는 동작). 저장 실패 시 알림 없음(참고) |
| FR-33 자동 보관 | 결함 | 경로·이름 충돌 처리는 테스트 통과. BUG-05(종료 직전 편집 유실) |
| FR-34 다시 편집 | 통과(자동) + 사용자 확인 필요 | 불러온 주석이 그대로 편집 가능한 상태 |
| FR-40 메뉴 막대 | 사용자 확인 필요 | 메뉴 항목 모두 구현 |
| FR-41 로그인 시 실행 | 사용자 확인 필요 | SMAppService. ad-hoc 서명이라 "승인 필요" 상태가 될 수 있어 실제 확인 필요 |
| FR-42 단축키 설정 | 결함(추정) | BUG-09, BUG-10 |
| FR-43 권한 안내 | 사용자 확인 필요 | 이유 + "시스템 설정 열기" 구현. 시스템 권한 창과 Kkok 안내가 동시에 뜰 수 있음(참고) |
| FR-44 캡처 후 동작 | 결함 | BUG-11 |

## 4. 결함 목록

### BUG-01 작은 캡처에서 왼쪽 도구 막대가 잘려 색·굵기 조절이 보이지 않음 — 높음
- 위치: `Sources/Kkok/Tools/ToolPaletteView.swift:15-44`(고정 y 배치, 필요 높이 약 542pt), `Sources/Kkok/Canvas/EditorWindowController.swift:23`(최소 높이 420), `:193-206`(`sizeWindowToFit`)
- 재현 근거: 도구 9개(44pt씩)+구분선+색 원+굵기 점 3개를 위에서부터 고정 좌표로 놓아 막대 높이가 약 542pt 필요하다. 창 높이는 `max(420, 이미지 높이 + 188)`이므로 화면상 높이 약 460pt 미만인 캡처(가장 흔한 작은 영역 캡처)는 막대가 잘린다. 점검 모드(450×300pt 이미지)에서 자르기 버튼이 반쯤 잘리고 색 원·굵기 점이 보이지 않음을 확인. 색은 단축키가 없어 창을 키우지 않으면 바꿀 수 없다.
- 제안: 창 최소 높이를 막대 필요 높이(약 650pt 창 높이)로 올리거나, 막대를 `NSScrollView`/`NSStackView`로 바꾸고 높이가 모자라면 색·굵기를 위로 옮기거나 두 열로 접는다. 창 크기 계산에 막대 높이를 넣는다.

### BUG-02 작은 창에서 툴바의 "복사·저장" 버튼이 넘침(») 메뉴로 숨음 — 중간
- 위치: `Sources/Kkok/Canvas/EditorWindowController.swift:23`(최소 폭 560), `:60-62`(툴바 항목), `:201`
- 재현 근거: 점검 모드 2배 이미지(창 약 586pt 폭)에서 제목 + 캡처 묶음 + 복사 + 저장이 들어가지 않아 오른쪽 두 버튼이 »로 숨는 것을 확인. 디자인 명세 1장의 "오른쪽: 복사, 저장"이 작은 캡처에서 보이지 않는다(⌘C·⌘S는 동작).
- 제안: 최소 폭을 툴바 전체 폭 이상(약 760pt)으로 올리거나, 캡처 묶음을 글자 없이 아이콘만으로 줄이고 복사·저장을 우선 표시(`visibilityPriority = .high`)한다.

### BUG-03 단축키 O(타원)·L(선)이 없고 R은 "사각"이 아니라 마지막 도형으로 전환 — 중간
- 위치: `Sources/Kkok/Settings/Preferences.swift:84-96`(`Tool.shortcut`), `Sources/Kkok/Canvas/CanvasView.swift:556-558`
- 재현 근거: 도구 단축키는 v·a·t·r·p·h·b·s·c 9개뿐이다. PRD FR-22의 "O 타원, L 선"이 없고, R은 `.shape` 도구로만 바꿔 직전에 고른 도형(예: 타원)으로 그려진다.
- 제안: keyDown에서 r/o/l을 `tools.shape = .rect/.ellipse/.line; tools.tool = .shape`로 처리하고 도구 설명 문구도 갱신.

### BUG-04 색·굵기를 바꾸면 다른 편집 창에서 선택된 주석까지 바뀜 — 중간
- 위치: `Sources/Kkok/Canvas/CanvasView.swift:520-535`(`toolsChanged`), `Sources/Kkok/Tools/ToolState.swift:24`
- 재현 근거: `ToolState`는 모든 창이 함께 쓰고 변경 알림을 모든 CanvasView가 받는다. 각 창은 자기 선택이 있으면 색·굵기를 적용한다. 그리기 직후 주석은 자동 선택(`CanvasView.swift:397`)되므로, 창 B에서 그린 뒤 창 A에서 다음 색을 고르면 B의 주석 색도 바뀌고 B에 실행 취소 기록이 생긴다. QA 테스트 `testColorChangeLeaksAcrossWindows`로 재현(B 주석이 분홍→파랑).
- 제안: 변경을 일으킨 창에만 적용. 예: 알림 처리에서 `window?.isKeyWindow == true`(또는 팔레트가 속한 창)일 때만 선택에 적용하고, 다른 창은 `lastColor/lastSize`만 갱신.

### BUG-05 종료(⌘Q) 직전 편집·입력 중인 글자가 보관되지 않음 — 중간
- 위치: `Sources/Kkok/App/AppDelegate.swift`(종료 처리 없음, `applicationShouldTerminate/WillTerminate` 미구현), `Sources/Kkok/Canvas/EditorDocument.swift:67-72`, `Sources/Kkok/Canvas/CanvasView.swift:478-482`
- 재현 근거: 자동 저장은 0.6초 뒤 실행되고 저장 작업은 `[weak self]`다. 창을 닫을 때만 `windowWillClose`에서 `endTextEditing + saveNow`를 하는데, ⌘Q(메뉴 막대 "Kkok 종료" 포함)는 창을 닫지 않고 앱을 끝내므로 호출되지 않는다. 또 글자 입력 중의 변경은 `update`만 하고 저장 예약을 하지 않아, 입력 중 종료하면 그 글자는 doc.json·~/Pictures PNG 어디에도 남지 않는다.
- 제안: `applicationWillTerminate`(또는 `applicationShouldTerminate`)에서 열린 모든 편집 창에 대해 `canvas.endTextEditing(); doc.saveNow()`를 부른다.

### BUG-06 글자 편집을 끝내면 글자가 위로 약 12% 튐 — 낮음
- 위치: `Sources/Kkok/Canvas/CanvasView.swift:443-447`(편집용 NSTextView 줄 높이 고정), `Sources/Kkok/Model/Renderer.swift:159`(기준선 = p1.y + ascent)
- 재현 근거: 편집 중 NSTextView는 고정 줄 높이(ascent+descent+max(leading, 0.1×크기))의 남는 공간을 위에 두어 기준선이 아래로 내려간다. QA 측정(48px): 편집 중 49.0px, 그린 결과 43.2px. 입력을 끝내는 순간 글자가 위로 약 6px(화면 100% 기준) 움직인다.
- 제안: 편집 뷰 원점을 `(lm 기준선 − renderer ascent) × k`만큼 위로 올리거나, 문단 스타일 대신 `baselineOffset`으로 맞추고 같은 측정을 테스트로 고정.

### BUG-07 사용자 지정 색 패널에서 끄는 동안 실행 취소 기록이 수십 개 쌓임 — 낮음
- 위치: `Sources/Kkok/Tools/ToolPaletteView.swift:201-203`, `Sources/Kkok/Canvas/CanvasView.swift:525-533`
- 재현 근거: NSColorPanel은 색을 끄는 동안 액션을 계속 보낸다. 선택된 주석이 있으면 바뀔 때마다 `doc.apply("색 바꾸기")`가 기록되고(자동 저장도 매번 예약), ⌘Z를 여러 번 눌러야 원래 색으로 돌아간다.
- 제안: 색 패널 변경은 연속 변경 동안 하나의 묶음으로 기록(첫 변경 전 상태를 잡아 두고 일정 시간 뒤 또는 패널을 놓을 때 한 번 `commit`).

### BUG-08 (추정) 한국어 입력 소스일 때 도구 단축키가 듣지 않을 수 있음 — 중간
- 위치: `Sources/Kkok/Canvas/CanvasView.swift:556-558`
- 재현 근거: 도구 전환을 키 코드가 아니라 `charactersIgnoringModifiers`(입력 소스에 따라 'ㅁ', 'ㅅ' 등이 될 수 있음)로 비교한다. 사용자는 한국어 입력을 주로 쓰므로 영향이 크다. 실제 문자값은 GUI 확인 필요(M-22).
- 제안: `e.keyCode`(kVK_ANSI_A 등)로 비교한다. 숫자 1~3도 키 코드로.

### BUG-09 (추정) 단축키 입력 칸을 누른 채 설정 창을 닫으면 모든 캡처 단축키가 꺼진 채로 남을 수 있음 — 중간
- 위치: `Sources/Kkok/Settings/SettingsWindowController.swift:103`(기록 시작 시 `unregisterAll`), `:135-138`, `Sources/Kkok/App/AppDelegate.swift:25-27, 81`
- 재현 근거: 칸을 누르면 모든 전역 단축키를 해제하고, 다시 등록은 Esc·키 입력·`resignFirstResponder`에서만 한다. 창을 닫거나 다른 앱으로 전환할 때 `resignFirstResponder`가 불린다는 보장이 없다. 1분 재시도와 메뉴 열 때 재시도는 `failures`가 비어 있지 않을 때만 동작하는데 `unregisterAll`이 `failures`도 비우므로 복구되지 않는다. → 앱을 다시 켜기 전까지 단축키가 안 먹을 수 있다.
- 제안: 설정 창 `windowWillClose`와 `NSWindow.didResignKey`에서 기록 중이면 끝내고 다시 등록. 또는 기록 중에도 다른 단축키는 해제하지 않고 그 칸의 단축키만 잠시 해제.

### BUG-10 (추정) 다른 앱·시스템 단축키와 겹쳐도 "등록 실패" 안내가 나오지 않을 수 있음 — 중간
- 위치: `Sources/Kkok/App/HotKeyCenter.swift:29`
- 재현 근거: `RegisterEventHotKey`를 옵션 0(비독점)으로 부른다. 이 API는 다른 앱이 비독점으로 잡은 조합이나 macOS 스크린샷(⇧⌘5) 같은 시스템 단축키와 겹쳐도 대개 성공을 돌려주므로, 단축키가 실제로는 안 먹는데 FR-42의 "등록 실패하면 알린다"가 나오지 않을 수 있다. 반대로 Kkok 안에서 두 방식에 같은 조합을 넣으면 두 번째가 실패하는데, 안내는 "다른 앱이 쓰고 있어"라고 나와 원인이 틀린다.
- 제안: 설정 저장 시 Kkok 안의 중복을 먼저 막고, `CopySymbolicHotKeys()`로 시스템 단축키와의 충돌을 검사해 경고. 등록 결과 문구를 "등록하지 못함(다른 앱·시스템과 겹침 가능)"처럼 사실대로. M-42 3번으로 실제 동작 확인 필요.

### BUG-11 FR-44 "캡처 후 클립보드에도 복사" 설정이 없음 — 낮음
- 위치: `Sources/Kkok/Settings/SettingsWindowController.swift:21-76`(항목 없음), `Sources/Kkok/App/AppDelegate.swift:133-136`
- 재현 근거: PRD FR-44는 설정 선택지를 요구하지만, 결정 기록(2026-11-13 "캡처 후에는 편집 창만 연다(자동 복사 없음)")과 구현은 편집 창만 연다. 문서끼리 어긋난다.
- 제안: PM이 PRD를 결정 기록에 맞춰 고치거나(FR-44를 v0.2로), 설정 체크 하나를 추가해 `openCapture`에서 `doc.copyToPasteboard()` 호출.

### BUG-12 이미지 가장자리 띠가 손잡이·그리기 시작보다 먼저 클릭을 가로챔 — 낮음
- 위치: `Sources/Kkok/Canvas/CanvasView.swift:268-272`
- 재현 근거: `mouseDown`이 가장 먼저 가장자리 띠(캔버스 밖 22pt)를 검사한다. 화살표 끝을 이미지 밖까지 끌어 놓으면 그 손잡이가 띠 안에 있어, 손잡이를 잡으려는 클릭이 캔버스 넓히기가 된다. 이미지 가장자리에 놓인 손잡이의 바깥 절반도 같다.
- 제안: 선택 주석 손잡이 검사를 띠 검사보다 먼저 하고, 띠는 `drag == .none`이고 손잡이가 아닐 때만 처리.

### BUG-13 캡처 결과에서 Kkok 자신의 창(열린 편집 창 등)이 빠짐 — 낮음
- 위치: `Sources/Kkok/Capture/ScreenCapturer.swift:68-69`
- 재현 근거: 카운트다운 창을 빼려고 Kkok 앱 전체를 제외 필터에 넣었다. 그래서 편집 창이 떠 있는 상태로 영역·전체 화면을 찍으면 얼린 화면과 결과에서 편집 창 자리가 그 뒤의 화면으로 보인다(누른 순간 보이던 화면과 다름). 이전 캡처 결과 창을 찍어 다른 주석을 다는 흐름이 막힌다.
- 제안: 앱 전체 대신 카운트다운·테두리 창만 `excludingWindows`로 제외(`SCContentFilter(display:excludingWindows:)`).

## 5. 사용자 확인이 필요한 항목

FR-01, FR-02, FR-03, FR-04, FR-05, FR-06, FR-07, FR-08, FR-11(한글 IME), FR-22(한국어 입력 상태, BUG-08), FR-30, FR-31, FR-34, FR-40, FR-41, FR-42(BUG-09·10), FR-43, 비기능(0.3초·오프라인·3000×2000 성능). 절차는 [테스트 계획](test-plan-v0.1.md) 4장.

특히 먼저 볼 것:
1. M-01 4번: 다른 앱을 쓰던 중 ⇧⌘5 → Esc가 바로 먹는지. 앱 활성화가 실패하면 덮개가 키 입력을 못 받아 영역을 골라야만 빠져나올 수 있다.
2. M-NF: 영역 캡처는 화면마다 차례로 `SCShareableContent`를 받아 찍은 뒤에 덮개를 띄운다(`ScreenCapturer.captureAll`). 모니터 2~3대에서 0.3초를 넘을 수 있다.

## 6. 참고(결함은 아니지만 명세와 다른 점)

- 둥근 사각 모서리 반경: 명세 "굵기×2", 구현 선 두께×2.4(`Renderer.swift:83`).
- ★ 스탬프 색 #FFCC00, 명세 팔레트 노랑은 #FFD60A(`Annotation.swift:55`).
- 모자이크는 원본 이미지에서 다시 그리므로 먼저 그린 주석 위에 겹치면 그 주석을 지운다(순서 의존).
- 글자 입력 중 색·굵기를 바꿔도 입력 중인 글자에는 적용되지 않는다(끝낸 뒤 선택 상태에서 바꾸면 적용).
- 저장(⌘S) 실패 시 알림 없음(`EditorWindowController.swift:260`, `try?`). 투명 PNG를 JPEG로 저장하면 투명 부분이 검게 될 수 있다.
- 권한이 없을 때 시스템 권한 창(`CGRequestScreenCaptureAccess`)과 Kkok 안내 창이 함께 뜬다.
- 보관함은 지우지 않아 계속 쌓이고, 메뉴를 열 때마다 모든 doc.json을 읽는다. 오래 쓰면 메뉴가 느려질 수 있다.

## 7. QA 산출물 위치(저장소 밖)

- 추가 테스트: `QAExtraTests.swift (QA 임시 폴더, 저장소에 넣지 않음)`
- 점검 모드 그림: 같은 폴더 `qa/snap1.png`(배율 1), `qa/snap2.png`(배율 2, BUG-01·02), 견본 `qa/sample.png`

## 개발 조치 결과 (2026-11-13, 개발)

| ID | 조치 | 확인 |
|---|---|---|
| BUG-01 | 도구 버튼 36pt·간격 38로 줄이고, 창 최소 높이를 도구 막대 필요 높이에 맞춤 | 360×240@2x 화면 점검 PNG에서 색·굵기까지 모두 보임 |
| BUG-02 | 창 최소 너비 780 | 같은 점검에서 복사·저장이 넘침 메뉴로 안 숨음 |
| BUG-03 | R 사각형, O 타원, L 선을 바로 고름 | 코드 확인, 사용자 확인 필요 |
| BUG-04 | 주 창(isMainWindow)의 캔버스만 선택 주석 스타일을 바꿈 | 코드 확인 |
| BUG-05 | applicationWillTerminate에서 글자 편집 마치고 모든 문서 즉시 저장 | 코드 확인 |
| BUG-06 | 렌더러 기준선 = 줄 위 + 줄 높이 − descent (NSTextView와 같은 배치) | 테스트 통과, 사용자 확인 필요 |
| BUG-07 | 색 패널 isContinuous = false (놓을 때 한 번만 기록) | 코드 확인 |
| BUG-08 | 도구 단축키를 문자 대신 키 코드로 판정 → 한글 입력 상태에서도 동작 | 사용자 확인 필요 |
| BUG-09 | 설정 창을 닫거나 키 창에서 벗어나면 기록 종료 + 단축키 다시 등록 | 코드 확인 |
| BUG-10 | Kkok 안에서 같은 단축키를 지정하면 이전 방식의 단축키를 비움. 다른 앱과 겹친 경우는 실기 확인 필요 | 부분 조치 |
| BUG-11 | PRD FR-44를 결정 기록에 맞춰 "제외"로 정리 | 문서 |
| BUG-12 | 선택 주석 손잡이 판정을 가장자리 띠보다 먼저 | 코드 확인 |
| BUG-13 | 자기 앱 제외 필터 제거(카운트다운·오버레이는 찍기 전에 숨김) → 편집 창도 찍힘 | 사용자 확인 필요 |
