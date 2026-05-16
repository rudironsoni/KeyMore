import XCTest
@testable import KeyMoreCore

final class ParityRouteMatrixTests: XCTestCase {
    func testRouteMatrixCoversEveryKnownParityRoute() {
        let routes = Set(ParityRouteMatrix.current.map(\.route))

        XCTAssertEqual(routes, Set(ParityRoute.allCases))
    }

    func testOnlyExternalHIDBridgeClaimsArbitraryAppPotentialWithoutPrivateAPI() {
        let candidates = ParityRouteMatrix.current.filter {
            $0.canTargetArbitraryApps && !$0.requiresPrivateAPI
        }

        XCTAssertEqual(candidates.map(\.route), [.externalHIDBridge])
        XCTAssertEqual(candidates.first?.expectedOutcome, .hardwareBridgeRequired)
    }
}
