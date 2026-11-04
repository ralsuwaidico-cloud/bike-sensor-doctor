import XCTest
@testable import BikeComputer

/// Checkpoint B: the dock says exactly what the fixed bar said (simulator unit target only — references a view type).
final class DockCopyTests: XCTestCase {
    func testCentreCopyIsUnchangedFromTheFixedBar() {
        let w = Workout(date: Date(), kind: .strength, minutes: 30)
        XCTAssertEqual(RideTabBar.centreCopy(recording: false, action: .train(w)).label, "Train now")
        XCTAssertEqual(RideTabBar.centreCopy(recording: false, action: .ride(w)).label, "Ride now")
        XCTAssertEqual(RideTabBar.centreCopy(recording: false, action: .healthHold).label, "Paused")
        XCTAssertEqual(RideTabBar.centreCopy(recording: true, action: .rest).label, "Riding")
    }
}
