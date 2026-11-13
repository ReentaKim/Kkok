import CoreGraphics
import CoreText
import Foundation

// 주석 모양 계산, 범위, 클릭 판정. 그리기(Renderer)와 화면(CanvasView)이 같이 쓴다.

extension CGPoint {
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var length: CGFloat { hypot(x, y) }
    func distance(to p: CGPoint) -> CGFloat { (self - p).length }
}

enum Geometry {

    // MARK: 화살표 (디자인 명세 3장)

    /// 꼬리(p1)에서 머리(p2)로 갈수록 굵어지는 화살표 외형. 채워서 그린다.
    static func arrowPath(from tail: CGPoint, to tip: CGPoint, width w: CGFloat) -> CGPath {
        let v = tip - tail
        let len = v.length
        let path = CGMutablePath()
        guard len > 0.5 else { return path }
        let d = v * (1 / len)
        let n = CGPoint(x: -d.y, y: d.x)

        // 짧은 화살표는 머리도 줄인다
        var headLen = w * 3.2
        var headHalf = w * 1.3
        if headLen > len * 0.6 {
            let k = (len * 0.6) / headLen
            headLen *= k; headHalf *= k
        }
        let bodyW = min(w, headHalf * 2 * 0.62)
        let tailW = bodyW * 0.45

        let base = tip - d * headLen
        let neck = tip - d * (headLen * 0.82)
        let tailL = tail + n * (tailW / 2), tailR = tail - n * (tailW / 2)
        let neckL = neck + n * (bodyW / 2), neckR = neck - n * (bodyW / 2)
        let baseL = base + n * headHalf, baseR = base - n * headHalf

        path.move(to: tailR)
        path.addArc(center: tail, radius: tailW / 2,
                    startAngle: atan2(-n.y, -n.x), endAngle: atan2(n.y, n.x), clockwise: true)
        path.addLine(to: tailL)
        path.addLine(to: neckL)
        path.addLine(to: baseL)
        path.addLine(to: tip)
        path.addLine(to: baseR)
        path.addLine(to: neckR)
        path.closeSubpath()
        return path
    }

    // MARK: 자유 곡선

    /// 점 사이를 중점 이차 곡선으로 이어 부드럽게 만든다 (FR-13)
    static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 { path.addLine(to: first); return path }
        if pts.count == 2 { path.addLine(to: pts[1]); return path }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    /// 펜 입력 점을 줄인다 (너무 촘촘한 점 제거)
    static func appendPoint(_ p: CGPoint, to pts: inout [CGPoint], minDistance: CGFloat) {
        if let last = pts.last, last.distance(to: p) < minDistance { return }
        pts.append(p)
    }

    // MARK: 글자

    struct TextLayout {
        var lines: [CTLine]
        var ascent: CGFloat
        var descent: CGFloat
        var lineHeight: CGFloat
        var size: CGSize
    }

    static let textFontName = TextFont.system.postScriptName

    static func font(name: String = textFontName, size: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    static func textLayout(_ text: String, fontSize: CGFloat, fontName: String = textFontName) -> TextLayout {
        let f = font(name: fontName, size: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): f,
        ]
        let rawLines = text.isEmpty ? [" "] : text.components(separatedBy: "\n")
        let lines = rawLines.map { CTLineCreateWithAttributedString(NSAttributedString(string: $0.isEmpty ? " " : $0, attributes: attrs)) }
        let ascent = CTFontGetAscent(f), descent = CTFontGetDescent(f), leading = CTFontGetLeading(f)
        let lh = ceil(ascent + descent + max(leading, fontSize * 0.1))
        let width = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        return TextLayout(lines: lines, ascent: ascent, descent: descent, lineHeight: lh,
                          size: CGSize(width: ceil(width), height: lh * CGFloat(lines.count)))
    }

    // MARK: 범위

    /// 주석이 차지하는 범위(외곽선 포함, 이미지 좌표)
    static func bounds(of a: Annotation) -> CGRect {
        switch a.kind {
        case .arrow:
            return CGRect(x: min(a.p1.x, a.p2.x), y: min(a.p1.y, a.p2.y),
                          width: abs(a.p2.x - a.p1.x), height: abs(a.p2.y - a.p1.y))
                .insetBy(dx: -a.arrowWidth * 1.6 - a.outlineExtra, dy: -a.arrowWidth * 1.6 - a.outlineExtra)
        case .line:
            return a.rect.insetBy(dx: -a.lineWidth - a.outlineExtra, dy: -a.lineWidth - a.outlineExtra)
        case .rect, .roundedRect, .ellipse:
            return a.rect.insetBy(dx: -a.lineWidth - a.outlineExtra, dy: -a.lineWidth - a.outlineExtra)
        case .pixelate:
            return a.rect
        case .pen:
            return pointsBounds(a.points).insetBy(dx: -a.lineWidth - a.outlineExtra, dy: -a.lineWidth - a.outlineExtra)
        case .highlighter:
            return pointsBounds(a.points).insetBy(dx: -a.highlighterWidth, dy: -a.highlighterWidth)
        case .text:
            return pointsBounds(textCorners(a))
        case .stamp:
            let r = a.stampDiameter / 2 + a.outlineExtra
            return CGRect(x: a.p1.x - r, y: a.p1.y - r, width: r * 2, height: r * 2)
        }
    }

