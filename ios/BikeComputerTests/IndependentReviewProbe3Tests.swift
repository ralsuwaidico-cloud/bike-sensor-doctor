// Copied unchanged from the independent review of 02d8795 (/home/claude/coach-review): assertions encode what a correct
// coach should do; they failed on 02d8795 and are kept as regression tests for the fixes.
import XCTest
@testable import BikeComputer

final class ReviewProbe3Tests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    func at(_ d: Int, _ h: Int = 7) -> Date { cal.date(byAdding: .day, value: d, to: today)!.addingTimeInterval(TimeInterval(h * 3600)) }
    // R17: rides capped by the WEEK BUILDER during a return phase carry no safetyOriginal, so they are not restored when the phase ends
    func testR17_GenerationCapNotReversible() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rev3-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 8; p.cyclingDaysPerWeek = 4
        var h = HealthScreen(); h.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = h; s.profile = p
        s.rides = [-60, -62, -64].map { RideRecord(start: at($0), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []) }
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let nextMon = cal.date(byAdding: .day, value: 7 - wd, to: today)!
        s.plan = PlanEngine.week(starting: nextMon, profile: p, availability: WeeklyAvailability.suggested(for: p), returning: s.cyclingReturnPhase())
        print("R17 generated during break:", s.plan.filter { $0.kind.isRide }.map { "\($0.kind.rawValue)\($0.minutes) orig:\($0.safetyOriginal != nil)" })
        s.rides += [-1, -2, -3].map { RideRecord(start: at($0), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []) }
        s.refreshRideSafety()
        print("R17 after the phase ended + refresh:", s.plan.filter { $0.kind.isRide }.map { "\($0.kind.rawValue)\($0.minutes)" }, "phase:", String(describing: s.cyclingReturnPhase()))
        XCTAssertTrue(s.plan.contains { $0.kind.zone >= 3 || $0.kind == .long }, "R17: generation-time caps are not lifted when the return phase ends")
    }
}
