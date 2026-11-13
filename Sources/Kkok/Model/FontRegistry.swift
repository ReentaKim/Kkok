import CoreText
import Foundation

/// 앱에 넣은 폰트를 이 프로세스에서만 쓰도록 등록한다 (시스템에 설치하지 않음)
enum FontRegistry {
    private static var done = false

    /// 찾는 곳: 앱 번들 Resources/Fonts → KKOK_FONTS_DIR(개발·테스트용)
    static func registerBundledFonts() {
        guard !done else { return }
        done = true
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Fonts")) }
        if let env = ProcessInfo.processInfo.environment["KKOK_FONTS_DIR"] { dirs.append(URL(fileURLWithPath: env)) }
        for font in TextFont.allCases {
            guard let file = font.fileName else { continue }
            for d in dirs {
                let url = d.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: url.path) {
                    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                    break
                }
            }
        }
    }

    /// 실제로 쓸 수 있는지 (등록 실패 시 다른 글꼴로 대체되는 것을 확인)
    static func isAvailable(_ font: TextFont) -> Bool {
        let f = CTFontCreateWithName(font.postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(f) as String) == font.postScriptName
    }
}
