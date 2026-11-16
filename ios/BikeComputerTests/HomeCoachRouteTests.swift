import XCTest
@testable import BikeComputer

/// Audit of 16 Nov 2026: in the redesign every Coach card was sent to the Coach page, which made hybrid-coach
/// suggestions, the FTP suggestion and the session-rating prompt unreachable. One route rule, tested for every source.
final class HomeCoachRouteTests: XCTestCase {
    private let w = UUID(), r = UUID()
    private var sources: [HomeCoachItem.Source] {
        [.adaptiveProposal("a"), .hybridProposal("h"), .adjustment(w), .ftp, .gap, .revise, .insight(w), .rate(.ride(r)), .rate(.strength(w))]
    }
    func testProductionRoutesAreTheOnesBuild216Had() {
        let expect: [HomeCoachItem.Route] = [.adaptiveSheet("a"), .hybridSheet("h"), .adjustments, .ftpSheet, .plan, .plan, .startStrength(w), .rateSheet(.ride(r)), .rateSheet(.strength(w))]
        XCTAssertEqual(sources.map { HomeCoachItem.route(for: $0, redesign: false) }, expect)
        XCTAssertFalse(sources.contains { HomeCoachItem.route(for: $0, redesign: false) == .coachPage }, "production has no Coach page")
    }
    func testRedesignSendsOnlyTheCoachsOwnPlanItemsToTheCoachPage() {
        let expect: [HomeCoachItem.Route] = [.coachPage, .hybridSheet("h"), .coachPage, .ftpSheet, .plan, .plan, .startStrength(w), .rateSheet(.ride(r)), .rateSheet(.strength(w))]
        XCTAssertEqual(sources.map { HomeCoachItem.route(for: $0, redesign: true) }, expect)
    }
    func testEveryOtherSourceKeepsItsDestinationInBothShells() {
        for s in sources {
            if case .adaptiveProposal = s { continue }; if case .adjustment = s { continue }
            XCTAssertEqual(HomeCoachItem.route(for: s, redesign: true), HomeCoachItem.route(for: s, redesign: false), "\(s)")
        }
    }
}
