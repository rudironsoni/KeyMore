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

public struct KeyboardLanguageLayout: Equatable, Sendable {
    public let languageIdentifier: String
    public let alphabeticRows: [[String]]
    public let numericRows: [[String]]
    public let symbolRows: [[String]]
    public let punctuationRow: [String]
    public let spaceTitle: String
    public let prefersRightToLeft: Bool

    public var languageCode: String {
        languageIdentifier.split(separator: "-").first.map(String.init) ?? "en"
    }

    public var languageSwitchTitle: String {
        languageCode.uppercased()
    }

    public init(
        languageIdentifier: String,
        alphabeticRows: [[String]],
        numericRows: [[String]] = Self.defaultNumericRows,
        symbolRows: [[String]] = Self.defaultSymbolRows,
        punctuationRow: [String] = [".", ",", "?", "!", "'"],
        spaceTitle: String = "space",
        prefersRightToLeft: Bool = false
    ) {
        self.languageIdentifier = languageIdentifier
        self.alphabeticRows = alphabeticRows
        self.numericRows = numericRows
        self.symbolRows = symbolRows
        self.punctuationRow = punctuationRow
        self.spaceTitle = spaceTitle
        self.prefersRightToLeft = prefersRightToLeft
    }

    public static func layout(
        for primaryLanguage: String?,
        preferredLanguages: [String] = []
    ) -> KeyboardLanguageLayout {
        let identifier = normalizedIdentifier(primaryLanguage, preferredLanguages: preferredLanguages) ?? "en-US"
        let languageCode = identifier.split(separator: "-").first.map(String.init) ?? "en"

        switch languageCode {
        case "fr":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: [
                    letters("azertyuiop"),
                    letters("qsdfghjklm"),
                    letters("wxcvbn")
                ],
                spaceTitle: "espace"
            )
        case "de":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: [
                    letters("qwertzuiop"),
                    letters("asdfghjkl"),
                    letters("yxcvbnm")
                ],
                spaceTitle: "Leerzeichen"
            )
        case "es":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: [
                    letters("qwertyuiop"),
                    letters("asdfghjkl") + ["\u{00F1}"],
                    letters("zxcvbnm")
                ],
                spaceTitle: "espacio"
            )
        case "it":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: qwertyRows,
                spaceTitle: "spazio"
            )
        case "pt":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: qwertyRows,
                spaceTitle: "espa\u{00E7}o"
            )
        case "nl":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: qwertyRows,
                spaceTitle: "spatie"
            )
        case "tr":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: [
                    letters("qwertyu") + ["\u{0131}", "o", "p"],
                    letters("asdfghjkl") + ["\u{015F}"],
                    letters("zxcvbnm") + ["\u{00F6}", "\u{00E7}"]
                ],
                spaceTitle: "bo\u{015F}luk"
            )
        case "ar":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: [
                    ["\u{0636}", "\u{0635}", "\u{062B}", "\u{0642}", "\u{0641}", "\u{063A}", "\u{0639}", "\u{0647}", "\u{062E}", "\u{062D}"],
                    ["\u{0634}", "\u{0633}", "\u{064A}", "\u{0628}", "\u{0644}", "\u{0627}", "\u{062A}", "\u{0646}", "\u{0645}", "\u{0643}"],
                    ["\u{0626}", "\u{0621}", "\u{0624}", "\u{0631}", "\u{0649}", "\u{0629}", "\u{0648}", "\u{0632}", "\u{0638}"]
                ],
                spaceTitle: "\u{0645}\u{0633}\u{0627}\u{0641}\u{0629}",
                prefersRightToLeft: true
            )
        case "he":
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: [
                    ["\u{05E7}", "\u{05E8}", "\u{05D0}", "\u{05D8}", "\u{05D5}", "\u{05DF}", "\u{05DD}", "\u{05E4}"],
                    ["\u{05E9}", "\u{05D3}", "\u{05D2}", "\u{05DB}", "\u{05E2}", "\u{05D9}", "\u{05D7}", "\u{05DC}", "\u{05DA}", "\u{05E3}"],
                    ["\u{05D6}", "\u{05E1}", "\u{05D1}", "\u{05D4}", "\u{05E0}", "\u{05DE}", "\u{05E6}", "\u{05EA}", "\u{05E5}"]
                ],
                spaceTitle: "\u{05E8}\u{05D5}\u{05D5}\u{05D7}",
                prefersRightToLeft: true
            )
        default:
            return KeyboardLanguageLayout(
                languageIdentifier: identifier,
                alphabeticRows: qwertyRows,
                spaceTitle: "space"
            )
        }
    }

    public static func enabledLayouts(
        primaryLanguage: String?,
        preferredLanguages: [String]
    ) -> [KeyboardLanguageLayout] {
        let candidates = [primaryLanguage].compactMap { $0 } + preferredLanguages + defaultLanguageIdentifiers
        var seenCodes = Set<String>()
        var layouts: [KeyboardLanguageLayout] = []

        for candidate in candidates {
            guard let identifier = normalizedIdentifier(candidate, preferredLanguages: []) else {
                continue
            }
            let layout = Self.layout(for: identifier)
            guard supportedLanguageCodes.contains(layout.languageCode), !seenCodes.contains(layout.languageCode) else {
                continue
            }
            seenCodes.insert(layout.languageCode)
            layouts.append(layout)
        }

        return layouts.isEmpty ? [Self.layout(for: "en-US")] : layouts
    }

    public static func nextLayout(
        after currentLayout: KeyboardLanguageLayout,
        in layouts: [KeyboardLanguageLayout]
    ) -> KeyboardLanguageLayout {
        guard !layouts.isEmpty,
              let currentIndex = layouts.firstIndex(where: { $0.languageCode == currentLayout.languageCode }) else {
            return layouts.first ?? Self.layout(for: "en-US")
        }
        return layouts[(currentIndex + 1) % layouts.count]
    }

    public static let defaultNumericRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
    ]

    public static let defaultSymbolRows: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "\u{20AC}", "\u{00A3}", "\u{00A5}", "\u{2022}"]
    ]

    public static let defaultLanguageIdentifiers = [
        "en-US", "fr-FR", "de-DE", "es-ES", "it-IT", "pt-PT", "nl-NL", "tr-TR", "ar-SA", "he-IL"
    ]

    private static var qwertyRows: [[String]] {
        [letters("qwertyuiop"), letters("asdfghjkl"), letters("zxcvbnm")]
    }

    private static func letters(_ text: String) -> [String] {
        text.map(String.init)
    }

    private static var supportedLanguageCodes: Set<String> {
        Set(defaultLanguageIdentifiers.compactMap { $0.split(separator: "-").first.map(String.init) })
    }

    private static func normalizedIdentifier(_ primaryLanguage: String?, preferredLanguages: [String]) -> String? {
        let candidates = [primaryLanguage] + preferredLanguages.map(Optional.some)
        for candidate in candidates {
            guard let candidate,
                  !candidate.isEmpty,
                  candidate != "und",
                  candidate != "mul" else {
                continue
            }
            return candidate.replacingOccurrences(of: "_", with: "-")
        }
        return nil
    }
}

