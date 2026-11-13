import AppKit

/// 아래 막대의 분홍 "끌어서 붙이기" 탭 (FR-30)
/// 끌면 합친 PNG를 임시 파일로 써서 파일 URL과 PNG 데이터를 함께 건넨다.
final class DragTabView: NSView, NSDraggingSource {
    weak var doc: EditorDocument?
    private var thumb: NSImage?
    private var sizeText = ""
    private var downPoint: CGPoint?
    private var pressed = false

    override var isFlipped: Bool { true }

    func refresh() {
        guard let doc else { return }
        let c = doc.state.canvasRect
        sizeText = "PNG · \(Int(c.width)) × \(Int(c.height))"
        if let cg = doc.flattened(), let t = HistoryStore.thumbnail(cg, maxSide: 120) {
            thumb = NSImage(cgImage: t, size: NSSize(width: t.width, height: t.height))
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let bg = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
        NSColor(srgbRed: 0.988, green: 0.047, blue: 0.349, alpha: pressed ? 0.8 : 1).setFill()
        bg.fill()
        // 썸네일
        let tr = CGRect(x: 7, y: 7, width: 46, height: r.height - 12)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: tr, xRadius: 4, yRadius: 4).fill()
        if let thumb {
            let s = thumb.size
            let k = min((tr.width - 4) / s.width, (tr.height - 4) / s.height)
            let w = s.width * k, h = s.height * k
            thumb.draw(in: CGRect(x: tr.midX - w / 2, y: tr.midY - h / 2, width: w, height: h),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let title = NSAttributedString(string: "끌어서 붙이기", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white])
        let sub = NSAttributedString(string: sizeText, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.85)])
        title.draw(at: CGPoint(x: tr.maxX + 10, y: 8))
        sub.draw(at: CGPoint(x: tr.maxX + 10, y: 26))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
        pressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        downPoint = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, let doc else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downPoint = nil
        pressed = false
        needsDisplay = true
        guard let url = doc.writeDragFile(), let png = try? Data(contentsOf: url) else { return }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(png, forType: .png)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        // 끄는 동안 보이는 그림 = 썸네일
        let img = thumb ?? NSImage(size: NSSize(width: 60, height: 40))
        let s = img.size
        let k = min(1, 160 / max(s.width, s.height))
        let frame = CGRect(x: p.x - s.width * k / 2, y: p.y - s.height * k / 2, width: s.width * k, height: s.height * k)
        dragItem.setDraggingFrame(frame, contents: img)
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }
}
