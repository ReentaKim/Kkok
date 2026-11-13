import AppKit
import ImageIO
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var editors: [EditorWindowController] = []
    private var settings: SettingsWindowController?
    private let recentMenu = NSMenu(title: "최근 항목")

    // MARK: 시작

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        if let input = ProcessInfo.processInfo.environment["KKOK_SNAPSHOT_IN"],
           let output = ProcessInfo.processInfo.environment["KKOK_SNAPSHOT_OUT"] {
            DevSnapshot.run(input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output))
            return
        }
        buildStatusItem()
        registerHotKeys()
        NotificationCenter.default.addObserver(self, selector: #selector(registerHotKeys), name: Preferences.didChange, object: nil)
        CaptureController.shared.onCaptured = { [weak self] img, scale in self?.openCapture(img, scale: scale) }
        // 실패한 단축키는 1분마다 다시 시도한다 (Skitch를 끈 뒤 바로 쓸 수 있게)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            if !HotKeyCenter.shared.failures.isEmpty { self?.registerHotKeys() }
        }

        // 처음 실행: 로그인 시 실행 켜기(기본) + 안내 (FR-41)
        if !Preferences.shared.didShowWelcome {
            Preferences.shared.didShowWelcome = true
            LaunchAtLogin.enabled = true
            showWelcome()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { CaptureController.shared.start(.area) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock 아이콘에 끌어 놓기·Finder "다음으로 열기" (FR-07)
    func application(_ application: NSApplication, open urls: [URL]) {
        open(urls: urls)
    }

    // MARK: 메뉴 막대 아이콘 (FR-40)

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.make()
        item.button?.toolTip = "Kkok"
        let menu = NSMenu()
        menu.delegate = self
        for mode in CaptureMode.allCases {
            let mi = NSMenuItem(title: mode.title, action: #selector(captureMenu(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = mode.rawValue
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "클립보드에서 새로 만들기", action: #selector(newFromClipboard(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "빈 캔버스", action: #selector(newBlank(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "파일 열기…", action: #selector(openDocument(_:)), keyEquivalent: "").target = self
        let recent = NSMenuItem(title: "최근 항목", action: nil, keyEquivalent: "")
        recent.submenu = recentMenu
        menu.addItem(recent)
        menu.addItem(.separator())
        menu.addItem(withTitle: "캡처 폴더 열기", action: #selector(openPicturesFolder(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "설정…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Kkok 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // 다른 앱(예: Skitch)이 쓰던 단축키가 풀렸으면 다시 잡는다
        if !HotKeyCenter.shared.failures.isEmpty { registerHotKeys() }
        // 단축키 표시를 현재 설정으로
        for mi in menu.items {
            guard let raw = mi.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { continue }
            if let hk = Preferences.shared.hotKey(for: mode) {
                mi.keyEquivalent = HotKey.keyName(hk.keyCode).lowercased()
                mi.keyEquivalentModifierMask = hk.keyEquivalentModifierMask
            } else {
                mi.keyEquivalent = ""
            }
        }
        rebuildRecent()
    }

    private func rebuildRecent() {
        recentMenu.removeAllItems()
        let items = HistoryStore.shared.recent(limit: 15)
        if items.isEmpty {
            recentMenu.addItem(withTitle: "없음", action: nil, keyEquivalent: "").isEnabled = false
            return
        }
        for m in items {
            let mi = NSMenuItem(title: m.name, action: #selector(openRecent(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = m.id.uuidString
            if let img = NSImage(contentsOf: HistoryStore.shared.thumbnailURL(id: m.id)) {
                let h: CGFloat = 32
                img.size = NSSize(width: max(1, img.size.width * h / max(1, img.size.height)), height: h)
                if img.size.width > 64 { img.size = NSSize(width: 64, height: 64 * img.size.height / img.size.width) }
                mi.image = img
            }
            recentMenu.addItem(mi)
        }
    }

    // MARK: 전역 단축키 (FR-42)

    @objc private func registerHotKeys() {
        let c = HotKeyCenter.shared
        c.unregisterAll()
        for mode in CaptureMode.allCases {
            guard let hk = Preferences.shared.hotKey(for: mode) else { continue }
            c.register(hk, name: mode.title) { CaptureController.shared.start(mode) }
        }
        if !c.failures.isEmpty {
            NSLog("Kkok: 단축키 등록 실패 %@", c.failures.joined(separator: ", "))
        }
        settings?.reloadFailures()
    }

    // MARK: 문서 열기

    func openCapture(_ img: CGImage, scale: CGFloat) {
        guard let doc = EditorDocument.create(image: img, scale: scale) else { return }
        show(doc)
    }

    private func show(_ doc: EditorDocument) {
        let wc = EditorWindowController(doc: doc)
        wc.onClose = { [weak self] wc in
            self?.editors.removeAll { $0 === wc }
            if self?.editors.isEmpty == true {
                // 편집 창이 다 닫히면 Dock에서 내려간다
                DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
            }
        }
        editors.append(wc)
        NSApp.setActivationPolicy(.regular)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        wc.window?.makeFirstResponder(wc.canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    func open(urls: [URL]) {
        for url in urls {
            guard let img = Renderer.loadImage(url) else { continue }
            openCapture(img, scale: Self.scale(of: url))
        }
    }

    /// 파일의 DPI로 배율을 정한다 (macOS 스크린샷은 144dpi = 2배)
    static func scale(of url: URL) -> CGFloat {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 0 else { return 1 }
        return max(1, min(3, CGFloat((dpi / 72).rounded())))
    }

    @objc private func captureMenu(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        CaptureController.shared.start(mode)
    }

    @objc func captureArea(_ sender: Any?) { CaptureController.shared.start(.area) }
    @objc func capturePrevious(_ sender: Any?) { CaptureController.shared.start(.previousArea) }
    @objc func captureWindow(_ sender: Any?) { CaptureController.shared.start(.window) }
    @objc func captureFullscreen(_ sender: Any?) { CaptureController.shared.start(.fullscreen) }
    @objc func captureTimed(_ sender: Any?) { CaptureController.shared.start(.timed) }

    @objc func newFromClipboard(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true,
                                                                         .urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           !urls.isEmpty {
            open(urls: urls); return
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pb.data(forType: type), let img = Renderer.loadImage(data: data) {
                let nsimg = NSImage(data: data)
                let scale = nsimg.map { CGFloat(img.width) / max(1, $0.size.width) } ?? 1
                openCapture(img, scale: max(1, min(3, scale.rounded())))
                return
            }
        }
        NSSound.beep()
    }

    @objc func newBlank(_ sender: Any?) {
        let scale = NSScreen.underMouse.backingScaleFactor
        let w = Int(800 * scale), h = Int(500 * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let img = ctx.makeImage() { openCapture(img, scale: scale) }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { open(urls: panel.urls) }
    }

    @objc private func openRecent(_ item: NSMenuItem) {
        guard let s = item.representedObject as? String, let id = UUID(uuidString: s) else { return }
        if let existing = editors.first(where: { $0.doc.meta.id == id }) {
            NSApp.setActivationPolicy(.regular)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let (meta, img) = HistoryStore.shared.load(id: id) else { NSSound.beep(); return }
        show(EditorDocument(meta: meta, base: img))
    }

    @objc func openPicturesFolder(_ sender: Any?) {
        let dir = HistoryStore.shared.picturesDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc func showSettings(_ sender: Any?) {
        if !HotKeyCenter.shared.failures.isEmpty { registerHotKeys() }
        if settings == nil { settings = SettingsWindowController() }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Kkok이 메뉴 막대에서 대기합니다"
        let area = Preferences.shared.hotKey(for: .area)?.display ?? "-"
        let win = Preferences.shared.hotKey(for: .window)?.display ?? "-"
        let full = Preferences.shared.hotKey(for: .fullscreen)?.display ?? "-"
        alert.informativeText = """
        \(area)  영역 캡처
        \(win)  창 캡처
        \(full)  전체 화면

        처음 캡처할 때 화면 기록 권한을 물어봅니다. 단축키는 설정에서 바꿀 수 있습니다.
        """
        if !HotKeyCenter.shared.failures.isEmpty {
            alert.informativeText += "\n\n다른 앱이 쓰고 있어 등록하지 못한 단축키: " + HotKeyCenter.shared.failures.joined(separator: ", ")
        }
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }

    // MARK: 앱 메뉴

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Kkok에 관하여", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "설정…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Kkok 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Kkok 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "파일")
        file.addItem(withTitle: "빈 캔버스", action: #selector(newBlank(_:)), keyEquivalent: "n")
        let clip = file.addItem(withTitle: "클립보드에서 새로 만들기", action: #selector(newFromClipboard(_:)), keyEquivalent: "v")
        clip.keyEquivalentModifierMask = [.command, .shift]
        file.addItem(withTitle: "열기…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        file.addItem(.separator())
        file.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "저장…", action: #selector(EditorWindowController.saveAs(_:)), keyEquivalent: "s")
        file.addItem(withTitle: "캡처 폴더 열기", action: #selector(openPicturesFolder(_:)), keyEquivalent: "")
        fileItem.submenu = file

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙이기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "지우기", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "자르기 적용", action: #selector(EditorWindowController.applyCrop(_:)), keyEquivalent: "\r")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "보기")
        view.addItem(withTitle: "확대", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "+")
        let zin2 = view.addItem(withTitle: "확대", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "=")
        zin2.isHidden = true; zin2.allowsKeyEquivalentWhenHidden = true
        view.addItem(withTitle: "축소", action: #selector(EditorWindowController.zoomOut(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "실제 크기", action: #selector(EditorWindowController.actualSize(_:)), keyEquivalent: "0")
        viewItem.submenu = view

        let capItem = NSMenuItem(); main.addItem(capItem)
        let cap = NSMenu(title: "캡처")
        let actions: [(CaptureMode, Selector)] = [(.area, #selector(captureArea(_:))), (.previousArea, #selector(capturePrevious(_:))),
                                                  (.window, #selector(captureWindow(_:))), (.fullscreen, #selector(captureFullscreen(_:))),
                                                  (.timed, #selector(captureTimed(_:)))]
        for (mode, sel) in actions { cap.addItem(withTitle: mode.title, action: sel, keyEquivalent: "") }
        capItem.submenu = cap

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "윈도우")
        win.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "확대/축소", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }
}

/// 로그인 시 실행 (FR-41)
enum LaunchAtLogin {
    static var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Kkok: 로그인 시 실행 설정 실패 %@", error.localizedDescription)
            }
        }
    }
}

/// 메뉴 막대 아이콘: 점 하나를 화살표가 콕 짚는 모양 (템플릿 이미지)
enum StatusIcon {
    static func make() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 5.5, height: 5.5))
            let path = Geometry.arrowPath(from: CGPoint(x: 16, y: 16), to: CGPoint(x: 7.5, y: 7.5), width: 2.6)
            ctx.addPath(path)
            ctx.fillPath()
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// 개발 점검용: 화면에 띄우지 않고 편집 창을 그려 PNG로 저장한다.
/// KKOK_SNAPSHOT_IN=이미지 KKOK_SNAPSHOT_OUT=결과.png .build/release/Kkok
enum DevSnapshot {
    static func run(input: URL, output: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kkok-snapshot-\(UUID().uuidString)")
        let store = HistoryStore(root: tmp, picturesDir: tmp.appendingPathComponent("pics"))
        guard let img = Renderer.loadImage(input),
              let doc = EditorDocument.create(image: img, scale: AppDelegate.scale(of: input), store: store) else { exit(1) }
        // 견본 주석
        var a = Annotation(kind: .arrow, color: .pink, size: 2, scale: Double(doc.scale))
        a.p1 = CGPoint(x: CGFloat(img.width) * 0.7, y: CGFloat(img.height) * 0.7)
        a.p2 = CGPoint(x: CGFloat(img.width) * 0.35, y: CGFloat(img.height) * 0.35)
        var t = Annotation(kind: .text, color: .pink, size: 2, scale: Double(doc.scale))
        t.p1 = CGPoint(x: CGFloat(img.width) * 0.4, y: CGFloat(img.height) * 0.75); t.text = "여기를 고쳐 주세요"
        doc.state.annotations = [a, t]
        let wc = EditorWindowController(doc: doc)
        guard let window = wc.window, let view = window.contentView?.superview else { exit(1) }
        window.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: output)
            try? FileManager.default.removeItem(at: tmp)
            exit(0)
        }
    }
}
