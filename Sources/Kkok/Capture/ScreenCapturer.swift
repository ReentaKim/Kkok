import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// 전역 CG 좌표(주 화면 왼쪽 위 원점, y 아래)에서의 이 화면 범위
    var cgFrame: CGRect {
        let primaryH = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryH - frame.maxY, width: frame.width, height: frame.height)
    }

    static func screen(displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == displayID }
    }

    static var underMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }
}

/// 얼린 화면 한 장
struct DisplayShot {
    let screen: NSScreen
    let image: CGImage

    /// 이미지 픽셀 / 화면 pt
    var scale: CGFloat { CGFloat(image.width) / screen.frame.width }

    /// 화면 안 좌표(왼쪽 위 원점, pt) 범위를 잘라 낸다
    func crop(_ rectInScreen: CGRect) -> CGImage? {
        let s = scale
        let px = CGRect(x: rectInScreen.minX * s, y: rectInScreen.minY * s,
                        width: rectInScreen.width * s, height: rectInScreen.height * s).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard px.width >= 1, px.height >= 1 else { return nil }
        return image.cropping(to: px)
    }
}

enum CaptureError: LocalizedError {
    case noPermission, displayNotFound, windowNotFound

    var errorDescription: String? {
        switch self {
        case .noPermission: return "화면 기록 권한이 없습니다."
        case .displayNotFound: return "화면을 찾지 못했습니다."
        case .windowNotFound: return "창을 찾지 못했습니다."
        }
    }
}

/// ScreenCaptureKit으로 화면·창을 찍는다 (FR-01·04·05·08)
enum ScreenCapturer {

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// 화면 하나 전체 (실제 픽셀 해상도)
    static func capture(screen: NSScreen) async throws -> DisplayShot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        // Kkok 자신의 창(카운트다운 등)은 빼고 찍는다
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return DisplayShot(screen: screen, image: img)
    }

    /// 모든 화면을 한꺼번에 얼린다 (영역 선택용)
    static func captureAll() async throws -> [DisplayShot] {
        var shots: [DisplayShot] = []
        for screen in NSScreen.screens {
            shots.append(try await capture(screen: screen))
        }
        return shots
    }

    /// 창 하나만, 그림자 없이 (FR-04)
    static func capture(windowID: CGWindowID) async throws -> (CGImage, CGFloat) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let win = content.windows.first(where: { $0.windowID == windowID }) else { throw CaptureError.windowNotFound }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        let center = CGPoint(x: win.frame.midX, y: win.frame.midY)
        let screen = NSScreen.screens.first { $0.cgFrame.contains(center) } ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        config.width = Int(win.frame.width * scale)
        config.height = Int(win.frame.height * scale)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (img, scale)
    }

    /// 화면에 보이는 일반 창 목록 (앞에서 뒤 순서, 전역 CG 좌표)
    static func visibleWindows() -> [(id: CGWindowID, frame: CGRect, owner: String)] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let myPID = ProcessInfo.processInfo.processIdentifier
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != myPID,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bd),
                  frame.width > 40, frame.height > 30
            else { return nil }
            return (id, frame, w[kCGWindowOwnerName as String] as? String ?? "")
        }
    }
}
