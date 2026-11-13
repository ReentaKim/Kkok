import AppKit

/// 왼쪽 세로 도구 막대 (디자인 명세 1장)
final class ToolPaletteView: NSView {
    private let tools = ToolState.shared
    private var buttons: [Tool: ToolButton] = [:]
    private let swatch = SwatchView()
    private var sizeDots: [SizeDot] = []
    private let fontButton = FontButton()
    private var colorPopover: NSPopover?

    override var isFlipped: Bool { true }

    /// 도구가 잘리지 않는 최소 높이 (BUG-01)
    private(set) var requiredHeight: CGFloat = 0

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        var y: CGFloat = 10
        for t in Tool.allCases {
            let b = ToolButton(tool: t)
            b.frame = CGRect(x: 10, y: y, width: 36, height: 36)
            b.onClick = { [weak self] in self?.clicked(t, button: b) }
            b.onMenu = { [weak self] in self?.showSubmenu(t, button: b) }
            addSubview(b)
            buttons[t] = b
            y += 38
            if t == .crop { break }
        }
        y += 4
        let sep = NSBox(frame: CGRect(x: 12, y: y, width: 32, height: 1))
        sep.boxType = .separator
        addSubview(sep)
        y += 8
        swatch.frame = CGRect(x: 13, y: y, width: 30, height: 30)
        swatch.onClick = { [weak self] in self?.showColors() }
        swatch.toolTip = "색"
        addSubview(swatch)
        y += 34
        for n in 1...3 {
            let d = SizeDot(size: n)
            d.frame = CGRect(x: 13, y: y, width: 30, height: 20)
            d.onClick = { [weak self] in self?.tools.size = n }
            d.toolTip = ["작게 (1)", "보통 (2)", "크게 (3)"][n - 1]
            addSubview(d)
            sizeDots.append(d)
            y += 22
        }
        y += 6
        // 글꼴 (글자 도구·선택한 글자에 적용)
        fontButton.frame = CGRect(x: 8, y: y, width: 40, height: 34)
        fontButton.onClick = { [weak self] in self?.showFonts() }
        addSubview(fontButton)
        y += 36
        requiredHeight = y + 8
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: ToolState.didChange, object: nil)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        CGRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    @objc private func refresh() {
        for (t, b) in buttons {
            b.isOn = tools.tool == t
            b.accent = tools.color
            b.symbol = symbol(for: t)
            b.toolTip = tooltip(for: t)
            b.needsDisplay = true
        }
        swatch.color = tools.color
        for d in sizeDots { d.isOn = d.size == tools.size; d.needsDisplay = true }
        fontButton.font = tools.font
        fontButton.toolTip = "글꼴: \(tools.font.title)"
        fontButton.needsDisplay = true
    }

    private func symbol(for t: Tool) -> String {
        switch t {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.left"
        case .text: return "textformat"
        case .shape: return tools.shape.symbol
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .pixelate: return "checkerboard.rectangle"
        case .stamp:
            switch tools.stamp {
            case .check: return "checkmark.circle.fill"
            case .cross: return "xmark.circle.fill"
            case .question: return "questionmark.circle.fill"
            case .exclamation: return "exclamationmark.circle.fill"
            case .star: return "star.circle.fill"
            case .number: return "1.circle.fill"
            }
        case .crop: return "crop"
        }
    }

    private func tooltip(for t: Tool) -> String {
        var s = "\(t.title) (\(t.shortcut.uppercased()))"
        if t == .shape || t == .stamp { s += " — 한 번 더 누르거나 길게 누르면 종류 선택" }
        return s
    }

    private func clicked(_ t: Tool, button: ToolButton) {
        if tools.tool == t, t == .shape || t == .stamp {
            showSubmenu(t, button: button)
        } else {
            tools.tool = t
        }
    }

    // MARK: 도형·스탬프 종류

    private func showSubmenu(_ t: Tool, button: ToolButton) {
        let menu = NSMenu()
        switch t {
        case .shape:
            for s in ShapeKind.allCases {
                let item = NSMenuItem(title: s.title, action: #selector(pickShape(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.rawValue
                item.image = NSImage(systemSymbolName: s.symbol, accessibilityDescription: s.title)
                item.state = tools.shape == s ? .on : .off
                menu.addItem(item)
            }
        case .stamp:
            let titles: [StampKind: String] = [.check: "승인 ✓", .cross: "거절 ✕", .question: "물음표 ?",
                                               .exclamation: "주의 !", .star: "완벽 ★", .number: "숫자 1·2·3"]
            for s in StampKind.allCases {
                let item = NSMenuItem(title: titles[s] ?? s.rawValue, action: #selector(pickStamp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.rawValue
                item.image = Self.stampImage(s, color: tools.color)
                item.state = tools.stamp == s ? .on : .off
                menu.addItem(item)
            }
        default:
            return
        }
        menu.popUp(positioning: nil, at: CGPoint(x: button.frame.maxX + 4, y: button.frame.minY), in: self)
    }

    @objc private func pickShape(_ item: NSMenuItem) {
        if let s = ShapeKind(rawValue: item.representedObject as? String ?? "") { tools.shape = s; tools.tool = .shape }
    }

    @objc private func pickStamp(_ item: NSMenuItem) {
        if let s = StampKind(rawValue: item.representedObject as? String ?? "") { tools.stamp = s; tools.tool = .stamp }
    }

    static func stampImage(_ s: StampKind, color: RGBA) -> NSImage {
        NSImage(size: NSSize(width: 20, height: 20), flipped: true) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var a = Annotation(kind: .stamp, color: color, size: 1, scale: 1)
            a.stamp = s; a.number = 1; a.p1 = CGPoint(x: r.midX, y: r.midY)
            a.magnify = 16.0 / 34.0
            Renderer.drawStamp(a, ctx)
            return true
        }
    }

    // MARK: 색 (FR-20)

    private func showColors() {
        let grid = ColorGridView(current: tools.color) { [weak self] c in
            self?.tools.color = c
            self?.colorPopover?.close()
        } custom: { [weak self] in
            self?.colorPopover?.close()
            self?.customColor()
        }
        let vc = NSViewController()
        vc.view = grid
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.contentSize = grid.fittingSize
        colorPopover = pop
        pop.show(relativeTo: swatch.bounds, of: swatch, preferredEdge: .maxX)
    }

    // MARK: 글꼴

    private func showFonts() {
        let menu = NSMenu()
        for f in TextFont.allCases {
            let item = NSMenuItem(title: f.title, action: #selector(pickFont(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = f.rawValue
            item.state = tools.font == f ? .on : .off
            let size = 15 * f.sizeFactor
            if let nf = NSFont(name: f.postScriptName, size: size) {
                item.attributedTitle = NSAttributedString(string: f.title + "  가나다 Aa", attributes: [.font: nf])
            }
            item.isEnabled = FontRegistry.isAvailable(f)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: CGPoint(x: fontButton.frame.maxX + 4, y: fontButton.frame.minY), in: self)
    }

    @objc private func pickFont(_ item: NSMenuItem) {
        guard let f = TextFont(rawValue: item.representedObject as? String ?? "") else { return }
        tools.font = f
    }

    @objc private func customColor() {
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

// MARK: - 버튼들

final class ToolButton: NSView {
    let tool: Tool
    var isOn = false
    var accent: RGBA = .pink
    var symbol = ""
    var onClick: (() -> Void)?
    var onMenu: (() -> Void)?
    private var hover = false
    private var holdTimer: Timer?
    private var menuShown = false

    init(tool: Tool) {
        self.tool = tool
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9)
        if isOn {
            (accent.isLight ? NSColor.systemGray : accent.nsColor).setFill(); bg.fill()
        } else if hover {
            NSColor.quaternaryLabelColor.setFill(); bg.fill()
        }
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            .applying(.init(paletteColors: [isOn ? .white : .labelColor]))
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tool.title)?.withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: tool.title)?.withSymbolConfiguration(config) {
            let s = img.size
            img.draw(in: CGRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2, width: s.width, height: s.height))
        }
        if tool == .shape || tool == .stamp {
            let p = NSBezierPath()
            p.move(to: CGPoint(x: bounds.maxX - 4, y: bounds.maxY - 9))
            p.line(to: CGPoint(x: bounds.maxX - 4, y: bounds.maxY - 4))
            p.line(to: CGPoint(x: bounds.maxX - 9, y: bounds.maxY - 4))
            p.close()
            (isOn ? NSColor.white : NSColor.secondaryLabelColor).setFill()
            p.fill()
        }
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        menuShown = false
        // 오른쪽 아래 삼각형이나 길게 누르기 → 종류 메뉴
        let p = convert(event.locationInWindow, from: nil)
        if (tool == .shape || tool == .stamp) && p.x > bounds.maxX - 12 && p.y > bounds.maxY - 12 {
            menuShown = true; onMenu?(); return
        }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, self.tool == .shape || self.tool == .stamp else { return }
            self.menuShown = true
            self.onMenu?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        if !menuShown { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { onMenu?() }
}

final class SwatchView: NSView {
    var color: RGBA = .pink { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        NSColor.white.setFill(); NSBezierPath(ovalIn: r).fill()
        color.nsColor.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 3, dy: 3)).fill()
        NSColor.separatorColor.setStroke(); NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

final class SizeDot: NSView {
    let size: Int
    var isOn = false
    var onClick: (() -> Void)?

    init(size: Int) { self.size = size; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = [6, 10, 15][size - 1]
        let r = CGRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        (isOn ? ToolState.shared.color.nsColor : NSColor.secondaryLabelColor).setFill()
        NSBezierPath(ovalIn: r).fill()
        if isOn && ToolState.shared.color.isLight {
            NSColor.separatorColor.setStroke(); NSBezierPath(ovalIn: r).stroke()
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// 12색 격자 (4×3) + 사용자 지정
final class ColorGridView: NSView {
    private let pick: (RGBA) -> Void
    private let custom: () -> Void
    private let current: RGBA
    private let cell: CGFloat = 30, gap: CGFloat = 8, pad: CGFloat = 12
    private let cols = 4

    init(current: RGBA, pick: @escaping (RGBA) -> Void, custom: @escaping () -> Void) {
        self.current = current
        self.pick = pick
        self.custom = custom
        super.init(frame: .zero)
        let rows = (RGBA.paletteNamed.count + cols - 1) / cols
        let w = pad * 2 + CGFloat(cols) * cell + CGFloat(cols - 1) * gap
        let h = pad * 2 + CGFloat(rows) * cell + CGFloat(rows - 1) * gap + 30
        setFrameSize(NSSize(width: w, height: h))
        let b = NSButton(title: "사용자 지정…", target: self, action: #selector(customTapped))
        b.isBordered = false
        b.contentTintColor = .controlAccentColor
        b.font = .systemFont(ofSize: 12)
        b.frame = CGRect(x: pad - 2, y: h - pad - 22, width: w - pad * 2, height: 22)
        b.alignment = .left
        addSubview(b)
        for (i, (name, c)) in RGBA.paletteNamed.enumerated() {
            let v = ColorDotButton(color: c, selected: c == current) { [weak self] in self?.pick(c) }
            v.frame = rect(i)
            v.toolTip = name
            addSubview(v)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var fittingSize: NSSize { frame.size }

    private func rect(_ i: Int) -> CGRect {
        CGRect(x: pad + CGFloat(i % cols) * (cell + gap), y: pad + CGFloat(i / cols) * (cell + gap), width: cell, height: cell)
    }

    @objc private func customTapped() { custom() }
}

final class ColorDotButton: NSView {
    let color: RGBA
    let selected: Bool
    let action: () -> Void
    private var hover = false { didSet { needsDisplay = true } }

    init(color: RGBA, selected: Bool, action: @escaping () -> Void) {
        self.color = color; self.selected = selected; self.action = action
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        color.nsColor.setFill()
        NSBezierPath(ovalIn: r).fill()
        NSColor(white: 0, alpha: 0.18).setStroke()
        NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        if selected || hover {
            (selected ? NSColor.labelColor : NSColor.secondaryLabelColor).setStroke()
            let p = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75)); p.lineWidth = 1.5; p.stroke()
        }
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// 도구 막대의 글꼴 버튼: 현재 글꼴로 "가"를 보여 준다
final class FontButton: NSView {
    var font: TextFont = .system
    var onClick: (() -> Void)?
    private var hover = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 7, yRadius: 7)
        if hover { NSColor.quaternaryLabelColor.setFill(); p.fill() }
        NSColor.separatorColor.setStroke(); p.stroke()
        let f = NSFont(name: font.postScriptName, size: 17 * font.sizeFactor) ?? .boldSystemFont(ofSize: 17)
        let s = NSAttributedString(string: "가", attributes: [.font: f, .foregroundColor: NSColor.labelColor])
        let sz = s.size()
        s.draw(at: CGPoint(x: bounds.midX - sz.width / 2 - 3, y: bounds.midY - sz.height / 2))
        // 메뉴가 있다는 작은 삼각형
        let t = NSBezierPath()
        t.move(to: CGPoint(x: bounds.maxX - 9, y: bounds.minY + 9))
        t.line(to: CGPoint(x: bounds.maxX - 5, y: bounds.minY + 9))
        t.line(to: CGPoint(x: bounds.maxX - 7, y: bounds.minY + 6))
        t.close()
        NSColor.secondaryLabelColor.setFill(); t.fill()
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
