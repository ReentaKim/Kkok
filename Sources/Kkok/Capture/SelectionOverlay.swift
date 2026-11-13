import AppKit

/// 화면을 덮는 투명 창 (키 입력을 받으려고 canBecomeKey)
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 영역 선택 (FR-01·02)

/// 얼린 화면 위에서 영역을 고른다. 결과는 화면 안 좌표(왼쪽 위 원점, pt).
final class RegionSelector {
    enum Result {
        case selected(DisplayShot, CGRect, timed: Bool)
        case cancelled
    }

    private var windows: [OverlayWindow] = []
    private var completion: ((Result) -> Void)?
    private var finished = false
    let adjustFirst: Bool

    init(adjustFirst: Bool = false) { self.adjustFirst = adjustFirst }

    func begin(shots: [DisplayShot], completion: @escaping (Result) -> Void) {
        self.completion = completion
        for shot in shots {
            let w = OverlayWindow(screen: shot.screen)
            let v = RegionSelectView(shot: shot, owner: self)
            w.contentView = v
            w.orderFrontRegardless()
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        // 마우스가 있는 화면 창을 키 창으로 (Esc를 받으려고)
        let target = windows.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? windows.first
        target?.makeKey()
        if let v = target?.contentView { target?.makeFirstResponder(v) }
        NSCursor.crosshair.push()
    }

    /// 한 화면에서 고르기 시작하면 다른 화면의 십자선은 지운다
    fileprivate func didStartDrag(on view: RegionSelectView) {
        for w in windows { (w.contentView as? RegionSelectView)?.otherScreenActive = (w.contentView !== view) }
    }

    fileprivate func refreshAll() {
        for w in windows { w.contentView?.needsDisplay = true }
    }

    fileprivate func finish(_ r: Result) {
        guard !finished else { return }
        finished = true
        NSCursor.pop()
        for w in windows { w.orderOut(nil); w.contentView = nil }
        windows.removeAll()
        let c = completion
        completion = nil
        c?(r)
    }
}

final class RegionSelectView: NSView {
    let shot: DisplayShot
    weak var owner: RegionSelector?
    var otherScreenActive = false

    private var mouse: CGPoint?
    private var start: CGPoint?
    private var selection: CGRect?
    /// 조절 단계(⌥를 누른 채 놓았거나 설정으로 켰을 때)
    private var adjusting = false
    private var dragHandle: Int? // 0~3 모서리, 4 이동
    private var dragOrigin: (CGPoint, CGRect)?

