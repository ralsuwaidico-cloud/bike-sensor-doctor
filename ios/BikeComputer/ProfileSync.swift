import Foundation
import Combine

/// Keeps the phone and the BikeComputer on the same athlete profile (Link v1.2, cap PROFILE_SYNC) and pushes device
/// settings (cap SETTINGS). Ownership model:
///  - board alone (no phone): the board's own profile, version 0 ("device-only").
///  - phone alone: the Store's profile.
///  - connected: the PHONE is authoritative for the shared athlete settings — but only after the rider confirmed it on
///    this phone once per board. Before that the differences are shown and nothing is written.
/// Versions are monotonic and the board only applies a newer one; an acknowledgement closes each push; unanswered
/// pushes are retried three times. Ride history, pairings, calibration and Wi-Fi are never part of this.
final class ProfileSync: ObservableObject {
    enum State: Equatable {
        case noBoard, notSupported(String), waitingForBoard, needsConfirmation, pushing(UInt32), inSync, failed(String)
        var label: String {
            switch self {
            case .noBoard: return "no BikeComputer connected"
            case .notSupported(let fw): return "needs firmware 0.6.0 (board has \(fw))"
            case .waitingForBoard: return "reading the board's profile…"
            case .needsConfirmation: return "phone and board differ — confirm"
            case .pushing(let v): return "sending version \(v)…"
            case .inSync: return "in sync"
            case .failed(let r): return "failed: \(r)"
            }
        }
    }
    @Published private(set) var state: State = .noBoard
    @Published private(set) var differences: [ProfileDifference] = []
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var settingsState = "not read yet"
    @Published private(set) var settingsPending = false

    private weak var store: Store?
    private weak var device: DeviceLink?
    private var bag = Set<AnyCancellable>()
    private var retryTimer: Timer?
    private var attempts = 0
    private var pushedVersion: UInt32 = 0
    private var settingsTimer: Timer?
    private var settingsVersion: UInt32 = 0

    init(store: Store, device: DeviceLink) {
        self.store = store; self.device = device
        device.onBoardProfile = { [weak self] p in self?.boardProfileArrived(p) }
        device.onProfileAck = { [weak self] a in self?.ackArrived(a) }
        device.onSettingsReply = { [weak self] s in self?.settingsReplyArrived(s) }
        device.$state.receive(on: DispatchQueue.main).sink { [weak self] s in self?.linkStateChanged(s) }.store(in: &bag)
        // a rider-made change on the phone (version bump) is pushed automatically once this board is confirmed
        store.$profile.map { $0.version }.removeDuplicates().dropFirst().debounce(for: .seconds(1), scheduler: DispatchQueue.main).sink { [weak self] _ in self?.pushIfConfirmed() }.store(in: &bag)
        store.$settings.map { $0.units }.removeDuplicates().dropFirst().debounce(for: .seconds(1), scheduler: DispatchQueue.main).sink { [weak self] _ in
            guard let self, let st = self.store else { return }
            if st.profile.version > 0 { var p = st.profile; p.touch(); st.profile = p }   /* units travel inside the profile message */
        }.store(in: &bag)
    }

    var boardId: String? { device?.state == .ready ? device?.boardId : nil }
    var record: BoardSyncRecord? { guard let id = boardId, let s = store else { return nil }; return s.syncRecord(for: id) }

    private func linkStateChanged(_ s: DeviceLink.State) {
        guard let d = device else { return }
        if s != .ready { state = .noBoard; retryTimer?.invalidate(); return }
        guard let i = d.info else { return }
        if !i.hasProfileSync { state = .notSupported(i.fw); return }
        state = .waitingForBoard
    }

    private func boardProfileArrived(_ p: BCLink.ProfileMessage) {
        guard let s = store, let id = boardId else { return }
        var rec = s.syncRecord(for: id); rec.boardFirmware = device?.info?.fw
        differences = s.profile.differences(from: p, units: s.settings.units)
        if rec.confirmed {
            s.setSyncRecord(rec)
            if p.version >= s.profile.version, differences.isEmpty { rec.ackedVersion = p.version; s.setSyncRecord(rec); state = .inSync; lastSyncAt = Date() }
            else { push() }
            return
        }
        // first pairing with this board: the rider decides. Identical profiles need no question.
        if differences.isEmpty { rec.confirmed = true; s.setSyncRecord(rec); push() } else { s.setSyncRecord(rec); state = .needsConfirmation }
    }

