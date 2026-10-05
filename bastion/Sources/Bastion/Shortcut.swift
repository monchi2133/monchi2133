import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var key: String

    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    static let defaultLock = Shortcut(
        keyCode: UInt16(kVK_ANSI_L),
        modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
        key: "L"
    )
    static let defaultUnlock = Shortcut(
        keyCode: UInt16(kVK_ANSI_U),
        modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
        key: "U"
    )

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantFlags) }

    var displayString: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if flags.contains(.command) { f.insert(.maskCommand) }
        if flags.contains(.option) { f.insert(.maskAlternate) }
        if flags.contains(.control) { f.insert(.maskControl) }
        if flags.contains(.shift) { f.insert(.maskShift) }
        return f
    }

    static func keyName(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
