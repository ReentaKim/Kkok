import CoreGraphics
import Foundation

/// 캡처 하나의 보관 정보 (FR-33·34)
struct HistoryMeta: Codable, Equatable {
    var id: UUID
    var created: Date
    var name: String
    /// 이미지 배율(Retina 2)
    var scale: Double
    var state: DocumentState
    /// ~/Pictures/Kkok 에 쓴 합친 PNG 경로
    var exportedPath: String?
}

/// `<root>/history/<id>/` 에 original.png, doc.json, thumb.png를 둔다.
/// 합친 PNG는 `picturesDir/<이름>.png`에 쓴다.
final class HistoryStore {
    let root: URL
    let picturesDir: URL
    let fm = FileManager.default

    static let shared = HistoryStore(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kkok", isDirectory: true),
        picturesDir: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kkok", isDirectory: true))

    init(root: URL, picturesDir: URL) {
        self.root = root
        self.picturesDir = picturesDir
    }

    var historyDir: URL { root.appendingPathComponent("history", isDirectory: true) }

    func dir(for id: UUID) -> URL { historyDir.appendingPathComponent(id.uuidString, isDirectory: true) }

    static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f
    }()

    /// 새 캡처를 보관함에 넣는다 (원본은 한 번만 쓴다)
    func create(original: CGImage, scale: Double, created: Date = Date()) throws -> HistoryMeta {
        let id = UUID()
        let d = dir(for: id)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        guard let png = Renderer.pngData(original) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: d.appendingPathComponent("original.png"))
        let meta = HistoryMeta(id: id, created: created, name: uniqueName(Self.nameFormatter.string(from: created)),
                               scale: scale, state: DocumentState(imageSize: CGSize(width: original.width, height: original.height)))
        try writeMeta(meta)
        return meta
    }

    /// 같은 초에 두 번 찍어도 서로 덮어쓰지 않게 " 2", " 3"을 붙인다
    func uniqueName(_ base: String) -> String {
        var name = base, n = 2
        while fm.fileExists(atPath: picturesDir.appendingPathComponent(name + ".png").path)
                || recentNames.contains(name) {
            name = "\(base) \(n)"; n += 1
        }
        recentNames.insert(name)
        return name
    }

    /// 아직 PNG를 쓰기 전인 이름 (같은 초 연속 캡처 대비)
    private var recentNames = Set<String>()

    func writeMeta(_ meta: HistoryMeta) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(meta).write(to: dir(for: meta.id).appendingPathComponent("doc.json"), options: .atomic)
    }

    /// 편집 상태 저장 + 합친 PNG·썸네일 갱신
    @discardableResult
    func save(meta: HistoryMeta, base: CGImage) throws -> HistoryMeta {
        var m = meta
        if let flat = Renderer.flatten(base: base, state: meta.state), let png = Renderer.pngData(flat) {
            try fm.createDirectory(at: picturesDir, withIntermediateDirectories: true)
            let out = picturesDir.appendingPathComponent(meta.name + ".png")
            try png.write(to: out, options: .atomic)
            m.exportedPath = out.path
            if let thumb = Self.thumbnail(flat, maxSide: 240), let tp = Renderer.pngData(thumb) {
                try tp.write(to: dir(for: meta.id).appendingPathComponent("thumb.png"), options: .atomic)
            }
        }
        try writeMeta(m)
        return m
    }

    func load(id: UUID) -> (HistoryMeta, CGImage)? {
        let d = dir(for: id)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: d.appendingPathComponent("doc.json")),
              let meta = try? dec.decode(HistoryMeta.self, from: data),
              let img = Renderer.loadImage(d.appendingPathComponent("original.png"))
        else { return nil }
        return (meta, img)
    }

    /// 최근 순서 목록
    func recent(limit: Int = 15) -> [HistoryMeta] {
        guard let ids = try? fm.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: nil) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let metas = ids.compactMap { url -> HistoryMeta? in
            guard let data = try? Data(contentsOf: url.appendingPathComponent("doc.json")) else { return nil }
            return try? dec.decode(HistoryMeta.self, from: data)
        }
        return Array(metas.sorted { $0.created > $1.created }.prefix(limit))
    }

    func thumbnailURL(id: UUID) -> URL { dir(for: id).appendingPathComponent("thumb.png") }

    static func thumbnail(_ img: CGImage, maxSide: CGFloat) -> CGImage? {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let k = min(1, maxSide / max(w, h))
        let tw = max(1, Int(w * k)), th = max(1, Int(h * k))
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage()
    }
}
