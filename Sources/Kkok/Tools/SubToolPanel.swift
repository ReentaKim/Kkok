import AppKit

/// 하위 막대에 보여 줄 내용
enum SubPanelMode: Equatable {
    case shape, stamp, font, color
}

/// 도구 막대 오른쪽에서 캔버스 위로 덮어 열리는 좁은 하위 막대 (FR-26)
/// 도형·스탬프·글꼴은 도구를 고르면 자동으로 열리고, 색은 색 원을 누를 때만 열린다.
/// 항목 이름은 tooltip으로만 보인다.
final class SubToolPanel: NSView {
    static let width: CGFloat = 44

    private let tools = ToolState.shared
    private(set) var mode: SubPanelMode?
    private var items: [SubItemButton] = []

    /// 제약은 EditorWindowController가 만든다. leading은 열고 닫을 때 −width ↔ 0으로 움직인다.
    var leadingConstraint: NSLayoutConstraint?
    var topConstraint: NSLayoutConstraint?
    var heightConstraint: NSLayoutConstraint?

    /// 그 모드를 부른 버튼의 위쪽 y(도구 막대 좌표)와 도구 막대 높이
    var anchor: ((SubPanelMode) -> CGFloat)?
    var availableHeight: (() -> CGFloat)?
    /// 글자 주석을 골랐거나 쓰는 중인지 (글꼴 하위 막대)
    var textContext: (() -> Bool)?

    private var colorOpen = false
    private var collapsedFor: Tool?
    private var lastTool: Tool

    override var isFlipped: Bool { true }

    init() {
        lastTool = ToolState.shared.tool
        super.init(frame: .zero)
        wantsLayer = true
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor(white: 0, alpha: 0.28)
            s.shadowBlurRadius = 8
            s.shadowOffset = NSSize(width: 2, height: -1)
            return s
        }()
        // 닫힌 상태 = 도구 막대 뒤에 숨어 있음(leading −width, 투명). isHidden은 쓰지 않는다:
        // 창이 처음 그려지기 전에 숨김을 풀면 그려지지 않는 경우가 있었다.
        alphaValue = 0
        NotificationCenter.default.addObserver(self, selector: #selector(toolsChanged), name: ToolState.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 왼쪽은 도구 막대에 붙고 오른쪽 모서리만 둥근 판
    override func draw(_ dirtyRect: NSRect) {
        let r: CGFloat = 10
        let b = bounds.insetBy(dx: 0, dy: 0.5)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: b.minX, y: b.minY))
        path.line(to: CGPoint(x: b.maxX - r, y: b.minY))
        path.appendArc(withCenter: CGPoint(x: b.maxX - r, y: b.minY + r), radius: r, startAngle: 270, endAngle: 0)
        path.line(to: CGPoint(x: b.maxX, y: b.maxY - r))
        path.appendArc(withCenter: CGPoint(x: b.maxX - r, y: b.maxY - r), radius: r, startAngle: 0, endAngle: 90)
        path.line(to: CGPoint(x: b.minX, y: b.maxY))
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: 바깥에서 부르는 것

    /// 색 원을 눌렀을 때: 색 하위 막대를 열고 닫는다
    func toggleColor() {
        colorOpen.toggle()
        update()
    }

    /// 이미 고른 도구를 한 번 더 눌렀을 때: 그 도구의 하위 막대를 접고 편다
    func toggleCollapsed(for tool: Tool) {
        collapsedFor = collapsedFor == tool ? nil : tool
        colorOpen = false
        update()
    }

    /// 캔버스 선택이 바뀌었을 때
    func selectionChanged() { update() }

    // MARK: 상태 → 모드

    @objc private func toolsChanged() {
        if tools.tool != lastTool {
            lastTool = tools.tool
            collapsedFor = nil
        }
        update()
    }

    private var desiredMode: SubPanelMode? {
        if colorOpen { return .color }
        if collapsedFor == tools.tool { return nil }
        switch tools.tool {
        case .shape: return .shape
        case .stamp: return .stamp
        case .text: return .font
        default: return (textContext?() ?? false) ? .font : nil
        }
    }

