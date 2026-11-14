// combine.swift — 각 이미지의 왼쪽 위 W×H 픽셀을 잘라 가로로 나란히 붙인다 (간격 24px)
//   사용법: swift scripts/docs/combine.swift <출력.png> <W> <H> <입력1.png> <입력2.png> ...
import AppKit
let args = Array(CommandLine.arguments.dropFirst())
let out = args[0], cw = Int(args[1])!, ch = Int(args[2])!
let crops: [CGImage] = args.dropFirst(3).compactMap { path in
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img.cropping(to: CGRect(x: 0, y: 0, width: min(cw, img.width), height: min(ch, img.height)))
}
let gap = 24
let w = crops.map(\.width).reduce(0, +) + gap * max(0, crops.count - 1)
let h = crops.map(\.height).max() ?? 0
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
var x = 0
for c in crops {
    ctx.draw(c, in: CGRect(x: x, y: h - c.height, width: c.width, height: c.height))
    x += c.width + gap
}
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out))
