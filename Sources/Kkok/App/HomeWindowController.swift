import AppKit

/// 시작 창: 앱 아이콘을 눌러 실행하거나 다시 눌렀을 때 보인다 (FR-45)
/// 캡처 버튼·단축키 안내·화면 기록 권한 상태·최근 캡처
final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private let recentStack = NSStackView()
    private let permissionRow = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "아직 캡처가 없습니다. 위 버튼이나 단축키로 시작하세요.")
    var onOpenRecent: ((UUID) -> Void)?

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 470),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Kkok"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }

        // 머리: 아이콘 + 이름 + 한 줄 소개
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let title = NSTextField(labelWithString: "Kkok")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let subtitle = NSTextField(labelWithString: "찍고, 콕 짚고, 끌어서 붙이기")
        subtitle.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [title, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 12

        // 캡처 버튼 4개
        let modes: [(CaptureMode, String, String)] = [
            (.area, "영역", "rectangle.dashed"), (.window, "창", "macwindow"),
            (.fullscreen, "전체 화면", "display"), (.timed, "\(Preferences.shared.timerSeconds)초 타이머", "timer"),
        ]
        let buttons = modes.map { mode, label, symbol -> NSView in
            let b = NSButton(title: label, image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!,
                             target: self, action: #selector(capture(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(mode.rawValue)
            b.imagePosition = .imageAbove
            b.bezelStyle = .regularSquare
            b.font = .systemFont(ofSize: 13, weight: .semibold)
            b.symbolConfiguration = .init(pointSize: 22, weight: .regular)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 130).isActive = true
            b.heightAnchor.constraint(equalToConstant: 72).isActive = true
            let hk = NSTextField(labelWithString: Preferences.shared.hotKey(for: mode)?.display ?? "단축키 없음")
            hk.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            hk.textColor = .secondaryLabelColor
            let col = NSStackView(views: [b, hk])
            col.orientation = .vertical
            col.spacing = 4
            return col
        }
        let captureRow = NSStackView(views: buttons)
        captureRow.spacing = 12
        captureRow.distribution = .fillEqually

        // 그 밖의 시작 방법
        let more = NSStackView(views: [
            link("클립보드에서 ⇧⌘V", #selector(AppDelegate.newFromClipboard(_:))),
            link("파일 열기 ⌘O", #selector(AppDelegate.openDocument(_:))),
            link("빈 캔버스 ⌘N", #selector(AppDelegate.newBlank(_:))),
            link("캡처 폴더", #selector(AppDelegate.openPicturesFolder(_:))),
            link("설정…", #selector(AppDelegate.showSettings(_:))),
        ])
        more.spacing = 14

        // 권한 상태
        permissionRow.spacing = 8

        // 최근 캡처
        let recentTitle = NSTextField(labelWithString: "최근 캡처")
        recentTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        recentStack.spacing = 10
        recentStack.alignment = .top
        emptyLabel.textColor = .secondaryLabelColor

        // 메뉴 막대 안내
        let hint = NSTextField(wrappingLabelWithString: "이 창을 닫아도 Kkok은 메뉴 막대에서 계속 대기합니다. 메뉴 막대에 아이콘이 안 보이면(노치에 가려짐) 단축키나 Kkok 아이콘을 다시 눌러 이 창을 여세요.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        let showAtLaunch = NSButton(checkboxWithTitle: "Kkok을 열 때 이 창 보기", target: self, action: #selector(toggleShowAtLaunch(_:)))
        showAtLaunch.state = Preferences.shared.showHomeAtLaunch ? .on : .off
        showAtLaunch.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [header, captureRow, more, permissionRow, recentTitle, recentStack, emptyLabel, hint, showAtLaunch])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.setCustomSpacing(22, after: header)
        stack.setCustomSpacing(20, after: permissionRow)
        stack.setCustomSpacing(8, after: recentTitle)
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            hint.widthAnchor.constraint(equalToConstant: 572),
        ])
    }

    private func link(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: nil, action: action) // 앱 대리자까지 응답 사슬로 간다
        b.isBordered = false
        b.contentTintColor = .controlAccentColor
        b.font = .systemFont(ofSize: 12, weight: .medium)
        return b
    }

    /// 창을 보일 때마다 권한·최근 항목을 새로 고친다
    func reload() {
        permissionRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let ok = ScreenCapturer.hasPermission
        let dot = NSImageView(image: NSImage(systemSymbolName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                             accessibilityDescription: nil)!)
        dot.contentTintColor = ok ? .systemGreen : .systemOrange
        let text = NSTextField(labelWithString: ok ? "화면 기록 권한 있음" : "화면 기록 권한이 필요합니다 — 켠 뒤 Kkok을 다시 실행하세요")
        text.font = .systemFont(ofSize: 12)
        permissionRow.addArrangedSubview(dot)
        permissionRow.addArrangedSubview(text)
        if !ok {
            let b = NSButton(title: "시스템 설정 열기", target: self, action: #selector(openPrivacy))
            b.controlSize = .small
            permissionRow.addArrangedSubview(b)
        }

        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = HistoryStore.shared.recent(limit: 5)
        emptyLabel.isHidden = !items.isEmpty
        for m in items {
            let img = NSImage(contentsOf: HistoryStore.shared.thumbnailURL(id: m.id)) ?? NSImage()
            let b = NSButton(image: img, target: self, action: #selector(openRecent(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(m.id.uuidString)
            b.imageScaling = .scaleProportionallyDown
            b.bezelStyle = .regularSquare
            b.isBordered = true
            b.toolTip = m.name
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 104).isActive = true
            b.heightAnchor.constraint(equalToConstant: 72).isActive = true
            let label = NSTextField(labelWithString: String(m.name.suffix(8)))
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            let col = NSStackView(views: [b, label])
            col.orientation = .vertical
            col.spacing = 3
            recentStack.addArrangedSubview(col)
        }
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
    }

    @objc private func capture(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let mode = CaptureMode(rawValue: raw) else { return }
        window?.orderOut(nil) // 시작 창이 찍히지 않게
        CaptureController.shared.start(mode)
    }

    @objc private func openRecent(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        onOpenRecent?(id)
    }

    @objc private func openPrivacy() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func toggleShowAtLaunch(_ sender: NSButton) {
        Preferences.shared.showHomeAtLaunch = sender.state == .on
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: HomeWindowController.didClose, object: self)
    }

    static let didClose = Notification.Name("KkokHomeDidClose")
}
