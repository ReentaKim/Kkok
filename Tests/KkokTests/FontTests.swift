import CoreGraphics
import XCTest
@testable import Kkok

final class FontTests: XCTestCase {

    override class func setUp() {
        // 저장소의 Resources/Fonts 를 쓰도록
        let fonts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Fonts").standardized.path
        setenv("KKOK_FONTS_DIR", fonts, 1)
        FontRegistry.registerBundledFonts()
    }

    func testAllBundledFontsAvailable() {
        for f in TextFont.allCases {
            XCTAssertTrue(FontRegistry.isAvailable(f), "\(f.title) 글꼴을 쓸 수 없음")
        }
    }

    /// 글꼴이 생기기 전에 저장한 보관 파일(font 없음)도 열려야 한다
    func testOldAnnotationWithoutFontDecodes() throws {
        var a = Annotation(kind: .text, color: .pink, size: 2, scale: 1)
        a.text = "예전"
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        obj.removeValue(forKey: "font")
        let back = try JSONDecoder().decode(Annotation.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.font)
        XCTAssertEqual(back.fontName, "AppleSDGothicNeo-Bold")
    }

    func testFontRoundTripAndSizeFactor() throws {
        var a = Annotation(kind: .text, color: .pink, size: 2, scale: 1)
        a.font = .nanumPen
        let back = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.font, .nanumPen)
        XCTAssertEqual(back.fontSize, 24 * 1.35, accuracy: 0.001)
    }

    /// 글꼴마다 실제로 다른 모양으로 그려지는지 (대체 글꼴로 빠지지 않았는지)
    func testFontsRenderDifferently() {
        var widths = Set<Int>()
        for f in TextFont.allCases {
            var a = Annotation(kind: .text, color: .pink, size: 2, scale: 1)
            a.font = f
            a.text = "이 버튼 위치 바꿔 주세요"
            widths.insert(Int(Geometry.bounds(of: a).width))
        }
        XCTAssertEqual(widths.count, TextFont.allCases.count)
    }

    func testPaletteHasTwelveColors() {
        XCTAssertEqual(RGBA.palette.count, 12)
        XCTAssertEqual(RGBA.palette.first, .pink)
        XCTAssertEqual(Set(RGBA.palette.map { "\($0.r)\($0.g)\($0.b)" }).count, 12)
    }
}