    init(shot: DisplayShot, owner: RegionSelector) {
        self.shot = shot
        self.owner = owner
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        Renderer.drawImage(shot.image, in: bounds, ctx: ctx)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.35))
        if let sel = selection, sel.width > 0, sel.height > 0 {
            // 고른 곳만 밝게
            ctx.addRect(bounds); ctx.addRect(sel)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
            ctx.setLineWidth(1)
            ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))
            if adjusting { drawHandles(sel, ctx) }
            drawSizeLabel(for: sel, near: adjusting ? CGPoint(x: sel.maxX, y: sel.maxY) : (mouse ?? CGPoint(x: sel.maxX, y: sel.maxY)), ctx: ctx)
        } else {
            // 끌기 전에는 어둡게 덮지 않고 십자선만 (사용자 피드백 2026-11-13)
            if let m = mouse, !otherScreenActive {
                // 십자선
                ctx.setLineWidth(1)
                ctx.setShadow(offset: .zero, blur: 2, color: CGColor(gray: 0, alpha: 0.8))
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
                ctx.move(to: CGPoint(x: 0, y: m.y.rounded() + 0.5)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: m.y.rounded() + 0.5))
                ctx.move(to: CGPoint(x: m.x.rounded() + 0.5, y: 0)); ctx.addLine(to: CGPoint(x: m.x.rounded() + 0.5, y: bounds.maxY))
                ctx.strokePath()
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
            }
        }
        if adjusting, let sel = selection { drawButtons(sel) }
    }

    private func drawSizeLabel(for sel: CGRect, near p: CGPoint, ctx: CGContext) {
        drawSizeLabel(text: "\(Int(sel.width.rounded())) × \(Int(sel.height.rounded()))", near: p, ctx: ctx)
    }

    private func drawSizeLabel(text: String, near p: CGPoint, ctx: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        var box = CGRect(x: p.x + 14, y: p.y + 14, width: sz.width + 14, height: sz.height + 8)
        if box.maxX > bounds.maxX - 4 { box.origin.x = p.x - box.width - 14 }
        if box.maxY > bounds.maxY - 4 { box.origin.y = p.y - box.height - 14 }
        let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
        NSColor(white: 0, alpha: 0.75).setFill(); path.fill()
        s.draw(at: CGPoint(x: box.minX + 7, y: box.minY + 4))
    }

    private func handleRects(_ sel: CGRect) -> [CGRect] {
        [CGPoint(x: sel.minX, y: sel.minY), CGPoint(x: sel.maxX, y: sel.minY),
         CGPoint(x: sel.maxX, y: sel.maxY), CGPoint(x: sel.minX, y: sel.maxY)]
            .map { CGRect(x: $0.x - 5, y: $0.y - 5, width: 10, height: 10) }
    }

    private func drawHandles(_ sel: CGRect, _ ctx: CGContext) {
        for r in handleRects(sel) {
            ctx.setFillColor(.white); ctx.fill(r)
            ctx.setStrokeColor(NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1).cgColor)
            ctx.setLineWidth(1); ctx.stroke(r)
        }
    }

    // 조절 단계의 "캡처" "타이머" 버튼 (직접 그린다)
    private var buttonRects: (capture: CGRect, timed: CGRect)?

    private func drawButtons(_ sel: CGRect) {
        let w: CGFloat = 76, h: CGFloat = 28, gap: CGFloat = 8
        var y = sel.maxY + 10
        if y + h > bounds.maxY - 8 { y = sel.maxY - h - 10 }
        let x = min(max(sel.maxX - (w * 2 + gap), 8), bounds.maxX - (w * 2 + gap) - 8)
        let timed = CGRect(x: x, y: y, width: w, height: h)
        let cap = CGRect(x: x + w + gap, y: y, width: w, height: h)
        buttonRects = (cap, timed)
        for (r, title, primary) in [(timed, "\(Preferences.shared.timerSeconds)초 후", false), (cap, "캡처 ↩", true)] {
            let p = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
            (primary ? NSColor(srgbRed: 0.988, green: 0.047, blue: 0.349, alpha: 1) : NSColor(white: 0.15, alpha: 0.9)).setFill()
            p.fill()
            let s = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                                  .foregroundColor: NSColor.white])
            let sz = s.size()
            s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
        }
    }

    // MARK: 마우스

    private func point(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    override func mouseMoved(with e: NSEvent) {
        mouse = point(e)
        owner?.didStartDrag(on: self)
        for w in NSApp.windows where w is OverlayWindow { w.contentView?.needsDisplay = true }
        if window?.isKeyWindow == false { window?.makeKey(); window?.makeFirstResponder(self) }
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        let p = point(e)
        if adjusting, let sel = selection {
            if let b = buttonRects {
                if b.capture.contains(p) { accept(timed: false); return }
                if b.timed.contains(p) { accept(timed: true); return }
            }
            if let i = handleRects(sel).firstIndex(where: { $0.insetBy(dx: -4, dy: -4).contains(p) }) {
                dragHandle = i; dragOrigin = (p, sel); return
            }
            if sel.contains(p) { dragHandle = 4; dragOrigin = (p, sel); return }
            // 바깥을 누르면 새로 고르기
            adjusting = false
        }
        owner?.didStartDrag(on: self)
        start = p
        selection = CGRect(origin: p, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        let p = point(e)
        mouse = p
        if let h = dragHandle, let (o, r) = dragOrigin {
            var nr = r
            switch h {
            case 4:
                nr.origin.x = min(max(0, r.minX + p.x - o.x), bounds.width - r.width)
                nr.origin.y = min(max(0, r.minY + p.y - o.y), bounds.height - r.height)
            default:
                let fixed = [CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                             CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)][h]
                nr = CGRect(x: min(fixed.x, p.x), y: min(fixed.y, p.y), width: abs(p.x - fixed.x), height: abs(p.y - fixed.y))
            }
            selection = nr
        } else if let s = start {
            var q = p
            if e.modifierFlags.contains(.shift) { q = Geometry.constrain(p, from: s, kind: .rect) }
            selection = CGRect(x: min(s.x, q.x), y: min(s.y, q.y), width: abs(q.x - s.x), height: abs(q.y - s.y))
                .intersection(bounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        if dragHandle != nil { dragHandle = nil; dragOrigin = nil; needsDisplay = true; return }
        guard let sel = selection else { return }
        start = nil
        if sel.width < 4 || sel.height < 4 {
            // 클릭만 했으면 다시 십자선으로
            selection = nil; needsDisplay = true; return
        }
        if (owner?.adjustFirst ?? false) || e.modifierFlags.contains(.option) {
            adjusting = true
            needsDisplay = true
        } else {
            accept(timed: false)
        }
    }

    private func accept(timed: Bool) {
        guard let sel = selection else { return }
        owner?.finish(.selected(shot, sel.integral, timed: timed))
    }

    // MARK: 키보드

    override func keyDown(with e: NSEvent) {
        switch Int(e.keyCode) {
        case 53: owner?.finish(.cancelled) // Esc
        case 36, 76: if selection != nil { accept(timed: false) } // Enter
        default: super.keyDown(with: e)
        }
    }

    override func cancelOperation(_ sender: Any?) { owner?.finish(.cancelled) }
}

// MARK: - 창 선택 (FR-04)

final class WindowSelector {
    private var windows: [OverlayWindow] = []
    private var completion: ((CGWindowID?) -> Void)?
    fileprivate var candidates: [(id: CGWindowID, frame: CGRect, owner: String)] = []
    fileprivate var hovered: (id: CGWindowID, frame: CGRect, owner: String)?
    private var done = false

    func begin(completion: @escaping (CGWindowID?) -> Void) {
        self.completion = completion
        candidates = ScreenCapturer.visibleWindows()
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen)
            w.contentView = WindowSelectView(screen: screen, owner: self)
            w.orderFrontRegardless()
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        let target = windows.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? windows.first
        target?.makeKey()
        if let v = target?.contentView { target?.makeFirstResponder(v) }
        updateHover()
        NSCursor.pointingHand.push()
    }

    /// 마우스 아래 가장 앞 창
    fileprivate func updateHover() {
        let m = NSEvent.mouseLocation
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: m.x, y: primaryH - m.y)
        hovered = candidates.first { $0.frame.contains(p) }
        for w in windows { w.contentView?.needsDisplay = true }
    }

    fileprivate func finish(_ id: CGWindowID?) {
        guard !done else { return }
        done = true
        NSCursor.pop()
        for w in windows { w.orderOut(nil); w.contentView = nil }
        windows.removeAll()
        let c = completion; completion = nil
        c?(id)
    }
}

