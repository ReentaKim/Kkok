import AppKit

/// 캡처 방식별 흐름을 묶는다. 결과 이미지는 `onCaptured`로 넘긴다.
final class CaptureController {
    static let shared = CaptureController()

    /// (이미지, 배율)
    var onCaptured: ((CGImage, CGFloat) -> Void)?

    private var busy = false
    private var region: RegionSelector?
    private var windowSelector: WindowSelector?
    private var countdown: CountdownWindow?

    func start(_ mode: CaptureMode) {
        guard !busy else { return }
        guard ensurePermission() else { return }
        busy = true
        // 메뉴 막대 메뉴가 닫힐 시간을 준다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            switch mode {
            case .area: selectArea(timed: false)
            case .timed: selectArea(timed: true)
            case .previousArea: previousArea()
            case .window: selectWindow()
            case .fullscreen: fullscreen()
            }
        }
    }

    // MARK: 권한 (FR-43)

    private func ensurePermission() -> Bool {
        if ScreenCapturer.hasPermission { return true }
        CGRequestScreenCaptureAccess()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요합니다"
        alert.informativeText = """
        Kkok이 화면을 찍으려면 시스템 설정 › 개인정보 보호 및 보안 › 화면 및 시스템 오디오 녹음에서 Kkok을 켜 주세요.
        켠 뒤에는 Kkok을 다시 실행해야 할 수 있습니다.
        """
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "나중에")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        return false
    }

    // MARK: 방식별

    private func selectArea(timed: Bool) {
        Task { @MainActor in
            do {
                let shots = try await ScreenCapturer.captureAll()
                let sel = RegionSelector()
                region = sel
                sel.begin(shots: shots) { [self] result in
                    region = nil
                    switch result {
                    case .cancelled:
                        busy = false
                    case let .selected(shot, rect, timedButton):
                        Preferences.shared.previousArea = (shot.screen.displayID, rect)
                        if timed || timedButton {
                            runTimed(screen: shot.screen, rect: rect)
                        } else if let img = shot.crop(rect) {
                            deliver(img, shot.scale)
                        } else {
                            busy = false
                        }
                    }
                }
            } catch {
                fail(error)
            }
        }
    }

    /// 카운트다운 뒤 그 영역을 지금 화면에서 찍는다 (메뉴·툴팁을 찍을 수 있게)
    private func runTimed(screen: NSScreen, rect: CGRect) {
        let cd = CountdownWindow(screen: screen, highlight: rect)
        countdown = cd
        cd.run(seconds: Preferences.shared.timerSeconds) { [self] in
            countdown = nil
            captureLive(screen: screen, rect: rect)
        }
    }

    private func previousArea() {
        guard let prev = Preferences.shared.previousArea, let screen = NSScreen.screen(displayID: prev.displayID) else {
            selectArea(timed: false)
            return
        }
        captureLive(screen: screen, rect: prev.rect)
    }

    private func captureLive(screen: NSScreen, rect: CGRect) {
        Task { @MainActor in
            do {
                let shot = try await ScreenCapturer.capture(screen: screen)
                if let img = shot.crop(rect) { deliver(img, shot.scale) } else { busy = false }
            } catch { fail(error) }
        }
    }

    private func selectWindow() {
        let ws = WindowSelector()
        windowSelector = ws
        ws.begin { [self] id in
            windowSelector = nil
            guard let id else { busy = false; return }
            Task { @MainActor in
                do {
                    let (img, scale) = try await ScreenCapturer.capture(windowID: id)
                    deliver(img, scale)
                } catch { fail(error) }
            }
        }
    }

    private func fullscreen() {
        let screen = NSScreen.underMouse
        Task { @MainActor in
            do {
                let shot = try await ScreenCapturer.capture(screen: screen)
                deliver(shot.image, shot.scale)
            } catch { fail(error) }
        }
    }

    // MARK: 마무리

    private func deliver(_ img: CGImage, _ scale: CGFloat) {
        busy = false
        CaptureSound.play()
        onCaptured?(img, scale)
    }

    private func fail(_ error: Error) {
        busy = false
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "캡처하지 못했습니다"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
