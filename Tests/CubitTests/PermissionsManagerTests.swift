import XCTest
@testable import Cubit

private struct FakePermissionProvider: ScreenCapturePermissionProviding {
    var preflightValue: Bool
    var requestValue: Bool

    func preflight() -> Bool { preflightValue }
    func request() -> Bool { requestValue }
}

@MainActor
final class PermissionsManagerTests: XCTestCase {
    func testGrantedPreflightPresentsOverlay() {
        let manager = PermissionsManager(
            provider: FakePermissionProvider(preflightValue: true, requestValue: true)
        )
        XCTAssertTrue(manager.isGranted)
        XCTAssertEqual(manager.entryDecision(hasContinuedWithout: false), .presentOverlay)
    }

    func testDeniedWithoutContinueShowsOnboarding() {
        let manager = PermissionsManager(
            provider: FakePermissionProvider(preflightValue: false, requestValue: false)
        )
        XCTAssertFalse(manager.isGranted)
        XCTAssertEqual(manager.entryDecision(hasContinuedWithout: false), .showOnboarding)
    }

    func testDeniedButContinuedPresentsOverlay() {
        let manager = PermissionsManager(
            provider: FakePermissionProvider(preflightValue: false, requestValue: false)
        )
        XCTAssertEqual(manager.entryDecision(hasContinuedWithout: true), .presentOverlay)
    }

    func testGrantedStillPresentsRegardlessOfContinueFlag() {
        let manager = PermissionsManager(
            provider: FakePermissionProvider(preflightValue: true, requestValue: true)
        )
        XCTAssertEqual(manager.entryDecision(hasContinuedWithout: false), .presentOverlay)
        XCTAssertEqual(manager.entryDecision(hasContinuedWithout: true), .presentOverlay)
    }

    func testRequestAccessForwardsProviderResult() {
        let granting = PermissionsManager(
            provider: FakePermissionProvider(preflightValue: false, requestValue: true)
        )
        XCTAssertTrue(granting.requestAccess())

        let denying = PermissionsManager(
            provider: FakePermissionProvider(preflightValue: false, requestValue: false)
        )
        XCTAssertFalse(denying.requestAccess())
    }
}
