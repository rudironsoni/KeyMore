import XCTest
@testable import KeyMoreCore

final class KeyboardInputMethodTests: XCTestCase {
    func testStickyModifierTogglesOnAndOff() {
        let initial = KeyboardInputContext()

        let controlOn = KeyboardInputMethod.resolve(.special(.control), context: initial)
        XCTAssertEqual(controlOn.nextContext.activeModifiers, [.control])
        XCTAssertEqual(controlOn.outputEvents, [
            .modifierState(keyLabel: "ctrl", report: HIDKeyboardReport(modifiers: .leftControl))
        ])
        XCTAssertTrue(controlOn.shouldUpdateModifierButtons)

        let controlOff = KeyboardInputMethod.resolve(.special(.control), context: controlOn.nextContext)
        XCTAssertEqual(controlOff.nextContext.activeModifiers, [])
        XCTAssertEqual(controlOff.outputEvents, [
            .modifierState(keyLabel: "ctrl", report: .empty)
        ])
    }

    func testEveryStickyModifierReportsCombinedStateWhileTogglingOnAndOff() {
        let steps: [(key: SpecialKey, expectedModifiers: Set<SpecialKey>, expectedByte: UInt8)] = [
            (.control, [.control], 0x01),
            (.option, [.control, .option], 0x05),
            (.command, [.control, .option, .command], 0x0D),
            (.option, [.control, .command], 0x09),
            (.control, [.command], 0x08),
            (.command, [], 0x00)
        ]
        var context = KeyboardInputContext()

        for step in steps {
            let result = KeyboardInputMethod.resolve(.special(step.key), context: context)

            XCTAssertEqual(result.nextContext.activeModifiers, step.expectedModifiers, "Unexpected active modifiers after \(step.key)")
            XCTAssertEqual(result.outputEvents, [
                .modifierState(
                    keyLabel: step.key.displayTitle,
                    report: HIDKeyboardReport(modifiers: HIDModifier(rawValue: step.expectedByte))
                )
            ])
            XCTAssertTrue(result.shouldUpdateModifierButtons)
            context = result.nextContext
        }
    }

