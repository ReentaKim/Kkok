import AppKit

/// 이미지가 창보다 작으면 가운데에 둔다
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

/// 편집 캔버스. 주석 그리기·선택·옮기기·자르기·캔버스 넓히기 (FR-10~22)
final class CanvasView: NSView, NSTextViewDelegate, NSMenuItemValidation {
    let doc: EditorDocument
    private let tools = ToolState.shared

    /// 100% = 화면 pt 하나에 이미지 픽셀 `scale`개 (Retina 캡처가 원래 크기로 보임)
    var zoom: CGFloat = 1 { didSet { endTextEditing(); relayout(); onZoomChange?(zoom) } }
    var onZoomChange: ((CGFloat) -> Void)?
    var onOpenFiles: (([URL]) -> Void)?

    /// 이미지 둘레 여백 (가장자리 띠가 들어간다)
    let pad: CGFloat = 40
    let edgeBand: CGFloat = 22

    private(set) var selection: Set<UUID> = [] { didSet { needsDisplay = true } }

    private enum Drag {
        case none
        case create(id: UUID, before: DocumentState, start: CGPoint)
        case move(before: DocumentState, start: CGPoint, originals: [UUID: Annotation])
        case handle(id: UUID, handle: Geometry.Handle, original: Annotation, before: DocumentState)
        case crop(start: CGPoint)
        case cropHandle(index: Int, original: CGRect)
    }
    private var drag: Drag = .none

    /// 자르기 도구로 고르는 중인 범위 (이미지 좌표)
    private var cropRect: CGRect? { didSet { needsDisplay = true } }
    private var hoverEdge: DocumentState.Edge? { didSet { if oldValue != hoverEdge { needsDisplay = true } } }

    private var textView: NSTextView?
    private var editingID: UUID?
    private var editBefore: DocumentState?

    private var lastColor: RGBA
    private var lastSize: Int

    init(doc: EditorDocument) {
        self.doc = doc
        lastColor = ToolState.shared.color
        lastSize = ToolState.shared.size
        super.init(frame: .zero)
        doc.onChange = { [weak self] in self?.documentChanged() }
        registerForDraggedTypes([.fileURL])
        NotificationCenter.default.addObserver(self, selector: #selector(toolsChanged), name: ToolState.didChange, object: nil)
        relayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 좌표

    /// 화면 pt / 이미지 px
    var k: CGFloat { zoom / doc.scale }
    private var canvas: CGRect { doc.state.canvasRect }

    func toImage(_ v: CGPoint) -> CGPoint {
        CGPoint(x: (v.x - pad) / k + canvas.minX, y: (v.y - pad) / k + canvas.minY)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - canvas.minX) * k + pad, y: (p.y - canvas.minY) * k + pad)
    }

    func toView(_ r: CGRect) -> CGRect {
        let o = toView(r.origin)
        return CGRect(x: o.x, y: o.y, width: r.width * k, height: r.height * k)
    }

    var canvasViewRect: CGRect { CGRect(x: pad, y: pad, width: canvas.width * k, height: canvas.height * k) }

    /// 100%일 때 창에 필요한 크기
    var naturalSize: CGSize {
        CGSize(width: canvas.width / doc.scale + pad * 2, height: canvas.height / doc.scale + pad * 2)
    }

