import Carbon.HIToolbox
import Foundation

/// ロック用のグローバルショートカット（Carbon ホットキー。アクセシビリティ権限不要）
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(_ shortcut: Shortcut) {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4253_544E), id: 1) // 'BSTN'
        RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyManager.shared.onPressed?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