    func update(animated: Bool = true) {
        let want = desiredMode
        if want == mode {
            if mode != nil { refreshItems(); position() }
            return
        }
        if let want {
            let wasHidden = mode == nil
            mode = want
            rebuild()
            position()
            if wasHidden { slide(open: true, animated: animated) }
        } else {
            mode = nil
            slide(open: false, animated: animated)
        }
    }

    // MARK: 열고 닫기

    private func slide(open: Bool, animated: Bool) {
        let target: CGFloat = open ? 0 : -Self.width
        // 창이 아직 화면에 그려지지 않았으면 애니메이션 없이 바로
        guard animated, window?.isVisible == true, window?.occlusionState.contains(.visible) == true else {
            leadingConstraint?.constant = target
            alphaValue = open ? 1 : 0
            // 제약만 바꾸면 다음 배치 때까지 제자리에 있으므로 바로 배치·그리기를 요청한다
            superview?.needsLayout = true
            superview?.layoutSubtreeIfNeeded()
            needsDisplay = true
            items.forEach { $0.needsDisplay = true }
            return
        }
        superview?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            leadingConstraint?.animator().constant = target
            animator().alphaValue = open ? 1 : 0
            superview?.layoutSubtreeIfNeeded()
        }
    }

    /// 부른 버튼 높이에 맞추되 도구 막대 아래로 넘치지 않게
    private func position() {
        guard let mode else { return }
        let h = contentHeight
        heightConstraint?.constant = h
        let avail = availableHeight?() ?? 600
        var top = (anchor?(mode) ?? 10) - 5
        top = min(top, avail - h - 6)
        topConstraint?.constant = max(6, top)
        superview?.needsLayout = true
    }

    // MARK: 항목

    private var pitch: CGFloat { mode == .color ? 30 : 38 }
    private var itemSize: CGFloat { mode == .color ? 28 : 36 }
    private var contentHeight: CGFloat { CGFloat(items.count) * pitch + 10 }

    private func rebuild() {
        items.forEach { $0.removeFromSuperview() }
        items = []
        guard let mode else { return }
        switch mode {
        case .shape:
            for s in ShapeKind.allCases {
                add(name: s.title, isOn: { [tools] in tools.shape == s },
                    pick: { [tools] in tools.shape = s; tools.tool = .shape }) { r, on in
                    let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
                        .applying(.init(paletteColors: [on ? ToolState.shared.color.visibleOnLight : .labelColor]))
                    guard let img = NSImage(systemSymbolName: s.symbol, accessibilityDescription: s.title)?
                        .withSymbolConfiguration(config) else { return }
                    let sz = img.size
                    img.draw(in: CGRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
                }
            }
        case .stamp:
            for s in StampKind.allCases {
                add(name: s.title, isOn: { [tools] in tools.stamp == s },
                    pick: { [tools] in tools.stamp = s; tools.tool = .stamp }) { r, _ in
                    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                    var a = Annotation(kind: .stamp, color: ToolState.shared.color, size: 1, scale: 1)
                    a.stamp = s; a.number = 1; a.p1 = CGPoint(x: r.midX, y: r.midY)
                    a.magnify = 24.0 / 34.0
                    Renderer.drawStamp(a, ctx)
                }
            }
        case .font:
            for f in TextFont.allCases where FontRegistry.isAvailable(f) {
                add(name: f.title, isOn: { [tools] in tools.font == f },
                    pick: { [tools] in tools.font = f }) { r, on in
                    let nf = NSFont(name: f.postScriptName, size: 19 * f.sizeFactor) ?? .boldSystemFont(ofSize: 19)
                    let s = NSAttributedString(string: "가", attributes: [
                        .font: nf, .foregroundColor: on ? ToolState.shared.color.visibleOnLight : NSColor.labelColor])
                    let sz = s.size()
                    s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
                }
            }
        case .color:
            for (name, c) in RGBA.paletteNamed {
                add(name: name, isOn: { [tools] in tools.color == c }, ring: true,
                    pick: { [weak self] in self?.tools.color = c; self?.colorOpen = false; self?.update() }) { r, _ in
                    let d = r.insetBy(dx: 5, dy: 5)
                    c.nsColor.setFill(); NSBezierPath(ovalIn: d).fill()
                    NSColor(white: 0, alpha: 0.18).setStroke(); NSBezierPath(ovalIn: d.insetBy(dx: 0.5, dy: 0.5)).stroke()
                }
            }
            add(name: "사용자 지정…", isOn: { false }, ring: true,
                pick: { [weak self] in self?.colorOpen = false; self?.update(); self?.openColorPanel() }) { r, _ in
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                    .applying(.init(paletteColors: [.secondaryLabelColor]))
                guard let img = NSImage(systemSymbolName: "plus", accessibilityDescription: "사용자 지정")?
                    .withSymbolConfiguration(config) else { return }
                let sz = img.size
                img.draw(in: CGRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
            }
        }
        for (i, b) in items.enumerated() {
            b.frame = CGRect(x: (Self.width - itemSize) / 2, y: 5 + CGFloat(i) * pitch + (pitch - itemSize) / 2,
                             width: itemSize, height: itemSize)
            addSubview(b)
        }
        needsDisplay = true
    }

    private func add(name: String, isOn: @escaping () -> Bool, ring: Bool = false,
                     pick: @escaping () -> Void, draw: @escaping (CGRect, Bool) -> Void) {
        let b = SubItemButton(isOn: isOn, ring: ring, action: pick, content: draw)
        b.toolTip = name
        b.setAccessibilityLabel(name)
        items.append(b)
    }

    private func refreshItems() { items.forEach { $0.needsDisplay = true } }

    // MARK: 사용자 지정 색

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.color = tools.color.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ panel: NSColorPanel) {
        tools.color = RGBA(panel.color)
    }
}

