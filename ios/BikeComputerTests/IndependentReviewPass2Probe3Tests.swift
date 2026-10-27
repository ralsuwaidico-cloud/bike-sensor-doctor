// Copied unchanged from the second independent review pass (29916e7, /home/claude/coach-review): assertions encode what a
// correct coach should do; they failed on 29916e7 and are kept as regression tests.
import XCTest
@testable import BikeComputer

final class Pass2Probe3Tests: XCTestCase {
    // Q12: a "see a doctor" answer that is more than a year old
    func testQ12_StopExpiresIntoTraining() {
        var s = HealthScreen(); s.chestPain = true; s.answeredAt = Calendar.current.date(byAdding: .day, value: -370, to: Date())
        let r = CoachReadiness(screen: s.status)
        print("Q12 chest-pain answer 370 days old -> status \(s.status), trainingAllowed \(r.trainingAllowed)")
        XCTAssertFalse(r.trainingAllowed, "Q12: an expired 'see a doctor' answer silently allows training again")
    }
    // Q13: answers saved by 02d8795 (no questionSet, no currentIllness)
    func testQ13_OldAnswersDecode() throws {
        let json = #"{"name":"x","healthScreen":{"answeredAt":800000000,"heartOrBloodPressure":false,"chestPain":false,"dizzinessOrFainting":false,"otherChronicCondition":false,"chronicMedication":false,"boneJointProblem":false,"supervisedOnly":false,"pregnancy":false}}"#
        let p = try JSONDecoder().decode(RiderProfile.self, from: Data(json.utf8))
        print("Q13 old answers ->", p.healthScreen.map { "\($0.status)" } ?? "nil (dropped)", "readiness", p.readiness.screen)
        XCTAssertEqual(p.readiness.screen, .notAnswered)
    }
}
