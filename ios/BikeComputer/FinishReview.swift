import Foundation

// Training Hub v1.4 — what the Finish, Saved and Review pages say (sheets 06e, 06f, 06a). Pure values: nothing here
// saves, marks or changes anything. Every figure is counted from the session as it was recorded.

/// The Finish page's facts about the session in progress.
struct FinishSummary: Equatable {
    enum State: Equatable { case complete, partial, nothing }
    var title: String
    var state: State
    var done: Int
    var total: Int
    var skipped: Int
    var minutes: Int
    /// "Pallof press · 2 sets" — the exercises with sets that were not done, in session order.
    var notDone: String
    /// The session belongs to a planned session (only then is anything said about the plan).
    var planned: Bool

    var statusLine: String {
        switch state {
        case .complete: return "Complete"
        case .partial: return "Partial · \(done) of \(total) sets"
        case .nothing: return ""
        }
    }
    var timeText: String { minutes < 1 ? "Under 1 min" : "\(minutes) min" }
    var setsText: String { "\(done) of \(total)" }
    var skippedText: String { "\(skipped) set\(skipped == 1 ? "" : "s")" }
    /// Before saving (sheet 06e). "As partial" describes this session at this moment: the plan itself keeps "done" and
    /// has no separate partial marker, so later screens do not repeat it.
    var planBefore: String {
        switch state {
        case .nothing: return "Not marked done"
        case .complete: return "Will be marked done"
        case .partial: return "Will be marked done as partial"
        }
    }
    /// "Full body · 9 of 11 sets" under "Saved".
    var savedLine: String { "\(title) · \(done) of \(total) sets" }

    static func make(_ s: StrengthSession, title: String, now: Date = Date()) -> FinishSummary {
        let es = s.exercises ?? []
        let done = es.reduce(0) { $0 + $1.doneSets.count }, total = es.reduce(0) { $0 + $1.sets.count }
        let skipped = es.reduce(0) { $0 + $1.sets.filter { $0.isSkipped }.count }
        let open: [String] = es.compactMap { e in
            let n = e.sets.filter { !$0.done }.count
            return n > 0 ? "\(e.name) · \(n) set\(n == 1 ? "" : "s")" : nil
        }
        var notDone = open.prefix(2).joined(separator: ", ")
        if open.count > 2 { notDone += " +\(open.count - 2) more" }
        let state: State = done == 0 && total > 0 ? .nothing : (done == total ? .complete : .partial)
        return FinishSummary(title: title, state: state, done: done, total: total, skipped: skipped,
                             minutes: max(0, (s.elapsedSeconds(now: now) + 30) / 60), notDone: notDone, planned: s.workoutId != nil)
    }
}

/// The word under a review value (sheet 06a shows "7 Demanding" and "8 Hard"). CANDIDATE wording: only those two words
/// are on the approved sheet; the rest of each scale is provisional until reviewed. The words describe the number the
/// athlete chose and are not stored.
enum ReviewScale: String, CaseIterable {
    case intensity, performance, effort
    var title: String { rawValue.capitalized }
    func word(_ v: Int?) -> String {
        guard let v else { return "Not answered" }
        let i = min(4, max(0, (min(10, max(1, v)) - 1) / 2))
        switch self {
        case .intensity: return ["Very light", "Light", "Moderate", "Demanding", "Maximal"][i]
        case .performance: return ["Far below", "Below usual", "As usual", "Good", "Excellent"][i]
        case .effort: return ["Very easy", "Easy", "Moderate", "Hard", v >= 10 ? "Maximal" : "Very hard"][i]
        }
    }
}

/// "Anything your Coach should know?" — the three written choices beside Pain. Each is stored under its own name in the
/// review (SessionReview.fatigue / .equipment / .note), exactly as written. They are words for the athlete and the
/// Coach page to show; nothing calculates with them. Nothing written = nothing stored.
struct ReviewNotes: Equatable {
    var fatigue = ""
    var equipment = ""
    var note = ""
    static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { Self.clean(fatigue).isEmpty && Self.clean(equipment).isEmpty && Self.clean(note).isEmpty }
}

/// What the read-only check after a save found (sheets 06e X4 / 06f X5, X7). "Saved" is shown only for `.confirmed`.
enum SaveCheck: Equatable {
    /// The workout is in the app's history AND in the file on this phone.
    case confirmed
    /// The app's history does not hold it.
    case notInHistory
    /// The file could be read and does not hold it.
    case notOnDisk
    /// The file could not be read just now (for example while the iPhone is locking).
    case unreadable
}

extension Store {
    /// Reads the stored file back and looks for the workout. READ-ONLY: it writes nothing and changes nothing, so
    /// checking again can never create a second record.
    func strengthSaveCheck(_ id: UUID) -> SaveCheck {
        guard strength.contains(where: { $0.id == id }) else { return .notInHistory }
        if UITestSupport.takeUnconfirmedSaveCheck() { return .notOnDisk }
        struct Probe: Decodable { struct Item: Decodable { let id: UUID }; let strength: [Item]? }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("store.json")),
              let p = try? JSONDecoder().decode(Probe.self, from: data) else { return .unreadable }
        return (p.strength ?? []).contains { $0.id == id } ? .confirmed : .notOnDisk
    }

    /// Onboarding › Athletic Blueprint: is the approved result really in the file? Read back, never assumed.
    func onboardingSaveCheck() -> SaveCheck {
        guard onboarded else { return .notInHistory }
        if UITestSupport.takeUnconfirmedSaveCheck() { return .notOnDisk }
        struct Probe: Decodable { let onboarded: Bool? }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("store.json")),
              let p = try? JSONDecoder().decode(Probe.self, from: data) else { return .unreadable }
        return p.onboarded == true ? .confirmed : .notOnDisk
    }
}
