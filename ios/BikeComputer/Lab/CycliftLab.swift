import SwiftUI
import CoreBluetooth

// CYCLIFT LAB — a separate prototype app (owner approval, 16 Nov 2026). Built from ios/project-lab.yml with the compile
// condition CYCLIFT_LAB. Everything Lab-specific is inside `#if CYCLIFT_LAB`, so the production app does not contain it.
//
// What keeps Lab apart from the athlete's real Cyclift:
//   • its own app identity (com.ralsuwaidico.cycliftlab) — iOS gives it its own files, preferences and keychain; no app
//     group, no iCloud, no shared keychain group, no Watch app, no account keys;
//   • no HealthKit entitlement — iOS refuses every Health read and write;
//   • no location permission text and no background modes — iOS never grants location;
//   • no Bluetooth: the three Bluetooth owners get the do-nothing stand-in below instead of a real Bluetooth manager;
//   • RideRecorder.start() refuses; the only athlete is the generated demo athlete, seeded when Lab has no record.
enum CycliftLab {
    #if CYCLIFT_LAB
    static let isLab = true
    #else
    static let isLab = false
    #endif
}

extension View {
    /// Lab: the permanent "demo data" label and the theme chooser. Production: the view, unchanged.
    #if CYCLIFT_LAB
    func cycliftLabChrome() -> some View { modifier(LabChrome()) }
    #else
    func cycliftLabChrome() -> some View { self }
    #endif
}

#if CYCLIFT_LAB
/// Stands in for CBCentralManager in Lab: never powered on, finds nothing, connects to nothing.
final class LabNoBluetooth {
    var state: CBManagerState { .unsupported }
    func stopScan() {}
    func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?) {}
    func retrievePeripherals(withIdentifiers: [UUID]) -> [CBPeripheral] { [] }
    func cancelPeripheralConnection(_ p: CBPeripheral) {}
    func connect(_ p: CBPeripheral, options: [String: Any]?) {}
}

enum LabTheme {
    /// Lab keeps the choice with the real preference store (its own key in Lab's own preferences).
    static let store = CyThemePreferenceStore()
    /// LAB_THEME (screenshot runs): a theme name, or "system". Otherwise the stored choice; Obsidian on first launch.
    static var launchPreference: CyThemePreference {
        if let raw = ProcessInfo.processInfo.environment["LAB_THEME"], let p = CyThemeState.preference(named: raw) { return p }
        return store.load(legacyAppearance: nil)
    }
}

struct LabChrome: ViewModifier {
    @ObservedObject private var theme = CyThemeState.shared
    @State private var restoreAsked = false
    private var label: String {
        return theme.preference.mode == .system ? "Theme: follows iOS" : "Theme: \(theme.preference.resolved(systemIsDark: false).title)"
    }
    func body(content: Content) -> some View {
        // The Lab mark is a slim row of its own ABOVE the app (Lab 3: as a safe-area inset it covered the navigation bar's
        // buttons and titles). Owner's iPhone review of build 4 (18 Nov 2026): the full-width yellow band dominated every
        // screen. It is now one compact yellow tag on the app's own background — still on every screen, still unmistakable —
        // and nothing about Lab's isolation depends on it. Its text does not grow past the largest standard size.
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("CYCLIFT LAB · DEMO DATA").font(.system(size: 10, weight: .heavy)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color(red: 1, green: 0.84, blue: 0.04)))
                Spacer(minLength: 4)
                // Lab 5, 6 and 8: choices in a pull-down menu here did not take effect reliably after the first change. The
                // six themes are chosen where the design puts them — Profile › App Preferences › Appearance — and this
                // row only names the theme shown. Restore is a plain button so it also works from the Welcome screen.
                Text(label).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(CyTheme.ink2)
                    .accessibilityIdentifier("labThemeName")
                Button { LabDemoData.restoreAtNextLaunch(); restoreAsked = true } label: {
                    Text(restoreAsked ? "Reopen Lab" : "Restore demo").font(.system(size: 10, weight: .heavy)).lineLimit(1)
                        .foregroundStyle(CyTheme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .overlay(Capsule().stroke(CyTheme.ink2, lineWidth: 1))
                        .frame(minWidth: 44, minHeight: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(restoreAsked ? "Restore asked for. Close and reopen Cyclift Lab" : "Restore the demo athlete")
                .accessibilityIdentifier("labRestore")
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(CyTheme.canvas.ignoresSafeArea(edges: .top))
            content
        }
    }
}

/// The only athlete Lab ever shows: generated, never read from anywhere. Every figure in Lab is simulated.
enum LabDemoData {
    /// Lab's own notes, kept beside (not inside) the record folder so "Delete all data" does not remove them.
    private static func note(_ name: String, _ dir: URL) -> URL { dir.deletingLastPathComponent().appendingPathComponent("cyclift-lab-\(name)") }
    private static var recordDir: URL? = nil