/// 하위 막대의 항목 하나. 고른 항목은 현재 색으로 테두리·옅은 바탕을 칠한다.
final class SubItemButton: NSView {
    private let isOn: () -> Bool
    private let ring: Bool
    private let action: () -> Void
    private let content: (CGRect, Bool) -> Void
    private var hover = false { didSet { needsDisplay = true } }

    init(isOn: @escaping () -> Bool, ring: Bool, action: @escaping () -> Void, content: @escaping (CGRect, Bool) -> Void) {
        self.isOn = isOn
        self.ring = ring
        self.action = action
        self.content = content
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let on = isOn()
        let accent = ToolState.shared.color.visibleOnLight
        if ring {
            let r = bounds.insetBy(dx: 1, dy: 1)
            if on {
                NSColor.labelColor.setStroke()
                let p = NSBezierPath(ovalIn: r); p.lineWidth = 1.6; p.stroke()
            } else if hover {
                NSColor.tertiaryLabelColor.setStroke()
                let p = NSBezierPath(ovalIn: r); p.lineWidth = 1.2; p.stroke()
            }
        } else {
            let bg = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            if on {
                accent.withAlphaComponent(0.14).setFill(); bg.fill()
                accent.setStroke(); bg.lineWidth = 1.5; bg.stroke()
            } else if hover {
                NSColor.quaternaryLabelColor.setFill(); bg.fill()
            }
        }
        content(bounds, on)
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

extension RGBA {
    /// 흰색처럼 밝은 색은 밝은 바탕에서 안 보이므로 회색으로 대신한다
    var visibleOnLight: NSColor { isLight ? .systemGray : nsColor }
}

extension StampKind {
    var title: String {
        switch self {
        case .check: return "승인 ✓"
        case .cross: return "거절 ✕"
        case .question: return "물음표 ?"
        case .exclamation: return "주의 !"
        case .star: return "완벽 ★"
        case .number: return "숫자 1·2·3"
        }
    }
}
