import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 원본 이미지 + 편집 상태를 그린다. 화면과 내보내기가 같은 코드를 쓴다.
///
/// 모든 함수는 "이미지 좌표, 왼쪽 위 원점, y 아래로 증가"로 뒤집힌 CGContext를 받는다.
enum Renderer {

    // MARK: 전체

    /// 캔버스 배경(넓힌 부분은 흰색) + 원본 + 주석
    static func drawDocument(base: CGImage, state: DocumentState, in ctx: CGContext,
                             skip: Set<UUID> = []) {
        if state.needsBackground {
            ctx.setFillColor(RGBA.white.cgColor)
            ctx.fill(state.canvasRect)
        }
        drawImage(base, in: CGRect(origin: .zero, size: state.imageSize), ctx: ctx)
        for a in state.annotations where !skip.contains(a.id) {
            draw(a, base: base, in: ctx)
        }
    }

    /// 주석을 합쳐 캔버스 범위만큼의 이미지로 만든다 (FR-30~33)
    static func flatten(base: CGImage, state: DocumentState) -> CGImage? {
        let r = state.canvasRect.integral
        let w = Int(r.width), h = Int(r.height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // 이미지 좌표(y 아래)로 맞추고 캔버스 원점을 0으로
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -r.minX, y: -r.minY)
        ctx.interpolationQuality = .high
        drawDocument(base: base, state: state, in: ctx)
        return ctx.makeImage()
    }

    /// y 아래 좌표계에서 이미지를 바로 선 채로 그린다
    static func drawImage(_ img: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    // MARK: 주석 하나

    static func draw(_ a: Annotation, base: CGImage?, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        switch a.kind {
        case .arrow:
            let path = Geometry.arrowPath(from: a.p1, to: a.p2, width: a.arrowWidth)
            ctx.addPath(path)
            ctx.setStrokeColor(a.outlineColor.cgColor)
            ctx.setLineWidth(a.outlineExtra)
            ctx.strokePath()
            ctx.addPath(path)
            ctx.setFillColor(a.color.cgColor)
            ctx.fillPath()

        case .line:
            let path = CGMutablePath()
            path.move(to: a.p1); path.addLine(to: a.p2)
            strokeWithOutline(path, a, ctx)

        case .rect:
            strokeWithOutline(CGPath(rect: a.rect, transform: nil), a, ctx)

        case .roundedRect:
            let r = a.rect
            let rad = min(a.lineWidth * 2.4, min(r.width, r.height) / 2)
            strokeWithOutline(CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil), a, ctx)

        case .ellipse:
            strokeWithOutline(CGPath(ellipseIn: a.rect, transform: nil), a, ctx)

        case .pen:
            strokeWithOutline(Geometry.smoothPath(a.points), a, ctx)

        case .highlighter:
            let path = Geometry.smoothPath(a.points)
            ctx.addPath(path)
            ctx.setLineCap(.square)
            ctx.setLineWidth(a.highlighterWidth)
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(a.color.withAlpha(0.55).cgColor)
            ctx.strokePath()

        case .pixelate:
            if let base { drawPixelate(a.rect, base: base, scale: a.scale, ctx: ctx) }

        case .text:
            drawText(a, ctx)

        case .stamp:
            drawStamp(a, ctx)
        }
    }

    /// 흰 외곽선을 먼저, 그 위에 색 선
    private static func strokeWithOutline(_ path: CGPath, _ a: Annotation, _ ctx: CGContext) {
        ctx.addPath(path)
        ctx.setStrokeColor(a.outlineColor.cgColor)
        ctx.setLineWidth(a.lineWidth + a.outlineExtra)
        ctx.strokePath()
        ctx.addPath(path)
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setLineWidth(a.lineWidth)
        ctx.strokePath()
    }

    // MARK: 모자이크 (FR-15)

    static func pixelCell(for rect: CGRect, scale: Double) -> CGFloat {
        max(8 * CGFloat(scale), (min(rect.width, rect.height) / 12).rounded())
    }

