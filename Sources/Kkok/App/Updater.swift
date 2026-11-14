import AppKit
import CryptoKit

/// 자체 업데이트 (FR-28) — MD Editor의 방식을 Swift로 옮긴 것
///
/// Apple 개발자 인증서가 없는 ad-hoc 서명 앱이라 Sparkle 같은 표준 방식 대신:
///   1. GitHub Releases API로 최신 버전 확인 (보내는 것은 요청뿐, 캡처·개인 정보 없음)
///   2. `Kkok-<버전>.zip` 다운로드 → SHA-256 검증(릴리스 asset digest 또는 릴리스 설명의 값)
///   3. 풀어서 번들 ID·버전·코드 서명 검증
///   4. 앱이 끝난 뒤 작은 셸 스크립트가 기존 앱과 바꾸고 다시 실행, 실패하면 되돌림
///   5. 다음 실행 때 결과를 알림
/// Homebrew로 설치한 경우에는 스스로 바꾸지 않고 `brew upgrade --cask kkok`을 안내한다.
final class Updater: NSObject, URLSessionDownloadDelegate {
    static let shared = Updater()

    static let repo = "ReentaKim/Kkok"
    static let bundleID = "io.github.reentakim.kkok"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!
    static let brewCommand = "brew upgrade --cask kkok"
    static let checkInterval: TimeInterval = 6 * 60 * 60

    private let env = ProcessInfo.processInfo.environment
    /// 테스트 전용: 로컬 가짜 릴리스 서버 (이때만 127.0.0.1 http 다운로드 허용)
    private var testAPI: String? { env["KKOK_UPDATE_API"] }
    private var apiURL: URL {
        URL(string: testAPI ?? "https://api.github.com/repos/\(Self.repo)/releases/latest")!
    }
    private func isAllowedDownload(_ url: URL) -> Bool {
        let s = url.absoluteString
        if testAPI != nil { return s.hasPrefix("http://127.0.0.1:") }
        return s.hasPrefix("https://github.com/\(Self.repo)/releases/download/")
    }

    struct Release {
        let version: String
        let notesURL: URL
        let zipURL: URL?
        let sha256: String?
    }

    /// 자동 확인으로 찾은 새 버전 (메뉴·시작 창 표시용)
    private(set) var pending: Release?
    static let didChange = Notification.Name("KkokUpdaterDidChange")

    private var busy = false
    private var timer: Timer?
    private var progressPanel: UpdateProgressPanel?
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var staged: (app: URL, dir: URL, version: String)?
    private var installOnQuit = false
    private var relaunchAfterInstall = false

