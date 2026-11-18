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