final class WindowSelectView: NSView {
    let screen: NSScreen
    weak var owner: WindowSelector?

    init(screen: NSScreen, owner: WindowSelector) {
        self.screen = screen
        self.owner = owner
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let h = owner?.hovered else {
            NSColor(white: 0, alpha: 0.15).setFill(); bounds.fill(); return
        }
        let origin = screen.cgFrame.origin
        let r = h.frame.offsetBy(dx: -origin.x, dy: -origin.y)
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.25).setFill()
        r.fill()
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.9).setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: 1.5, dy: 1.5)); p.lineWidth = 3; p.stroke()
        if bounds.intersects(r) {
            let s = NSAttributedString(string: "\(h.owner)  \(Int(h.frame.width)) × \(Int(h.frame.height))",
                                       attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
            let sz = s.size()
            let box = CGRect(x: r.midX - sz.width / 2 - 10, y: r.midY - sz.height / 2 - 6, width: sz.width + 20, height: sz.height + 12)
            NSColor(white: 0, alpha: 0.7).setFill()
            NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            s.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 6))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        owner?.updateHover()
        if window?.isKeyWindow == false { window?.makeKey(); window?.makeFirstResponder(self) }
    }

    override func mouseDown(with event: NSEvent) {
        owner?.updateHover()
        owner?.finish(owner?.hovered?.id)
    }

    override func keyDown(with e: NSEvent) {
        if e.keyCode == 53 { owner?.finish(nil) } else { super.keyDown(with: e) }
    }
}

// MARK: - 카운트다운 (FR-06)

final class CountdownWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private var remaining = 0
    private var timer: Timer?
    private var frameWindow: NSPanel?

    init(screen: NSScreen, highlight: CGRect?) {
        let size: CGFloat = 120
        let rect = CGRect(x: screen.frame.midX - size / 2, y: screen.frame.midY - size / 2, width: size, height: size)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSView(frame: CGRect(origin: .zero, size: rect.size))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 0, alpha: 0.6).cgColor
        v.layer?.cornerRadius = size / 2
        label.font = .monospacedDigitSystemFont(ofSize: 56, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.frame = CGRect(x: 0, y: (size - 70) / 2, width: size, height: 70)
        v.addSubview(label)
        contentView = v

        // 찍힐 영역 테두리
        if let h = highlight {
            let f = CGRect(x: screen.frame.minX + h.minX - 2, y: screen.frame.maxY - h.maxY - 2, width: h.width + 4, height: h.height + 4)
            let fw = NSPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            fw.level = .screenSaver
            fw.isOpaque = false
            fw.backgroundColor = .clear
            fw.ignoresMouseEvents = true
            let bv = NSView(frame: CGRect(origin: .zero, size: f.size))
            bv.wantsLayer = true
            bv.layer?.borderColor = NSColor(srgbRed: 0.988, green: 0.047, blue: 0.349, alpha: 0.9).cgColor
            bv.layer?.borderWidth = 2
            fw.contentView = bv
            frameWindow = fw
        }
    }

    func run(seconds: Int, completion: @escaping () -> Void) {
        remaining = seconds
        label.stringValue = "\(remaining)"
        orderFrontRegardless()
        frameWindow?.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            self.remaining -= 1
            if self.remaining <= 0 {
                t.invalidate()
                self.orderOut(nil)
                self.frameWindow?.orderOut(nil)
                // 창이 사라진 뒤에 찍도록 잠깐 기다린다
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { completion() }
            } else {
                self.label.stringValue = "\(self.remaining)"
            }
        }
    }
}
