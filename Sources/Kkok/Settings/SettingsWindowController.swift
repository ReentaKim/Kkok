import AppKit

/// 설정: 캡처 단축키 5개, 타이머 초, 로그인 시 실행 (FR-41·42)
final class SettingsWindowController: NSWindowController {
    private var recorders: [CaptureMode: HotKeyRecorder] = [:]
    private let failureLabel = NSTextField(wrappingLabelWithString: "")
    private let loginCheck = NSButton(checkboxWithTitle: "로그인할 때 Kkok 실행", target: nil, action: nil)
    private let timerPopup = NSPopUpButton()

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Kkok 설정"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        let grid = NSGridView()
        grid.rowSpacing = 10
        grid.columnSpacing = 12

        let header = NSTextField(labelWithString: "캡처 단축키")
        header.font = .boldSystemFont(ofSize: 13)
        grid.addRow(with: [header, NSGridCell.emptyContentView])

        for mode in CaptureMode.allCases {
            let label = NSTextField(labelWithString: mode.title)
            let rec = HotKeyRecorder(mode: mode)
            rec.translatesAutoresizingMaskIntoConstraints = false
            rec.widthAnchor.constraint(equalToConstant: 170).isActive = true
            rec.heightAnchor.constraint(equalToConstant: 24).isActive = true
            recorders[mode] = rec
            grid.addRow(with: [label, rec])
        }

        timerPopup.addItems(withTitles: (1...15).map { "\($0)초" })
        timerPopup.selectItem(at: Preferences.shared.timerSeconds - 1)
        timerPopup.target = self
        timerPopup.action = #selector(timerChanged)
        grid.addRow(with: [NSTextField(labelWithString: "타이머"), timerPopup])

        loginCheck.target = self
        loginCheck.action = #selector(loginChanged)
        loginCheck.state = LaunchAtLogin.enabled ? .on : .off
        grid.addRow(with: [NSGridCell.emptyContentView, loginCheck])

        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false

        let help = NSTextField(wrappingLabelWithString: "칸을 누르고 새 단축키를 누르세요. ⌫로 지우고, esc로 취소합니다. 영역 캡처에서 ⌥를 누른 채 놓으면 영역을 다듬은 뒤 찍을 수 있습니다.")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 11)
        help.translatesAutoresizingMaskIntoConstraints = false
        failureLabel.textColor = .systemRed
        failureLabel.font = .systemFont(ofSize: 11)
        failureLabel.translatesAutoresizingMaskIntoConstraints = false

        for v in [grid, help, failureLabel] { content.addSubview(v) }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            help.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            help.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            help.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            failureLabel.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 8),
            failureLabel.leadingAnchor.constraint(equalTo: help.leadingAnchor),
            failureLabel.trailingAnchor.constraint(equalTo: help.trailingAnchor),
            failureLabel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
        ])
        reloadFailures()
    }

    func reloadFailures() {
        let f = HotKeyCenter.shared.failures
        failureLabel.stringValue = f.isEmpty ? "" : "다른 앱이 쓰고 있어 등록하지 못함: " + f.joined(separator: ", ")
        recorders.values.forEach { $0.reload() }
    }

    override func showWindow(_ sender: Any?) {
        loginCheck.state = LaunchAtLogin.enabled ? .on : .off
        reloadFailures()
        super.showWindow(sender)
    }

    @objc private func timerChanged() {
        Preferences.shared.timerSeconds = timerPopup.indexOfSelectedItem + 1
    }

    @objc private func loginChanged() {
        LaunchAtLogin.enabled = loginCheck.state == .on
        loginCheck.state = LaunchAtLogin.enabled ? .on : .off
    }
}

/// 누르면 다음 키 조합을 받아 단축키로 정한다
final class HotKeyRecorder: NSView {
    let mode: CaptureMode
    private var recording = false { didSet { needsDisplay = true; if recording { HotKeyCenter.shared.unregisterAll() } } }

    init(mode: CaptureMode) {
        self.mode = mode
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    func reload() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let p = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        p.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        p.stroke()
        let text = recording ? "키를 누르세요…" : (Preferences.shared.hotKey(for: mode)?.display ?? "없음")
        let s = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: recording ? .regular : .medium),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor])
        let sz = s.size()
        s.draw(at: CGPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2))
    }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        if recording { recording = false; NotificationCenter.default.post(name: Preferences.didChange, object: nil) }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch Int(event.keyCode) {
        case 53: // esc
            recording = false
            NotificationCenter.default.post(name: Preferences.didChange, object: nil)
            return
        case 51, 117: // 지우기
            recording = false
            Preferences.shared.setHotKey(nil, for: mode)
            return
        default: break
        }
        // 수정키 하나 이상 필요 (F키는 예외)
        let isF = (122...127).contains(Int(event.keyCode)) || [96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120].contains(Int(event.keyCode))
        guard !mods.isEmpty || isF else { NSSound.beep(); return }
        recording = false
        Preferences.shared.setHotKey(HotKey(keyCode: UInt32(event.keyCode), modifiers: HotKey.carbonModifiers(mods)), for: mode)
    }
}
