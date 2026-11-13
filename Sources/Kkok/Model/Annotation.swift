import CoreGraphics
import Foundation

/// 색. JSON에 그대로 저장하려고 CGColor 대신 RGBA 값으로 둔다. (0~1)
struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// "#RRGGBB"
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
        a = 1
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    func withAlpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    /// 흰색에 가까운 색인지 (외곽선을 검정으로 바꿀 때 쓴다)
    var isLight: Bool { (0.299 * r + 0.587 * g + 0.114 * b) > 0.85 }

    static let pink = RGBA(hex: "#FC0C59")
    static let highlighterYellow = RGBA(hex: "#FFF700")
    static let white = RGBA(r: 1, g: 1, b: 1)
    static let black = RGBA(r: 0, g: 0, b: 0)

    /// 디자인 명세 2장의 색 8개
    static let palette: [RGBA] = [
        "#FC0C59", "#FF3B30", "#FF9500", "#FFD60A",
        "#34C759", "#0A84FF", "#1C1C1E", "#FFFFFF",
    ].map { RGBA(hex: $0) }
}

enum AnnotationKind: String, Codable, CaseIterable {
    case arrow, line, rect, roundedRect, ellipse, pen, highlighter, pixelate, text, stamp
}

enum StampKind: String, Codable, CaseIterable {
    case check, cross, question, exclamation, star, number

    var fill: RGBA? {
        switch self {
        case .check: return RGBA(hex: "#34C759")
        case .cross: return RGBA(hex: "#FF3B30")
        case .question: return RGBA(hex: "#0A84FF")
        case .exclamation: return RGBA(hex: "#FF9500")
        case .star: return RGBA(hex: "#FFCC00")
        case .number: return nil // 현재 색
        }
    }
}

/// 주석 하나. 좌표는 모두 "원본 이미지 픽셀, 왼쪽 위 원점(y 아래로 증가)" 기준이다.
///
/// - 화살표·선: `p1`(꼬리) → `p2`(머리)
/// - 사각·둥근 사각·타원·모자이크: `p1`, `p2`가 마주 보는 두 모서리
/// - 펜·형광펜: `points`
/// - 글자: `p1`이 왼쪽 위, `text`
/// - 스탬프: `p1`이 중심, `p2.x`는 지름이 아니라 쓰지 않음 → 지름은 `size`와 `scale`로 계산
struct Annotation: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: AnnotationKind
    var color: RGBA
    /// 굵기 단계 1~3
    var size: Int
    /// 이미지 배율(Retina 캡처면 2). 굵기를 이미지 픽셀로 바꿀 때 곱한다.
    var scale: Double
    var p1: CGPoint = .zero
    var p2: CGPoint = .zero
    var points: [CGPoint] = []
    var text: String = ""
    var stamp: StampKind = .check
    var number: Int = 1
    /// 사용자가 손잡이로 늘린 스탬프·글자 크기 배수
    var magnify: Double = 1

    init(kind: AnnotationKind, color: RGBA, size: Int, scale: Double) {
        self.kind = kind
        self.color = color
        self.size = max(1, min(3, size))
        self.scale = scale
    }

    // MARK: 굵기 (디자인 명세 2장 표)

    var lineWidth: CGFloat { CGFloat([3, 5, 9][size - 1] * scale) }
    var arrowWidth: CGFloat { CGFloat([6, 10, 16][size - 1] * scale) }
    var fontSize: CGFloat { CGFloat([18, 24, 36][size - 1] * scale * magnify) }
    var highlighterWidth: CGFloat { CGFloat(Double(size) * 4 * 3 * scale) }
    var stampDiameter: CGFloat { CGFloat((Double(size) * 14 + 20) * scale * magnify) }
    /// 흰 외곽선이 색 선보다 양쪽으로 더 두꺼운 양
    var outlineExtra: CGFloat { CGFloat(4 * scale) }

    /// 두 점으로 정한 사각형 (정규화)
    var rect: CGRect {
        CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    var outlineColor: RGBA { color.isLight ? RGBA.black.withAlpha(0.4) : .white }

    /// 끌어서 옮기기
    mutating func translate(dx: CGFloat, dy: CGFloat) {
        p1.x += dx; p1.y += dy
        p2.x += dx; p2.y += dy
        points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// 너무 작아서 의미 없는 주석 (클릭 한 번으로 생긴 것)
    var isDegenerate: Bool {
        switch kind {
        case .arrow, .line:
            return hypot(p2.x - p1.x, p2.y - p1.y) < 4 * scale
        case .rect, .roundedRect, .ellipse, .pixelate:
            return rect.width < 3 * scale || rect.height < 3 * scale
        case .pen, .highlighter:
            return points.count < 2
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stamp:
            return false
        }
    }
}
