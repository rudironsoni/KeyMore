import Foundation

public struct HIDModifier: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let leftControl = HIDModifier(rawValue: 0x01)
    public static let leftShift = HIDModifier(rawValue: 0x02)
    public static let leftOption = HIDModifier(rawValue: 0x04)
    public static let leftCommand = HIDModifier(rawValue: 0x08)
    public static let rightControl = HIDModifier(rawValue: 0x10)
    public static let rightShift = HIDModifier(rawValue: 0x20)
    public static let rightOption = HIDModifier(rawValue: 0x40)
    public static let rightCommand = HIDModifier(rawValue: 0x80)
}

public enum HIDKeyboardUsage: UInt8, CaseIterable, Equatable, Sendable {
    case a = 0x04
    case b = 0x05
    case c = 0x06
    case d = 0x07
    case e = 0x08
    case f = 0x09
    case g = 0x0A
    case h = 0x0B
    case i = 0x0C
    case j = 0x0D
    case k = 0x0E
    case l = 0x0F
    case m = 0x10
    case n = 0x11
    case o = 0x12
    case p = 0x13
    case q = 0x14
    case r = 0x15
    case s = 0x16
    case t = 0x17
    case u = 0x18
    case v = 0x19
    case w = 0x1A
    case x = 0x1B
    case y = 0x1C
    case z = 0x1D
    case one = 0x1E
    case two = 0x1F
    case three = 0x20
    case four = 0x21
    case five = 0x22
    case six = 0x23
    case seven = 0x24
    case eight = 0x25
    case nine = 0x26
    case zero = 0x27
    case returnOrEnter = 0x28
    case escape = 0x29
    case deleteOrBackspace = 0x2A
    case tab = 0x2B
    case space = 0x2C
    case deleteForward = 0x4C
    case rightArrow = 0x4F
    case leftArrow = 0x50
    case downArrow = 0x51
    case upArrow = 0x52

    public static func letter(_ character: Character) -> HIDKeyboardUsage? {
        guard let scalar = character.lowercased().unicodeScalars.first,
              scalar.value >= 97,
              scalar.value <= 122 else {
            return nil
        }
        return HIDKeyboardUsage(rawValue: UInt8(scalar.value - 93))
    }
}

public struct HIDKeyboardReport: Equatable, Sendable {
    public let modifiers: HIDModifier
    public let usages: [UInt8]

    public init(modifiers: HIDModifier = [], usages: [UInt8] = []) {
        self.modifiers = modifiers
        self.usages = Array(usages.prefix(6))
    }

    public var bytes: [UInt8] {
        var bytes = [modifiers.rawValue, 0, 0, 0, 0, 0, 0, 0]
        for (index, usage) in usages.enumerated() {
            bytes[index + 2] = usage
        }
        return bytes
    }

    public static let empty = HIDKeyboardReport()
}

public enum HIDKeyboardReportDescriptor {
    public static let bootKeyboard: [UInt8] = [
        0x05, 0x01,       // Generic Desktop
        0x09, 0x06,       // Keyboard
        0xA1, 0x01,       // Application collection
        0x05, 0x07,       // Keyboard/Keypad usages
        0x19, 0xE0,       // Left Control
        0x29, 0xE7,       // Right Command
        0x15, 0x00,
        0x25, 0x01,
        0x75, 0x01,
        0x95, 0x08,
        0x81, 0x02,       // Modifier byte
        0x95, 0x01,
        0x75, 0x08,
        0x81, 0x01,       // Reserved byte
        0x95, 0x05,
        0x75, 0x01,
        0x05, 0x08,
        0x19, 0x01,
        0x29, 0x05,
        0x91, 0x02,       // LED output report
        0x95, 0x01,
        0x75, 0x03,
        0x91, 0x01,       // LED padding
        0x95, 0x06,
        0x75, 0x08,
        0x15, 0x00,
        0x25, 0x65,
        0x05, 0x07,
        0x19, 0x00,
        0x29, 0x65,
        0x81, 0x00,       // Six key usage bytes
        0xC0
    ]
}

public struct HIDKeyPress: Equatable, Sendable {
    public let down: HIDKeyboardReport
    public let up: HIDKeyboardReport

    public init(down: HIDKeyboardReport, up: HIDKeyboardReport = .empty) {
        self.down = down
        self.up = up
    }

    public init(usage: HIDKeyboardUsage, modifiers: HIDModifier = []) {
        self.down = HIDKeyboardReport(modifiers: modifiers, usages: [usage.rawValue])
        self.up = HIDKeyboardReport(modifiers: modifiers)
    }
}

public enum HIDReportBuilder {
    public static func modifiers(for specialKeys: Set<SpecialKey>) -> HIDModifier {
        var modifiers: HIDModifier = []
        if specialKeys.contains(.control) {
            modifiers.insert(.leftControl)
        }
        if specialKeys.contains(.option) {
            modifiers.insert(.leftOption)
        }
        if specialKeys.contains(.command) {
            modifiers.insert(.leftCommand)
        }
        return modifiers
    }

    public static func keyPress(for specialKey: SpecialKey, activeModifiers: Set<SpecialKey> = []) -> HIDKeyPress? {
        let modifiers = modifiers(for: activeModifiers)
        switch specialKey {
        case .escape:
            return HIDKeyPress(usage: .escape, modifiers: modifiers)
        case .tab:
            return HIDKeyPress(usage: .tab, modifiers: modifiers)
        case .control:
            return HIDKeyPress(down: HIDKeyboardReport(modifiers: .leftControl))
        case .option:
            return HIDKeyPress(down: HIDKeyboardReport(modifiers: .leftOption))
        case .command:
            return HIDKeyPress(down: HIDKeyboardReport(modifiers: .leftCommand))
        }
    }

    public static func keyPress(for character: Character, activeModifiers: Set<SpecialKey>) -> HIDKeyPress? {
        guard let usage = HIDKeyboardUsage.letter(character) else {
            return nil
        }
        return HIDKeyPress(usage: usage, modifiers: modifiers(for: activeModifiers))
    }
}
