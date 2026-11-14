// demo-base.swift — README·가이드용 가상의 앱 화면("Team Board")을 그린다. 1100×680, 배율 1
//   사용법: swift scripts/docs/demo-base.swift <출력.png>
import AppKit
let W: CGFloat = 1100, H: CGFloat = 680
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let g = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: g.cgContext, flipped: true)
let ctx = g.cgContext
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
func c(_ hex: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((hex>>16)&255)/255, green: CGFloat((hex>>8)&255)/255, blue: CGFloat(hex&255)/255, alpha: 1) }
func rect(_ r: CGRect, _ col: NSColor, radius: CGFloat = 0) { col.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() }
func text(_ s: String, _ p: CGPoint, _ size: CGFloat, _ col: NSColor = c(0x1d1d1f), weight: NSFont.Weight = .regular) {
  NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: col]).draw(at: p)
}
rect(CGRect(x: 0, y: 0, width: W, height: H), c(0xF5F6F8))
rect(CGRect(x: 0, y: 0, width: W, height: 56), .white)
rect(CGRect(x: 0, y: 55, width: W, height: 1), c(0xE3E5E8))
rect(CGRect(x: 24, y: 16, width: 24, height: 24), c(0x5B5BD6), radius: 7)
text("Team Board", CGPoint(x: 58, y: 17), 17, weight: .bold)
for (i, m) in ["대시보드", "프로젝트", "팀원", "설정"].enumerated() { text(m, CGPoint(x: 230 + CGFloat(i) * 92, y: 19), 14, i == 3 ? c(0x5B5BD6) : c(0x6E6E73), weight: i == 3 ? .semibold : .regular) }
rect(CGRect(x: W - 60, y: 13, width: 30, height: 30), c(0xD9DBF7), radius: 15)
rect(CGRect(x: 0, y: 56, width: 220, height: H - 56), .white)
rect(CGRect(x: 219, y: 56, width: 1, height: H - 56), c(0xE3E5E8))
for (i, m) in ["프로필", "알림", "보안", "결제", "연동"].enumerated() {
  if i == 0 { rect(CGRect(x: 12, y: 80 + CGFloat(i) * 44, width: 196, height: 36), c(0xEEEEFC), radius: 8) }
  text(m, CGPoint(x: 28, y: 88 + CGFloat(i) * 44), 14, i == 0 ? c(0x5B5BD6) : c(0x3A3A3C), weight: i == 0 ? .semibold : .regular)
}
rect(CGRect(x: 260, y: 90, width: 800, height: 540), .white, radius: 14)
text("프로필 설정", CGPoint(x: 296, y: 118), 24, weight: .bold)
text("다른 팀원에게 보이는 정보입니다.", CGPoint(x: 296, y: 156), 14, c(0x8E8E93))
rect(CGRect(x: 296, y: 200, width: 72, height: 72), c(0xD9DBF7), radius: 36)
text("사진 바꾸기", CGPoint(x: 390, y: 226), 14, c(0x5B5BD6), weight: .semibold)
let fields = [("이름", "홍길동"), ("이메일", "gildong.hong@example.com"), ("소속", "디자인팀")]
for (i, f) in fields.enumerated() {
  let y = 300 + CGFloat(i) * 76
  text(f.0, CGPoint(x: 296, y: y), 13, c(0x6E6E73), weight: .medium)
  rect(CGRect(x: 296, y: y + 22, width: 460, height: 40), c(0xF5F6F8), radius: 8)
  text(f.1, CGPoint(x: 310, y: y + 32), 15)
}
text("이메일로 알림 받기", CGPoint(x: 800, y: 322), 14, weight: .medium)
rect(CGRect(x: 800, y: 350, width: 48, height: 28), c(0x34C759), radius: 14)
rect(CGRect(x: 822, y: 352, width: 24, height: 24), .white, radius: 12)
rect(CGRect(x: 296, y: 556, width: 120, height: 44), c(0x5B5BD6), radius: 10)
text("저장하기", CGPoint(x: 326, y: 568), 16, .white, weight: .semibold)
text("취소", CGPoint(x: 440, y: 568), 16, c(0x6E6E73), weight: .medium)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
