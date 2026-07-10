import XCTest
@testable import Cubit

/// A queued handoff must not resurface later over unrelated content. These pin the freshness
/// window that `OverlayController` consults before injecting a proposal that arrived while the
/// overlay was closed (e.g. behind the Screen Recording gate).
final class PendingHandoffTests: XCTestCase {

    private func makePending(queuedAt: Date) -> PendingHandoff {
        let measurement = Measurement(
            kind: .rectangle,
            rect: CanonicalRect(x: 0, y: 0, width: 10, height: 10),
            colorIndex: 0
        )
        return PendingHandoff(measurements: [measurement], note: "n", queuedAt: queuedAt)
    }

    func testFreshImmediately() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(makePending(queuedAt: now).isFresh(now: now))
    }

    func testFreshJustInsideTheWindow() {
        let queued = Date(timeIntervalSince1970: 1_000)
        let now = queued.addingTimeInterval(PendingHandoff.maxAge - 0.001)
        XCTAssertTrue(makePending(queuedAt: queued).isFresh(now: now))
    }

    func testFreshExactlyAtTheBoundary() {
        let queued = Date(timeIntervalSince1970: 1_000)
        let now = queued.addingTimeInterval(PendingHandoff.maxAge)
        XCTAssertTrue(makePending(queuedAt: queued).isFresh(now: now))
    }

    func testStaleJustPastTheWindow() {
        let queued = Date(timeIntervalSince1970: 1_000)
        let now = queued.addingTimeInterval(PendingHandoff.maxAge + 0.001)
        XCTAssertFalse(makePending(queuedAt: queued).isFresh(now: now))
    }

    /// The bug this guards: the user opens the overlay by hotkey long after an agent's proposal
    /// was queued behind the permission gate. The proposal must NOT appear.
    func testStaleAnHourLater() {
        let queued = Date(timeIntervalSince1970: 1_000)
        let now = queued.addingTimeInterval(3_600)
        XCTAssertFalse(makePending(queuedAt: queued).isFresh(now: now))
    }

    /// A clock adjusted backwards must read as stale, not fresh-forever.
    func testNegativeAgeIsStale() {
        let queued = Date(timeIntervalSince1970: 1_000)
        let now = queued.addingTimeInterval(-1)
        XCTAssertFalse(makePending(queuedAt: queued).isFresh(now: now))
    }

    func testCustomMaxAgeIsHonored() {
        let queued = Date(timeIntervalSince1970: 1_000)
        let pending = makePending(queuedAt: queued)
        XCTAssertTrue(pending.isFresh(now: queued.addingTimeInterval(5), maxAge: 10))
        XCTAssertFalse(pending.isFresh(now: queued.addingTimeInterval(15), maxAge: 10))
    }

    func testDefaultWindowIsTwoMinutes() {
        XCTAssertEqual(PendingHandoff.maxAge, 120)
    }
}

/// The `show`/`show_overlay` result must not claim the overlay is visible — it cannot know.
final class HandoffStatusTests: XCTestCase {

    func testStatusIsDeliveredNotDisplayed() {
        XCTAssertEqual(HandoffStatus.delivered.rawValue, "delivered")
    }

    func testNoteWarnsThatDisplayIsUnconfirmed() {
        let note = HandoffStatus.deliveredNote
        XCTAssertTrue(note.contains("does not confirm"))
        XCTAssertTrue(note.contains("permission gate"))
        XCTAssertFalse(note.lowercased().contains("is now on screen"))
    }

    func testShowResultEncodesStatusAndNote() throws {
        let result = ShowCommand.ShowResult(
            opened: "/tmp/x.json",
            measurementCount: 3,
            status: HandoffStatus.delivered.rawValue,
            note: HandoffStatus.deliveredNote
        )
        let data = try JSONEncoder().encode(result)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "delivered")
        XCTAssertEqual(json["measurementCount"] as? Int, 3)
        XCTAssertNotNil(json["note"])
    }
}
