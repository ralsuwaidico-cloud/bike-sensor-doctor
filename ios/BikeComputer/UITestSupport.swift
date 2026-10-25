import Foundation

/// Hooks for the launch smoke tests (BikeComputerUITests). Active ONLY in the iOS simulator: on a real device these
/// environment variables are ignored, so a shipped build can never be reset or seeded from outside.
enum UITestSupport {
    /// `BC_UITEST_RESET=1` wipes the store directory before the app reads it (fresh-install path).
    /// `BC_UITEST_SEED_JSON=<store.json contents>` writes that file first (upgrade-from-older-build path).
    static func prepareStoreDirectory(_ dir: URL) {
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
}
