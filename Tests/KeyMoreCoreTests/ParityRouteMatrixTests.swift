import XCTest
@testable import KeyMoreCore

final class ParityRouteMatrixTests: XCTestCase {
    func testRouteMatrixCoversEveryKnownParityRoute() {
        let routes = Set(ParityRouteMatrix.current.map(\.route))

        XCTAssertEqual(routes, Set(ParityRoute.allCases))
    }

    func testExternalHIDBridgeRemainsOnlyUnrestrictedPublicArbitraryAppRoute() {
        let candidates = ParityRouteMatrix.current.filter {
            $0.canTargetArbitraryApps
                && !$0.requiresPrivateAPI
                && !$0.requiresRestrictedEntitlement
                && !$0.requiresExternalHardware
        }

        XCTAssertTrue(candidates.isEmpty)
    }

    func testCoreHIDVirtualDeviceIsEntitlementGatedSoftwareRoute() {
        let route = ParityRouteMatrix.current.first { $0.route == .coreHIDVirtualDevice }

        XCTAssertEqual(route?.canTargetArbitraryApps, true)
        XCTAssertEqual(route?.requiresPrivateAPI, false)
        XCTAssertEqual(route?.requiresRestrictedEntitlement, true)
        XCTAssertEqual(route?.requiresExternalHardware, false)
        XCTAssertEqual(route?.expectedOutcome, .blockedByEntitlement)
    }

    func testExternalHIDBridgeDoesNotRequireAppleEntitlement() {
        let route = ParityRouteMatrix.current.first { $0.route == .externalHIDBridge }

        XCTAssertEqual(route?.canTargetArbitraryApps, true)
        XCTAssertEqual(route?.requiresPrivateAPI, false)
        XCTAssertEqual(route?.requiresRestrictedEntitlement, false)
        XCTAssertEqual(route?.requiresExternalHardware, true)
        XCTAssertEqual(route?.expectedOutcome, .hardwareBridgeRequired)
    }
}
