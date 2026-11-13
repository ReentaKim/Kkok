import AppKit
import Carbon.HIToolbox

/// Carbon 전역 단축키 (손쉬운 사용 권한이 필요 없다). FR-01·42
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false
    private var nextID: UInt32 = 1

    /// 등록 실패한 이름 (다른 앱이 이미 쓰는 단축키)
    private(set) var failures: [String] = []

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actions.removeAll()
        failures.removeAll()
    }

    @discardableResult
    func register(_ hk: HotKey, name: String, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4B4B4F4B) /* 'KKOK' */, id: id)
        let status = RegisterEventHotKey(hk.keyCode, hk.modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            failures.append("\(name) (\(hk.display))")
            return false
        }
        refs[id] = ref
        actions[id] = action
        return true
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let id = hkID.id
            DispatchQueue.main.async { HotKeyCenter.shared.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
