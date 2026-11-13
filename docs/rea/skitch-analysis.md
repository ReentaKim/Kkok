# Skitch 분석 (rea)

- 대상: `/Applications/Skitch.app` 2.9 (빌드 265153, Xcode 11.3, macOS 10.15 SDK)
- 방법: **읽기 전용.** Info.plist, 리소스 파일 이름, 영문 문자열 테이블, 앱 설정 파일(`defaults`)의 기본값만 봤다. 실행 파일을 디스어셈블하거나 리소스를 복사하지 않았다.
- 날짜: 2026-11-13

## 1. 왜 곧 못 쓰게 되나
- 실행 파일이 `Mach-O 64-bit executable x86_64` 하나뿐이다. Apple 실리콘에서는 Rosetta 2로만 돈다. Rosetta가 빠지면 실행되지 않는다.
- 프레임워크: EDAM(Evernote API), HockeySDK(종료된 서비스), Log4Cocoa. Evernote 계정 연동이 깊게 섞여 있다.

## 2. 구성
| 부분 | 역할 |
|---|---|
| Skitch.app | 문서(편집) 창, 메뉴 |
| LoginItems/SkitchHelper.app | 로그인 때 실행. 전역 단축키(`installHotKeys`)와 캡처 담당 |
| PlugIns/SkitchMacAction.appex, SkitchMacPhotoEditing.appex | Finder/사진 앱 확장 |

## 3. 캡처 기능 (Helper 심볼 이름에서)
- `crosshairSnapshot` 영역 캡처 — 선택 중 가로·세로 숫자 표시(`crosshairImageWithTopNumber:bottomNumber:`)
- `crosshairResizeController…AcceptCapture / AcceptTimedCapture` — 영역을 고른 뒤 **크기를 조절하고** 바로 찍거나 타이머로 찍을 수 있다
- `previousCrosshairSnapshot` — **직전 영역 다시 찍기**
- `fullscreenSnapshot`, `allScreenSnapshot`, `timedSnapshot`(카운트다운 이미지 1~15, 설정값 5초)
- Window 캡처, Camera(v0.1 제외)

## 4. 주석 도구 (커서·리소스 이름에서)
arrow, text, rect, rrect(둥근 사각), ellipse, line, marker(펜), highlighter, pixelate, stamp, crop/resize, expand canvas(가장자리 클릭으로 넓히기), move, rotate 핸들, 색 선택(사용자 지정 색 포함), 굵기.
스탬프 종류: accept(승인), reject(거절), question(물음표), alert(주의), perfect(완벽), 이모티콘 계열(Happy·Angry·Cool·Hehe 등 문자열).

## 5. 설정 파일에서 본 기본 동작
| 항목 | 값 | 해석 |
|---|---|---|
| dragMeExportFormat | public.png | 끌기 형식 PNG |
| lastCanvasTool | toolID 3 | 마지막 도구 기억 |
| 색 | RGB(0.988, 0.047, 0.349) ≈ `#FC0C59` | 기본 분홍 |
| 형광펜 빈 색 | `#FFF700` | 노랑 |
| 글꼴 | AppleSDGothicNeo-Bold 24pt | 한글 굵은 글꼴 |
| KeepHelperRunningInBackground / StartHelperAtLogin | 1 / 1 | 항상 대기 |

## 6. Kkok에 옮길 것 / 버릴 것
- **옮김**: 영역·직전 영역·창·전체·타이머 캡처, 위 주석 도구 전부, 끌기 탭, 마지막 도구·색 기억, 로그인 시 대기
- **버림**: Evernote 로그인·동기화·노트북·공유 URL·이메일 보내기, 프리미엄 안내, 별점 요청, 크래시 리포터, 카메라
- **다음 버전**: PDF 주석
