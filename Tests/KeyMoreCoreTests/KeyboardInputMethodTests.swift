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
                    keyPress: HIDKeyPress(
                        down: HIDKeyboardReport(modifiers: HIDModifier(rawValue: expectedModifierByte), usages: [HIDKeyboardUsage.c.rawValue])
                    ),
                    fallback: fallback
                )
            ] + (modifiers.isEmpty ? [] : [.modifierState(keyLabel: "modifiers", report: .empty)])

            XCTAssertEqual(result.outputEvents, expectedOutputs, "Unexpected output events for \(modifiers)")
            XCTAssertEqual(result.nextContext.activeModifiers, [])
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

    func testShiftedCommandCIncludesShiftAndCommandInHardwareReport() throws {
        let context = KeyboardInputContext(activeModifiers: [.command], isShifted: true)
        let result = KeyboardInputMethod.resolve(.character("c"), context: context)

        XCTAssertEqual(result.nextContext, KeyboardInputContext(activeModifiers: [], isShifted: true))
        XCTAssertEqual(result.outputEvents, [
            .keyPress(
                keyLabel: "C",
                keyPress: HIDKeyPress(
                    down: HIDKeyboardReport(modifiers: [.leftShift, .leftCommand], usages: [HIDKeyboardUsage.c.rawValue])
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
                keyPress: HIDKeyPress(down: HIDKeyboardReport(modifiers: [.leftShift, .leftCommand], usages: [HIDKeyboardUsage.tab.rawValue])),
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
                keyPress: HIDKeyPress(down: HIDKeyboardReport(modifiers: .leftCommand, usages: [HIDKeyboardUsage.c.rawValue])),
                fallback: commandFallback
            ),
            .modifierState(keyLabel: "modifiers", report: .empty),
            .modifierState(keyLabel: "ctrl", report: HIDKeyboardReport(modifiers: .leftControl)),
            .modifierState(keyLabel: "opt", report: HIDKeyboardReport(modifiers: [.leftControl, .leftOption])),
            .keyPress(
                keyLabel: "tab",
                keyPress: HIDKeyPress(down: HIDKeyboardReport(modifiers: [.leftControl, .leftOption], usages: [HIDKeyboardUsage.tab.rawValue])),
                fallback: KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly)
            ),
            .modifierState(keyLabel: "modifiers", report: .empty),
            .modifierState(keyLabel: "cmd", report: HIDKeyboardReport(modifiers: .leftCommand)),
            .keyPress(
                keyLabel: "V",
                keyPress: HIDKeyPress(down: HIDKeyboardReport(modifiers: [.leftShift, .leftCommand], usages: [HIDKeyboardUsage.v.rawValue])),
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

    private var commandFallback: KeyResolution {
        KeyResolution(
            action: .noOperation("Command shortcuts require a hardware-equivalent event path"),
            outcome: .unknown
        )
    }

    private func bottomRowKeyPressEvent(
        _ label: String,
        usage: HIDKeyboardUsage,
        modifiers: HIDModifier = [],
        fallback: TextProxyAction
    ) -> KeyboardOutputEvent {
        .keyPress(
            keyLabel: label,
            keyPress: HIDKeyPress(down: HIDKeyboardReport(modifiers: modifiers, usages: [usage.rawValue])),
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