    /// 원본에서 그 범위를 잘라 작게 줄였다가 보간 없이 키워 그린다.
    static func drawPixelate(_ rect: CGRect, base: CGImage, scale: Double, ctx: CGContext) {
        let imgBounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let r = rect.integral.intersection(imgBounds)
        guard !r.isNull, r.width >= 1, r.height >= 1, let crop = base.cropping(to: r) else { return }
        let cell = pixelCell(for: r, scale: scale)
        let sw = max(1, Int(ceil(r.width / cell))), sh = max(1, Int(ceil(r.height / cell)))
        guard let small = CGContext(data: nil, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        small.interpolationQuality = .high // 칸마다 평균 색이 되도록
        small.draw(crop, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let tiny = small.makeImage() else { return }
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.interpolationQuality = .none
        // 칸이 범위를 넘치지 않게 칸 크기 그대로 키운다
        drawImage(tiny, in: CGRect(x: r.minX, y: r.minY, width: CGFloat(sw) * cell, height: CGFloat(sh) * cell), ctx: ctx)
        ctx.restoreGState()
    }

    // MARK: 글자 (FR-11)

    static func drawText(_ a: Annotation, _ ctx: CGContext) {
        let layout = Geometry.textLayout(a.text, fontSize: a.fontSize)
        ctx.saveGState()
        ctx.textMatrix = .identity
        for (i, line) in layout.lines.enumerated() {
            // 고정 줄 높이에서 남는 공간은 위쪽에 (편집 중 NSTextView와 같은 위치, BUG-06)
            let baseline = a.p1.y + CGFloat(i) * layout.lineHeight + layout.lineHeight - layout.descent
            ctx.saveGState()
            // y 아래 좌표계에서 글자가 뒤집히지 않도록 그 줄만 다시 뒤집는다
            ctx.translateBy(x: a.p1.x, y: baseline)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero

            // 외곽선
            ctx.setTextDrawingMode(.stroke)
            ctx.setLineWidth(a.fontSize * 0.18)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(a.outlineColor.cgColor)
            drawLine(line, stroke: a.outlineColor.cgColor, ctx: ctx)

            ctx.textPosition = .zero
            ctx.setTextDrawingMode(.fill)
            drawLine(line, fill: a.color.cgColor, ctx: ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// CTLine의 글자 색은 속성에서 오므로, 색을 지정해 다시 만든다
    private static func drawLine(_ line: CTLine, fill: CGColor? = nil, stroke: CGColor? = nil, ctx: CGContext) {
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let font = attrs[kCTFontAttributeName as String] as! CTFont
            if let fill { ctx.setFillColor(fill) }
            if let stroke { ctx.setStrokeColor(stroke) }
            CTFontDrawGlyphs(font, glyphs, positions, count, ctx)
        }
    }

    // MARK: 스탬프 (FR-16)

    static func drawStamp(_ a: Annotation, _ ctx: CGContext) {
        let d = a.stampDiameter
        let c = a.p1
        let circle = CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
        let fill = a.stamp.fill ?? a.color
        ctx.setShadow(offset: CGSize(width: 0, height: 1 * a.scale), blur: 3 * a.scale,
                      color: CGColor(gray: 0, alpha: 0.35))
        ctx.setFillColor(RGBA.white.cgColor)
        ctx.fillEllipse(in: circle.insetBy(dx: -3 * a.scale, dy: -3 * a.scale))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setFillColor(fill.cgColor)
        ctx.fillEllipse(in: circle)

        let glyphColor: CGColor = (fill.isLight ? RGBA.black : RGBA.white).cgColor
        let u = d / 2 // 반지름 단위
        ctx.setStrokeColor(glyphColor)
        ctx.setFillColor(glyphColor)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setLineWidth(u * 0.26)

        switch a.stamp {
        case .check:
            ctx.move(to: CGPoint(x: c.x - u * 0.45, y: c.y + u * 0.02))
            ctx.addLine(to: CGPoint(x: c.x - u * 0.12, y: c.y + u * 0.36))
            ctx.addLine(to: CGPoint(x: c.x + u * 0.48, y: c.y - u * 0.34))
            ctx.strokePath()
        case .cross:
            let k = u * 0.36
            ctx.move(to: CGPoint(x: c.x - k, y: c.y - k)); ctx.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
            ctx.move(to: CGPoint(x: c.x + k, y: c.y - k)); ctx.addLine(to: CGPoint(x: c.x - k, y: c.y + k))
            ctx.strokePath()
        case .star:
            let path = CGMutablePath()
            for i in 0..<10 {
                let ang = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let rr = i % 2 == 0 ? u * 0.62 : u * 0.26
                let p = CGPoint(x: c.x + cos(ang) * rr, y: c.y + sin(ang) * rr + u * 0.04)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            ctx.addPath(path); ctx.fillPath()
        case .question, .exclamation, .number:
            let s = a.stamp == .number ? String(a.number) : (a.stamp == .question ? "?" : "!")
            let fs = (s.count >= 2 ? u * 0.95 : u * 1.2)
            drawCenteredGlyph(s, center: c, fontSize: fs, color: glyphColor, ctx: ctx)
        }
    }

    private static func drawCenteredGlyph(_ s: String, center c: CGPoint, fontSize: CGFloat, color: CGColor, ctx: CGContext) {
        let f = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): f]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        let b = CTLineGetImageBounds(line, nil)
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: c.x - b.midX, y: c.y + b.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        ctx.setTextDrawingMode(.fill)
        drawLine(line, fill: color, ctx: ctx)
        ctx.restoreGState()
    }

    // MARK: 파일

    static func pngData(_ img: CGImage) -> Data? {
        encode(img, type: .png, quality: nil)
    }

    static func encode(_ img: CGImage, type: UTType, quality: Double?) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary)
    }

    static func loadImage(data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
