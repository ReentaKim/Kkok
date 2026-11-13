#!/bin/bash
# generate-icons.sh — 앱 아이콘(AppIcon.icns)을 Swift 스크립트로 직접 그린다. 외부 도구·Skitch 그림 사용 안 함.
# 디자인 명세 7장: 분홍 둥근 사각 + 흰 굵은 화살표가 왼쪽 위 노란 점을 콕 짚는 모양
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Resources"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

cat > "$TMP/draw.swift" <<'SWIFT'
import AppKit

func arrow(_ ctx: CGContext, from tail: CGPoint, to tip: CGPoint, width w: CGFloat) -> CGPath {
    let vx = tip.x - tail.x, vy = tip.y - tail.y
    let len = hypot(vx, vy)
    let d = CGPoint(x: vx / len, y: vy / len), n = CGPoint(x: -d.y, y: d.x)
    func p(_ base: CGPoint, _ along: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: base.x + d.x * along + n.x * side, y: base.y + d.y * along + n.y * side)
    }
    let headLen = w * 3.0, headHalf = w * 1.35, tailW = w * 0.5
    let path = CGMutablePath()
    path.move(to: p(tail, 0, -tailW / 2))
    path.addArc(center: tail, radius: tailW / 2, startAngle: atan2(-n.y, -n.x), endAngle: atan2(n.y, n.x), clockwise: true)
    path.addLine(to: p(tip, -headLen * 0.82, w / 2))
    path.addLine(to: p(tip, -headLen, headHalf))
    path.addLine(to: tip)
    path.addLine(to: p(tip, -headLen, -headHalf))
    path.addLine(to: p(tip, -headLen * 0.82, -w / 2))
    path.closeSubpath()
    return path
}

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    // 바탕 (macOS 아이콘 격자: 가장자리 여백 ~10%)
    let bg = CGRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.3))
    let bgPath = CGPath(roundedRect: bg, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(srgbRed: 0.988, green: 0.047, blue: 0.349, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    // 위쪽 은은한 밝기
    ctx.saveGState()
    ctx.addPath(bgPath); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: bg.maxY), end: CGPoint(x: 0, y: bg.midY), options: [])
    ctx.restoreGState()
    // 노란 점 (왼쪽 위; CG는 y 위가 +)
    let dot = CGPoint(x: s * 0.33, y: s * 0.67)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: dot.x - s * 0.085, y: dot.y - s * 0.085, width: s * 0.17, height: s * 0.17))
    ctx.setStrokeColor(.white); ctx.setLineWidth(s * 0.018)
    ctx.strokeEllipse(in: CGRect(x: dot.x - s * 0.085, y: dot.y - s * 0.085, width: s * 0.17, height: s * 0.17))
    // 흰 화살표: 오른쪽 아래에서 점 가장자리로
    let tip = CGPoint(x: dot.x + s * 0.085, y: dot.y - s * 0.085)
    let a = arrow(ctx, from: CGPoint(x: s * 0.74, y: s * 0.26), to: tip, width: s * 0.075)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02, color: CGColor(gray: 0, alpha: 0.25))
    ctx.addPath(a); ctx.setFillColor(.white); ctx.fillPath()
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments[1]
for (name, px) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),
                   ("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),
                   ("icon_512x512",512),("icon_512x512@2x",1024)] {
    let rep = draw(size: CGFloat(px))
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
SWIFT

mkdir -p "$TMP/AppIcon.iconset"
swift "$TMP/draw.swift" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT/AppIcon.icns"
cp "$TMP/AppIcon.iconset/icon_512x512.png" "$ROOT/docs/design/icon.png"
echo "✔ $OUT/AppIcon.icns"
