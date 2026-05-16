import XCTest
@testable import KeyMoreCore

final class PrivatePathProbeTests: XCTestCase {
    func testMissingRuntimeSurfacesAreRecordedAsMissingRuntimeEvidence() {
        let results = PrivatePathProbe.inspect { _ in false }

        XCTAssertEqual(Set(results.map(\.outcome)), [.missingRuntime])
        XCTAssertEqual(results.count, PrivatePathProbe.candidates.count)
    }

    func testPresentRuntimeSurfacesRemainUnprovenUntilEventDeliveryIsProven() {
        let results = PrivatePathProbe.inspect { _ in true }

        XCTAssertTrue(Set(results.map(\.outcome)).isSubset(of: [.unknown, .automationOnly]))
        XCTAssertTrue(results.allSatisfy { $0.detail.contains("delivery") })
    }

    func testProbeMatrixIncludesXCTestIOKitGraphicsServicesAndHostHookRoutes() {
        let routes = Set(PrivatePathProbe.candidates.map(\.route))

        XCTAssertTrue(routes.contains(.privateXCTestSynthesis))
        XCTAssertTrue(routes.contains(.privateIOKitHIDInjection))
        XCTAssertTrue(routes.contains(.graphicsServicesGSEvent))
        XCTAssertTrue(routes.contains(.hostAppPrivateHIDHook))
    }
}