    /// Writes the demo athlete once: on Lab's first launch, or when "Restore the demo athlete" was chosen. After
    /// "Delete all data" Lab stays empty (it starts at Welcome, like a new install) until the demo athlete is restored.
    static func seedIfMissing(_ dir: URL) {
        recordDir = dir
        let fm = FileManager.default
        let url = dir.appendingPathComponent("store.json"), seeded = note("seeded", dir), restore = note("restore", dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // LAB_FRESH_DEMO=1 (screen tests): start this launch from a fresh demo athlete, so each journey is independent of
        // what an earlier test left behind. Lab only; it touches Lab's own folder and nothing else.
        if ProcessInfo.processInfo.environment["LAB_FRESH_DEMO"] == "1" { try? Data().write(to: restore) }
        // LAB_NEW_ATHLETE=1 (screen tests): start this launch with no athlete at all, exactly as after "Delete all data",
        // so an onboarding screen can be checked without first deleting through the interface. Lab's own folder only.
        if ProcessInfo.processInfo.environment["LAB_NEW_ATHLETE"] == "1" {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) { for f in files { try? fm.removeItem(at: f) } }
            try? Data().write(to: seeded)
            return
        }
        if fm.fileExists(atPath: restore.path) {
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) { for f in files { try? fm.removeItem(at: f) } }
            try? fm.removeItem(at: restore); try? fm.removeItem(at: seeded)
        }
        guard !fm.fileExists(atPath: seeded.path), !fm.fileExists(atPath: url.path) else { return }
        try? Data(demoStore().utf8).write(to: url)
        try? Data().write(to: seeded)
    }
    /// Asks for the demo athlete to be written again at the next launch. Only ever touches Lab's own folder.
    static func restoreAtNextLaunch() { if let d = recordDir { try? Data().write(to: note("restore", d)) } }

