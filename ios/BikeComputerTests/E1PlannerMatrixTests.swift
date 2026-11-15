import XCTest
@testable import BikeComputer

/// E1-C (owner directive 15 Nov 2026): a full-body session the planner builds must never be refused by the planner's own
/// full-body rule. E0 run 225 proved the cause for beginners without equipment; this matrix covers the athlete
/// configurations the directive lists. Synthetic store in a temporary directory.
final class E1PlannerMatrixTests: XCTestCase {
    private func store() -> (Store, UUID) {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("e1-planner-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        s.profile.name = "E1 Planner"; s.onboarded = true
        let w = Workout(date: Calendar.current.startOfDay(for: Date()).addingTimeInterval(18 * 3600), kind: .strength, minutes: 45, strengthFocus: .fullBody)
        s.plan = [w]
        return (s, w.id)
    }
    private let equipment: [(String, EquipmentProfile)] = [
        ("not recorded", EquipmentProfile()),
        ("bodyweight only", EquipmentProfile(confirmed: true)),
        ("dumbbells and bench", EquipmentProfile(owned: ["dumbbell", "bench"])),
        ("full gym", EquipmentProfile(owned: ["barbell", "dumbbell", "kettlebell", "bench", "rack", "machine", "cable", "pull-up bar", "band"])),
    ]

    func testPlannerNeverBuildsAFullBodySessionItsOwnRuleRefuses() {
        var rows: [String] = [], refused: [String] = [], blockedAtUsualLengths: [String] = []
        for level in [StrengthPrefs.Experience.beginner, .intermediate, .advanced] {
            for (name, eq) in equipment {
                let (s, id) = store()
                s.strengthPrefs.experience = level; s.equipment = eq
                for m in [20, 30, 45, 60, 90] {
                    var req = SessionChangeRequest(); req.minutes = m; req.detachRoutine = true
                    guard let p = s.evaluateSessionChange(workoutId: id, request: req) else { rows.append("\(level.rawValue) · \(name) · \(m) min: no proposal"); continue }
                    let cov = WorkoutValidator.coverage(p.afterEntries, catalogue: s.allExercises)
                    let blocks = p.report.issues.filter { $0.outcome == .block }.map { $0.ruleId }
                    let row = "\(level.rawValue) · \(name) · \(m) min: \(p.report.outcome.rawValue) blocks=\(blocks) knee=\(cov.knee) hip=\(cov.hip) push=\(cov.push) pull=\(cov.pull) :: \(p.afterEntries.map { "\($0.name)×\($0.sets.count)" }.joined(separator: ", "))"
                    rows.append(row); print("E1-PLANNER \(row)")
                    if p.report.has("SPLIT-001") { refused.append(row) }
                    if m >= 45, p.report.outcome == .block { blockedAtUsualLengths.append(row) }
                }
            }
        }
        XCTAssertTrue(refused.isEmpty, "the planner built a full-body session that its own full-body rule refuses:\n\(refused.joined(separator: "\n"))")
        XCTAssertTrue(blockedAtUsualLengths.isEmpty, "a 45-minute or longer full-body rebuild cannot be applied:\n\(blockedAtUsualLengths.joined(separator: "\n"))")
    }
}
