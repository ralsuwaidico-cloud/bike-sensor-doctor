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
    static let key = "lab.theme"
    static var chosen: CyThemeID {
        let raw = ProcessInfo.processInfo.environment["LAB_THEME"] ?? UserDefaults.standard.string(forKey: key) ?? ""
        return CyThemeID(rawValue: raw) ?? .newAthleteDefault
    }
}

struct LabChrome: ViewModifier {
    @ObservedObject private var theme = CyThemeState.shared
    func body(content: Content) -> some View {
        let shown = theme.active ?? .newAthleteDefault
        return content
            // a new identity per theme redraws every screen with the new tokens at once (the page returns to Home)
            .id(shown)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 8) {
                    Text("CYCLIFT LAB · DEMO DATA").font(.caption2.weight(.heavy)).tracking(0.6)
                    Spacer(minLength: 4)
                    Menu {
                        ForEach(CyThemeID.allCases, id: \.self) { t in
                            Button { UserDefaults.standard.set(t.rawValue, forKey: LabTheme.key); theme.show(t) } label: {
                                if t == shown { Label(t.title, systemImage: "checkmark") } else { Text(t.title) }
                            }
                        }
                    } label: {
                        Text("Theme: \(shown.title)").font(.caption2.weight(.bold)).lineLimit(1).padding(.vertical, 6)
                    }
                    .accessibilityIdentifier("labThemeMenu")
                }
                .padding(.horizontal, 12)
                .foregroundStyle(Color.black)
                .background(Color(red: 1, green: 0.84, blue: 0.04))
                .accessibilityIdentifier("labBanner")
            }
            .preferredColorScheme(shown.isDark ? .dark : .light)
    }
}

/// The only athlete Lab ever shows: generated, never read from anywhere. Every figure in Lab is simulated.
enum LabDemoData {
    /// Writes the demo athlete when Lab has no record yet. Never touches an existing file.
    static func seedIfMissing(_ dir: URL) {
        let url = dir.appendingPathComponent("store.json")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(demoStore().utf8).write(to: url)
    }

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
        let data = try! JSONSerialization.data(withJSONObject: file)
        return String(data: data, encoding: .utf8)!
    }
}
#endif