    static func demoStore() -> String {       // same demo athlete as the screenshot tests (LayoutAudit.demoStore)
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        func d(_ day: Date, _ h: Double) -> String { iso.string(from: day.addingTimeInterval(h * 3600)) }
        var plan: [[String: Any]] = []
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: monday)!
            var kind = ["endurance", "rest", "tempo", "rest", "endurance", "long", "rest"][i]
            if cal.isDate(day, inSameDayAs: today) || cal.isDate(day, inSameDayAs: tomorrow) { kind = "strength" }
            let mins = kind == "rest" ? 0 : kind == "long" ? 120 : kind == "strength" ? 40 : 60
            var w: [String: Any] = ["id": UUID().uuidString, "date": d(day, 7), "kind": kind, "minutes": mins, "done": false, "skipped": false, "note": "", "edited": false, "sequence": 0]
            if kind == "strength" { w["strengthFocus"] = "fullBody" }
            if cal.isDate(day, inSameDayAs: tomorrow) { w["done"] = true }       // the reported bug: "completed" tomorrow
            plan.append(w)
        }
        let tomorrowId = plan.first { ($0["done"] as? Bool) == true }?["id"] as? String ?? ""
        var rides: [[String: Any]] = []
        for k in 0..<16 {
            let m = cal.date(byAdding: .day, value: -7 * (k + 1), to: monday)!
            let pattern: [[Int]] = [[50, 75], [45, 60, 110], [60, 90], [40, 70, 95]]
            let lens: [Int] = pattern[k % 4]
            for j in 0..<lens.count {
                let len = lens[j]
                let start = cal.date(byAdding: .day, value: j * 2 + 1, to: m)!
                rides.append(["id": UUID().uuidString, "start": d(start, 6.5), "durationS": len * 60, "distanceM": len * 470, "avgHR": 136, "maxHR": 160,
                              "zoneSeconds": [len * 6, len * 42, len * 12, 0, 0, 0, 0], "recorder": "phone", "sources": ["Demo data"], "demo": false, "samples": [] as [Any]])
            }
        }
        // this week: one recorded ride (Monday) and one Apple Health ride, so "Done this week" ≠ "Planned this week"
        rides.append(["id": UUID().uuidString, "start": d(monday, 6.5), "durationS": 3780, "distanceM": 31_000, "avgHR": 138, "maxHR": 162,
                      "zoneSeconds": [300, 3000, 480, 0, 0, 0, 0], "recorder": "phone", "sources": ["Demo data"], "demo": false, "samples": [] as [Any]])
        rides.append(["id": UUID().uuidString, "start": d(monday, 18), "durationS": 1800, "distanceM": 12_000, "zoneSeconds": [0, 1800, 0, 0, 0, 0, 0],
                      "recorder": "phone", "sources": ["Demo data"], "demo": false, "samples": [] as [Any]])
        func set(_ reps: Int, _ kg: Double) -> [String: Any] { ["id": UUID().uuidString, "reps": reps, "weightKg": kg, "bodyweight": false, "unilateral": false, "done": true] }
        func entry(_ id: String, _ name: String, _ pat: String, _ reps: Int, _ kg: Double) -> [String: Any] {
            ["id": UUID().uuidString, "exerciseId": id, "name": name, "pattern": pat, "sets": [set(reps, kg), set(reps, kg), set(reps, kg)], "notes": ""]
        }
        var strength: [[String: Any]] = []
        for k in 1...16 {      /* RC2 audit: a realistic 16-week lifting history, like the riding one */
            for day in [1, 4] {
                let date = cal.date(byAdding: .day, value: -7 * k + day, to: monday)!
                strength.append(["id": UUID().uuidString, "date": d(date, 18), "minutes": 40 + k, "focus": "fullBody", "customName": "", "rpe": 7, "notes": "", "source": "manual",
                                 "exercises": [entry("ex-003", "Goblet squat", "squat", 10, 20 + Double(6 - k)), entry("ex-088", "Dumbbell row", "pull", 10, 16), entry("ex-059", "Dumbbell bench press", "push", 8, 18)]])
            }
        }
        // the 1-minute record saved from workout mode with no set ticked, linked to tomorrow's session
        strength.append(["id": UUID().uuidString, "date": d(today, 9), "minutes": 1, "focus": "fullBody", "customName": "", "notes": "", "source": "manual",
                         "workoutId": tomorrowId, "startedAt": d(today, 8.98), "finishedAt": d(today, 9)])
        let profile: [String: Any] = ["name": "Demo", "goal": "fitness", "hoursPerWeek": 5, "level": "intermediate", "weightKg": 75, "age": 40, "ftpW": 225, "ftpHow": "tested", "birthYear": 1986, "provenance": ["weight": ["source": "entered"], "ftp": ["source": "legacyUnverified"]],   /* S2-0: deliberate demo values, not the old sample defaults */
                                      "sports": ["roadCycling", "strength"], "version": 3, "updatedAt": "2026-10-25T20:00:00Z", "wheelMm": 2096, "cadenceLow": 85, "cadenceHigh": 95, "hrZoneMethod": "maxHR",
                                      "trainingMode": "hybrid", "priority": "balanced", "cyclingDaysPerWeek": 3, "liftDaysPerWeek": 3, "liftingHoursPerWeek": 1, "preferredDays": [0, 2, 4, 5],
                                      "hybridGoal": "balanced", "strengthSplit": "fullBody"]
        let settings: [String: Any] = ["units": "metric", "phoneOnlyMode": true, "hrPref": "strap", "keepScreenOn": true, "autoConnectBoard": false, "enabledConnections": [] as [Any], "appearance": "system",
                                       "backgroundNotice": true, "coachTalk": "normal", "coachEnabled": true, "appleHealthImportWorkouts": false]
        let file: [String: Any] = ["schema": 1, "profile": profile, "settings": settings, "plan": plan, "rides": rides, "tiles": ["power", "cadence", "hr", "speed", "time", "dist"],
                                   "onboarded": true, "guest": true, "createdAt": "2026-06-01T10:00:00Z", "boardSync": [] as [Any], "onboardingStage": 0, "templates": [] as [Any], "customExercises": [] as [Any],
                                   "appliedProposals": [] as [Any], "equipment": ["owned": ["dumbbell", "bench", "kettlebell"], "excluded": [] as [Any]], "ignoredInsights": [] as [Any], "strength": strength]
        var out = file
        // LAB_DEMO_SUPERSETS=1 (screen tests): the demo athlete has said they prefer supersets, so the app's own session
        // builder pairs exercises and the preparation screen and recorder show a real superset. Nothing is drawn by hand.
        if ProcessInfo.processInfo.environment["LAB_DEMO_SUPERSETS"] == "1" { out["strengthPrefs"] = ["prefersSupersets": true] }
        // LAB_DEMO_PROPOSAL=1 (screen tests): the demo athlete also has one saved routine of their own, planned for
        // today, at the weight the demo history shows lifted twice in a row at a moderate effort. No suggestion is written
        // here: the app's own rules read these records and raise the increase themselves, and it waits for approval like
        // any other. (Earlier in the day than the Coach-built session: the rules look at the NEXT session of an exercise.)
        if ProcessInfo.processInfo.environment["LAB_DEMO_PROPOSAL"] == "1" {
            func open(_ reps: Int, _ kg: Double) -> [String: Any] { ["id": UUID().uuidString, "reps": reps, "weightKg": kg, "bodyweight": false, "unilateral": false, "done": false] }
            let squat: [String: Any] = ["id": UUID().uuidString, "exerciseId": "ex-003", "name": "Goblet squat", "pattern": "squat", "sets": [open(10, 25), open(10, 25), open(10, 25)], "notes": ""]
            let routineId = UUID().uuidString
            out["templates"] = [["id": routineId, "name": "Demo routine", "focus": "fullBody", "entries": [squat], "updatedAt": "2026-06-01T10:00:00Z"] as [String: Any]]
            plan.append(["id": UUID().uuidString, "date": d(today, 6), "kind": "strength", "minutes": 30, "done": false, "skipped": false, "note": "", "edited": false, "sequence": 0,
                         "strengthFocus": "fullBody", "templateId": routineId])
            out["plan"] = plan
        }
        let data = try! JSONSerialization.data(withJSONObject: out)
        return String(data: data, encoding: .utf8)!
    }
}
#endif