public struct KeyboardSwipeResolution: Equatable, Sendable {
    public let text: String
    public let isDictionaryMatch: Bool

    public init(text: String, isDictionaryMatch: Bool) {
        self.text = text
        self.isDictionaryMatch = isDictionaryMatch
    }
}

public enum KeyboardSwipeResolver {
    public static func resolve(
        path: [String],
        languageIdentifier: String,
        documentContextBeforeInput: String? = nil
    ) -> KeyboardSwipeResolution? {
        let signature = normalizedSignature(path)
        guard signature.count >= 2 else {
            return nil
        }

        let languageCode = languageIdentifier.split(separator: "-").first.map(String.init) ?? "en"
        if let word = dictionary(for: languageCode).first(where: { normalizedSignature(Array($0).map(String.init)) == signature }) {
            return KeyboardSwipeResolution(
                text: insertionText(for: word, documentContextBeforeInput: documentContextBeforeInput),
                isDictionaryMatch: true
            )
        }

        let fallback = signature.joined()
        return KeyboardSwipeResolution(
            text: insertionText(for: fallback, documentContextBeforeInput: documentContextBeforeInput),
            isDictionaryMatch: false
        )
    }

    public static func normalizedSignature(_ path: [String]) -> [String] {
        var result: [String] = []
        for rawKey in path {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, result.last != key else {
                continue
            }
            result.append(key)
        }
        return result
    }

    private static func insertionText(for word: String, documentContextBeforeInput: String?) -> String {
        let needsLeadingSpace: Bool
        if let last = documentContextBeforeInput?.last {
            needsLeadingSpace = !last.isWhitespace
        } else {
            needsLeadingSpace = false
        }
        return (needsLeadingSpace ? " " : "") + word + " "
    }

    private static func dictionary(for languageCode: String) -> [String] {
        switch languageCode {
        case "fr":
            return ["bonjour", "merci", "oui", "non", "clavier", "salut", "monde"]
        case "de":
            return ["hallo", "danke", "ja", "nein", "tastatur", "welt", "gut"]
        case "es":
            return ["hola", "gracias", "si", "no", "teclado", "mundo"]
        case "it":
            return ["ciao", "grazie", "si", "no", "tastiera", "mondo"]
        case "pt":
            return ["ola", "obrigado", "sim", "nao", "teclado", "mundo"]
        case "nl":
            return ["hallo", "dank", "ja", "nee", "toetsenbord", "wereld"]
        case "tr":
            return ["merhaba", "tesekkur", "evet", "hayir", "klavye", "dunya"]
        default:
            return ["the", "and", "you", "hello", "world", "keymore", "keyboard", "swift", "swipe", "test", "thanks", "please", "good", "morning", "night", "yes", "no"]
        }
    }
}

public enum KeyboardTextBehavior {
    private static let sentenceTerminators: Set<Character> = [".", "!", "?"]

    public static func shouldAutoCapitalize(documentContextBeforeInput: String?) -> Bool {
        guard let context = documentContextBeforeInput, !context.isEmpty else {
            return true
        }

        guard let lastMeaningfulCharacter = context.last(where: { !$0.isWhitespace }) else {
            return true
        }

        if context.last == "\n" {
            return true
        }

        if let lastCharacter = context.last, !lastCharacter.isWhitespace {
            return false
        }

        return sentenceTerminators.contains(lastMeaningfulCharacter)
    }

    public static func shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: String?) -> Bool {
        guard let context = documentContextBeforeInput,
              context.hasSuffix(" ") else {
            return false
        }

        let beforeTrailingSpace = context.dropLast()
        guard let previous = beforeTrailingSpace.last,
              !previous.isWhitespace else {
            return false
        }

        return !sentenceTerminators.contains(previous)
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
