import AppKit
import ImageIO
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var editors: [EditorWindowController] = []
    private var settings: SettingsWindowController?
    private var home: HomeWindowController?
    private var openedWithFiles = false
    private let recentMenu = NSMenu(title: "최근 항목")

    // MARK: 시작

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()
        buildMainMenu()
        if let out = ProcessInfo.processInfo.environment["KKOK_SNAPSHOT_CURSORS_OUT"] {
            // 손잡이 커서 견본: 0°·45°·90°·135° ↔ + 회전
            let cursors = [HandleCursor.resize(along: CGPoint(x: 1, y: 0)), HandleCursor.resize(along: CGPoint(x: 1, y: 1)),
                           HandleCursor.resize(along: CGPoint(x: 0, y: 1)), HandleCursor.resize(along: CGPoint(x: 1, y: -1)), HandleCursor.rotate]
            let img = NSImage(size: NSSize(width: 5 * 60, height: 60), flipped: false) { _ in
                NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 300, height: 60).fill()
                for (i, c) in cursors.enumerated() { c.image.draw(in: NSRect(x: CGFloat(i) * 60 + 6, y: 6, width: 48, height: 48)) }
                return true
            }
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            }
            exit(0)
        }
        if let out = ProcessInfo.processInfo.environment["KKOK_SNAPSHOT_HOME_OUT"] {
            DevSnapshot.runHome(output: URL(fileURLWithPath: out))
            return
        }
        if let input = ProcessInfo.processInfo.environment["KKOK_SNAPSHOT_IN"],
           let output = ProcessInfo.processInfo.environment["KKOK_SNAPSHOT_OUT"] {
            DevSnapshot.run(input: URL(fileURLWithPath: input), output: URL(fileURLWithPath: output))
            return
        }
        // 업데이트 시험 모드: 메뉴 막대·단축키 없이 업데이트만 진행한다
        if ProcessInfo.processInfo.environment["KKOK_UPDATE_AUTOINSTALL"] != nil {
            Updater.shared.start()
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

        NotificationCenter.default.addObserver(forName: HomeWindowController.didClose, object: nil, queue: .main) { [weak self] _ in
            self?.updateActivationPolicy()
        }

        // 처음 실행: 로그인 시 실행 켜기(기본) (FR-41)
        let firstRun = !Preferences.shared.didShowWelcome
        if firstRun {
            Preferences.shared.didShowWelcome = true
            LaunchAtLogin.enabled = true
        }

        // 업데이트 확인 (FR-28)
        NotificationCenter.default.addObserver(self, selector: #selector(updaterChanged), name: Updater.didChange, object: nil)
        Updater.shared.start()

        // 직접 실행했으면 시작 창 (로그인 자동 실행·파일 열기로 실행된 경우는 제외) (FR-45)
        let launchedAtLogin = Self.isLoginLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            guard !openedWithFiles, editors.isEmpty else { return }
            if firstRun || (!launchedAtLogin && Preferences.shared.showHomeAtLaunch) { showHome(nil) }
        }
    }

    /// 로그인 항목으로 실행됐는지 (Apple 이벤트의 launched-as-login-item 표시)
    private static func isLoginLaunch() -> Bool {
        guard let ev = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return ev.eventID == kAEOpenApplication
            && ev.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// 실행 중에 앱 아이콘을 다시 누르면 시작 창 (창이 이미 있으면 그대로)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHome(nil) }
        return true
    }

    @objc func showHome(_ sender: Any?) {
        if home == nil {
            let h = HomeWindowController()
            h.onOpenRecent = { [weak self] id in self?.openHistory(id) }
            home = h
        }
        NSApp.setActivationPolicy(.regular)
        home?.showWindow(nil)
        home?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 보이는 창이 하나도 없으면 Dock에서 내려가 메뉴 막대에만 남는다
    private func updateActivationPolicy() {
        DispatchQueue.main.async { [self] in
            let visible = !editors.isEmpty || home?.window?.isVisible == true || settings?.window?.isVisible == true
            NSApp.setActivationPolicy(visible ? .regular : .accessory)
        }
    }

    /// ⌘Q로 끝낼 때 입력 중인 글자와 저장 대기 중인 편집을 저장한다 (BUG-05)
    func applicationWillTerminate(_ notification: Notification) {
        for wc in editors {
            wc.canvas.endTextEditing()
            wc.doc.saveNow()
        }
        // 받아 둔 업데이트가 있으면 앱이 끝난 뒤 바꾼다
        Updater.shared.runInstallerIfNeeded()
    }

    // MARK: 업데이트 (FR-28)

    @objc func checkForUpdates(_ sender: Any?) {
        Task { @MainActor in await Updater.shared.check(manual: true) }
    }

    @objc func offerUpdate(_ sender: Any?) { Task { @MainActor in Updater.shared.offer() } }

    /// 새 버전을 찾으면 메뉴 막대 아이콘에 점을 찍고 메뉴에 "새 버전 받기"를 보인다
    @objc private func updaterChanged() {
        let has = Updater.shared.pending != nil
        statusItem?.button?.image = StatusIcon.make(badge: has)
        statusItem?.button?.toolTip = has ? "Kkok — 새 버전 \(Updater.shared.pending!.version)" : "Kkok"
        home?.reload()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock 아이콘에 끌어 놓기·Finder "다음으로 열기" (FR-07)
    func application(_ application: NSApplication, open urls: [URL]) {
        openedWithFiles = true
        open(urls: urls)
    }

    // MARK: 메뉴 막대 아이콘 (FR-40)

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.make()
        item.button?.toolTip = "Kkok"
        let menu = NSMenu()
        menu.delegate = self
        let upd = NSMenuItem(title: "새 버전 받기", action: #selector(offerUpdate(_:)), keyEquivalent: "")
        upd.target = self
        upd.tag = 9001
        upd.isHidden = true
        menu.addItem(upd)
        menu.addItem(withTitle: "Kkok 열기", action: #selector(showHome(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
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
        menu.addItem(withTitle: "업데이트 확인…", action: #selector(checkForUpdates(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Kkok 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let upd = menu.item(withTag: 9001) {
            upd.isHidden = Updater.shared.pending == nil
            if let v = Updater.shared.pending?.version { upd.title = "⬆︎ 새 버전 \(v) 받기…" }
        }
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
            self?.updateActivationPolicy()
        }
        editors.append(wc)
        NSApp.setActivationPolicy(.regular)
        home?.window?.orderOut(nil) // 편집을 시작하면 시작 창은 비킨다
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
        openHistory(id)
    }

    private func openHistory(_ id: UUID) {
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
        if settings == nil {
            let sw = SettingsWindowController()
            settings = sw
            if let w = sw.window {
                NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                    self?.updateActivationPolicy()
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: 앱 메뉴

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Kkok에 관하여", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(withTitle: "업데이트 확인…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
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
    /// `badge`: 새 버전이 있으면 오른쪽 위에 작은 점
    static func make(badge: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillEllipse(in: CGRect(x: 2, y: 2, width: 5.5, height: 5.5))
            if badge { ctx.fillEllipse(in: CGRect(x: 13, y: 0.5, width: 4.5, height: 4.5)) }
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
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    private static func capture(_ window: NSWindow, to output: URL, cleanup: URL? = nil) {
        guard let view = window.contentView?.superview else { exit(1) }
        window.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: output)
            if let cleanup { try? FileManager.default.removeItem(at: cleanup) }
            exit(0)
        }
    }

    private static func tempStore() -> (HistoryStore, URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kkok-snapshot-\(UUID().uuidString)")
        return (HistoryStore(root: tmp, picturesDir: tmp.appendingPathComponent("pics")), tmp)
    }

    /// 시작 창. KKOK_SNAPSHOT_IN이 있으면 그 이미지로 만든 임시 최근 캡처를 보여 준다(실제 보관함은 읽지 않음)
    static func runHome(output: URL) {
        // 번들 밖에서 실행하면 앱 아이콘이 없으므로 저장소의 아이콘을 쓴다
        if let icon = env["KKOK_ICON_PATH"], let img = NSImage(contentsOfFile: icon) { NSApp.applicationIconImage = img }
        let wc = HomeWindowController()
        var cleanup: URL?
        if let input = env["KKOK_SNAPSHOT_IN"], let img = Renderer.loadImage(URL(fileURLWithPath: input)) {
            let (store, tmp) = tempStore()
            cleanup = tmp
            for i in 0..<3 {
                if let doc = EditorDocument.create(image: img, scale: 1, store: store) {
                    doc.state.annotations = demoAnnotations(scale: 1).prefix(2 + i * 2).map { $0 }
                    doc.saveNow()
                }
            }
            wc.store = store
        }
        wc.reload()
        guard let window = wc.window else { exit(1) }
        capture(window, to: output, cleanup: cleanup)
    }

    static func run(input: URL, output: URL) {
        let (store, tmp) = tempStore()
        guard let img = Renderer.loadImage(input),
              let doc = EditorDocument.create(image: img, scale: AppDelegate.scale(of: input), store: store) else { exit(1) }
        var selectID: UUID?
        if env["KKOK_SNAPSHOT_DEMO"] != nil {
            doc.state.annotations = demoAnnotations(scale: Double(doc.scale))
            if env["KKOK_SNAPSHOT_SELECT_ROTATED"] != nil { selectID = doc.state.annotations.first { $0.rotation != nil }?.id }
        } else {
            var a = Annotation(kind: .arrow, color: .pink, size: 2, scale: Double(doc.scale))
            a.p1 = CGPoint(x: CGFloat(img.width) * 0.7, y: CGFloat(img.height) * 0.7)
            a.p2 = CGPoint(x: CGFloat(img.width) * 0.35, y: CGFloat(img.height) * 0.35)
            var t = Annotation(kind: .text, color: .pink, size: 2, scale: Double(doc.scale))
            t.p1 = CGPoint(x: CGFloat(img.width) * 0.4, y: CGFloat(img.height) * 0.75); t.text = "여기를 고쳐 주세요"
            doc.state.annotations = [a, t]
            for (i, f) in TextFont.allCases.enumerated() {
                var ft = Annotation(kind: .text, color: RGBA.palette[(i * 2) % 12], size: 2, scale: Double(doc.scale))
                ft.font = f
                ft.text = f.title
                ft.p1 = CGPoint(x: 20 * doc.scale, y: CGFloat(20 + i * 40) * doc.scale)
                doc.state.annotations.append(ft)
            }
            var rt = Annotation(kind: .text, color: RGBA.palette[8], size: 3, scale: Double(doc.scale))
            rt.font = .jua
            rt.text = "회전 20°"
            rt.p1 = CGPoint(x: CGFloat(img.width) * 0.62, y: CGFloat(img.height) * 0.1)
            rt.rotation = 20 * .pi / 180
            doc.state.annotations.append(rt)
            selectID = rt.id
        }
        // 하위 막대를 연 상태로: KKOK_SNAPSHOT_TOOL=shape|stamp|text|color
        // 실제 사용과 같은 순서로 — 창을 띄운 뒤에 도구를 고른다
        ToolState.shared.tool = .arrow
        let wc = EditorWindowController(doc: doc)
        if let selectID { wc.canvas.select([selectID]) }
        if let t = env["KKOK_SNAPSHOT_TOOL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                switch t {
                case "shape": ToolState.shared.tool = .shape
                case "stamp": ToolState.shared.tool = .stamp
                case "text": ToolState.shared.tool = .text
                case "color": wc.subPanel.toggleColor()
                default: break
                }
            }
        }
        wc.overrideStatus("자동 저장됨 · ~/Pictures/Kkok/\(doc.name).png")
        guard let window = wc.window else { exit(1) }
        capture(window, to: output, cleanup: tmp)
    }

    /// README 데모(가상의 "Team Board" 설정 화면, 1100×680)에 맞춘 주석
    static func demoAnnotations(scale s: Double) -> [Annotation] {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var list: [Annotation] = []
        // 이메일 가리기
        var px = Annotation(kind: .pixelate, color: .pink, size: 2, scale: s)
        px.p1 = pt(300, 404); px.p2 = pt(560, 434)
        list.append(px)
        // 저장 버튼 짚기
        var ar = Annotation(kind: .arrow, color: .pink, size: 3, scale: s)
        ar.p1 = pt(604, 640); ar.p2 = pt(422, 594)
        list.append(ar)
        var tx = Annotation(kind: .text, color: .pink, size: 2, scale: s)
        tx.text = "버튼을 오른쪽 끝으로 옮겨 주세요"
        tx.p1 = pt(616, 624)
        list.append(tx)
        // 알림 토글
        var rr = Annotation(kind: .roundedRect, color: RGBA.palette[7], size: 2, scale: s)
        rr.p1 = pt(788, 310); rr.p2 = pt(924, 390)
        list.append(rr)
        var n1 = Annotation(kind: .stamp, color: RGBA.palette[7], size: 1, scale: s)
        n1.stamp = .number; n1.number = 1; n1.p1 = pt(924, 310)
        list.append(n1)
        var pen = Annotation(kind: .text, color: RGBA.palette[7], size: 2, scale: s)
        pen.font = .nanumPen; pen.text = "기본은 꺼 두기"
        pen.p1 = pt(800, 398)
        list.append(pen)
        // 설명 강조
        var hl = Annotation(kind: .highlighter, color: .highlighterYellow, size: 2, scale: s)
        hl.points = [pt(296, 166), pt(390, 165), pt(482, 166)]
        list.append(hl)
        // 사진 바꾸기 승인
        var ok = Annotation(kind: .stamp, color: .pink, size: 2, scale: s)
        ok.stamp = .check; ok.p1 = pt(486, 234)
        list.append(ok)
        // 기울인 글자
        var rot = Annotation(kind: .text, color: RGBA.palette[8], size: 3, scale: s)
        rot.font = .jua; rot.text = "좋아요!"
        rot.p1 = pt(48, 380); rot.rotation = -12 * .pi / 180
        list.append(rot)
        return list
    }
}
