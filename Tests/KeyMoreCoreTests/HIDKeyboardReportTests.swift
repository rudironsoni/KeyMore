import XCTest
@testable import KeyMoreCore

final class HIDKeyboardReportTests: XCTestCase {
    func testCommandCProducesUSBHIDModifierAndUsageReport() {
        let stroke = HIDReportBuilder.stroke(for: "c", activeModifiers: [.command])

        XCTAssertEqual(stroke?.down.bytes, [0x08, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(stroke?.up.bytes, HIDKeyboardReport.empty.bytes)
    }

    func testControlOptionTabProducesCombinedModifierAndTabUsageReport() {
        let stroke = HIDReportBuilder.stroke(for: .tab, activeModifiers: [.control, .option])

        XCTAssertEqual(stroke?.down.bytes, [0x05, 0x00, 0x2B, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testEscapeUsageMatchesUSBHIDKeyboardTable() {
        let stroke = HIDReportBuilder.stroke(for: .escape)

        XCTAssertEqual(stroke?.down.bytes, [0x00, 0x00, 0x29, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testStandaloneCommandProducesModifierOnlyReport() {
        let stroke = HIDReportBuilder.stroke(for: .command)

        XCTAssertEqual(stroke?.down.bytes, [0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }
}