    static func pointsBounds(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .null }
        var minX = f.x, minY = f.y, maxX = f.x, maxY = f.y
        for p in pts { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: 글자 회전

    /// 회전 전 글자 상자(여백 포함, 이미지 좌표)
    static func textLocalRect(_ a: Annotation) -> CGRect {
        let l = textLayout(a.text, fontSize: a.fontSize, fontName: a.fontName)
        let pad = a.fontSize * 0.12
        return CGRect(origin: a.p1, size: l.size).insetBy(dx: -pad, dy: -pad)
    }

    /// 회전 중심 = 글자 상자 가운데
    static func textCenter(_ a: Annotation) -> CGPoint {
        let r = textLocalRect(a)
        return CGPoint(x: r.midX, y: r.midY)
    }

    static func rotate(_ p: CGPoint, around c: CGPoint, by t: CGFloat) -> CGPoint {
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * cos(t) - dy * sin(t), y: c.y + dx * sin(t) + dy * cos(t))
    }

    /// 회전한 글자 상자의 네 모서리: 왼위, 오위, 오아래, 왼아래
    static func textCorners(_ a: Annotation) -> [CGPoint] {
        let r = textLocalRect(a), c = CGPoint(x: r.midX, y: r.midY)
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
            .map { rotate($0, around: c, by: a.angle) }
    }

    /// 회전 손잡이 각도(라디안)를 15° 단위로, 또는 0·90·180·270° 가까이면 붙인다
    static func snapAngle(_ t: CGFloat, step15: Bool) -> CGFloat {
        if step15 { return (t / (.pi / 12)).rounded() * (.pi / 12) }
        let right = (t / (.pi / 2)).rounded() * (.pi / 2)
        return abs(t - right) < (4 * .pi / 180) ? right : t
    }

