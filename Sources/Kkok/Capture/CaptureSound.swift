import AudioToolbox
import Foundation

/// 캡처 순간의 "찰칵" 소리 (FR-27)
/// macOS 스크린샷과 같은 시스템 소리 파일을 그대로 쓴다(앱에 소리 파일을 넣지 않음).
/// 시스템 사운드로 재생하므로 "알림 음량"과 "사용자 인터페이스 사운드 효과 재생" 설정을 따른다.
enum CaptureSound {
    private static let candidates = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif",
    ]

    /// 처음 쓸 때 한 번만 등록한다. 파일이 없으면 0(소리 없음)
    private static let soundID: SystemSoundID = {
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &id) == noErr { return id }
        }
        return 0
    }()

    static var isAvailable: Bool { soundID != 0 }

    static func play() {
        guard Preferences.shared.captureSound, soundID != 0 else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