    /// The rider agreed: the phone profile replaces the board's shared settings from now on (history etc. untouched).
    func confirmPhoneIsAuthoritative() {
        guard let s = store, let id = boardId else { return }
        var rec = s.syncRecord(for: id); rec.confirmed = true; s.setSyncRecord(rec)
        push()
    }
    /// The rider prefers the board's values: copy them into the phone profile (the phone stays authoritative afterwards).
    func adoptBoardProfile() {
        guard let s = store, let b = device?.boardProfile else { return }
        var p = s.profile
        if let n = b.name, !n.isEmpty { p.name = n }
        if let v = b.ftpW, v > 0 { p.ftpW = v; p.ftpHow = RiderProfile.FTPHow.from(linkCode: b.ftpHow ?? 1) }
        if let v = b.weightKgX10 { p.weightKg = Double(v) / 10 }
        if let v = b.birthYear { p.birthYear = v }
        if let v = b.maxHR { p.maxHR = v }
        if let v = b.restHR { p.restHR = v }
        if let v = b.hoursPerWeek, v > 0 { p.hoursPerWeek = v }
        if let v = b.level { p.level = RiderProfile.Level.from(linkCode: v) }
        if let v = b.goal { p.goal = RiderProfile.Goal.from(linkCode: v) }
        if let v = b.lthr { p.lthr = v }
        if let u = b.units { s.settings.units = u == 1 ? .imperial : .metric }
        s.profile = p          /* didSet bumps the version → pushIfConfirmed */
        confirmPhoneIsAuthoritative()
    }

    private func pushIfConfirmed() { guard let r = record, r.confirmed, device?.info?.hasProfileSync == true else { return }; if (store?.profile.version ?? 0) > r.ackedVersion { push() } }

    private func push() {
        guard let s = store, let d = device, d.state == .ready, d.info?.hasProfileSync == true else { return }
        var m = s.profile.linkMessage(units: s.settings.units)
        // the board refuses versions ≤ its stored one; if ours fell behind (another phone), jump above it once
        if let bv = d.boardProfile?.version, m.version <= bv { var p = s.profile; p.version = bv; p.touch(); s.profile = p; m = s.profile.linkMessage(units: s.settings.units) }
        pushedVersion = m.version; attempts += 1
        guard d.profileSet(m) else { state = .failed("could not write to the board"); return }
        state = .pushing(m.version)
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.attempts < 3 { self.push() } else { self.attempts = 0; self.state = .failed("no acknowledgement from the board") }
        }
    }

    private func ackArrived(_ a: BCLink.ProfileAck) {
        retryTimer?.invalidate(); attempts = 0
        guard let s = store, let id = boardId else { return }
        var rec = s.syncRecord(for: id)
        switch a.status {
        case 0: rec.ackedVersion = a.version; rec.ackedAt = Date(); s.setSyncRecord(rec); state = .inSync; lastSyncAt = Date(); differences = []
        case 1:   /* board has a newer version: never overwrite blindly — re-read and let the rider see the differences */
            state = .failed("the board holds a newer profile (v\(a.boardVersion))"); device?.profileGet()
        default: state = .failed(a.statusText)
        }
    }

    // MARK: device settings (cap SETTINGS) — one change at a time, each waits for the board's reply
    var supported: BCLink.SettingsMessage? { device?.boardSettings }
    func supports(tag: Int) -> Bool { device?.boardSettings?.supports(tag: tag) ?? false }

    /// Sends one changed setting. The caller passes a message with only the changed field(s) set.
    func apply(_ change: BCLink.SettingsMessage) {
        guard let d = device, d.state == .ready, d.info?.hasSettings == true else { settingsState = "needs firmware 0.6.0"; return }
        var m = change
        settingsVersion = max(settingsVersion, d.boardSettings?.version ?? 0) + 1
        m.version = settingsVersion
        settingsPending = true; settingsState = "sending…"
        guard d.settingsSet(m) else { settingsPending = false; settingsState = "could not write to the board"; return }
        settingsTimer?.invalidate()
        settingsTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.settingsPending = false; self?.settingsState = "no reply from the board" }
    }
    private func settingsReplyArrived(_ s: BCLink.SettingsMessage) {
        settingsTimer?.invalidate(); settingsPending = false
        settingsState = s.status == nil ? "read from the board" : (s.status == 0 ? "synced" : "failed: \(s.statusText)")
        if s.version > settingsVersion { settingsVersion = s.version }
    }
}
