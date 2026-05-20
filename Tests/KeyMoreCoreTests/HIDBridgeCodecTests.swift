import XCTest
@testable import KeyMoreCore

final class HIDBridgeCodecTests: XCTestCase {
    func testHIDBridgeMessageRoundTripsAsLineDelimitedJSON() throws {
        let keyPress = HIDReportBuilder.keyPress(for: "c", activeModifiers: [.command])!
        let message = HIDBridgeMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_779_000_000),
            source: .keyboardExtension,
            keyLabel: "cmd+c",
            frames: [
                HIDBridgeFrame(phase: .keyDown, report: keyPress.down),
                HIDBridgeFrame(phase: .keyUp, report: keyPress.up)
            ],
            fallbackAction: "Command shortcuts require a bridge"
        )

        let encoded = try HIDBridgeCodec.encode(message)
        let decoded = try HIDBridgeCodec.decodeMessage(encoded)

        XCTAssertEqual(encoded.last, HIDBridgeConstants.frameTerminator)
        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.frames.map(\.bytes), [
            [0x08, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00],
            HIDKeyboardReport.empty.bytes
        ])
    }

    func testModifierStateMessageCarriesStandaloneModifierReport() throws {
        let message = HIDBridgeMessage.modifierState(
            keyLabel: "ctrl",
            report: HIDKeyboardReport(modifiers: .leftControl)
        )

        let decoded = try HIDBridgeCodec.decodeMessage(try HIDBridgeCodec.encode(message))

        XCTAssertEqual(decoded.frames, [
            HIDBridgeFrame(
                phase: .modifierState,
                bytes: [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            )
        ])
    }

    func testComboKeyPressMessagePreservesKeyDownThenKeyUpFrameOrder() throws {
        let keyPress = try XCTUnwrap(HIDReportBuilder.keyPress(for: "c", activeModifiers: [.control, .option, .command]))
        let message = HIDBridgeMessage.keyPress(
            keyLabel: "ctrl+opt+cmd+c",
            keyPress: keyPress,
            fallbackAction: TextProxyAction.noOperation("hardware route required").diagnosticDescription
        )

        XCTAssertEqual(message.frames.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(message.frames.map(\.bytes), [
            [0x0D, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00],
            HIDKeyboardReport.empty.bytes
        ])
        XCTAssertEqual(message.fallbackAction, "hardware route required")
    }

    func testSpecialKeyComboMessagesCarryModifierUsageAndFallbackMetadata() throws {
        let tab = try XCTUnwrap(HIDReportBuilder.keyPress(for: .tab, activeModifiers: [.control, .option]))
        let message = HIDBridgeMessage.keyPress(
            keyLabel: "ctrl+opt+tab",
            keyPress: tab,
            fallbackAction: TextProxyAction.insertText("\t").diagnosticDescription
        )

        let decoded = try HIDBridgeCodec.decodeMessage(try HIDBridgeCodec.encode(message))

        XCTAssertEqual(decoded.keyLabel, "ctrl+opt+tab")
        XCTAssertEqual(decoded.frames.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(decoded.frames.map(\.bytes), [
            [0x05, 0x00, 0x2B, 0x00, 0x00, 0x00, 0x00, 0x00],
            HIDKeyboardReport.empty.bytes
        ])
        XCTAssertEqual(decoded.fallbackAction, "insertText(\"\\t\")")
    }

    func testModifierStateMessagesCoverEveryStickyModifierCombination() throws {
        let cases: [(Set<SpecialKey>, [UInt8])] = [
            ([], [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            ([.control], [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            ([.option], [0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            ([.command], [0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            ([.control, .option], [0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            ([.control, .command], [0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            ([.option, .command], [0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            ([.control, .option, .command], [0x0D, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        ]

        for (modifiers, bytes) in cases {
            let message = HIDBridgeMessage.modifierState(
                keyLabel: modifiers.map(\.displayTitle).sorted().joined(separator: "+"),
                report: HIDKeyboardReport(modifiers: HIDReportBuilder.modifiers(for: modifiers))
            )

            let decoded = try HIDBridgeCodec.decodeMessage(try HIDBridgeCodec.encode(message))

            XCTAssertEqual(decoded.frames, [HIDBridgeFrame(phase: .modifierState, bytes: bytes)])
        }
    }

    func testAckRoundTripsWithDispatchModeAndOutcome() throws {
        let ack = HIDBridgeAck(
            id: UUID(),
            accepted: true,
            mode: .diagnosticAppSink,
            outcome: .appIntegratedOnly,
            detail: "accepted"
        )

        let decoded = try HIDBridgeCodec.decodeAck(try HIDBridgeCodec.encode(ack))

        XCTAssertEqual(decoded, ack)
    }
}
