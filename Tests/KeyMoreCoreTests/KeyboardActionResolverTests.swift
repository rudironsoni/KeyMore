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
}

