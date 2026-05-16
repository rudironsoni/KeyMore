import XCTest
@testable import KeyMoreCore

final class HIDBridgeCodecTests: XCTestCase {
    func testHIDBridgeMessageRoundTripsAsLineDelimitedJSON() throws {
        let stroke = HIDReportBuilder.stroke(for: "c", activeModifiers: [.command])!
        let message = HIDBridgeMessage(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_779_000_000),
            source: .keyboardExtension,
            keyLabel: "cmd+c",
            frames: [
                HIDBridgeFrame(phase: .keyDown, report: stroke.down),
                HIDBridgeFrame(phase: .keyUp, report: stroke.up)
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
