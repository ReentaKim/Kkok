import CoreGraphics
import XCTest
@testable import Kkok

final class ModelTests: XCTestCase {

    /// 칸마다 다른 색인 시험 이미지 (모자이크 확인용)
    func makeStripes(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            let v: CGFloat = x % 2 == 0 ? 0 : 1
            ctx.setFillColor(CGColor(srgbRed: v, green: v, blue: v, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return ctx.makeImage()!
    }

    func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // CGContext 메모리는 위쪽 줄부터
        let i = (y * img.width + x) * 4
        return (p[i], p[i + 1], p[i + 2], p[i + 3])
    }

    // FR-33·34: 주석 JSON 왕복
    func testAnnotationRoundTrip() throws {
        var s = DocumentState(imageSize: CGSize(width: 400, height: 300))
        var a = Annotation(kind: .arrow, color: .pink, size: 2, scale: 2)
        a.p1 = CGPoint(x: 10, y: 20); a.p2 = CGPoint(x: 200, y: 100)
        var t = Annotation(kind: .text, color: .pink, size: 3, scale: 2)
        t.text = "한글 테스트\n둘째 줄"; t.p1 = CGPoint(x: 5, y: 5)
        var st = Annotation(kind: .stamp, color: .pink, size: 1, scale: 1)
        st.stamp = .number; st.number = 3
        var pen = Annotation(kind: .pen, color: RGBA(hex: "#0A84FF"), size: 1, scale: 1)
        pen.points = [CGPoint(x: 1, y: 1), CGPoint(x: 5, y: 9)]
        s.annotations = [a, t, st, pen]
        s.expand(.right)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(DocumentState.self, from: data)
        XCTAssertEqual(back, s)
        XCTAssertEqual(back.nextStampNumber, 4)
    }

    func testHexColor() {
        let c = RGBA(hex: "#FC0C59")
        XCTAssertEqual(c.r, 252.0 / 255, accuracy: 1e-6)
        XCTAssertEqual(c.g, 12.0 / 255, accuracy: 1e-6)
        XCTAssertEqual(c.b, 89.0 / 255, accuracy: 1e-6)
        XCTAssertTrue(RGBA.white.isLight)
        XCTAssertFalse(RGBA.pink.isLight)
    }

    // FR-17: 자르기는 캔버스 안으로 제한, 너무 작으면 무시
    func testCrop() {
        var s = DocumentState(imageSize: CGSize(width: 100, height: 80))
        s.crop(to: CGRect(x: -10, y: 10, width: 50, height: 200))
        XCTAssertEqual(s.canvasRect, CGRect(x: 0, y: 10, width: 40, height: 70))
        s.crop(to: CGRect(x: 0, y: 10, width: 2, height: 2))
        XCTAssertEqual(s.canvasRect, CGRect(x: 0, y: 10, width: 40, height: 70))
    }

    // FR-18: 넓히기
    func testExpand() {
        var s = DocumentState(imageSize: CGSize(width: 400, height: 200))
        s.expand(.left)
        XCTAssertEqual(s.canvasRect, CGRect(x: -50, y: 0, width: 450, height: 200))
        XCTAssertTrue(s.needsBackground)
        var small = DocumentState(imageSize: CGSize(width: 60, height: 60))
        small.expand(.bottom)
        XCTAssertEqual(small.canvasRect.height, 100) // 최소 40
    }

    // ⇧ 고정
    func testConstrain() {
        let p = Geometry.constrain(CGPoint(x: 100, y: 8), from: .zero, kind: .line)
        XCTAssertEqual(p.y, 0, accuracy: 0.001)
        let q = Geometry.constrain(CGPoint(x: 50, y: -20), from: .zero, kind: .rect)
        XCTAssertEqual(q, CGPoint(x: 50, y: -50))
    }

    func testHitTest() {
        var a = Annotation(kind: .rect, color: .pink, size: 2, scale: 1)
        a.p1 = CGPoint(x: 10, y: 10); a.p2 = CGPoint(x: 110, y: 60)
        XCTAssertTrue(Geometry.hitTest(a, at: CGPoint(x: 10, y: 30), tolerance: 2, inside: false))
        XCTAssertFalse(Geometry.hitTest(a, at: CGPoint(x: 60, y: 35), tolerance: 2, inside: false))
        XCTAssertTrue(Geometry.hitTest(a, at: CGPoint(x: 60, y: 35), tolerance: 2, inside: true))

        var arrow = Annotation(kind: .arrow, color: .pink, size: 2, scale: 1)
        arrow.p1 = .zero; arrow.p2 = CGPoint(x: 100, y: 0)
        XCTAssertTrue(Geometry.hitTest(arrow, at: CGPoint(x: 50, y: 4), tolerance: 2, inside: false))
        XCTAssertFalse(Geometry.hitTest(arrow, at: CGPoint(x: 50, y: 40), tolerance: 2, inside: false))
    }

    func testCornerHandleKeepsOppositeCorner() {
        var a = Annotation(kind: .rect, color: .pink, size: 2, scale: 1)
        a.p1 = CGPoint(x: 10, y: 10); a.p2 = CGPoint(x: 50, y: 50)
        let orig = a
        Geometry.apply(handle: .corner(2), to: &a, point: CGPoint(x: 80, y: 90), original: orig)
        XCTAssertEqual(a.rect, CGRect(x: 10, y: 10, width: 70, height: 80))
    }

    // FR-15: 모자이크 결과에서 원래 1px 줄무늬가 사라져야 한다
    func testPixelateDestroysDetail() throws {
        let base = makeStripes(width: 200, height: 100)
        var s = DocumentState(imageSize: CGSize(width: 200, height: 100))
        var px = Annotation(kind: .pixelate, color: .pink, size: 2, scale: 1)
        px.p1 = CGPoint(x: 0, y: 0); px.p2 = CGPoint(x: 120, y: 100)
        s.annotations = [px]
        let flat = try XCTUnwrap(Renderer.flatten(base: base, state: s))
        // 모자이크 안: 같은 칸 안의 이웃 픽셀이 같은 색
        let a = pixel(flat, 1, 1), b = pixel(flat, 2, 1)
        XCTAssertEqual(a.0, b.0)
        // 그리고 회색(평균)에 가깝다
        XCTAssertTrue((60...200).contains(Int(a.0)), "칸 평균이어야 함: \(a.0)")
        // 모자이크 밖: 줄무늬 그대로
        XCTAssertNotEqual(pixel(flat, 150, 50).0, pixel(flat, 151, 50).0)
    }

    // 넓힌 부분은 흰색, 자르면 크기가 줄어든다
    func testFlattenExpandedAndCropped() throws {
        let base = makeStripes(width: 100, height: 100)
        var s = DocumentState(imageSize: CGSize(width: 100, height: 100))
        s.expand(.top)
        var flat = try XCTUnwrap(Renderer.flatten(base: base, state: s))
        XCTAssertEqual(flat.height, 140)
        let top = pixel(flat, 0, 5)
        XCTAssertEqual(top.0, 255); XCTAssertEqual(top.3, 255)
        // 원본 첫 줄(x=0은 검정)이 y=40에서 시작
        XCTAssertEqual(pixel(flat, 0, 45).0, 0)
        s.crop(to: CGRect(x: 10, y: 0, width: 30, height: 50))
        flat = try XCTUnwrap(Renderer.flatten(base: base, state: s))
        XCTAssertEqual(flat.width, 30); XCTAssertEqual(flat.height, 50)
    }

    // 모든 종류가 그려지며 죽지 않는다 + 화살표 색이 실제로 찍힌다
    func testRenderAllKinds() throws {
        let base = makeStripes(width: 300, height: 300)
        var s = DocumentState(imageSize: CGSize(width: 300, height: 300))
        for kind in AnnotationKind.allCases {
            var a = Annotation(kind: kind, color: .pink, size: 2, scale: 1)
            a.p1 = CGPoint(x: 20, y: 20); a.p2 = CGPoint(x: 200, y: 150)
            a.points = [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 60), CGPoint(x: 90, y: 30)]
            a.text = "콕"
            s.annotations.append(a)
        }
        XCTAssertNotNil(Renderer.flatten(base: base, state: s))

        var only = DocumentState(imageSize: CGSize(width: 300, height: 300))
        var arrow = Annotation(kind: .arrow, color: .pink, size: 3, scale: 1)
        arrow.p1 = CGPoint(x: 20, y: 150); arrow.p2 = CGPoint(x: 280, y: 150)
        only.annotations = [arrow]
        let flat = try XCTUnwrap(Renderer.flatten(base: base, state: only))
        let c = pixel(flat, 200, 150)
        XCTAssertEqual(Int(c.0), 252, accuracy: 2)
        XCTAssertEqual(Int(c.1), 12, accuracy: 2)
    }

    // FR-33: 보관함 저장·불러오기
    func testHistoryStore() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kkok-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = HistoryStore(root: tmp.appendingPathComponent("support"), picturesDir: tmp.appendingPathComponent("pics"))
        let base = makeStripes(width: 50, height: 40)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var meta = try store.create(original: base, scale: 2, created: date)
        let second = try store.create(original: base, scale: 2, created: date)
        XCTAssertNotEqual(meta.name, second.name, "같은 초에 찍어도 이름이 달라야 함")
        var a = Annotation(kind: .line, color: .pink, size: 1, scale: 2)
        a.p1 = .zero; a.p2 = CGPoint(x: 30, y: 30)
        meta.state.annotations = [a]
        meta = try store.save(meta: meta, base: base)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(meta.exportedPath)))
        let (loaded, img) = try XCTUnwrap(store.load(id: meta.id))
        XCTAssertEqual(loaded.state, meta.state)
        XCTAssertEqual(img.width, 50)
        XCTAssertEqual(store.recent().count, 2)
    }
}
