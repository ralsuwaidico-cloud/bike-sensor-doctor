import Foundation

/// What Settings › BikeComputer › Storage shows, and the one rule for "safe cleanup" (BLE_CONTRACT.md §7). Pure, so every
/// case is unit-tested. Numbers come only from the board's STORAGE_STATUS (or LIVE storage_state); nothing is estimated.
enum BoardStorageModel {
    enum Health: Equatable { case good, degraded, failed, unknown
        var title: String { switch self { case .good: return "Good"; case .degraded: return "Degraded"; case .failed: return "Failed"; case .unknown: return "Not reported" } }
    }
    /// Health category: the board's `13 health` when sent, else derived from the failure state; the specific category
    /// (e.g. "Directory corrupted") is always the board's own `01 state`, never a generic "storage".
    static func health(_ s: BCLink.StorageStatus?) -> Health {
        guard let s else { return .unknown }
        switch s.healthRaw { case 0: return .good; case 1: return .degraded; case 2: return .failed; default: break }
        switch s.state {
        case .ok: return .good
        case .full, .reportsFull, .diagUnavailable: return .degraded
        case .fsUnavailable, .dirCorrupted, .writeFailed: return .failed
        case .notChecked, nil: return .unknown
        }
    }
    static func category(_ s: BCLink.StorageStatus?, liveState: Int?) -> String {
        if let s { return s.state?.title ?? "Unknown state \(s.stateRaw)" }
        if let l = liveState { return BCLink.StorageState(rawValue: UInt8(clamping: l))?.title ?? "Unknown state \(l)" }
        return "Not reported"
    }
    static func crashPartitionText(_ v: UInt8?) -> String {
        switch v { case 0: return "missing"; case 1: return "empty"; case 2: return "crash dump stored"; case 3: return "dump unreadable"; case nil: return "not reported"; default: return "state \(v!)" }
    }
    static func kb(_ v: UInt32?) -> String {
        guard let v else { return "—" }
        return v >= 1024 ? String(format: "%.1f MB", Double(v) / 1024) : "\(v) KB"
    }
    static func bytes(_ v: UInt32?) -> String {
        guard let v else { return "—" }
        return v < 1024 ? "\(v) B" : v < 1024 * 1024 ? String(format: "%.1f KB", Double(v) / 1024) : String(format: "%.1f MB", Double(v) / 1_048_576)
    }
    /// Fraction 0…1 of the filesystem in use; nil without both numbers.
    static func usedFraction(_ s: BCLink.StorageStatus?) -> Double? {
        guard let t = s?.fsTotalKB, let f = s?.fsFreeKB, t > 0, f <= t else { return nil }
        return Double(t - f) / Double(t)
    }

    /// The safe-cleanup decision. It asks the board for at most the three cleanable categories; the board itself can
    /// never delete unsynced rides, unsent reports, the crash dump before its report is ACKed, or NVS (contract §7). On
    /// top of that the app refuses while the filesystem is not OK (no repair over Bluetooth) or a ride records, and asks
    /// the rider to confirm with a list of what stays.
    struct Cleanup: Equatable {
        var allowed: Bool
        var what: BCLink.StorageCleanWhat
        /// Why the button is disabled (plain words), nil when allowed.
        var blockedReason: String?
        /// What the cleanup removes and what it never touches — the confirmation dialog shows both.
        var removes: [String]
        var keeps: [String]
    }
    static func cleanup(status s: BCLink.StorageStatus?, linkEnabled: Bool, boardRecording: Bool, unsentReports: Int, unsyncedRides: Int) -> Cleanup {
        let keeps = ["Rides not yet saved in Cyclift" + (unsyncedRides > 0 ? " (\(unsyncedRides) on the board)" : ""),
                     "Crash reports not yet received by this iPhone" + (unsentReports > 0 ? " (\(unsentReports))" : ""),
                     "The crash dump until its report is received",
                     "Settings, sensor pairings, phone pairing and the ride counter"]
        let removes = ["Diagnostic reports this iPhone already received and verified", "Samples of rides already saved in Cyclift (their summaries stay)", "Temporary copies and caches"]
        let what: BCLink.StorageCleanWhat = [.ackedReports, .syncedRideSamples, .caches]
        func no(_ why: String) -> Cleanup { Cleanup(allowed: false, what: [], blockedReason: why, removes: removes, keeps: keeps) }
        guard linkEnabled else { return no("Needs a BikeComputer with storage status (Link 1.3), connected.") }
        guard let s else { return no("Waiting for the BikeComputer's storage status.") }
        guard !boardRecording else { return no("The BikeComputer is recording a ride — clean up after the ride.") }
        switch s.state {
        case .ok, .full, .reportsFull:
            return Cleanup(allowed: true, what: what, blockedReason: nil, removes: removes, keeps: keeps)
        case .fsUnavailable, .dirCorrupted, .writeFailed, .diagUnavailable:
            return no("\(s.state!.title): cleanup is not possible and storage is never repaired over Bluetooth. Follow the owner-approved PC procedure (storage report §7).")
        case .notChecked, nil:
            return no("The BikeComputer has not checked its storage yet.")
        }
    }
}
