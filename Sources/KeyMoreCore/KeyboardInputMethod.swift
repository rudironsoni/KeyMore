import Foundation

public struct KeyboardInputContext: Equatable, Sendable {
    public var activeModifiers: Set<SpecialKey>
    public var isShifted: Bool

    public init(activeModifiers: Set<SpecialKey> = [], isShifted: Bool = false) {
        self.activeModifiers = activeModifiers
        self.isShifted = isShifted
    }
}

public enum KeyboardInput: Equatable, Sendable {
    case special(SpecialKey)
    case character(String)
    case shift
    case delete
    case space
    case `return`
}

public enum KeyboardOutputEvent: Equatable, Sendable {
    case keyPress(keyLabel: String, keyPress: HIDKeyPress, fallback: KeyResolution)
    case modifierState(keyLabel: String, report: HIDKeyboardReport)
    case textInput(KeyResolution)
}

public struct KeyboardInputResult: Equatable, Sendable {
    public let outputEvents: [KeyboardOutputEvent]
    public let nextContext: KeyboardInputContext
    public let shouldRebuildCharacterLabels: Bool
    public let shouldUpdateModifierButtons: Bool

    public init(
        outputEvents: [KeyboardOutputEvent],
        nextContext: KeyboardInputContext,
        shouldRebuildCharacterLabels: Bool = false,
        shouldUpdateModifierButtons: Bool = false
    ) {
        self.outputEvents = outputEvents
        self.nextContext = nextContext
        self.shouldRebuildCharacterLabels = shouldRebuildCharacterLabels
        self.shouldUpdateModifierButtons = shouldUpdateModifierButtons
    }
}

public enum KeyboardInputMethod {
    public static func resolve(_ input: KeyboardInput, context: KeyboardInputContext) -> KeyboardInputResult {
        switch input {
        case .special(let specialKey):
            return resolveSpecialKey(specialKey, context: context)
        case .character(let rawCharacter):
            return resolveCharacter(rawCharacter, context: context)
        case .shift:
            var nextContext = context
            nextContext.isShifted.toggle()
            return KeyboardInputResult(
                outputEvents: [],
                nextContext: nextContext,
                shouldRebuildCharacterLabels: true
            )
        case .delete:
            return resolveBottomKey(
                keyLabel: "delete",
                usage: .deleteOrBackspace,
                fallbackAction: .deleteBackward,
                context: context
            )
        case .space:
            return resolveBottomKey(
                keyLabel: "space",
                usage: .space,
                fallbackAction: .insertText(" "),
                context: context
            )
        case .return:
            return resolveBottomKey(
                keyLabel: "return",
                usage: .returnOrEnter,
                fallbackAction: .insertText("\n"),
                context: context
            )
        }
    }

    private static func resolveSpecialKey(
        _ key: SpecialKey,
        context: KeyboardInputContext
    ) -> KeyboardInputResult {
        if key.isStickyModifier {
            var nextContext = context
            if nextContext.activeModifiers.contains(key) {
                nextContext.activeModifiers.remove(key)
            } else {
                nextContext.activeModifiers.insert(key)
            }

            return KeyboardInputResult(
                outputEvents: [
                    .modifierState(
                        keyLabel: key.displayTitle,
                        report: HIDKeyboardReport(modifiers: HIDReportBuilder.modifiers(for: nextContext.activeModifiers))
                    )
                ],
                nextContext: nextContext,
                shouldUpdateModifierButtons: true
            )
        }

        var outputEvents: [KeyboardOutputEvent] = []
        let fallback = KeyboardActionResolver.resolveSpecialKey(key)
        if let keyPress = shiftedIfNeeded(
            HIDReportBuilder.keyPress(for: key, activeModifiers: context.activeModifiers),
            context: context
        ) {
            outputEvents.append(.keyPress(keyLabel: key.displayTitle, keyPress: keyPress, fallback: fallback))
        } else {
            outputEvents.append(.textInput(fallback))
        }

        return clearingOneShotModifiersIfNeeded(outputEvents: outputEvents, context: context)
    }

    private static func resolveBottomKey(
        keyLabel: String,
        usage: HIDKeyboardUsage,
        fallbackAction: TextProxyAction,
        context: KeyboardInputContext
    ) -> KeyboardInputResult {
        let fallback = KeyResolution(action: fallbackAction, outcome: .textProxyOnly)
        let keyPress = shiftedIfNeeded(
            HIDKeyPress(usage: usage, modifiers: HIDReportBuilder.modifiers(for: context.activeModifiers)),
            context: context
        )!
        return clearingOneShotModifiersIfNeeded(
            outputEvents: [.keyPress(keyLabel: keyLabel, keyPress: keyPress, fallback: fallback)],
            context: context
        )
    }

    private static func resolveCharacter(
        _ rawCharacter: String,
        context: KeyboardInputContext
    ) -> KeyboardInputResult {
        let character = displayCharacter(rawCharacter, isShifted: context.isShifted)
        let fallback = KeyboardActionResolver.resolveCharacter(character, activeModifiers: context.activeModifiers)
        var outputEvents: [KeyboardOutputEvent] = []

        if let keyPress = characterKeyPress(for: rawCharacter, context: context) {
            outputEvents.append(.keyPress(keyLabel: character, keyPress: keyPress, fallback: fallback))
        } else {
            outputEvents.append(.textInput(fallback))
        }

        return clearingOneShotModifiersIfNeeded(outputEvents: outputEvents, context: context)
    }

    private static func clearingOneShotModifiersIfNeeded(
        outputEvents: [KeyboardOutputEvent],
        context: KeyboardInputContext
    ) -> KeyboardInputResult {
        guard !context.activeModifiers.isEmpty else {
            return KeyboardInputResult(outputEvents: outputEvents, nextContext: context)
        }

        var nextContext = context
        nextContext.activeModifiers.removeAll()
        return KeyboardInputResult(
            outputEvents: outputEvents + [.modifierState(keyLabel: "modifiers", report: .empty)],
            nextContext: nextContext,
            shouldUpdateModifierButtons: true
        )
    }

    private static func characterKeyPress(
        for rawCharacter: String,
        context: KeyboardInputContext
    ) -> HIDKeyPress? {
        guard let keyPress = HIDReportBuilder.keyPress(
            for: Character(rawCharacter.lowercased()),
            activeModifiers: context.activeModifiers
        ) else {
            return nil
        }

        return shiftedIfNeeded(keyPress, context: context)
    }

    private static func shiftedIfNeeded(_ keyPress: HIDKeyPress?, context: KeyboardInputContext) -> HIDKeyPress? {
        guard let keyPress else {
            return nil
        }

        guard context.isShifted else { return keyPress }

        var modifiers = keyPress.down.modifiers
        modifiers.insert(.leftShift)
        return HIDKeyPress(
            down: HIDKeyboardReport(modifiers: modifiers, usages: keyPress.down.usages),
            up: keyPress.up
        )
    }

    private static func displayCharacter(_ character: String, isShifted: Bool) -> String {
        isShifted ? character.uppercased() : character.lowercased()
    }
}

private extension SpecialKey {
    var isStickyModifier: Bool {
        switch self {
        case .control, .option, .command:
            return true
        case .escape, .tab:
            return false
        }
    }
}