    // MARK: 지금 실행 중인 앱

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 실행 중인 .app 번들 (개발 중 `swift run`이면 nil)
    static var appBundle: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// Homebrew cask로 설치했는지
    static var isHomebrewInstall: Bool {
        guard let app = appBundle, app.path.hasPrefix("/Applications/") else { return false }
        return ["/opt/homebrew/Caskroom/kkok", "/usr/local/Caskroom/kkok"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// 앱이 스스로 바꿀 수 있는지 (번들 폴더에 쓸 수 있어야 함)
    static var canSelfInstall: Bool {
        guard let app = appBundle, !isHomebrewInstall else { return false }
        return FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    private var resultFile: URL {
        if let p = env["KKOK_UPDATE_RESULT"] { return URL(fileURLWithPath: p) }
        return HistoryStore.shared.root.appendingPathComponent("update-result.json")
    }

    // MARK: 시작

    func start() {
        reportPreviousResult()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.autoCheck() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.autoCheck()
        }
        // 테스트 전용: 확인 → 받기 → 설치를 묻지 않고 진행(다시 실행하지 않음)
        if env["KKOK_UPDATE_AUTOINSTALL"] != nil {
            Task { @MainActor in await self.check(manual: false, autoInstallForTest: true) }
        }
    }

    private func autoCheck() {
        guard Preferences.shared.autoUpdateCheck, env["KKOK_UPDATE_AUTOINSTALL"] == nil else { return }
        Task { @MainActor in await self.check(manual: false) }
    }

    // MARK: 확인

    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
        let pb = b.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
        for i in 0..<3 {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// 릴리스 JSON에서 필요한 것만 꺼낸다 (테스트하기 쉽게 따로 둠)
    static func parse(_ data: Data) -> Release? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let notes = (obj["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
        let assets = obj["assets"] as? [[String: Any]] ?? []
        let asset = assets.first { ($0["name"] as? String) == "Kkok-\(version).zip" }
        let zip = (asset?["browser_download_url"] as? String).flatMap(URL.init(string:))
        var sha: String?
        if let d = asset?["digest"] as? String, d.hasPrefix("sha256:") { sha = String(d.dropFirst(7)) }
        if sha == nil, let body = obj["body"] as? String,
           let r = body.range(of: "`[0-9a-fA-F]{64}`", options: .regularExpression) {
            sha = String(body[r].dropFirst().dropLast())
        }
        return Release(version: version, notesURL: notes, zipURL: zip, sha256: sha?.lowercased())
    }

    @MainActor
    func check(manual: Bool, autoInstallForTest: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            var req = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("Kkok-Updater", forHTTPHeaderField: "User-Agent")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let rel = Self.parse(data) else {
                throw UpdateError.message("GitHub 응답을 읽지 못했습니다 (\((resp as? HTTPURLResponse)?.statusCode ?? 0)).")
            }
            guard Self.compare(rel.version, Self.currentVersion) > 0 else {
                pending = nil
                NotificationCenter.default.post(name: Self.didChange, object: nil)
                if manual { alert("최신 버전을 쓰고 있습니다.", "현재 버전: \(Self.currentVersion)") }
                return
            }
            pending = rel
            NotificationCenter.default.post(name: Self.didChange, object: nil)
            if autoInstallForTest {
                busy = false
                await install(rel, askToRelaunch: false)
            } else if manual {
                busy = false
                offer(rel)
            }
        } catch {
            if manual { alert("업데이트를 확인하지 못했습니다.", error.localizedDescription) }
            else { NSLog("Kkok: 업데이트 확인 실패 %@", error.localizedDescription) }
        }
    }

    @MainActor
    private func alert(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.runModal()
    }

    // MARK: 새 버전 안내

    /// 메뉴·시작 창의 "새 버전 받기"나 수동 확인에서
    @MainActor
    func offer(_ rel: Release? = nil) {
        guard let rel = rel ?? pending else { return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "새 버전 Kkok \(rel.version)이 나왔습니다"
        if Self.isHomebrewInstall {
            a.informativeText = "지금 버전: \(Self.currentVersion)\n\nHomebrew로 설치하셨습니다. 터미널에서 아래 명령으로 업데이트하세요.\n\n\(Self.brewCommand)"
            a.addButton(withTitle: "명령 복사")
            a.addButton(withTitle: "바뀐 점 보기")
            a.addButton(withTitle: "닫기")
            switch a.runModal() {
            case .alertFirstButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.brewCommand, forType: .string)
            case .alertSecondButtonReturn: NSWorkspace.shared.open(rel.notesURL)
            default: break
            }
        } else if Self.canSelfInstall, rel.zipURL != nil, rel.sha256 != nil {
            a.informativeText = "지금 버전: \(Self.currentVersion)\n\n받아서 확인한 뒤 Kkok을 다시 시작하면 바뀝니다. 설정과 캡처는 그대로 남습니다."
            a.addButton(withTitle: "업데이트")
            a.addButton(withTitle: "바뀐 점 보기")
            a.addButton(withTitle: "나중에")
            switch a.runModal() {
            case .alertFirstButtonReturn: Task { @MainActor in await self.install(rel, askToRelaunch: true) }
            case .alertSecondButtonReturn: NSWorkspace.shared.open(rel.notesURL)
            default: break
            }
        } else {
            a.informativeText = "지금 버전: \(Self.currentVersion)\n\n이 위치에서는 자동으로 바꿀 수 없습니다. 내려받기 페이지에서 받아 주세요."
            a.addButton(withTitle: "내려받기 페이지 열기")
            a.addButton(withTitle: "닫기")
            if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(rel.notesURL) }
        }
    }

    // MARK: 받기 · 검증 · 준비

    enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    @MainActor
    private func install(_ rel: Release, askToRelaunch: Bool) async {
        guard !busy, let zipURL = rel.zipURL, let sha = rel.sha256, Self.appBundle != nil else { return }
        busy = true
        defer { busy = false }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("kkok-update-\(UUID().uuidString)", isDirectory: true)
        do {
            guard isAllowedDownload(zipURL) else { throw UpdateError.message("허용되지 않은 다운로드 주소입니다.") }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let panel = UpdateProgressPanel(version: rel.version)
            progressPanel = panel
            if askToRelaunch { panel.show() }

            // 1) 받기
            let tmp = try await download(zipURL)
            let zip = dir.appendingPathComponent(zipURL.lastPathComponent)
            try fm.moveItem(at: tmp, to: zip)

            // 2) SHA-256
            panel.setStatus("확인하는 중…")
            guard try Self.sha256(of: zip) == sha else {
                throw UpdateError.message("받은 파일의 SHA-256이 릴리스와 다릅니다. 파일이 손상되었을 수 있습니다.")
            }

            // 3) 풀기 → 번들 ID·버전·서명
            let out = dir.appendingPathComponent("unzipped", isDirectory: true)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
            guard let appName = try fm.contentsOfDirectory(atPath: out.path).first(where: { $0.hasSuffix(".app") }) else {
                throw UpdateError.message("받은 파일 안에서 앱을 찾지 못했습니다.")
            }
            let app = out.appendingPathComponent(appName)
            let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == Self.bundleID else { throw UpdateError.message("앱 ID가 다릅니다.") }
            guard info?["CFBundleShortVersionString"] as? String == rel.version else { throw UpdateError.message("앱 버전이 다릅니다.") }
            try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            _ = try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])

            staged = (app, dir, rel.version)
            panel.close()
            progressPanel = nil

            // 4) 설치는 앱이 끝난 뒤
            installOnQuit = true
            if !askToRelaunch {
                relaunchAfterInstall = false
                NSApp.terminate(nil)
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Kkok \(rel.version) 설치 준비가 끝났습니다"
            a.informativeText = "지금 다시 시작하면 바로 바뀝니다. 나중에 하면 Kkok을 끌 때 바뀝니다."
            a.addButton(withTitle: "지금 다시 시작")
            a.addButton(withTitle: "끌 때 설치")
            if a.runModal() == .alertFirstButtonReturn {
                relaunchAfterInstall = true
                NSApp.terminate(nil)
            }
        } catch {
            progressPanel?.close()
            progressPanel = nil
            try? fm.removeItem(at: dir)
            if askToRelaunch {
                NSApp.activate(ignoringOtherApps: true)
                let a = NSAlert()
                a.messageText = "업데이트를 받지 못했습니다"
                a.informativeText = error.localizedDescription
                a.addButton(withTitle: "내려받기 페이지 열기")
                a.addButton(withTitle: "닫기")
                if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(rel.notesURL) }
            } else {
                NSLog("Kkok: 업데이트 실패 %@", error.localizedDescription)
                if env["KKOK_UPDATE_AUTOINSTALL"] != nil { exit(2) }
            }
        }
    }

