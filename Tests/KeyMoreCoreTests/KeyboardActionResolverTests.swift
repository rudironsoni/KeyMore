import XCTest
@testable import KeyMoreCore

final class KeyboardActionResolverTests: XCTestCase {
    func testTabIsTextProxyOnlyFallback() {
        let resolution = KeyboardActionResolver.resolveSpecialKey(.tab)

        XCTAssertEqual(resolution, KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly))
    }

    func testEscapeIsTextProxyOnlyFallback() {
        let resolution = KeyboardActionResolver.resolveSpecialKey(.escape)

        XCTAssertEqual(resolution, KeyResolution(action: .insertText("\u{1B}"), outcome: .textProxyOnly))
    }

    func testControlLetterEmitsControlCharacterAsFallbackOnly() {
        let resolution = KeyboardActionResolver.resolveCharacter("c", activeModifiers: [.control])

        XCTAssertEqual(resolution, KeyResolution(action: .insertText("\u{3}"), outcome: .textProxyOnly))
    }

    func testOptionLetterEmitsEscapePrefixedFallbackOnly() {
        let resolution = KeyboardActionResolver.resolveCharacter("x", activeModifiers: [.option])

        XCTAssertEqual(resolution, KeyResolution(action: .insertText("\u{1B}x"), outcome: .textProxyOnly))
    }

    func testCommandLetterDoesNotPretendToSendShortcut() {
        let resolution = KeyboardActionResolver.resolveCharacter("c", activeModifiers: [.command])

        XCTAssertEqual(resolution.outcome, .unknown)
        XCTAssertEqual(
            resolution.action,
            .noOperation("Command shortcuts require a hardware-equivalent event path")
        )
    }

    func testEverySpecialKeyHasExpectedTextProxyFallback() {
        let expected: [SpecialKey: KeyResolution] = [
            .escape: KeyResolution(action: .insertText("\u{1B}"), outcome: .textProxyOnly),
            .control: KeyResolution(action: .noOperation("ctrl requires a hardware-equivalent event path"), outcome: .unknown),
            .option: KeyResolution(action: .noOperation("opt requires a hardware-equivalent event path"), outcome: .unknown),
            .command: KeyResolution(action: .noOperation("cmd requires a hardware-equivalent event path"), outcome: .unknown),
            .tab: KeyResolution(action: .insertText("\t"), outcome: .textProxyOnly)
        ]

        for key in SpecialKey.allCases {
            XCTAssertEqual(KeyboardActionResolver.resolveSpecialKey(key), expected[key])
        }
    }

    func testPlainCharactersInsertThemselvesAsTextProxyFallback() {
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("a", activeModifiers: []),
            KeyResolution(action: .insertText("a"), outcome: .textProxyOnly)
        )
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("A", activeModifiers: []),
            KeyResolution(action: .insertText("A"), outcome: .textProxyOnly)
        )
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("1", activeModifiers: []),
            KeyResolution(action: .insertText("1"), outcome: .textProxyOnly)
        )
    }

    func testControlFallbackMapsEveryLetterToControlCharacter() throws {
        for scalarValue in UInt8(ascii: "a")...UInt8(ascii: "z") {
            let letter = String(UnicodeScalar(scalarValue))
            let expectedScalar = try XCTUnwrap(UnicodeScalar(UInt32(scalarValue - 96)))

            XCTAssertEqual(
                KeyboardActionResolver.resolveCharacter(letter, activeModifiers: [.control]),
                KeyResolution(action: .insertText(String(expectedScalar)), outcome: .textProxyOnly),
                "Unexpected control fallback for \(letter)"
            )
        }
    }

    func testControlFallbackIsCaseInsensitive() {
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("C", activeModifiers: [.control]),
            KeyResolution(action: .insertText("\u{3}"), outcome: .textProxyOnly)
        )
    }

    func testOptionFallbackPrefixesCharacterWithEscape() {
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("x", activeModifiers: [.option]),
            KeyResolution(action: .insertText("\u{1B}x"), outcome: .textProxyOnly)
        )
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("X", activeModifiers: [.option]),
            KeyResolution(action: .insertText("\u{1B}X"), outcome: .textProxyOnly)
        )
    }

    func testCommandWinsOverOtherTextProxyFallbacksBecauseShortcutNeedsHardwareRoute() {
        for modifiers in [
            Set<SpecialKey>([.command]),
            Set<SpecialKey>([.command, .control]),
            Set<SpecialKey>([.command, .option]),
            Set<SpecialKey>([.command, .control, .option])
        ] {
            XCTAssertEqual(
                KeyboardActionResolver.resolveCharacter("c", activeModifiers: modifiers),
                KeyResolution(
                    action: .noOperation("Command shortcuts require a hardware-equivalent event path"),
                    outcome: .unknown
                )
            )
        }
    }

    func testControlWinsOverOptionForTextProxyFallbackWhenCommandIsNotActive() {
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("c", activeModifiers: [.control, .option]),
            KeyResolution(action: .insertText("\u{3}"), outcome: .textProxyOnly)
        )
    }

    func testEmptyCharacterIsNoOperation() {
        XCTAssertEqual(
            KeyboardActionResolver.resolveCharacter("", activeModifiers: []),
            KeyResolution(action: .noOperation("Empty character"), outcome: .unknown)
        )
    }

    func testDiagnosticDescriptionsAreStableForBridgeFallbackMetadata() {
        XCTAssertEqual(TextProxyAction.insertText("\t").diagnosticDescription, "insertText(\"\\t\")")
        XCTAssertEqual(TextProxyAction.deleteBackward.diagnosticDescription, "deleteBackward")
        XCTAssertEqual(TextProxyAction.noOperation("reason").diagnosticDescription, "reason")
    }
}
