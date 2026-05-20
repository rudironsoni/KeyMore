import XCTest
@testable import KeyMoreCore

final class VirtualHIDKeyboardDispatcherTests: XCTestCase {
    func testDispatchResultsMapToFeasibilityOutcomes() {
        XCTAssertEqual(VirtualHIDDispatchResult.dispatched.outcome, .hardwareEquivalent)
        XCTAssertEqual(VirtualHIDDispatchResult.unavailable("missing").outcome, .missingRuntime)
        XCTAssertEqual(VirtualHIDDispatchResult.entitlementMissing("denied").outcome, .blockedByEntitlement)
        XCTAssertEqual(VirtualHIDDispatchResult.failed("failed").outcome, .unknown)
    }

    func testOnlyDispatchedSuppressesTextProxyFallback() {
        XCTAssertFalse(VirtualHIDDispatchResult.dispatched.shouldApplyTextProxyFallback)
        XCTAssertTrue(VirtualHIDDispatchResult.unavailable("missing").shouldApplyTextProxyFallback)
        XCTAssertTrue(VirtualHIDDispatchResult.entitlementMissing("denied").shouldApplyTextProxyFallback)
        XCTAssertTrue(VirtualHIDDispatchResult.failed("failed").shouldApplyTextProxyFallback)
    }

    func testRuntimeDispatchReportsEntitlementOrPlatformBlockWithoutGrantedEntitlement() async throws {
        let keyPress = try XCTUnwrap(HIDReportBuilder.keyPress(for: .escape))
        let message = HIDBridgeMessage.keyPress(keyLabel: "esc", keyPress: keyPress)
        let result = await withCheckedContinuation { continuation in
            VirtualHIDKeyboardDispatcher.shared.dispatch(message) { dispatchResult in
                continuation.resume(returning: dispatchResult)
            }
        }

        XCTAssertNotEqual(result, .dispatched)
        XCTAssertTrue(result.shouldApplyTextProxyFallback)
        XCTAssertTrue([.blockedByEntitlement, .missingRuntime, .unknown].contains(result.outcome))
    }
}
