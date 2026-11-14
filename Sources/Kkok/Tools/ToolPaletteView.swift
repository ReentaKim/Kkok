import AppKit

/// 왼쪽 세로 도구 막대 (디자인 명세 1장)
final class ToolPaletteView: NSView {
    private let tools = ToolState.shared
    private var buttons: [Tool: ToolButton] = [:]
    private let swatch = SwatchView()
    private var sizeDots: [SizeDot] = []

    /// 이미 고른 도형·스탬프·글자 도구를 한 번 더 눌렀을 때 (하위 막대 접기·펴기)
    var onToggleSubPanel: ((Tool) -> Void)?
    /// 색 원을 눌렀을 때 (색 하위 막대)
    var onToggleColors: (() -> Void)?

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
            b.onClick = { [weak self] in self?.clicked(t) }
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
        swatch.onClick = { [weak self] in self?.onToggleColors?() }
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
        t == .shape ? "도형 (R 사각형 · O 타원 · L 선)" : "\(t.title) (\(t.shortcut.uppercased()))"
    }

    private func clicked(_ t: Tool) {
        if tools.tool == t, t == .shape || t == .stamp || t == .text {
            onToggleSubPanel?(t)
        } else {
            tools.tool = t
        }
    }

    /// 하위 막대를 부른 버튼의 위쪽 y (이 뷰 좌표, 위가 0)
    func anchorY(for mode: SubPanelMode) -> CGFloat {
        switch mode {
        case .shape: return buttons[.shape]?.frame.minY ?? 0
        case .stamp: return buttons[.stamp]?.frame.minY ?? 0
        case .font: return buttons[.text]?.frame.minY ?? 0
        case .color: return swatch.frame.minY
        }
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

}

// MARK: - 버튼들

final class ToolButton: NSView {
    let tool: Tool
    var isOn = false
    var accent: RGBA = .pink
    var symbol = ""
    var onClick: (() -> Void)?
    private var hover = false

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
        // 켜진 버튼은 흰 아이콘 한 색이라 ".fill" 모양이면 안쪽 표시가 사라진다 → 테두리 모양으로
        let name = isOn && symbol.hasSuffix(".fill") ? String(symbol.dropLast(5)) : symbol
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: tool.title)?.withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: tool.title)?.withSymbolConfiguration(config) {
            let s = img.size
            img.draw(in: CGRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2, width: s.width, height: s.height))
        }
    }

    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
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
