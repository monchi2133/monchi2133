import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

/// CGEventTap で HID レベルのすべての入力（キーボード・マウス・トラックパッド・ジェスチャー）を破棄する。
/// 入力はどのアプリ（ターミナル・IDE・エージェント）にも届かない。
final class InputBlocker {
    var unlockShortcut: Shortcut = .defaultUnlock
    var onUnlockShortcut: (() -> Void)?
    /// ロック画面の指紋ボタンの位置（グローバル座標）か判定する
    var isUnlockHotspot: ((CGPoint) -> Bool)?
    var onActivity: (() -> Void)?
    /// 手元のマウスが動いた（目の前に人がいる）
    var onLocalPointer: (() -> Void)?
    private var lastLocalPointer = Date.distantPast

    /// true の間は入力を通す（認証ダイアログの操作用）
    var passThrough = false

    /// ロック中もリモートデスクトップ（画面共有・Chrome リモートデスクトップ）からの入力を通す
    var allowRemoteInput = false
    var onRemoteInput: (() -> Void)?
    /// ブロックしたプログラム由来の入力の送り元（設定画面の診断表示用）
    var onBlockedSource: ((String) -> Void)?

    /// リモートデスクトップの入力を送り込むプロセス名・パスに含まれる文字列
    private static let remoteSourceHints = [
        "screensharingd", "screensharingagent", "screen sharing",          // macOS 画面共有
        "remoting_me2me_host", "chromeremotedesktop", "chrome remote desktop", // Chrome リモートデスクトップ
    ]
    private var remoteSourceCache: [pid_t: Bool] = [:]
    private var lastRemoteNotice = Date.distantPast
    private var lastBlockedNotice = Date.distantPast

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
        remoteSourceCache.removeAll()
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

    /// 認証ダイアログ表示中でも通さない操作（アプリ切替・Spotlight・Mission Control など）。
    /// 認証に必要なのは文字入力・Return・Esc・クリックだけ。
    private static func isEscapeAttempt(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp else { return false }
        let flags = event.flags
        if flags.contains(.maskCommand) { return true }   // ⌘Tab, ⌘Space, ⌘Q, ⌘W …
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
        if flags.contains(.maskControl) && arrows.contains(code) { return true } // デスクトップ切替
        // Mission Control / Launchpad / Spotlight / F3 / F4
        return [160, 131, 177, kVK_F3, kVK_F4].contains(code)
    }

    private func isRemoteSource(_ pid: pid_t) -> Bool {
        if let cached = remoteSourceCache[pid] { return cached }
        let name = Self.processDescription(pid).lowercased()
        let isRemote = Self.remoteSourceHints.contains { name.contains($0) }
        remoteSourceCache[pid] = isRemote
        return isRemote
    }

    private func noteBlockedSource(_ pid: pid_t) {
        let now = Date()
        guard now.timeIntervalSince(lastBlockedNotice) > 2 else { return }
        lastBlockedNotice = now
        let description = Self.processDescription(pid)
        DispatchQueue.main.async { [weak self] in self?.onBlockedSource?(description) }
    }

    /// "プロセス名 (実行ファイルのパス)"
    static func processDescription(_ pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: 256)
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let name = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 ? String(cString: nameBuffer) : "pid \(pid)"
        let path = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 ? String(cString: pathBuffer) : ""
        return path.isEmpty ? name : "\(name) (\(path))"
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if passThrough {
            return Self.isEscapeAttempt(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        // 手元のキーボード・マウスの入力は送り元 PID が 0。プログラムが送り込んだ入力だけ送り元を調べる。
        let sourcePID = pid_t(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID))
        if sourcePID > 0 {
            if allowRemoteInput && isRemoteSource(sourcePID) {
                let now = Date()
                if now.timeIntervalSince(lastRemoteNotice) > 1 {
                    lastRemoteNotice = now
                    DispatchQueue.main.async { [weak self] in self?.onRemoteInput?() }
                }
                return Unmanaged.passUnretained(event)
            }
            if type != .mouseMoved {
                noteBlockedSource(sourcePID)
            }
        }
        // カーソル移動だけは通す（指紋ボタンまで動かせるように）。クリックやドラッグは通さない。
        if type == .mouseMoved {
            if sourcePID == 0 {
                let now = Date()
                if now.timeIntervalSince(lastLocalPointer) > 1 {
                    lastLocalPointer = now
                    DispatchQueue.main.async { [weak self] in self?.onLocalPointer?() }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown, isUnlockHotspot?(event.location) == true {
            DispatchQueue.main.async { [weak self] in self?.onUnlockShortcut?() }
            return nil
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