    private func download(_ url: URL) async throws -> URL {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        var req = URLRequest(url: url)
        req.setValue("Kkok-Updater", forHTTPHeaderField: "User-Agent")
        return try await withCheckedThrowingContinuation { cont in
            downloadContinuation = cont
            session.downloadTask(with: req).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressPanel?.setProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 이 함수가 끝나면 임시 파일이 지워지므로 바로 옮긴다
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("kkok-dl-\(UUID().uuidString).zip")
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateError.message("다운로드 실패 (\(http.statusCode))")
            }
            try FileManager.default.moveItem(at: location, to: keep)
            downloadContinuation?.resume(returning: keep)
        } catch {
            downloadContinuation?.resume(throwing: error)
        }
        downloadContinuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, let c = downloadContinuation {
            downloadContinuation = nil
            c.resume(throwing: error)
        }
        session.finishTasksAndInvalidate()
    }

    static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw UpdateError.message("\((tool as NSString).lastPathComponent) 실패: \(out.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return out
    }

    // MARK: 설치 (앱이 끝난 뒤)

    static let installScript = """
    #!/bin/sh
    # Kkok 업데이트 설치 — 앱이 완전히 끝난 뒤 실행된다
    PID="$1"; TARGET="$2"; STAGED="$3"; RESULT="$4"; RELAUNCH="$5"; VERSION="$6"; DIR="$7"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.2; i=$((i+1)); done
    BACKUP="$DIR/previous.app"
    write() { mkdir -p "$(dirname "$RESULT")"; printf '{"ok":%s,"version":"%s","reason":"%s"}' "$1" "$VERSION" "$2" > "$RESULT"; }
    fail() {
      write false "$1"
      [ "$RELAUNCH" = 1 ] && open "$TARGET"
      exit 1
    }
    mv "$TARGET" "$BACKUP" 2>/dev/null || fail move-old
    if ! mv "$STAGED" "$TARGET" 2>/dev/null; then
      mv "$BACKUP" "$TARGET" 2>/dev/null
      fail move-new
    fi
    rm -rf "$DIR"
    write true ""
    [ "$RELAUNCH" = 1 ] && open "$TARGET"
    exit 0
    """

    /// applicationWillTerminate에서 부른다
    func runInstallerIfNeeded() {
        guard installOnQuit, let staged, let target = Self.appBundle else { return }
        installOnQuit = false
        let script = staged.dir.appendingPathComponent("install.sh")
        do {
            try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, staged.app.path,
                           resultFile.path, relaunchAfterInstall ? "1" : "0", staged.version, staged.dir.path]
            try p.run() // 앱이 끝나도 계속 돈다
        } catch {
            NSLog("Kkok: 업데이트 설치 스크립트 실행 실패 %@", error.localizedDescription)
        }
    }

    // MARK: 지난 설치 결과

    private func reportPreviousResult() {
        guard env["KKOK_UPDATE_AUTOINSTALL"] == nil,
              let data = try? Data(contentsOf: resultFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: resultFile)
        let version = obj["version"] as? String ?? ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            if obj["ok"] as? Bool == true {
                guard version == Self.currentVersion else { return }
                a.messageText = "Kkok \(version)으로 업데이트했습니다"
                a.informativeText = "바뀐 점은 메뉴 › 업데이트 확인… 또는 GitHub의 변경 기록에서 볼 수 있습니다."
                a.addButton(withTitle: "확인")
                a.addButton(withTitle: "바뀐 점 보기")
                if a.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(Self.repo)/blob/main/CHANGELOG.md")!)
                }
            } else {
                a.messageText = "Kkok \(version) 업데이트를 설치하지 못했습니다"
                a.informativeText = """
                macOS가 앱 파일 교체를 막았습니다. 기존 앱은 그대로입니다.

                • 시스템 설정 › 개인정보 보호 및 보안 › 앱 관리에서 Kkok을 허용한 뒤 다시 업데이트하거나
                • 내려받기 페이지에서 직접 받아 응용 프로그램 폴더에 넣어 주세요.
                """
                a.addButton(withTitle: "내려받기 페이지 열기")
                a.addButton(withTitle: "앱 관리 설정 열기")
                a.addButton(withTitle: "닫기")
                switch a.runModal() {
                case .alertFirstButtonReturn: NSWorkspace.shared.open(Self.releasesPage)
                case .alertSecondButtonReturn:
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!)
                default: break
                }
            }
        }
    }
}

/// 받는 동안 보이는 작은 창
final class UpdateProgressPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()

    init(version: String) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 320, height: 96), styleMask: [.titled], backing: .buffered, defer: false)
        title = "Kkok 업데이트"
        isReleasedWhenClosed = false
        label.stringValue = "Kkok \(version) 받는 중…"
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        let stack = NSStackView(views: [label, bar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView = NSView()
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor),
            bar.widthAnchor.constraint(equalToConstant: 280),
        ])
    }

    func show() {
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func setProgress(_ v: Double) { bar.doubleValue = v }

    func setStatus(_ s: String) {
        label.stringValue = s
        bar.isIndeterminate = true
        bar.startAnimation(nil)
    }
}
