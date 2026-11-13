import AppKit

/// 편집 창 하나의 문서. 상태 변경·실행 취소·자동 저장을 맡는다 (FR-21·33)
final class EditorDocument {
    private(set) var meta: HistoryMeta
    let base: CGImage
    let store: HistoryStore

    var state: DocumentState {
        get { meta.state }
        set { meta.state = newValue; onChange?() }
    }

    var scale: CGFloat { CGFloat(meta.scale) }
    var name: String { meta.name }

    var onChange: (() -> Void)?
    weak var undoManager: UndoManager?

    private var saveWork: DispatchWorkItem?

    init(meta: HistoryMeta, base: CGImage, store: HistoryStore = .shared) {
        self.meta = meta
        self.base = base
        self.store = store
    }

    /// 새 캡처로 문서를 만들고 바로 보관함에 넣는다
    static func create(image: CGImage, scale: CGFloat, store: HistoryStore = .shared) -> EditorDocument? {
        guard let meta = try? store.create(original: image, scale: Double(scale)) else { return nil }
        let doc = EditorDocument(meta: meta, base: image, store: store)
        doc.saveNow()
        return doc
    }

    // MARK: 실행 취소

    /// 한 번의 편집 동작을 마친 뒤 부른다. 이전 상태로 되돌리는 기록을 남긴다.
    func commit(from before: DocumentState, actionName: String) {
        guard before != state else { return }
        registerUndo(restoring: before, actionName: actionName)
        scheduleSave()
    }

    private func registerUndo(restoring old: DocumentState, actionName: String) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { doc in
            let current = doc.state
            doc.state = old
            doc.registerUndo(restoring: current, actionName: actionName)
            doc.scheduleSave()
        }
        um.setActionName(actionName)
    }

    /// 상태를 바꾸고 바로 실행 취소 기록까지 남긴다
    func apply(_ actionName: String, _ change: (inout DocumentState) -> Void) {
        let before = state
        var s = state
        change(&s)
        state = s
        commit(from: before, actionName: actionName)
    }

    // MARK: 저장

    func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        if let m = try? store.save(meta: meta, base: base) { meta.exportedPath = m.exportedPath }
        NotificationCenter.default.post(name: EditorDocument.didSave, object: self)
    }

    static let didSave = Notification.Name("KkokDocumentDidSave")

    // MARK: 내보내기

    func flattened() -> CGImage? { Renderer.flatten(base: base, state: state) }

    /// 끌기·복사용 NSImage (pt 크기는 픽셀/배율 → Retina에서 제 크기로 보이게)
    func flattenedNSImage() -> NSImage? {
        guard let cg = flattened() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }

    /// 끌기용 임시 PNG 파일 (FR-30)
    func writeDragFile() -> URL? {
        guard let cg = flattened(), let png = Renderer.pngData(cg) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Kkok-drag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        do { try png.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// ⌘C (FR-31)
    func copyToPasteboard() {
        guard let cg = flattened(), let png = Renderer.pngData(cg) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = flattenedNSImage()?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.writeObjects([item])
    }
}