    // MARK: 클릭 판정

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = b - a, ap = p - a
        let len2 = ab.x * ab.x + ab.y * ab.y
        guard len2 > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / len2))
        return p.distance(to: a + ab * t)
    }

    /// 주석 위를 눌렀는지. `inside`가 참이면 도형 안쪽 클릭도 맞는 것으로 친다(선택 도구).
    static func hitTest(_ a: Annotation, at p: CGPoint, tolerance tol: CGFloat, inside: Bool) -> Bool {
        switch a.kind {
        case .arrow:
            return distance(from: p, toSegment: a.p1, a.p2) <= a.arrowWidth + tol
        case .line:
            return distance(from: p, toSegment: a.p1, a.p2) <= a.lineWidth + tol
        case .rect, .roundedRect:
            let r = a.rect
            if inside && r.contains(p) { return true }
            let outer = r.insetBy(dx: -(a.lineWidth + tol), dy: -(a.lineWidth + tol))
            let inner = r.insetBy(dx: a.lineWidth + tol, dy: a.lineWidth + tol)
            return outer.contains(p) && (inner.isNull || inner.width <= 0 || inner.height <= 0 || !inner.contains(p))
        case .ellipse:
            let r = a.rect
            guard r.width > 0, r.height > 0 else { return false }
            let c = CGPoint(x: r.midX, y: r.midY)
            let rx = r.width / 2, ry = r.height / 2
            let nx = (p.x - c.x) / rx, ny = (p.y - c.y) / ry
            let d = sqrt(nx * nx + ny * ny) // 1이면 테두리 위
            if inside && d <= 1 { return true }
            let band = (a.lineWidth + tol) / min(rx, ry)
            return abs(d - 1) <= band
        case .pen, .highlighter:
            let w = (a.kind == .pen ? a.lineWidth : a.highlighterWidth / 2) + tol
            let pts = a.points
            if pts.count == 1 { return p.distance(to: pts[0]) <= w }
            for i in 1..<max(1, pts.count) where distance(from: p, toSegment: pts[i - 1], pts[i]) <= w { return true }
            return false
        case .text:
            let local = rotate(p, around: textCenter(a), by: -a.angle)
            return textLocalRect(a).insetBy(dx: -tol, dy: -tol).contains(local)
        case .pixelate, .stamp:
            return bounds(of: a).insetBy(dx: -tol, dy: -tol).contains(p)
        }
    }

    // MARK: 손잡이

    enum Handle: Equatable {
        case p1, p2                // 화살표·선 양 끝
        case corner(Int)           // 0 왼위, 1 오위, 2 오아래, 3 왼아래
        case magnify               // 글자·스탬프 크기
        case rotate                // 글자 회전
    }

    /// `rotateOffset`: 회전 손잡이를 글자 위쪽으로 얼마나 띄울지(이미지 px)
    static func handles(of a: Annotation, rotateOffset: CGFloat = 0) -> [(Handle, CGPoint)] {
        switch a.kind {
        case .arrow, .line:
            return [(.p1, a.p1), (.p2, a.p2)]
        case .rect, .roundedRect, .ellipse, .pixelate:
            let r = a.rect
            return [(.corner(0), CGPoint(x: r.minX, y: r.minY)), (.corner(1), CGPoint(x: r.maxX, y: r.minY)),
                    (.corner(2), CGPoint(x: r.maxX, y: r.maxY)), (.corner(3), CGPoint(x: r.minX, y: r.maxY))]
        case .text:
            let cs = textCorners(a)
            let topMid = CGPoint(x: (cs[0].x + cs[1].x) / 2, y: (cs[0].y + cs[1].y) / 2)
            let up = CGPoint(x: sin(a.angle), y: -cos(a.angle))
            return [(.magnify, cs[2]), (.rotate, topMid + up * rotateOffset)]
        case .stamp:
            let b = bounds(of: a)
            return [(.magnify, CGPoint(x: b.maxX, y: b.maxY))]
        case .pen, .highlighter:
            return []
        }
    }

    /// 손잡이를 끌어 모양을 바꾼다
    static func apply(handle: Handle, to a: inout Annotation, point p: CGPoint, original: Annotation) {
        switch handle {
        case .p1: a.p1 = p
        case .p2: a.p2 = p
        case .corner(let i):
            let r = original.rect
            // 반대편 모서리를 고정하고 끌린 모서리를 p로
            let fixed: CGPoint
            switch i {
            case 0: fixed = CGPoint(x: r.maxX, y: r.maxY)
            case 1: fixed = CGPoint(x: r.minX, y: r.maxY)
            case 2: fixed = CGPoint(x: r.minX, y: r.minY)
            default: fixed = CGPoint(x: r.maxX, y: r.minY)
            }
            a.p1 = fixed; a.p2 = p
        case .magnify where original.kind == .text:
            // 글자는 가운데를 고정한 채 키운다 (회전해도 제자리)
            let c = textCenter(original)
            let oldDist = textCorners(original)[2].distance(to: c)
            guard oldDist > 1 else { return }
            let k = p.distance(to: c) / oldDist
            a.magnify = max(0.3, min(8, original.magnify * Double(k)))
            let size = textLocalRect(a).size
            let pad = a.fontSize * 0.12
            a.p1 = CGPoint(x: c.x - size.width / 2 + pad, y: c.y - size.height / 2 + pad)
        case .magnify:
            let ob = bounds(of: original)
            let anchor: CGPoint = original.kind == .stamp ? original.p1 : CGPoint(x: ob.minX, y: ob.minY)
            let oldDist = CGPoint(x: ob.maxX, y: ob.maxY).distance(to: anchor)
            guard oldDist > 1 else { return }
            let k = p.distance(to: anchor) / oldDist
            a.magnify = max(0.3, min(8, original.magnify * Double(k)))
        case .rotate:
            // 손잡이는 회전 0°일 때 위쪽(-90°)에 있다
            let c = textCenter(original)
            var t = atan2(p.y - c.y, p.x - c.x) + .pi / 2
            if t > .pi { t -= 2 * .pi }
            a.rotation = Double(t)
        }
    }

    // MARK: ⇧ 고정

    /// ⇧: 선·화살표는 45° 단위, 도형은 정사각·정원
    static func constrain(_ p: CGPoint, from start: CGPoint, kind: AnnotationKind) -> CGPoint {
        let v = p - start
        switch kind {
        case .arrow, .line:
            let ang = atan2(v.y, v.x)
            let snapped = (ang / (.pi / 4)).rounded() * (.pi / 4)
            let len = v.length
            return CGPoint(x: start.x + cos(snapped) * len, y: start.y + sin(snapped) * len)
        case .rect, .roundedRect, .ellipse, .pixelate:
            let s = max(abs(v.x), abs(v.y))
            return CGPoint(x: start.x + (v.x < 0 ? -s : s), y: start.y + (v.y < 0 ? -s : s))
        default:
            return p
        }
    }
}
