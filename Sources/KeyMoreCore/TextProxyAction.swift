import Foundation

public enum TextProxyAction: Equatable {
    case insertText(String)
    case deleteBackward
    case noOperation(String)
}

public struct KeyResolution: Equatable {
    public let action: TextProxyAction
    public let outcome: KeyEmissionOutcome

    public init(action: TextProxyAction, outcome: KeyEmissionOutcome) {
        self.action = action
        self.outcome = outcome
    }
}

public enum KeyboardActionResolver {
    public static func resolveSpecialKey(_ key: SpecialKey) -> KeyResolution {
        switch key {
        case .tab:
            return KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly)
        case .escape:
            return KeyResolution(action: .insertText("\u{1B}"), outcome: .textProxyOnly)
        case .control, .option, .command:
            return KeyResolution(
                action: .noOperation("\(key.displayTitle) requires a hardware-equivalent event path"),
                outcome: .unknown
            )
        }
    }

    public static func resolveCharacter(_ character: String, activeModifiers: Set<SpecialKey>) -> KeyResolution {
        guard let scalar = character.uppercased().unicodeScalars.first else {
            return KeyResolution(action: .noOperation("Empty character"), outcome: .unknown)
        }

        if activeModifiers.contains(.command) {
            return KeyResolution(
                action: .noOperation("Command shortcuts require a hardware-equivalent event path"),
                outcome: .unknown
            )
        }

        if activeModifiers.contains(.control),
           let controlScalar = controlCharacter(for: scalar) {
            return KeyResolution(action: .insertText(String(controlScalar)), outcome: .textProxyOnly)
        }

        if activeModifiers.contains(.option) {
            return KeyResolution(action: .insertText("\u{1B}" + character), outcome: .textProxyOnly)
        }

        return KeyResolution(action: .insertText(character), outcome: .textProxyOnly)
    }

    private static func controlCharacter(for scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let value = scalar.value
        guard value >= 65, value <= 90 else {
            return nil
        }
        return Unicode.Scalar(value - 64)
    }
}

