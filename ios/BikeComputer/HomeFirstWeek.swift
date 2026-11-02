import SwiftUI

// MARK: - V1: Home for a rider's first week (owner 2 Nov: approving the plan lands on a useful Home)
// Shown while nothing has been recorded yet (no non-demo ride, no strength log) and a plan exists. Every number comes
// from the approved plan and the profile; the Getting-started rows read the real device states. Nothing is a sample.

struct HomeFirstWeekSection: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var hub: SensorHub
    var openPlan: () -> Void
    var openDevices: () -> Void
    var openProgress: () -> Void

    /// First week = a plan exists and nothing has been logged yet.
    static func applies(_ store: Store) -> Bool {
        store.rides.filter { !$0.demo }.isEmpty && store.strength.isEmpty && store.plan.contains { HomeWeekStrip.isTraining($0.kind) }
    }

    var body: some View {
        let w = store.homeWeek()
        let rides = w.riding, lifts = w.lifting
        VStack(alignment: .leading, spacing: CyTheme.sp3) {
            HomeSectionTitle(text: "This week")
            CyHeroRingCard(caption: "WEEK 1", title: ringTitle(w),
                           done: w.total.completed, planned: w.total.planned,
                           ridesDone: rides?.completed, ridesPlanned: rides?.planned,
                           liftsDone: lifts?.completed, liftsPlanned: lifts?.planned)
                .onTapGesture(perform: openProgress)
            if !store.profile.goals.isEmpty {
                HomeSectionTitle(text: "Goals")
                goals
            }
            HomeSectionTitle(text: "Getting started")
            gettingStarted
        }
    }

    private func ringTitle(_ w: HomeWeek) -> String {
        if w.total.planned == 0 { return "Nothing planned yet" }
        return w.total.completed == 0 ? "Your first week starts now" : "\(w.total.completed) of \(w.total.planned) done"
    }

    // MARK: goals — the selected goals, main goal first; progress appears only once something is logged
    private var goals: some View {
        let main = store.profile.primaryGoal
        let ordered = store.profile.goals.sorted { a, b in (a == main) && (b != main) }
        return VStack(spacing: CyTheme.sp2) {
            ForEach(ordered.prefix(2)) { g in
                CyGoalIndicatorCard(goal: g.title, isMain: g == main, indicator: GoalInfo.effect(g), value: nil,
                                    sub: "Progress appears after your first logged \(g.sport == .strength ? "session" : "ride").", tag: .needsData)
                    .accessibilityIdentifier("homeGoal-\(g.rawValue)")
            }
        }
    }

    // MARK: getting started — only rows that are still open, each with a real destination
    private var gettingStarted: some View {
        let watchOK = hub.deviceState("watch")?.isConnectedOrBetter ?? false
        let hrOK = watchOK || hub.deviceStates.values.contains { $0.provides.localizedCaseInsensitiveContains("heart") && $0.state.isConnectedOrBetter }
        let first = store.plan.filter { HomeWeekStrip.isTraining($0.kind) && !$0.skipped }.sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }.first
        return CyRowGroup {
            CyListRow(title: "Plan approved", value: "\(store.plan.filter { HomeWeekStrip.isTraining($0.kind) }.count) sessions this week", systemImage: "checkmark.circle.fill", sport: .recovery, action: openPlan)
                .accessibilityIdentifier("homeStartPlan")
            CyDivider()
            if !hrOK {
                CyListRow(title: "Add heart rate", value: "Apple Watch or a strap gives heart-rate targets on rides", systemImage: "heart.fill", sport: .cycling, action: openDevices)
                    .accessibilityIdentifier("homeStartHR")
                CyDivider()
            }
            if let f = first {
                CyListRow(title: f.kind == .strength ? "Log your first session" : "Record your first ride",
                          value: f.kind == .strength ? "The weights you log set your working loads" : "Rides use effort\(hrOK ? " and heart-rate" : "") targets until an FTP is known",
                          systemImage: f.kind == .strength ? "dumbbell.fill" : "bicycle", sport: f.kind == .strength ? .strength : .cycling, action: openPlan)
                    .accessibilityIdentifier("homeStartFirst")
            }
        }
    }
}
