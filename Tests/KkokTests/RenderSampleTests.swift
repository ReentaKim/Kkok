import CoreGraphics
import XCTest
@testable import Kkok

/// KKOK_SAMPLE_OUT 환경 변수가 있으면 모든 주석을 그린 견본 PNG를 쓴다 (눈 확인용)
final class RenderSampleTests: XCTestCase {
    func testWriteSample() throws {
        guard let out = ProcessInfo.processInfo.environment["KKOK_SAMPLE_OUT"] else { throw XCTSkip("견본 경로 없음") }
        let w = 900, h = 600
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.25, blue: 0.35, alpha: 1)); ctx.fill(CGRect(x: 450, y: 0, width: 450, height: 300))
        for i in 0..<20 { ctx.setFillColor(CGColor(gray: CGFloat(i % 2), alpha: 1)); ctx.fill(CGRect(x: 40 + i * 6, y: 60, width: 3, height: 40)) }
        let base = ctx.makeImage()!
        var s = DocumentState(imageSize: CGSize(width: w, height: h))
        func add(_ k: AnnotationKind, _ p1: CGPoint, _ p2: CGPoint, size: Int = 2, color: RGBA = .pink, _ f: (inout Annotation) -> Void = { _ in }) {
            var a = Annotation(kind: k, color: color, size: size, scale: 1); a.p1 = p1; a.p2 = p2; f(&a); s.annotations.append(a)
        }
        add(.arrow, CGPoint(x: 400, y: 200), CGPoint(x: 120, y: 60), size: 3)
        add(.arrow, CGPoint(x: 600, y: 250), CGPoint(x: 820, y: 80), size: 2)
        add(.arrow, CGPoint(x: 700, y: 560), CGPoint(x: 760, y: 520), size: 1)
        add(.text, CGPoint(x: 120, y: 230), .zero, size: 3) { $0.text = "이 버튼 위치 바꿔 주세요\nSecond line" }
        add(.text, CGPoint(x: 500, y: 200), .zero, size: 2, color: .white) { $0.text = "흰 글자" }
        add(.rect, CGPoint(x: 40, y: 330), CGPoint(x: 220, y: 430))
        add(.roundedRect, CGPoint(x: 250, y: 330), CGPoint(x: 430, y: 430), color: RGBA(hex: "#0A84FF"))
        add(.ellipse, CGPoint(x: 460, y: 330), CGPoint(x: 640, y: 430), color: RGBA(hex: "#34C759"))
        add(.line, CGPoint(x: 660, y: 330), CGPoint(x: 860, y: 430), size: 1)
        add(.pixelate, CGPoint(x: 30, y: 50), CGPoint(x: 100, y: 110))
        add(.highlighter, .zero, .zero, color: .highlighterYellow) { $0.points = [CGPoint(x: 40, y: 480), CGPoint(x: 200, y: 478), CGPoint(x: 300, y: 485), CGPoint(x: 200, y: 490)] }
        add(.pen, .zero, .zero) { $0.points = (0..<30).map { CGPoint(x: 330 + Double($0) * 8, y: 500 + sin(Double($0) / 3) * 30) } }
        for (i, st) in StampKind.allCases.enumerated() {
            add(.stamp, CGPoint(x: 620 + Double(i % 3) * 70, y: 460 + Double(i / 3) * 70), .zero, size: 2) { $0.stamp = st; $0.number = 7 }
        }
        let flat = try XCTUnwrap(Renderer.flatten(base: base, state: s))
        try XCTUnwrap(Renderer.pngData(flat)).write(to: URL(fileURLWithPath: out))
    }
}
