import Foundation

/// Hooks for the launch smoke tests (BikeComputerUITests). Active ONLY in the iOS simulator: on a real device these
/// environment variables are ignored, so a shipped build can never be reset or seeded from outside.
enum UITestSupport {
    /// `BC_UITEST_RESET=1` wipes the store directory before the app reads it (fresh-install path).
    /// `BC_UITEST_SEED_JSON=<store.json contents>` writes that file first (upgrade-from-older-build path).
    static func prepareStoreDirectory(_ dir: URL) {
        #if CYCLIFT_LAB
        LabDemoData.seedIfMissing(dir)      // Lab only: the generated demo athlete, when Lab has no record
        #endif
        #if targetEnvironment(simulator)
        let env = ProcessInfo.processInfo.environment
        guard env["BC_UITEST_RESET"] == "1" || env["BC_UITEST_SEED_JSON"] != nil else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let seed = env["BC_UITEST_SEED_JSON"] {
            try? Data(seed.utf8).write(to: dir.appendingPathComponent("store.json"))
        }
        #endif
    }

    /// `BC_UITEST_DEVICE_STATES="apple-health=connected;watch=receiving;bikecomputer=problem:Bluetooth is off"`
    /// SIMULATOR ONLY: lets the Profile › Devices page be SHOWN in chosen connection states without hardware. It
    /// changes nothing the app uses to record or connect — only what that one page is given to draw. nil on a device.
    static func deviceStatesForDisplay() -> [String: DeviceStatus]? {
        #if targetEnvironment(simulator)
        guard let raw = ProcessInfo.processInfo.environment["BC_UITEST_DEVICE_STATES"], !raw.isEmpty else { return nil }
        var out: [String: DeviceStatus] = [:]
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let word = kv[1].split(separator: ":", maxSplits: 1).map(String.init)
            let state: DeviceState
            switch word[0] {
            case "paired": state = .paired
            case "connected": state = .connected
            case "receiving": state = .receivingData(lastSampleAt: Date())
            case "stale": state = .stale(lastSampleAt: Date().addingTimeInterval(-120))
            case "problem": state = .problem(reason: word.count > 1 ? word[1] : "Connection lost")
            default: state = .notPaired
            }
            out[kv[0]] = DeviceStatus(id: kv[0], name: kv[0], state: state, lastSyncedAt: nil, provides: "", detail: "")
        }
        return out
        #else
        return nil
        #endif
    }

    // Training Hub v1.4 save states (sheets 06e X6, 06f X7): two switches so the "Not saved yet" and "Save not confirmed"
    // pages can be seen and their retries exercised. SIMULATOR ONLY, like everything in this file: on a real device both
    // always answer false. Neither touches the store or its file — they only make the screen take its failure path once.
    private static var failSavesLeft: Int = { number("BC_UITEST_SAVE_FAIL") }()
    private static var unconfirmedChecksLeft: Int = { number("BC_UITEST_SAVE_UNCONFIRMED") }()
    private static func number(_ key: String) -> Int {
        #if targetEnvironment(simulator)
        return Int(ProcessInfo.processInfo.environment[key] ?? "") ?? 0
        #else
        return 0
        #endif
    }
    /// true = the screen must treat this Save tap as failed, without calling the store (so nothing is written).
    static func takeFailedSave() -> Bool { guard failSavesLeft > 0 else { return false }; failSavesLeft -= 1; return true }
    /// true = the read-back check must answer "not confirmed" this time.
    static func takeUnconfirmedSaveCheck() -> Bool { guard unconfirmedChecksLeft > 0 else { return false }; unconfirmedChecksLeft -= 1; return true }
}