    func relayout() {
        let r = canvasViewRect
        setFrameSize(CGSize(width: ceil(r.width + pad * 2), height: ceil(r.height + pad * 2)))
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func documentChanged() {
        // 자르기·넓히기로 캔버스가 바뀌면 크기도 다시
        let want = CGSize(width: ceil(canvasViewRect.width + pad * 2), height: ceil(canvasViewRect.height + pad * 2))
        if want != frame.size { relayout() }
        // 지워진 주석은 선택에서 뺀다
        let ids = Set(doc.state.annotations.map(\.id))
        if !selection.isSubset(of: ids) { selection = selection.intersection(ids) }
        needsDisplay = true
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cv = canvasViewRect

        // 그림자
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 18, color: CGColor(gray: 0, alpha: 0.45))
        ctx.setFillColor(.white)
        ctx.fill(cv)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: cv)
        ctx.translateBy(x: pad, y: pad)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -canvas.minX, y: -canvas.minY)
        ctx.interpolationQuality = zoom >= 2 ? .none : .high
        Renderer.drawDocument(base: doc.base, state: doc.state, in: ctx, skip: editingID.map { [$0] } ?? [])
        ctx.restoreGState()

        drawSelection(ctx)
        drawCrop(ctx)
        drawEdgeHover(ctx)
    }

    private let selBlue = NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)

    private func drawSelection(_ ctx: CGContext) {
        guard editingID == nil else { return }
        let selected = doc.state.annotations.filter { selection.contains($0.id) }
        for a in selected {
            let r = toView(Geometry.bounds(of: a)).insetBy(dx: -3, dy: -3)
            ctx.saveGState()
            ctx.setStrokeColor(selBlue.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(r.integral.insetBy(dx: 0.5, dy: 0.5))
            ctx.restoreGState()
        }
        if selected.count == 1, let a = selected.first {
            for (h, p) in Geometry.handles(of: a) {
                let v = toView(p)
                let hr = CGRect(x: v.x - 4.5, y: v.y - 4.5, width: 9, height: 9)
                ctx.setFillColor(.white)
                ctx.setStrokeColor(selBlue.cgColor)
                ctx.setLineWidth(1.2)
                if case .p1 = h { ctx.fillEllipse(in: hr); ctx.strokeEllipse(in: hr) }
                else if case .p2 = h { ctx.fillEllipse(in: hr); ctx.strokeEllipse(in: hr) }
                else { ctx.fill(hr); ctx.stroke(hr) }
            }
        }
    }

    private func drawCrop(_ ctx: CGContext) {
        guard tools.tool == .crop, let cr = cropRect else { return }
        let v = toView(cr)
        ctx.saveGState()
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.5))
        ctx.addRect(canvasViewRect); ctx.addRect(v)
        ctx.fillPath(using: .evenOdd)
        ctx.setStrokeColor(.white); ctx.setLineWidth(1.5)
        ctx.stroke(v)
        // 삼분할 안내선
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35)); ctx.setLineWidth(0.8)
        for i in 1...2 {
            let x = v.minX + v.width * CGFloat(i) / 3, y = v.minY + v.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: v.minY)); ctx.addLine(to: CGPoint(x: x, y: v.maxY))
            ctx.move(to: CGPoint(x: v.minX, y: y)); ctx.addLine(to: CGPoint(x: v.maxX, y: y))
        }
        ctx.strokePath()
        for hr in cropHandleRects(v) { ctx.setFillColor(.white); ctx.fill(hr) }
        ctx.restoreGState()
        let label = "\(Int(cr.width)) × \(Int(cr.height))   ↩ 자르기 · esc 취소"
        drawBadge(label, at: CGPoint(x: v.midX, y: v.maxY + 18))
    }

    private func cropHandleRects(_ v: CGRect) -> [CGRect] {
        [CGPoint(x: v.minX, y: v.minY), CGPoint(x: v.maxX, y: v.minY), CGPoint(x: v.maxX, y: v.maxY), CGPoint(x: v.minX, y: v.maxY)]
            .map { CGRect(x: $0.x - 5, y: $0.y - 5, width: 10, height: 10) }
    }

    private func drawBadge(_ text: String, at center: CGPoint) {
        let s = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                              .foregroundColor: NSColor.white])
        let sz = s.size()
        var box = CGRect(x: center.x - sz.width / 2 - 10, y: center.y - sz.height / 2 - 4, width: sz.width + 20, height: sz.height + 8)
        box.origin.y = min(box.origin.y, bounds.maxY - box.height - 2)
        NSColor(white: 0, alpha: 0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        s.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 4))
    }

    // MARK: 캔버스 넓히기 띠 (FR-18)

    private func edgeRect(_ e: DocumentState.Edge) -> CGRect {
        let c = canvasViewRect
        switch e {
        case .top: return CGRect(x: c.minX, y: c.minY - edgeBand, width: c.width, height: edgeBand)
        case .bottom: return CGRect(x: c.minX, y: c.maxY, width: c.width, height: edgeBand)
        case .left: return CGRect(x: c.minX - edgeBand, y: c.minY, width: edgeBand, height: c.height)
        case .right: return CGRect(x: c.maxX, y: c.minY, width: edgeBand, height: c.height)
        }
    }

    private func edge(at v: CGPoint) -> DocumentState.Edge? {
        guard tools.tool != .crop else { return nil }
        return [DocumentState.Edge.top, .bottom, .left, .right].first { edgeRect($0).contains(v) }
    }

    private func drawEdgeHover(_ ctx: CGContext) {
        guard let e = hoverEdge, case .none = drag else { return }
        let r = edgeRect(e)
        NSColor(srgbRed: 0.988, green: 0.047, blue: 0.349, alpha: 0.35).setFill()
        NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        let s = NSAttributedString(string: "＋", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor.white])
        let sz = s.size()
        s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
    }

    // MARK: 커서

    override func resetCursorRects() {
        let c: NSCursor
        switch tools.tool {
        case .select: c = .arrow
        case .text: c = .iBeam
        default: c = .crosshair
        }
        addCursorRect(canvasViewRect, cursor: c)
        for e in [DocumentState.Edge.top, .bottom, .left, .right] { addCursorRect(edgeRect(e), cursor: .pointingHand) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with e: NSEvent) {
        hoverEdge = edge(at: convert(e.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) { hoverEdge = nil }

    // MARK: 마우스

    /// 화면 4pt를 이미지 픽셀로
    private var tolerance: CGFloat { 4 / k }

    override func mouseDown(with e: NSEvent) {
        if editingID != nil { endTextEditing(); return }
        window?.makeFirstResponder(self)
        let v = convert(e.locationInWindow, from: nil)
        let p = toImage(v)

        if let edge = edge(at: v) {
            doc.apply("캔버스 넓히기") { $0.expand(edge) }
            hoverEdge = nil
            return
        }

        if tools.tool == .crop {
            if let cr = cropRect {
                let vr = toView(cr)
                if let i = cropHandleRects(vr).firstIndex(where: { $0.insetBy(dx: -4, dy: -4).contains(v) }) {
                    drag = .cropHandle(index: i, original: cr); return
                }
            }
            drag = .crop(start: p)
            cropRect = CGRect(origin: p, size: .zero)
            return
        }

        // 선택한 주석의 손잡이
        if selection.count == 1, let id = selection.first, let a = annotation(id) {
            for (h, hp) in Geometry.handles(of: a) where toView(hp).distance(to: v) <= 7 {
                drag = .handle(id: id, handle: h, original: a, before: doc.state)
                return
            }
        }

        // 기존 주석 위
        if let hit = doc.state.annotations.reversed().first(where: {
            Geometry.hitTest($0, at: p, tolerance: tolerance, inside: tools.tool == .select)
        }) {
            if e.clickCount == 2, hit.kind == .text {
                selection = []
                beginTextEditing(id: hit.id, before: doc.state)
                return
            }
            if e.modifierFlags.contains(.shift) {
                if selection.contains(hit.id) { selection.remove(hit.id) } else { selection.insert(hit.id) }
            } else if !selection.contains(hit.id) {
                selection = [hit.id]
            }
            var originals: [UUID: Annotation] = [:]
            for a in doc.state.annotations where selection.contains(a.id) { originals[a.id] = a }
            drag = .move(before: doc.state, start: p, originals: originals)
            return
        }

        guard let kind = tools.annotationKind else {
            selection = []
            return
        }
        selection = []

        var a = Annotation(kind: kind, color: tools.color(for: kind), size: tools.size, scale: Double(doc.scale))
        let before = doc.state
        switch kind {
        case .text:
            a.p1 = CGPoint(x: p.x, y: p.y - a.fontSize * 0.65)
            doc.state.annotations.append(a)
            beginTextEditing(id: a.id, before: before)
            return
        case .stamp:
            a.p1 = p
            a.stamp = tools.stamp
            if a.stamp == .number { a.number = doc.state.nextStampNumber }
            doc.apply("스탬프") { $0.annotations.append(a) }
            selection = [a.id]
            return
        case .pen, .highlighter:
            a.points = [p]
        default:
            a.p1 = p; a.p2 = p
        }
        doc.state.annotations.append(a)
        drag = .create(id: a.id, before: before, start: p)
    }

    override func mouseDragged(with e: NSEvent) {
        let v = convert(e.locationInWindow, from: nil)
        var p = toImage(v)
        autoscroll(with: e)
        switch drag {
        case .none:
            break
        case let .create(id, _, start):
            update(id) { a in
                switch a.kind {
                case .pen, .highlighter:
                    Geometry.appendPoint(p, to: &a.points, minDistance: max(1, 1.5 / self.k))
                default:
                    if e.modifierFlags.contains(.shift) { p = Geometry.constrain(p, from: start, kind: a.kind) }
                    a.p2 = p
                }
            }
        case let .move(_, start, originals):
            var dx = p.x - start.x, dy = p.y - start.y
            if e.modifierFlags.contains(.shift) { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            var s = doc.state
            for i in s.annotations.indices {
                if let o = originals[s.annotations[i].id] {
                    var m = o; m.translate(dx: dx, dy: dy); s.annotations[i] = m
                }
            }
            doc.state = s
        case let .handle(id, h, original, _):
            if e.modifierFlags.contains(.shift) {
                if case .p2 = h { p = Geometry.constrain(p, from: original.p1, kind: original.kind) }
                if case .p1 = h { p = Geometry.constrain(p, from: original.p2, kind: original.kind) }
            }
            update(id) { a in Geometry.apply(handle: h, to: &a, point: p, original: original) }
        case let .crop(start):
            cropRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
                .intersection(canvas).integral
        case let .cropHandle(i, r):
            let fixed = [CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                         CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)][i]
            cropRect = CGRect(x: min(fixed.x, p.x), y: min(fixed.y, p.y), width: abs(p.x - fixed.x), height: abs(p.y - fixed.y))
                .intersection(canvas).integral
        }
    }

    override func mouseUp(with e: NSEvent) {
        let d = drag
        drag = .none
        switch d {
        case let .create(id, before, _):
            if let a = annotation(id), a.isDegenerate {
                doc.state = before // 클릭만 한 것은 없던 일로
            } else {
                doc.commit(from: before, actionName: "그리기")
                selection = [id]
            }
        case let .move(before, _, _):
            doc.commit(from: before, actionName: "옮기기")
        case let .handle(_, _, _, before):
            doc.commit(from: before, actionName: "크기 조절")
        case .crop:
            if let cr = cropRect, cr.width < 4 || cr.height < 4 { cropRect = nil }
        default:
            break
        }
        needsDisplay = true
    }

    private func annotation(_ id: UUID) -> Annotation? { doc.state.annotations.first { $0.id == id } }

    private func update(_ id: UUID, _ f: (inout Annotation) -> Void) {
        guard let i = doc.state.annotations.firstIndex(where: { $0.id == id }) else { return }
        var s = doc.state
        f(&s.annotations[i])
        doc.state = s
    }

    // MARK: 글자 편집 (FR-11)

    private func beginTextEditing(id: UUID, before: DocumentState) {
        guard let a = annotation(id) else { return }
        editingID = id
        editBefore = before
        textUndo = UndoManager()
        let tv = NSTextView(frame: .zero)
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.importsGraphics = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = CGSize(width: 100_000, height: 100_000)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.maxSize = CGSize(width: 100_000, height: 100_000)
        let font = NSFont(name: Geometry.textFontName, size: a.fontSize * k) ?? .boldSystemFont(ofSize: a.fontSize * k)
        let para = NSMutableParagraphStyle()
        let lh = Geometry.textLayout("A", fontSize: a.fontSize).lineHeight * k
        para.minimumLineHeight = lh
        para.maximumLineHeight = lh
        tv.typingAttributes = [.font: font, .foregroundColor: a.color.nsColor, .paragraphStyle: para]
        tv.font = font
        tv.textColor = a.color.nsColor
        tv.insertionPointColor = a.color.isLight ? .black : a.color.nsColor
        tv.string = a.text
        tv.setTextColor(a.color.nsColor, range: NSRange(location: 0, length: (a.text as NSString).length))
        tv.textStorage?.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: (a.text as NSString).length))
        tv.delegate = self
        // 흰 글자도 보이도록 옅은 그림자
        tv.shadow = { let s = NSShadow(); s.shadowColor = NSColor(white: a.color.isLight ? 0 : 1, alpha: 0.9); s.shadowBlurRadius = 2; return s }()
        textView = tv
        addSubview(tv)
        layoutTextView()
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)
        needsDisplay = true
    }

    private func layoutTextView() {
        guard let tv = textView, let id = editingID, let a = annotation(id) else { return }
        tv.sizeToFit()
        let origin = toView(a.p1)
        let w = max(tv.frame.width, 20), h = max(tv.frame.height, a.fontSize * k * 1.2)
        tv.frame = CGRect(x: origin.x, y: origin.y, width: w + 4, height: h)
    }

    /// 글자 입력 중 실행 취소는 문서 기록과 섞이지 않게 따로 둔다
    private var textUndo = UndoManager()
    func undoManager(for view: NSTextView) -> UndoManager? { textUndo }

    func textDidChange(_ notification: Notification) {
        guard let tv = textView, let id = editingID else { return }
        update(id) { $0.text = tv.string }
        layoutTextView()
    }

    func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { endTextEditing(); return true }
        return false
    }

    func textDidEndEditing(_ notification: Notification) {
        // 다른 곳을 눌러 포커스를 잃으면 마친다
        DispatchQueue.main.async { [weak self] in
            guard let self, let tv = self.textView, self.window?.firstResponder !== tv else { return }
            self.endTextEditing()
        }
    }

    func endTextEditing() {
        guard let id = editingID, let before = editBefore else { return }
        let tv = textView
        editingID = nil
        editBefore = nil
        textView = nil
        tv?.delegate = nil
        tv?.removeFromSuperview()
        if let a = annotation(id), a.isDegenerate {
            var s = doc.state
            s.annotations.removeAll { $0.id == id }
            doc.state = s
        }
        doc.commit(from: before, actionName: "글자")
        if annotation(id) != nil { selection = [id] }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    var isEditingText: Bool { editingID != nil }

    // MARK: 도구·스타일 변경

    @objc private func toolsChanged() {
        if tools.tool != .crop { cropRect = nil }
        if tools.tool == .crop { selection = [] }
        if editingID != nil, tools.tool != .text { endTextEditing() }
        // 선택한 주석의 색·굵기 바꾸기 (FR-19)
        if (tools.color != lastColor || tools.size != lastSize), !selection.isEmpty {
            let color = tools.color, size = tools.size
            let colorChanged = tools.color != lastColor
            doc.apply(colorChanged ? "색 바꾸기" : "굵기 바꾸기") { s in
                for i in s.annotations.indices where selection.contains(s.annotations[i].id) {
                    if colorChanged { s.annotations[i].color = color } else { s.annotations[i].size = size }
                }
            }
        }
        lastColor = tools.color
        lastSize = tools.size
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    // MARK: 키보드

    override func keyDown(with e: NSEvent) {
        let code = Int(e.keyCode)
        let mods = e.modifierFlags.intersection([.command, .control, .option])
        switch code {
        case 51, 117: deleteSelection(); return
        case 53:
            if cropRect != nil { cropRect = nil } else { selection = [] }
            return
        case 36, 76:
            applyCrop(); return
        case 123, 124, 125, 126:
            nudge(code, big: e.modifierFlags.contains(.shift)); return
        default: break
        }
        if mods.isEmpty, let ch = e.charactersIgnoringModifiers?.lowercased() {
            if let t = Tool.allCases.first(where: { $0.shortcut == ch }) { tools.tool = t; return }
            if let n = Int(ch), (1...3).contains(n) { tools.size = n; return }
        }
        super.keyDown(with: e)
    }

    func applyCrop() {
        guard let cr = cropRect, cr.width >= 4, cr.height >= 4 else { return }
        doc.apply("자르기") { $0.crop(to: cr) }
        cropRect = nil
    }

    private func nudge(_ code: Int, big: Bool) {
        guard !selection.isEmpty else { return }
        let step = (big ? 10 : 1) * doc.scale
        let (dx, dy): (CGFloat, CGFloat) = [123: (-step, 0), 124: (step, 0), 125: (0, step), 126: (0, -step)][code] ?? (0, 0)
        doc.apply("옮기기") { s in
            for i in s.annotations.indices where selection.contains(s.annotations[i].id) { s.annotations[i].translate(dx: dx, dy: dy) }
        }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        let sel = selection
        doc.apply("지우기") { $0.annotations.removeAll { sel.contains($0.id) } }
        selection = []
    }

    // MARK: 메뉴 동작

    @objc func copy(_ sender: Any?) { doc.copyToPasteboard() }
    @objc func delete(_ sender: Any?) { deleteSelection() }
    override func selectAll(_ sender: Any?) { selection = Set(doc.state.annotations.map(\.id)) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(delete(_:)) { return !selection.isEmpty && !isEditingText }
        return true
    }

    // MARK: 파일 끌어 놓기 (FR-07)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingSource == nil && imageURLs(sender).isEmpty == false ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageURLs(sender)
        guard !urls.isEmpty else { return false }
        onOpenFiles?(urls)
        return true
    }

    private func imageURLs(_ sender: NSDraggingInfo) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                          .urlReadingContentsConformToTypes: ["public.image"]]
        return sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
    }
}
