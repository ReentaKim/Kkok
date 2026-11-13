import AppKit

/// 손잡이 위에서 보이는 커서: 끄는 방향을 가리키는 ↔ 화살표, 회전은 둥근 화살표
enum HandleCursor {
    private static var cache: [Int: NSCursor] = [:]

    /// `along`: 화면(뒤집힌 뷰, y 아래) 기준 방향. 15° 단위로 맞춰 만들어 둔다
    static func resize(along d: CGPoint) -> NSCursor {
        // 커서 그림은 y 위 좌표라 y를 뒤집어 각도를 구한다
        var deg = Int((atan2(-d.y, d.x) * 180 / .pi).rounded())
        deg = ((deg % 180) + 180) % 180
        deg = (deg + 7) / 15 * 15 % 180
        if let c = cache[deg] { return c }
        let size: CGFloat = 24
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: size / 2, y: size / 2)
            ctx.rotate(by: CGFloat(deg) * .pi / 180)
            let path = CGMutablePath()
            let L: CGFloat = 9, head: CGFloat = 4.5, w: CGFloat = 1.6
            // 양쪽 화살촉이 달린 막대
            path.move(to: CGPoint(x: -L, y: 0))
            path.addLine(to: CGPoint(x: -L + head, y: head))
            path.addLine(to: CGPoint(x: -L + head, y: w))
            path.addLine(to: CGPoint(x: L - head, y: w))
            path.addLine(to: CGPoint(x: L - head, y: head))
            path.addLine(to: CGPoint(x: L, y: 0))
            path.addLine(to: CGPoint(x: L - head, y: -head))
            path.addLine(to: CGPoint(x: L - head, y: -w))
            path.addLine(to: CGPoint(x: -L + head, y: -w))
            path.addLine(to: CGPoint(x: -L + head, y: -head))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setStrokeColor(.white); ctx.setLineWidth(2.4); ctx.setLineJoin(.round)
            ctx.strokePath()
            ctx.addPath(path)
            ctx.setFillColor(.black); ctx.fillPath()
            return true
        }
        let c = NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
        cache[deg] = c
        return c
    }

    static let rotate: NSCursor = {
        let size: CGFloat = 24
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let c = CGPoint(x: size / 2, y: size / 2)
            func arrow() {
                ctx.addArc(center: c, radius: 7, startAngle: .pi * 0.15, endAngle: .pi * 1.55, clockwise: false)
            }
            ctx.setLineCap(.round)
            arrow(); ctx.setStrokeColor(.white); ctx.setLineWidth(4.2); ctx.strokePath()
            arrow(); ctx.setStrokeColor(.black); ctx.setLineWidth(1.8); ctx.strokePath()
            // 화살촉 (호의 시작점)
            let s = CGPoint(x: c.x + 7 * cos(.pi * 0.15), y: c.y + 7 * sin(.pi * 0.15))
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: s.x + 4, y: s.y + 1)); tri.addLine(to: CGPoint(x: s.x - 3.5, y: s.y + 3))
            tri.addLine(to: CGPoint(x: s.x, y: s.y - 4)); tri.closeSubpath()
            ctx.addPath(tri); ctx.setStrokeColor(.white); ctx.setLineWidth(2); ctx.setLineJoin(.round); ctx.strokePath()
            ctx.addPath(tri); ctx.setFillColor(.black); ctx.fillPath()
            return true
        }
        return NSCursor(image: img, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()
}
