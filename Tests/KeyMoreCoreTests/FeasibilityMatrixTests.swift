import XCTest
@testable import KeyMoreCore

final class FeasibilityMatrixTests: XCTestCase {
    func testBaselineMatrixCoversEveryRequestedSpecialKey() {
        let keys = Set(KeyFeasibilityMatrix.baseline.map(\.key))

        XCTAssertEqual(keys, Set(SpecialKey.allCases))
    }

    func testBaselineDoesNotClaimHardwareEquivalentSupport() {
        XCTAssertFalse(KeyFeasibilityMatrix.baseline.contains { $0.currentResult == .hardwareEquivalent })
    }
}

