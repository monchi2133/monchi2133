import CoreGraphics
import Foundation

/// CGEventTap で HID レベルのすべての入力（キーボード・マウス・トラックパッド・ジェスチャー）を破棄する。
/// 入力はどのアプリ（ターミナル・IDE・エージェント）にも届かない。
final class InputBlocker {
    var unlockShortcut: Shortcut = .defaultUnlock
    var onUnlockShortcut: (() -> Void)?
    var onActivity: (() -> Void)?

    /// true の間は入力を通す（認証ダイアログの操作用）
    var passThrough = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastActivity = Date.distantPast

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        if tap != nil { return true }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask.max,
            callback: inputBlockerCallback,
            userInfo: userInfo
        ) else {
            return false
        }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        passThrough = false
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        passThrough = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if passThrough {
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            if code == unlockShortcut.keyCode && event.flags.intersection(relevant) == unlockShortcut.cgFlags {
                DispatchQueue.main.async { [weak self] in self?.onUnlockShortcut?() }
                return nil
            }
        }
        let now = Date()
        if now.timeIntervalSince(lastActivity) > 0.6 {
            lastActivity = now
            DispatchQueue.main.async { [weak self] in self?.onActivity?() }
        }
        return nil
    }
}

private func inputBlockerCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<InputBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    return blocker.handle(type: type, event: event)
}
