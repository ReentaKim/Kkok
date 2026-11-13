import AppKit
import Carbon.HIToolbox

/// 전역 단축키 하나 (Carbon 키 코드 + 수정키)
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon 수정키 (cmdKey, shiftKey, optionKey, controlKey)
    var modifiers: UInt32

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + HotKey.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let map: [Int: String] = [
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
            kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
            kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
            kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
            kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
            kVK_ANSI_Z: "Z", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11",
            kVK_F12: "F12", kVK_Space: "Space",
        ]
        return map[Int(code)] ?? "#\(code)"
    }

    /// NSEvent 수정키 → Carbon 수정키
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }
}

enum CaptureMode: String, CaseIterable, Codable {
    case area, previousArea, window, fullscreen, timed

    var title: String {
        switch self {
        case .area: return "영역 캡처"
        case .previousArea: return "직전 영역 다시 찍기"
        case .window: return "창 캡처"
        case .fullscreen: return "전체 화면 캡처"
        case .timed: return "타이머 캡처"
        }
    }

    /// 결정 기록: ⇧⌘5 영역 (Skitch에서 손에 익은 키. macOS 스크린샷 도구 ⇧⌘5와 겹치면 가이드 참고)
    var defaultHotKey: HotKey {
        let cs = UInt32(cmdKey | shiftKey)
        switch self {
        case .area: return HotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: cs)
        case .previousArea: return HotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: cs | UInt32(optionKey))
        case .window: return HotKey(keyCode: UInt32(kVK_ANSI_7), modifiers: cs)
        case .fullscreen: return HotKey(keyCode: UInt32(kVK_ANSI_6), modifiers: cs)
        case .timed: return HotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: cs | UInt32(controlKey))
        }
    }
}

enum Tool: String, CaseIterable, Codable {
    case select, arrow, text, shape, pen, highlighter, pixelate, stamp, crop

    var shortcut: String {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .text: return "t"
        case .shape: return "r"
        case .pen: return "p"
        case .highlighter: return "h"
        case .pixelate: return "b"
        case .stamp: return "s"
        case .crop: return "c"
        }
    }

    var title: String {
        switch self {
        case .select: return "선택"
        case .arrow: return "화살표"
        case .text: return "글자"
        case .shape: return "도형"
        case .pen: return "펜"
        case .highlighter: return "형광펜"
        case .pixelate: return "모자이크"
        case .stamp: return "스탬프"
        case .crop: return "자르기"
        }
    }
}

enum ShapeKind: String, CaseIterable, Codable {
    case rect, roundedRect, ellipse, line

    var annotationKind: AnnotationKind {
        switch self {
        case .rect: return .rect
        case .roundedRect: return .roundedRect
        case .ellipse: return .ellipse
        case .line: return .line
        }
    }

    var title: String {
        switch self {
        case .rect: return "사각형"
        case .roundedRect: return "둥근 사각형"
        case .ellipse: return "타원"
        case .line: return "선"
        }
    }

    var symbol: String {
        switch self {
        case .rect: return "rectangle"
        case .roundedRect: return "app"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        }
    }
}

/// UserDefaults 설정. 마지막 도구·색·굵기도 여기서 기억한다 (FR-20)
final class Preferences {
    static let shared = Preferences()
    private let d = UserDefaults.standard

    static let didChange = Notification.Name("KkokPreferencesDidChange")

    func hotKey(for mode: CaptureMode) -> HotKey? {
        let key = "hotkey.\(mode.rawValue)"
        if d.object(forKey: key) == nil { return mode.defaultHotKey }
        guard let data = d.data(forKey: key) else { return nil } // 지운 경우
        return try? JSONDecoder().decode(HotKey.self, from: data)
    }

    func setHotKey(_ hk: HotKey?, for mode: CaptureMode) {
        let key = "hotkey.\(mode.rawValue)"
        // 같은 단축키를 다른 캡처 방식이 쓰고 있으면 그쪽을 비운다 (BUG-10)
        if let hk {
            for other in CaptureMode.allCases where other != mode && hotKey(for: other) == hk {
                d.set(Data(), forKey: "hotkey.\(other.rawValue)")
            }
        }
        if let hk, let data = try? JSONEncoder().encode(hk) { d.set(data, forKey: key) }
        else { d.set(Data(), forKey: key) }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    var timerSeconds: Int {
        get { let v = d.integer(forKey: "timerSeconds"); return v == 0 ? 5 : max(1, min(15, v)) }
        set { d.set(newValue, forKey: "timerSeconds") }
    }

    var tool: Tool {
        get { Tool(rawValue: d.string(forKey: "tool") ?? "") ?? .arrow }
        set { d.set(newValue.rawValue, forKey: "tool") }
    }

    var shape: ShapeKind {
        get { ShapeKind(rawValue: d.string(forKey: "shape") ?? "") ?? .rect }
        set { d.set(newValue.rawValue, forKey: "shape") }
    }

    var stamp: StampKind {
        get { StampKind(rawValue: d.string(forKey: "stamp") ?? "") ?? .check }
        set { d.set(newValue.rawValue, forKey: "stamp") }
    }

    var color: RGBA {
        get {
            guard let data = d.data(forKey: "color"), let c = try? JSONDecoder().decode(RGBA.self, from: data) else { return .pink }
            return c
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "color") }
    }

    var size: Int {
        get { let v = d.integer(forKey: "size"); return v == 0 ? 2 : max(1, min(3, v)) }
        set { d.set(newValue, forKey: "size") }
    }

    /// 앱을 직접 실행할 때 시작 창 보기 (기본 켬)
    var showHomeAtLaunch: Bool {
        get { d.object(forKey: "showHomeAtLaunch") == nil ? true : d.bool(forKey: "showHomeAtLaunch") }
        set { d.set(newValue, forKey: "showHomeAtLaunch") }
    }

    var didShowWelcome: Bool {
        get { d.bool(forKey: "didShowWelcome") }
        set { d.set(newValue, forKey: "didShowWelcome") }
    }

    /// 직전 영역 (FR-03): 화면 번호 + 화면 안 좌표(왼쪽 위 원점, pt)
    var previousArea: (displayID: CGDirectDisplayID, rect: CGRect)? {
        get {
            guard let arr = d.array(forKey: "previousArea") as? [Double], arr.count == 5 else { return nil }
            return (CGDirectDisplayID(arr[0]), CGRect(x: arr[1], y: arr[2], width: arr[3], height: arr[4]))
        }
        set {
            guard let v = newValue else { d.removeObject(forKey: "previousArea"); return }
            d.set([Double(v.displayID), v.rect.minX, v.rect.minY, v.rect.width, v.rect.height], forKey: "previousArea")
        }
    }
}
