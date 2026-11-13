import AppKit
import UniformTypeIdentifiers

/// 편집 창: 위 도구 막대(캡처·복사·저장), 왼쪽 도구, 가운데 캔버스, 아래 끌기 탭 (디자인 명세 1장)
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let doc: EditorDocument
    let canvas: CanvasView
    private let scroll = NSScrollView()
    private let palette = ToolPaletteView()
    private let bottom = NSView()
    private let dragTab = DragTabView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    var onClose: ((EditorWindowController) -> Void)?

    init(doc: EditorDocument) {
        self.doc = doc
        canvas = CanvasView(doc: doc)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = doc.name
        window.minSize = NSSize(width: 780, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        doc.undoManager = window.undoManager
        buildToolbar()
        buildContent()
        // 도구 막대 + 위 막대(52) + 아래 막대(56)가 다 들어가게 (BUG-01)
        window.minSize.height = max(420, palette.requiredHeight + 52 + 56)
        sizeWindowToFit()

        NotificationCenter.default.addObserver(self, selector: #selector(docSaved), name: EditorDocument.didSave, object: doc)
        canvas.onZoomChange = { [weak self] z in self?.zoomLabel.stringValue = "\(Int((z * 100).rounded()))%" }
        let previous = doc.onChange
        doc.onChange = { [weak self] in
            previous?()
            self?.scheduleTabRefresh()
        }
        dragTab.refresh()
        docSaved()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: 화면 구성

    private func buildToolbar() {
        let tb = NSToolbar(identifier: "KkokEditor")
        tb.delegate = self
        tb.displayMode = .iconOnly
        tb.allowsUserCustomization = false
        window?.toolbar = tb
        window?.toolbarStyle = .unified
    }

    private static let captureID = NSToolbarItem.Identifier("capture")
    private static let copyID = NSToolbarItem.Identifier("copy")
    private static let saveID = NSToolbarItem.Identifier("save")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.captureID, .flexibleSpace, Self.copyID, Self.saveID]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.captureID:
            let seg = NSSegmentedControl(labels: ["영역", "창", "전체", "\(Preferences.shared.timerSeconds)초"],
                                         trackingMode: .momentary, target: self, action: #selector(captureSegment(_:)))
            let symbols = ["rectangle.dashed", "macwindow", "display", "timer"]
            let tips = [CaptureMode.area, .window, .fullscreen, .timed]
            for i in 0..<4 {
                seg.setImage(NSImage(systemSymbolName: symbols[i], accessibilityDescription: nil), forSegment: i)
                seg.setImageScaling(.scaleProportionallyDown, forSegment: i)
                let hk = Preferences.shared.hotKey(for: tips[i])?.display ?? ""
                seg.setToolTip("\(tips[i].title) \(hk)", forSegment: i)
            }
            item.view = seg
            item.label = "캡처"
        case Self.copyID:
            let b = NSButton(title: "복사", image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)!,
                             target: self, action: #selector(copyImage(_:)))
            b.bezelStyle = .texturedRounded
            b.imagePosition = .imageLeading
            b.toolTip = "주석을 합친 이미지를 복사 (⌘C)"
            item.view = b
            item.label = "복사"
        case Self.saveID:
            let b = NSButton(title: "저장…", image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)!,
                             target: self, action: #selector(saveAs(_:)))
            b.bezelStyle = .texturedRounded
            b.imagePosition = .imageLeading
            b.toolTip = "파일로 저장 (⌘S)"
            item.view = b
            item.label = "저장"
        default:
            return nil
        }
        return item
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let paletteW: CGFloat = 56, bottomH: CGFloat = 56

        palette.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        bottom.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(palette)
        content.addSubview(scroll)
        content.addSubview(bottom)

        let top = window!.contentLayoutGuide as! NSLayoutGuide
        NSLayoutConstraint.activate([
            palette.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            palette.topAnchor.constraint(equalTo: top.topAnchor),
            palette.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            palette.widthAnchor.constraint(equalToConstant: paletteW),

            scroll.leadingAnchor.constraint(equalTo: palette.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: top.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor),

            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: bottomH),
        ])

        scroll.contentView = CenteringClipView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(srgbRed: 0.227, green: 0.227, blue: 0.235, alpha: 1)
        scroll.allowsMagnification = false
        canvas.onOpenFiles = { urls in (NSApp.delegate as? AppDelegate)?.open(urls: urls) }

        // 아래 막대
        bottom.wantsLayer = true
        bottom.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let line = NSBox(); line.boxType = .separator; line.translatesAutoresizingMaskIntoConstraints = false
        dragTab.doc = doc
        dragTab.toolTip = "끌어서 다른 앱에 놓으면 PNG로 들어갑니다"
        dragTab.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let zoomOut = NSButton(image: NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "축소")!,
                               target: self, action: #selector(zoomOut(_:)))
        let zoomIn = NSButton(image: NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "확대")!,
                              target: self, action: #selector(zoomIn(_:)))
        for b in [zoomOut, zoomIn] { b.isBordered = false; b.translatesAutoresizingMaskIntoConstraints = false }
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        zoomLabel.alignment = .center
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        let zoomClick = NSClickGestureRecognizer(target: self, action: #selector(actualSize(_:)))
        zoomLabel.addGestureRecognizer(zoomClick)
        zoomLabel.toolTip = "누르면 100% (⌘0)"

        for v in [line, dragTab, statusLabel, zoomOut, zoomLabel, zoomIn] { bottom.addSubview(v) }
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: bottom.topAnchor),
            line.leadingAnchor.constraint(equalTo: bottom.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: bottom.trailingAnchor),
            dragTab.leadingAnchor.constraint(equalTo: bottom.leadingAnchor, constant: 12),
            dragTab.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            dragTab.widthAnchor.constraint(equalToConstant: 196),
            dragTab.heightAnchor.constraint(equalToConstant: 44),
            statusLabel.leadingAnchor.constraint(equalTo: dragTab.trailingAnchor, constant: 14),
            statusLabel.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: zoomOut.leadingAnchor, constant: -10),
            zoomIn.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -12),
            zoomIn.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            zoomLabel.trailingAnchor.constraint(equalTo: zoomIn.leadingAnchor, constant: -4),
            zoomLabel.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 46),
            zoomOut.trailingAnchor.constraint(equalTo: zoomLabel.leadingAnchor, constant: -4),
            zoomOut.centerYAnchor.constraint(equalTo: bottom.centerYAnchor),
        ])
    }

    /// 100%로 다 보이면 그대로, 아니면 화면의 85% 안에 맞춘다
    private func sizeWindowToFit() {
        guard let window else { return }
        let screen = NSScreen.underMouse.visibleFrame
        let chromeW: CGFloat = 56, chromeH: CGFloat = 56 + 52
        let natural = canvas.naturalSize
        let maxW = screen.width * 0.85 - chromeW, maxH = screen.height * 0.85 - chromeH
        let fit = min(1, maxW / natural.width, maxH / natural.height)
        canvas.zoom = fit < 1 ? max(0.1, (fit * 20).rounded(.down) / 20) : 1
        let w = max(window.minSize.width, min(maxW, natural.width * canvas.zoom) + chromeW)
        let h = max(window.minSize.height, min(maxH, natural.height * canvas.zoom) + chromeH)
        window.setContentSize(NSSize(width: w, height: h))
        window.setFrameOrigin(CGPoint(x: screen.midX - window.frame.width / 2, y: screen.midY - window.frame.height / 2))
        zoomLabel.stringValue = "\(Int((canvas.zoom * 100).rounded()))%"
    }

    // MARK: 갱신

    private var tabWork: DispatchWorkItem?
    private func scheduleTabRefresh() {
        tabWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.dragTab.refresh() }
        tabWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }

    @objc private func docSaved() {
        if let p = doc.meta.exportedPath {
            statusLabel.stringValue = "자동 저장됨 · " + (p as NSString).abbreviatingWithTildeInPath
        }
        window?.representedURL = doc.meta.exportedPath.map { URL(fileURLWithPath: $0) }
    }

    // MARK: 동작

    @objc private func captureSegment(_ seg: NSSegmentedControl) {
        let modes: [CaptureMode] = [.area, .window, .fullscreen, .timed]
        CaptureController.shared.start(modes[seg.selectedSegment])
    }

    @objc func copyImage(_ sender: Any?) {
        canvas.endTextEditing()
        doc.copyToPasteboard()
        flashStatus("클립보드에 복사했습니다")
    }

    /// ⌘S (FR-32)
    @objc func saveAs(_ sender: Any?) {
        canvas.endTextEditing()
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = doc.name + ".png"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.isExtensionHidden = false
        let format = NSPopUpButton(frame: .zero, pullsDown: false)
        format.addItems(withTitles: ["PNG", "JPEG"])
        format.target = self
        let accessory = NSStackView(views: [NSTextField(labelWithString: "형식:"), format])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = accessory
        let handler = FormatHandler(panel: panel)
        format.action = #selector(FormatHandler.changed(_:))
        format.target = handler
        panel.beginSheetModal(for: window) { [doc] resp in
            _ = handler
            guard resp == .OK, let url = panel.url, let img = doc.flattened() else { return }
            let isJPEG = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
            let data = isJPEG ? Renderer.encode(img, type: .jpeg, quality: 0.9) : Renderer.pngData(img)
            try? data?.write(to: url, options: .atomic)
        }
    }

    private final class FormatHandler: NSObject {
        weak var panel: NSSavePanel?
        init(panel: NSSavePanel) { self.panel = panel }
        @objc func changed(_ sender: NSPopUpButton) {
            guard let panel else { return }
            let jpeg = sender.indexOfSelectedItem == 1
            let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = base + (jpeg ? ".jpg" : ".png")
        }
    }

    private func flashStatus(_ s: String) {
        let old = statusLabel.stringValue
        statusLabel.stringValue = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.statusLabel.stringValue == s { self?.statusLabel.stringValue = old }
        }
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(canvas.zoom * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setZoom(canvas.zoom / 1.25) }
    @objc func actualSize(_ sender: Any?) { setZoom(1) }

    private func setZoom(_ z: CGFloat) {
        let clip = scroll.contentView
        let center = canvas.toImage(CGPoint(x: clip.bounds.midX, y: clip.bounds.midY))
        canvas.zoom = min(8, max(0.1, z))
        let v = canvas.toView(center)
        clip.scroll(to: CGPoint(x: v.x - clip.bounds.width / 2, y: v.y - clip.bounds.height / 2))
        scroll.reflectScrolledClipView(clip)
    }

    @objc func applyCrop(_ sender: Any?) { canvas.applyCrop() }

    // MARK: 창

    func windowWillClose(_ notification: Notification) {
        canvas.endTextEditing()
        doc.saveNow()
        onClose?(self)
    }
}