    func testCommandCResolvesHardwareComboThenClearsOneShotModifier() throws {
        let commandOn = KeyboardInputMethod.resolve(.special(.command), context: KeyboardInputContext())
        let commandC = KeyboardInputMethod.resolve(.character("c"), context: commandOn.nextContext)

        XCTAssertEqual(commandC.nextContext.activeModifiers, [])
        XCTAssertTrue(commandC.shouldUpdateModifierButtons)
        XCTAssertEqual(commandC.outputEvents, [
            .keyPress(
                keyLabel: "c",
                keyPress: try XCTUnwrap(HIDReportBuilder.keyPress(for: "c", activeModifiers: [.command])),
                fallback: KeyResolution(
                    action: .noOperation("Command shortcuts require a hardware-equivalent event path"),
                    outcome: .unknown
                )
            ),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
    }

    func testControlOptionTabResolvesComboThenClearsOneShotModifiers() throws {
        let controlOn = KeyboardInputMethod.resolve(.special(.control), context: KeyboardInputContext())
        let optionOn = KeyboardInputMethod.resolve(.special(.option), context: controlOn.nextContext)
        let tab = KeyboardInputMethod.resolve(.special(.tab), context: optionOn.nextContext)

        XCTAssertEqual(optionOn.nextContext.activeModifiers, [.control, .option])
        XCTAssertEqual(tab.nextContext.activeModifiers, [])
        XCTAssertEqual(tab.outputEvents, [
            .keyPress(
                keyLabel: "tab",
                keyPress: try XCTUnwrap(HIDReportBuilder.keyPress(for: .tab, activeModifiers: [.control, .option])),
                fallback: KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly)
            ),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
    }

    func testEscapeCarriesActiveModifiersThenClearsThem() throws {
        let context = KeyboardInputContext(activeModifiers: [.control, .command])
        let result = KeyboardInputMethod.resolve(.special(.escape), context: context)

        XCTAssertEqual(result.nextContext.activeModifiers, [])
        XCTAssertEqual(result.outputEvents, [
            .keyPress(
                keyLabel: "esc",
                keyPress: try XCTUnwrap(HIDReportBuilder.keyPress(for: .escape, activeModifiers: [.control, .command])),
                fallback: KeyResolution(action: .insertText("\u{1B}"), outcome: .textProxyOnly)
            ),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
    }

    func testControlLetterResolvesHardwareComboAndControlCharacterFallback() throws {
        let context = KeyboardInputContext(activeModifiers: [.control])
        let result = KeyboardInputMethod.resolve(.character("c"), context: context)

        XCTAssertEqual(result.nextContext.activeModifiers, [])
        XCTAssertEqual(result.outputEvents, [
            .keyPress(
                keyLabel: "c",
                keyPress: try XCTUnwrap(HIDReportBuilder.keyPress(for: "c", activeModifiers: [.control])),
                fallback: KeyResolution(action: .insertText("\u{3}"), outcome: .textProxyOnly)
            ),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
    }

    func testOptionLetterResolvesHardwareComboAndEscapePrefixedFallback() throws {
        let context = KeyboardInputContext(activeModifiers: [.option])
        let result = KeyboardInputMethod.resolve(.character("x"), context: context)

        XCTAssertEqual(result.nextContext.activeModifiers, [])
        XCTAssertEqual(result.outputEvents, [
            .keyPress(
                keyLabel: "x",
                keyPress: try XCTUnwrap(HIDReportBuilder.keyPress(for: "x", activeModifiers: [.option])),
                fallback: KeyResolution(action: .insertText("\u{1B}x"), outcome: .textProxyOnly)
            ),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
    }

    func testAllModifierCombosForLetterCResolveExpectedModifierBytesAndClearState() throws {
        let cases: [(Set<SpecialKey>, UInt8, KeyResolution)] = [
            ([], 0x00, KeyResolution(action: .insertText("c"), outcome: .textProxyOnly)),
            ([.control], 0x01, KeyResolution(action: .insertText("\u{3}"), outcome: .textProxyOnly)),
            ([.option], 0x04, KeyResolution(action: .insertText("\u{1B}c"), outcome: .textProxyOnly)),
            ([.command], 0x08, commandFallback),
            ([.control, .option], 0x05, KeyResolution(action: .insertText("\u{3}"), outcome: .textProxyOnly)),
            ([.control, .command], 0x09, commandFallback),
            ([.option, .command], 0x0C, commandFallback),
            ([.control, .option, .command], 0x0D, commandFallback)
        ]

        for (modifiers, expectedModifierByte, fallback) in cases {
            let result = KeyboardInputMethod.resolve(
                .character("c"),
                context: KeyboardInputContext(activeModifiers: modifiers)
            )
            let expectedOutputs: [KeyboardOutputEvent] = [
                .keyPress(
                    keyLabel: "c",
                    keyPress: HIDKeyPress(usage: .c, modifiers: HIDModifier(rawValue: expectedModifierByte)),
                    fallback: fallback
                )
            ] + (modifiers.isEmpty ? [] : [.modifierState(keyLabel: "modifiers", report: .empty)])

            XCTAssertEqual(result.outputEvents, expectedOutputs, "Unexpected output events for \(modifiers)")
            XCTAssertEqual(result.nextContext.activeModifiers, [])
        }
    }

    func testEveryLetterResolvesExpectedHIDUsageFallbackAndClearsAcrossEveryStickyModifierCombo() throws {
        for letterCase in allLetterCases {
            for modifierCase in allModifierCases {
                let context = KeyboardInputContext(activeModifiers: modifierCase.keys)
                let result = KeyboardInputMethod.resolve(.character(letterCase.raw), context: context)
                let expectedOutput = KeyboardOutputEvent.keyPress(
                    keyLabel: letterCase.raw,
                    keyPress: expectedKeyPress(usage: letterCase.usage, modifierByte: modifierCase.byte, isShifted: false),
                    fallback: expectedCharacterFallback(letterCase.raw, modifiers: modifierCase.keys)
                )
                let expectedEvents = [expectedOutput] + expectedClearEvents(for: modifierCase.keys)

                XCTAssertEqual(result.outputEvents, expectedEvents, "Unexpected output for \(modifierCase.name)+\(letterCase.raw)")
                XCTAssertEqual(result.nextContext, KeyboardInputContext(activeModifiers: [], isShifted: false))
                XCTAssertEqual(result.shouldUpdateModifierButtons, !modifierCase.keys.isEmpty)
                XCTAssertFalse(result.shouldRebuildCharacterLabels)
            }
        }
    }

    func testEveryShiftedLetterKeepsShiftStateAndReleasesOnlyTheLetterAcrossEveryStickyModifierCombo() throws {
        for letterCase in allLetterCases {
            for modifierCase in allModifierCases {
                let context = KeyboardInputContext(activeModifiers: modifierCase.keys, isShifted: true)
                let result = KeyboardInputMethod.resolve(.character(letterCase.raw), context: context)
                let expectedOutput = KeyboardOutputEvent.keyPress(
                    keyLabel: letterCase.shifted,
                    keyPress: expectedKeyPress(usage: letterCase.usage, modifierByte: modifierCase.byte, isShifted: true),
                    fallback: expectedCharacterFallback(letterCase.shifted, modifiers: modifierCase.keys)
                )
                let expectedEvents = [expectedOutput] + expectedClearEvents(for: modifierCase.keys)

                XCTAssertEqual(result.outputEvents, expectedEvents, "Unexpected shifted output for \(modifierCase.name)+\(letterCase.raw)")
                XCTAssertEqual(result.nextContext, KeyboardInputContext(activeModifiers: [], isShifted: true))
                XCTAssertEqual(result.shouldUpdateModifierButtons, !modifierCase.keys.isEmpty)
                XCTAssertFalse(result.shouldRebuildCharacterLabels)
            }
        }
    }

    func testShiftTogglesCharacterCaseAndAddsShiftModifierToHIDReport() throws {
        let shiftOn = KeyboardInputMethod.resolve(.shift, context: KeyboardInputContext())
        let shiftedA = KeyboardInputMethod.resolve(.character("a"), context: shiftOn.nextContext)

        XCTAssertTrue(shiftOn.nextContext.isShifted)
        XCTAssertTrue(shiftOn.shouldRebuildCharacterLabels)
        XCTAssertEqual(shiftedA.nextContext.isShifted, true)
        XCTAssertEqual(shiftedA.outputEvents, [
            .keyPress(
                keyLabel: "A",
                keyPress: HIDKeyPress(
                    down: HIDKeyboardReport(modifiers: .leftShift, usages: [HIDKeyboardUsage.a.rawValue])
                ),
                fallback: KeyResolution(action: .insertText("A"), outcome: .textProxyOnly)
            )
        ])
    }

    func testShiftTogglesOnAndOffWithoutEmittingKeyEvents() {
        let shiftOn = KeyboardInputMethod.resolve(.shift, context: KeyboardInputContext())
        let shiftOff = KeyboardInputMethod.resolve(.shift, context: shiftOn.nextContext)

        XCTAssertEqual(shiftOn.nextContext, KeyboardInputContext(isShifted: true))
        XCTAssertEqual(shiftOn.outputEvents, [])
        XCTAssertTrue(shiftOn.shouldRebuildCharacterLabels)
        XCTAssertFalse(shiftOn.shouldUpdateModifierButtons)
        XCTAssertEqual(shiftOff.nextContext, KeyboardInputContext(isShifted: false))
        XCTAssertEqual(shiftOff.outputEvents, [])
        XCTAssertTrue(shiftOff.shouldRebuildCharacterLabels)
        XCTAssertFalse(shiftOff.shouldUpdateModifierButtons)
    }

    func testShiftedCommandCIncludesShiftAndCommandInHardwareReport() throws {
        let context = KeyboardInputContext(activeModifiers: [.command], isShifted: true)
        let result = KeyboardInputMethod.resolve(.character("c"), context: context)

        XCTAssertEqual(result.nextContext, KeyboardInputContext(activeModifiers: [], isShifted: true))
        XCTAssertEqual(result.outputEvents, [
            .keyPress(
                keyLabel: "C",
                keyPress: HIDKeyPress(
                    down: HIDKeyboardReport(modifiers: [.leftShift, .leftCommand], usages: [HIDKeyboardUsage.c.rawValue]),
                    up: HIDKeyboardReport(modifiers: .leftCommand)
                ),
                fallback: commandFallback
            ),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
    }

    func testPlainBottomRowKeysAreHIDFirstWithTextProxyFallback() {
        let context = KeyboardInputContext()

        XCTAssertEqual(
            KeyboardInputMethod.resolve(.delete, context: context),
            KeyboardInputResult(
                outputEvents: [bottomRowKeyPressEvent("delete", usage: .deleteOrBackspace, fallback: .deleteBackward)],
                nextContext: context
            )
        )
        XCTAssertEqual(
            KeyboardInputMethod.resolve(.space, context: context),
            KeyboardInputResult(
                outputEvents: [bottomRowKeyPressEvent("space", usage: .space, fallback: .insertText(" "))],
                nextContext: context
            )
        )
        XCTAssertEqual(
            KeyboardInputMethod.resolve(.return, context: context),
            KeyboardInputResult(
                outputEvents: [bottomRowKeyPressEvent("return", usage: .returnOrEnter, fallback: .insertText("\n"))],
                nextContext: context
            )
        )
    }

    func testEveryActionKeyResolvesExpectedHIDUsageFallbackAndClearsAcrossEveryModifierAndShiftCombo() {
        for keyCase in visibleActionKeyCases {
            for modifierCase in allModifierCases {
                for isShifted in [false, true] {
                    let context = KeyboardInputContext(activeModifiers: modifierCase.keys, isShifted: isShifted)
                    let result = KeyboardInputMethod.resolve(keyCase.input, context: context)
                    let expectedOutput = KeyboardOutputEvent.keyPress(
                        keyLabel: keyCase.label,
                        keyPress: expectedKeyPress(
                            usage: keyCase.usage,
                            modifierByte: modifierCase.byte,
                            isShifted: isShifted
                        ),
                        fallback: KeyResolution(action: keyCase.fallback, outcome: .textProxyOnly)
                    )
                    let expectedEvents = [expectedOutput] + expectedClearEvents(for: modifierCase.keys)

                    XCTAssertEqual(
                        result.outputEvents,
                        expectedEvents,
                        "Unexpected output for \(modifierCase.name)+\(isShifted ? "shift+" : "")\(keyCase.label)"
                    )
                    XCTAssertEqual(result.nextContext, KeyboardInputContext(activeModifiers: [], isShifted: isShifted))
                    XCTAssertEqual(result.shouldUpdateModifierButtons, !modifierCase.keys.isEmpty)
                    XCTAssertFalse(result.shouldRebuildCharacterLabels)
                }
            }
        }
    }

    func testBottomRowKeyCombosIncludeActiveModifiersShiftAndClearOneShotModifiers() {
        let context = KeyboardInputContext(activeModifiers: [.control, .option], isShifted: true)

        for (key, label, usage, fallback) in [
            (KeyboardInput.delete, "delete", HIDKeyboardUsage.deleteOrBackspace, TextProxyAction.deleteBackward),
            (.space, "space", .space, .insertText(" ")),
            (.return, "return", .returnOrEnter, .insertText("\n"))
        ] {
            let result = KeyboardInputMethod.resolve(key, context: context)

            XCTAssertEqual(
                result,
                KeyboardInputResult(
                    outputEvents: [
                        bottomRowKeyPressEvent(
                            label,
                            usage: usage,
                            modifiers: [.leftControl, .leftOption, .leftShift],
                            releaseModifiers: [.leftControl, .leftOption],
                            fallback: fallback
                        ),
                        .modifierState(keyLabel: "modifiers", report: .empty)
                    ],
                    nextContext: KeyboardInputContext(activeModifiers: [], isShifted: true),
                    shouldUpdateModifierButtons: true
                )
            )
        }
    }

    func testShiftAppliesToTabEscapeAndBottomRowsWithoutBeingCleared() throws {
        let shiftOnly = KeyboardInputContext(isShifted: true)
        let shiftedTab = KeyboardInputMethod.resolve(.special(.tab), context: shiftOnly)
        let shiftedEscape = KeyboardInputMethod.resolve(.special(.escape), context: shiftOnly)
        let shiftedSpace = KeyboardInputMethod.resolve(.space, context: shiftOnly)

        XCTAssertEqual(shiftedTab.nextContext, shiftOnly)
        XCTAssertEqual(shiftedEscape.nextContext, shiftOnly)
        XCTAssertEqual(shiftedSpace.nextContext, shiftOnly)
        XCTAssertEqual(shiftedTab.outputEvents, [
            .keyPress(
                keyLabel: "tab",
                keyPress: HIDKeyPress(down: HIDKeyboardReport(modifiers: .leftShift, usages: [HIDKeyboardUsage.tab.rawValue])),
                fallback: KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly)
            )
        ])
        XCTAssertEqual(shiftedEscape.outputEvents, [
            .keyPress(
                keyLabel: "esc",
                keyPress: HIDKeyPress(down: HIDKeyboardReport(modifiers: .leftShift, usages: [HIDKeyboardUsage.escape.rawValue])),
                fallback: KeyResolution(action: .insertText("\u{1B}"), outcome: .textProxyOnly)
            )
        ])
        XCTAssertEqual(shiftedSpace.outputEvents, [
            bottomRowKeyPressEvent("space", usage: .space, modifiers: .leftShift, fallback: .insertText(" "))
        ])
    }

    func testShiftCommandTabIncludesBothModifiersThenOnlyClearsCommand() throws {
        let context = KeyboardInputContext(activeModifiers: [.command], isShifted: true)
        let result = KeyboardInputMethod.resolve(.special(.tab), context: context)

        XCTAssertEqual(result.nextContext, KeyboardInputContext(activeModifiers: [], isShifted: true))
        XCTAssertEqual(result.outputEvents, [
            .keyPress(
                keyLabel: "tab",
                keyPress: HIDKeyPress(
                    down: HIDKeyboardReport(modifiers: [.leftShift, .leftCommand], usages: [HIDKeyboardUsage.tab.rawValue]),
                    up: HIDKeyboardReport(modifiers: .leftCommand)
                ),
                fallback: KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly)
            ),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
    }

    func testNonLetterCharacterUsesTextFallbackAndStillClearsOneShotModifiers() {
        let context = KeyboardInputContext(activeModifiers: [.option])
        let result = KeyboardInputMethod.resolve(.character("."), context: context)

        XCTAssertEqual(result.outputEvents, [
            .textInput(KeyResolution(action: .insertText("\u{1B}."), outcome: .textProxyOnly)),
            .modifierState(keyLabel: "modifiers", report: .empty)
        ])
        XCTAssertEqual(result.nextContext.activeModifiers, [])
    }

    func testRepresentativeKeySequenceMaintainsContextAndOutputsExpectedCombos() throws {
        let sequence: [KeyboardInput] = [
            .special(.command),
            .character("c"),
            .special(.control),
            .special(.option),
            .special(.tab),
            .shift,
            .special(.command),
            .character("v"),
            .delete
        ]

        let result = resolveSequence(sequence)

        XCTAssertEqual(result.context, KeyboardInputContext(activeModifiers: [], isShifted: true))
        XCTAssertEqual(result.outputEvents, [
            .modifierState(keyLabel: "cmd", report: HIDKeyboardReport(modifiers: .leftCommand)),
            .keyPress(
                keyLabel: "c",
                keyPress: HIDKeyPress(usage: .c, modifiers: .leftCommand),
                fallback: commandFallback
            ),
            .modifierState(keyLabel: "modifiers", report: .empty),
            .modifierState(keyLabel: "ctrl", report: HIDKeyboardReport(modifiers: .leftControl)),
            .modifierState(keyLabel: "opt", report: HIDKeyboardReport(modifiers: [.leftControl, .leftOption])),
            .keyPress(
                keyLabel: "tab",
                keyPress: HIDKeyPress(usage: .tab, modifiers: [.leftControl, .leftOption]),
                fallback: KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly)
            ),
            .modifierState(keyLabel: "modifiers", report: .empty),
            .modifierState(keyLabel: "cmd", report: HIDKeyboardReport(modifiers: .leftCommand)),
            .keyPress(
                keyLabel: "V",
                keyPress: HIDKeyPress(
                    down: HIDKeyboardReport(modifiers: [.leftShift, .leftCommand], usages: [HIDKeyboardUsage.v.rawValue]),
                    up: HIDKeyboardReport(modifiers: .leftCommand)
                ),
                fallback: commandFallback
            ),
            .modifierState(keyLabel: "modifiers", report: .empty),
            bottomRowKeyPressEvent("delete", usage: .deleteOrBackspace, modifiers: .leftShift, fallback: .deleteBackward)
        ])
    }

    func testEveryVisibleNonGlobeKeyProducesOutputWithoutUnexpectedNoOutputExceptShift() {
        let keys: [KeyboardInput] = [
            .special(.escape), .special(.control), .special(.option), .special(.command), .special(.tab),
            .character("q"), .character("w"), .character("e"), .character("r"), .character("t"),
            .character("y"), .character("u"), .character("i"), .character("o"), .character("p"),
            .character("a"), .character("s"), .character("d"), .character("f"), .character("g"),
            .character("h"), .character("j"), .character("k"), .character("l"), .shift,
            .character("z"), .character("x"), .character("c"), .character("v"), .character("b"),
            .character("n"), .character("m"), .delete, .space, .return
        ]

        for key in keys {
            let result = KeyboardInputMethod.resolve(key, context: KeyboardInputContext())

            if key == .shift {
                XCTAssertTrue(result.outputEvents.isEmpty)
                XCTAssertTrue(result.shouldRebuildCharacterLabels)
            } else {
                XCTAssertFalse(result.outputEvents.isEmpty, "Expected output for \(key)")
            }
        }
    }

    func testLanguageLayoutsFollowIOSLanguageFamilies() {
        let english = KeyboardLanguageLayout.layout(for: "en-US")
        XCTAssertEqual(english.alphabeticRows[0], ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
        XCTAssertEqual(english.spaceTitle, "space")

        let french = KeyboardLanguageLayout.layout(for: "fr-FR")
        XCTAssertEqual(french.alphabeticRows[0], ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"])
        XCTAssertEqual(french.spaceTitle, "espace")

        let german = KeyboardLanguageLayout.layout(for: "de-DE")
        XCTAssertEqual(german.alphabeticRows[0], ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p"])
        XCTAssertEqual(german.alphabeticRows[2].first, "y")
    }

    func testLanguageLayoutsIncludeLocaleSpecificVisibleKeysAndDirection() {
        let spanish = KeyboardLanguageLayout.layout(for: "es-ES")
        XCTAssertTrue(spanish.alphabeticRows[1].contains("\u{00F1}"))

        let turkish = KeyboardLanguageLayout.layout(for: "tr-TR")
        XCTAssertTrue(turkish.alphabeticRows[0].contains("\u{0131}"))
        XCTAssertTrue(turkish.alphabeticRows[1].contains("\u{015F}"))

        let arabic = KeyboardLanguageLayout.layout(for: "ar-SA")
        XCTAssertTrue(arabic.prefersRightToLeft)
        XCTAssertEqual(arabic.spaceTitle, "\u{0645}\u{0633}\u{0627}\u{0641}\u{0629}")

        let hebrew = KeyboardLanguageLayout.layout(for: "he-IL")
        XCTAssertTrue(hebrew.prefersRightToLeft)
        XCTAssertEqual(hebrew.spaceTitle, "\u{05E8}\u{05D5}\u{05D5}\u{05D7}")
    }

    func testLanguageLayoutFallsBackToPreferredIOSLanguages() {
        let layout = KeyboardLanguageLayout.layout(for: "mul", preferredLanguages: ["de-DE", "en-US"])

        XCTAssertEqual(layout.languageIdentifier, "de-DE")
        XCTAssertEqual(layout.alphabeticRows[0], ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p"])
    }

    func testAutoCapitalizationMatchesStockSentenceBoundaries() {
        XCTAssertTrue(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: nil))
        XCTAssertTrue(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: ""))
        XCTAssertTrue(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: "Hello. "))
        XCTAssertTrue(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: "Hello!  "))
        XCTAssertTrue(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: "Hello\n"))

        XCTAssertFalse(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: "Hello"))
        XCTAssertFalse(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: "Hello "))
        XCTAssertFalse(KeyboardTextBehavior.shouldAutoCapitalize(documentContextBeforeInput: "Hello, "))
    }

    func testDoubleSpacePeriodOnlyAppliesAfterAWordSpace() {
        XCTAssertTrue(KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: "Hello "))
        XCTAssertTrue(KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: "Hello world "))

        XCTAssertFalse(KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: nil))
        XCTAssertFalse(KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: ""))
        XCTAssertFalse(KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: "Hello"))
        XCTAssertFalse(KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: "Hello. "))
        XCTAssertFalse(KeyboardTextBehavior.shouldInsertPeriodOnDoubleSpace(documentContextBeforeInput: "Hello  "))
    }

    private var commandFallback: KeyResolution {
        KeyResolution(
            action: .noOperation("Command shortcuts require a hardware-equivalent event path"),
            outcome: .unknown
        )
    }

    private var allModifierCases: [(keys: Set<SpecialKey>, byte: UInt8, name: String)] {
        [
            ([], 0x00, "none"),
            ([.control], 0x01, "ctrl"),
            ([.option], 0x04, "opt"),
            ([.command], 0x08, "cmd"),
            ([.control, .option], 0x05, "ctrl+opt"),
            ([.control, .command], 0x09, "ctrl+cmd"),
            ([.option, .command], 0x0C, "opt+cmd"),
            ([.control, .option, .command], 0x0D, "ctrl+opt+cmd")
        ]
    }

    private var allLetterCases: [(raw: String, shifted: String, usage: HIDKeyboardUsage)] {
        let letters: [(raw: String, shifted: String, usage: HIDKeyboardUsage)] = (UInt8(ascii: "a")...UInt8(ascii: "z")).map { scalarValue in
            let raw = String(UnicodeScalar(scalarValue))
            return (raw: raw, shifted: raw.uppercased(), usage: HIDKeyboardUsage(rawValue: scalarValue - 93)!)
        }
        return letters
    }

    private var visibleActionKeyCases: [(input: KeyboardInput, label: String, usage: HIDKeyboardUsage, fallback: TextProxyAction)] {
        [
            (.special(.escape), "esc", .escape, .insertText("\u{1B}")),
            (.special(.tab), "tab", .tab, .insertText("\t")),
            (.delete, "delete", .deleteOrBackspace, .deleteBackward),
            (.space, "space", .space, .insertText(" ")),
            (.return, "return", .returnOrEnter, .insertText("\n"))
        ]
    }

    private func expectedCharacterFallback(_ character: String, modifiers: Set<SpecialKey>) -> KeyResolution {
        guard let scalar = character.uppercased().unicodeScalars.first else {
            return KeyResolution(action: .noOperation("Empty character"), outcome: .unknown)
        }

        if modifiers.contains(.command) {
            return commandFallback
        }

        if modifiers.contains(.control),
           scalar.value >= 65,
           scalar.value <= 90,
           let controlScalar = UnicodeScalar(scalar.value - 64) {
            return KeyResolution(action: .insertText(String(controlScalar)), outcome: .textProxyOnly)
        }

        if modifiers.contains(.option) {
            return KeyResolution(action: .insertText("\u{1B}" + character), outcome: .textProxyOnly)
        }

        return KeyResolution(action: .insertText(character), outcome: .textProxyOnly)
    }

    private func expectedKeyPress(
        usage: HIDKeyboardUsage,
        modifierByte: UInt8,
        isShifted: Bool
    ) -> HIDKeyPress {
        var downModifiers = HIDModifier(rawValue: modifierByte)
        if isShifted {
            downModifiers.insert(.leftShift)
        }
        let releaseModifiers = HIDModifier(rawValue: modifierByte)
        return HIDKeyPress(
            down: HIDKeyboardReport(modifiers: downModifiers, usages: [usage.rawValue]),
            up: HIDKeyboardReport(modifiers: releaseModifiers)
        )
    }

    private func expectedClearEvents(for modifiers: Set<SpecialKey>) -> [KeyboardOutputEvent] {
        modifiers.isEmpty ? [] : [.modifierState(keyLabel: "modifiers", report: .empty)]
    }

    private func bottomRowKeyPressEvent(
        _ label: String,
        usage: HIDKeyboardUsage,
        modifiers: HIDModifier = [],
        releaseModifiers: HIDModifier = [],
        fallback: TextProxyAction
    ) -> KeyboardOutputEvent {
        .keyPress(
            keyLabel: label,
            keyPress: HIDKeyPress(
                down: HIDKeyboardReport(modifiers: modifiers, usages: [usage.rawValue]),
                up: HIDKeyboardReport(modifiers: releaseModifiers)
            ),
            fallback: KeyResolution(action: fallback, outcome: .textProxyOnly)
        )
    }

    private func resolveSequence(_ keys: [KeyboardInput]) -> (context: KeyboardInputContext, outputEvents: [KeyboardOutputEvent]) {
        var context = KeyboardInputContext()
        var outputEvents: [KeyboardOutputEvent] = []

        for key in keys {
            let result = KeyboardInputMethod.resolve(key, context: context)
            context = result.nextContext
            outputEvents.append(contentsOf: result.outputEvents)
        }

        return (context, outputEvents)
    }
}
