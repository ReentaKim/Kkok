import AppKit

/// 현재 도구·색·굵기. 모든 편집 창이 함께 쓰고, 앱을 다시 켜도 기억한다 (FR-20)
final class ToolState {
    static let shared = ToolState()
    static let didChange = Notification.Name("KkokToolStateDidChange")

    private let prefs = Preferences.shared

    var tool: Tool { didSet { prefs.tool = tool; post() } }
    var shape: ShapeKind { didSet { prefs.shape = shape; post() } }
    var stamp: StampKind { didSet { prefs.stamp = stamp; post() } }
    var color: RGBA { didSet { prefs.color = color; post() } }
    var size: Int { didSet { prefs.size = size; post() } }

    private init() {
        tool = prefs.tool
        shape = prefs.shape
        stamp = prefs.stamp
        color = prefs.color
        size = prefs.size
    }

    private func post() { NotificationCenter.default.post(name: Self.didChange, object: self) }

    /// 지금 도구로 만들 주석 종류
    var annotationKind: AnnotationKind? {
        switch tool {
        case .arrow: return .arrow
        case .text: return .text
        case .shape: return shape.annotationKind
        case .pen: return .pen
        case .highlighter: return .highlighter
        case .pixelate: return .pixelate
        case .stamp: return .stamp
        case .select, .crop: return nil
        }
    }

    /// 형광펜은 분홍 대신 노랑이 기본 (디자인 명세 3장)
    func color(for kind: AnnotationKind) -> RGBA {
        if kind == .highlighter && color == .pink { return .highlighterYellow }
        return color
    }
}

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    init(_ c: NSColor) {
        let s = c.usingColorSpace(.sRGB) ?? .black
        self.init(r: Double(s.redComponent), g: Double(s.greenComponent), b: Double(s.blueComponent), a: Double(s.alphaComponent))
    }
}
