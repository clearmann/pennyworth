import AppKit
import Carbon

enum ModifierTapKey: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case command
    case option
    case control
    case shift

    static let trackedModifierFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        }
    }

    var keyCodes: Set<UInt16> {
        switch self {
        case .command: return [UInt16(kVK_Command), UInt16(kVK_RightCommand)]
        case .option: return [UInt16(kVK_Option), UInt16(kVK_RightOption)]
        case .control: return [UInt16(kVK_Control), UInt16(kVK_RightControl)]
        case .shift: return [UInt16(kVK_Shift), UInt16(kVK_RightShift)]
        }
    }

    static func from(keyCode: UInt16) -> ModifierTapKey? {
        allCases.first { $0.keyCodes.contains(keyCode) }
    }
}

enum HotKeyTrigger: Hashable, Sendable {
    case keyCombo(keyCode: UInt32, modifiers: UInt32)
    case rightCommandTap
    case doubleTap(ModifierTapKey)
}

enum HotKeyModifiers {
    static let rightCommand: UInt32 = 1 << 16
    static let deviceLeftCommandMask: UInt = 0x0000_0008
    static let deviceRightCommandMask: UInt = 0x0000_0010

    static var allowedModifiers: UInt32 {
        UInt32(cmdKey | optionKey | controlKey | shiftKey) | rightCommand
    }

    static func isRightCommandOnly(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command)
            && (flags.rawValue & deviceRightCommandMask) != 0
            && (flags.rawValue & deviceLeftCommandMask) == 0
    }

    static func hasBothCommandKeys(_ flags: NSEvent.ModifierFlags) -> Bool {
        let both = deviceLeftCommandMask | deviceRightCommandMask
        return (flags.rawValue & both) == both
    }

    static func usesRightCommand(_ modifiers: UInt32) -> Bool {
        (modifiers & rightCommand) != 0
    }

    static func hasConflictingCommandFlags(_ modifiers: UInt32) -> Bool {
        (modifiers & UInt32(cmdKey)) != 0 && (modifiers & rightCommand) != 0
    }

    static func carbonModifiers(for modifiers: UInt32) -> UInt32 {
        let base = modifiers & ~rightCommand
        return usesRightCommand(modifiers) ? (base | UInt32(cmdKey)) : base
    }
}

enum HotKeyKeyCodeTitles {
    static let extendedFunctionKeys: [UInt32: String] = [
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]

    private static let standardKeyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓", UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    static func title(for keyCode: UInt32) -> String {
        if let name = standardKeyNames[keyCode] { return name }
        if let functionKey = extendedFunctionKeys[keyCode] { return functionKey }
        return "Key \(keyCode)"
    }
}
