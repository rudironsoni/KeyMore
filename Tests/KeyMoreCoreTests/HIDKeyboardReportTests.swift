import XCTest
@testable import KeyMoreCore

final class HIDKeyboardReportTests: XCTestCase {
    private typealias ModifierCase = (keys: Set<SpecialKey>, byte: UInt8)

    func testCommandCProducesUSBHIDModifierAndUsageReport() {
        let keyPress = HIDReportBuilder.keyPress(for: "c", activeModifiers: [.command])

        XCTAssertEqual(keyPress?.down.bytes, [0x08, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(keyPress?.up.bytes, [0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testControlOptionTabProducesCombinedModifierAndTabUsageReport() {
        let keyPress = HIDReportBuilder.keyPress(for: .tab, activeModifiers: [.control, .option])

        XCTAssertEqual(keyPress?.down.bytes, [0x05, 0x00, 0x2B, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(keyPress?.up.bytes, [0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testEscapeUsageMatchesUSBHIDKeyboardTable() {
        let keyPress = HIDReportBuilder.keyPress(for: .escape)

        XCTAssertEqual(keyPress?.down.bytes, [0x00, 0x00, 0x29, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testStandaloneCommandProducesModifierOnlyReport() {
        let keyPress = HIDReportBuilder.keyPress(for: .command)

        XCTAssertEqual(keyPress?.down.bytes, [0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testBootKeyboardDescriptorMatchesEightByteReportShape() {
        let descriptor = HIDKeyboardReportDescriptor.bootKeyboard

        XCTAssertTrue(descriptor.starts(with: [0x05, 0x01, 0x09, 0x06]))
        XCTAssertTrue(descriptor.contains(0xE0))
        XCTAssertTrue(descriptor.contains(0xE7))
        XCTAssertTrue(descriptor.contains(0xC0))
        XCTAssertEqual(HIDKeyboardReport.empty.bytes.count, 8)
    }

    func testAllModifierCombinationsProduceExpectedModifierByte() {
        for modifierCase in allModifierCases {
            let modifiers = HIDReportBuilder.modifiers(for: modifierCase.keys)

            XCTAssertEqual(
                modifiers.rawValue,
                modifierCase.byte,
                "Unexpected modifier byte for \(modifierCase.keys.map(\.displayTitle).sorted())"
            )
        }
    }

    func testEveryRequestedSpecialKeyProducesExpectedStandaloneReport() throws {
        let expected: [SpecialKey: [UInt8]] = [
            .escape: reportBytes(usage: HIDKeyboardUsage.escape.rawValue),
            .control: reportBytes(modifiers: 0x01),
            .option: reportBytes(modifiers: 0x04),
            .command: reportBytes(modifiers: 0x08),
            .tab: reportBytes(usage: HIDKeyboardUsage.tab.rawValue)
        ]

        for key in SpecialKey.allCases {
            let keyPress = try XCTUnwrap(HIDReportBuilder.keyPress(for: key), "Missing keyPress for \(key)")

            XCTAssertEqual(keyPress.down.bytes, expected[key], "Unexpected down report for \(key)")
            XCTAssertEqual(keyPress.up.bytes, HIDKeyboardReport.empty.bytes, "Unexpected up report for \(key)")
        }
    }

    func testTabAndEscapeCarryEveryModifierCombination() throws {
        for modifierCase in allModifierCases {
            let tab = try XCTUnwrap(HIDReportBuilder.keyPress(for: .tab, activeModifiers: modifierCase.keys))
            let escape = try XCTUnwrap(HIDReportBuilder.keyPress(for: .escape, activeModifiers: modifierCase.keys))

            XCTAssertEqual(tab.down.bytes, reportBytes(modifiers: modifierCase.byte, usage: HIDKeyboardUsage.tab.rawValue))
            XCTAssertEqual(escape.down.bytes, reportBytes(modifiers: modifierCase.byte, usage: HIDKeyboardUsage.escape.rawValue))
            XCTAssertEqual(tab.up.bytes, reportBytes(modifiers: modifierCase.byte))
            XCTAssertEqual(escape.up.bytes, reportBytes(modifiers: modifierCase.byte))
        }
    }

    func testLettersMapToContiguousUSBHIDKeyboardUsages() throws {
        for scalarValue in UInt8(ascii: "a")...UInt8(ascii: "z") {
            let character = Character(UnicodeScalar(scalarValue))
            let keyPress = try XCTUnwrap(HIDReportBuilder.keyPress(for: character, activeModifiers: []))
            let expectedUsage = scalarValue - 93

            XCTAssertEqual(keyPress.down.bytes, reportBytes(usage: expectedUsage), "Unexpected report for \(character)")
            XCTAssertEqual(keyPress.up.bytes, HIDKeyboardReport.empty.bytes)
        }
    }

    func testEveryLetterKeyPressCarriesEveryModifierCombination() throws {
        for modifierCase in allModifierCases {
            for scalarValue in UInt8(ascii: "a")...UInt8(ascii: "z") {
                let character = Character(UnicodeScalar(scalarValue))
                let keyPress = try XCTUnwrap(HIDReportBuilder.keyPress(for: character, activeModifiers: modifierCase.keys))
                let expectedUsage = scalarValue - 93

                XCTAssertEqual(
                    keyPress.down.bytes,
                    reportBytes(modifiers: modifierCase.byte, usage: expectedUsage),
                    "Unexpected keyDown report for \(modifierCase.keys) + \(character)"
                )
                XCTAssertEqual(
                    keyPress.up.bytes,
                    reportBytes(modifiers: modifierCase.byte),
                    "Unexpected keyUp report for \(modifierCase.keys) + \(character)"
                )
            }
        }
    }

    func testComboKeyReleasePreservesActiveModifiersUntilClearReport() throws {
        let keyPress = try XCTUnwrap(HIDReportBuilder.keyPress(for: "x", activeModifiers: [.control, .option, .command]))

        XCTAssertEqual(keyPress.down.bytes, reportBytes(modifiers: 0x0D, usage: HIDKeyboardUsage.x.rawValue))
        XCTAssertEqual(keyPress.up.bytes, reportBytes(modifiers: 0x0D))
    }

    func testLetterUsageLookupIsCaseInsensitiveAndRejectsNonLetters() {
        XCTAssertEqual(HIDKeyboardUsage.letter("A"), .a)
        XCTAssertEqual(HIDKeyboardUsage.letter("z"), .z)
        XCTAssertNil(HIDKeyboardUsage.letter("1"))
        XCTAssertNil(HIDKeyboardUsage.letter("\t"))
    }

    func testReportsAlwaysUseBootKeyboardEightByteShapeAndTruncateExtraUsages() {
        let report = HIDKeyboardReport(
            modifiers: [.leftControl, .leftCommand],
            usages: [1, 2, 3, 4, 5, 6, 7, 8]
        )

        XCTAssertEqual(report.bytes, [0x09, 0x00, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(report.bytes.count, 8)
    }

    private var allModifierCases: [ModifierCase] {
        [
            ([], 0x00),
            ([.control], 0x01),
            ([.option], 0x04),
            ([.command], 0x08),
            ([.control, .option], 0x05),
            ([.control, .command], 0x09),
            ([.option, .command], 0x0C),
            ([.control, .option, .command], 0x0D)
        ]
    }

    private func reportBytes(modifiers: UInt8 = 0, usage: UInt8 = 0) -> [UInt8] {
        [modifiers, 0x00, usage, 0x00, 0x00, 0x00, 0x00, 0x00]
    }
}
