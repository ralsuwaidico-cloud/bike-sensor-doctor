import Foundation
import Combine

/// App-side owner of the board diagnostic reports (ios/DIAG_TRANSFER.md): connects the pure `DiagTransfer` engine to
/// the BikeComputer link, drives its clock while it works, and publishes the saved reports for the UI. Firmware
/// without cap 0x400 never gets a request and the UI shows nothing for it.
final class DiagReportCenter: ObservableObject {
    @Published private(set) var reports: [DiagReportMeta] = []
    @Published private(set) var transferring: DiagTransfer.Progress?
    @Published private(set) var lastError: String?
    /// Saved during this app session (for "Report saved" on the BikeComputer page).
    @Published private(set) var savedThisSession: [DiagReportMeta] = []
    /// The connected board supports report transfer (INFO cap 0x400).
    @Published private(set) var boardSupports = false

    let store: DiagStore
    private(set) var engine: DiagTransfer?
    private weak var device: DeviceLink?
    private weak var recorder: RideRecorder?
    private var timer: Timer?
    /// Diagnostics event log (PipelineMonitor) — one line per saved report.
    var onLog: ((String) -> Void)?
    /// Link 1.3 DIAG_AUTO enabled by the board's HELLO_ACK (set by Link13Center): verified reports are ACKed with delete = 1.
    var ackWithDelete: () -> Bool = { false }

    init(store: DiagStore = DiagStore(root: DiagStore.defaultRoot())) {
        self.store = store
        reload()
    }

    func attach(device d: DeviceLink, recorder r: RideRecorder) {
        device = d; recorder = r
        d.onReady = { [weak self] in self?.linkReady() }
        d.onDiagMessage = { [weak self] m in
            guard let self, let e = self.engine else { return }
            e.receive(m, now: Date())
            self.publish(); self.ensureTimer()
        }
        d.onLinkDown = { [weak self] in self?.linkDown() }
    }

    // MARK: link
    /// Version compatibility (1.2.3): only a board whose INFO carries cap 0x400 DIAG_XFER (firmware 0.7.3+) is ever asked;
    /// older firmware never sees a DIAG_* byte. (A board with the cap and an older app simply keeps its reports.)
    static func transferAllowed(_ info: BCLink.Info?) -> Bool { info?.hasDiagXfer == true }
    /// Link 1.3: HELLO_ACK enabled DIAG_AUTO — pull now (the 1.2.3 start 3 s after ready already covers it when idle).
    func helloEnabledAutoTransfer() {
        guard let e = engine, device?.state == .ready, !e.isBusy else { return }
        e.start(now: Date()); ensureTimer()
    }
    private func linkReady() {
        guard let d = device, Self.transferAllowed(d.info) else { boardSupports = false; engine?.linkDown(); engine = nil; publish(); return }
        boardSupports = true
        let boardId = d.boardId
        if engine?.boardId != boardId { engine = makeEngine(boardId) }
        engine?.linkDown()
        // let the connect-time traffic (time, settings, profile) go first; a diag_ready on connect may start it sooner
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.device?.state == .ready, let e = self.engine, !e.isBusy else { return }
            e.start(now: Date()); self.ensureTimer()
        }
    }
    private func linkDown() {
        engine?.linkDown()
        stopTimer(); publish()
    }
    private func makeEngine(_ boardId: String) -> DiagTransfer {
        let e = DiagTransfer(boardId: boardId, store: store) { [weak self] d in self?.device?.sendDiag(d) ?? false }
        e.rideActive = { [weak self] in self?.recorder?.isActive ?? false }
        // the board records a ride (its LIVE says so, and it is fresh): it would answer BUSY, so the phone does not ask
        e.boardRecording = { [weak self] in guard let d = self?.device, d.liveIsFresh else { return false }; return d.live?.rideState == .running }
        // chunk size from the NEGOTIATED link (ATT MTU − 3), never from failures — docs/LINK_V1_2_SPEC.md 1.2.3
        e.linkPayload = { [weak self] in self?.device?.maxNotifyBytes }
        e.ackWithDelete = { [weak self] in self?.ackWithDelete() ?? false }
        e.onSaved = { [weak self] m in
            guard let self else { return }
            self.savedThisSession.append(m)
            self.onLog?("Board diagnostic report \(m.reportId) saved (\(m.kindTitle.lowercased()), \(m.sizeText), firmware \(m.firmware.isEmpty ? "?" : m.firmware))")
            self.reload()
        }
        e.onChange = { [weak self] in self?.publish() }
        return e
    }

    // MARK: clock (only while the engine works)
    private func ensureTimer() {
        guard timer == nil, engine?.isBusy == true else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let e = self.engine else { self?.stopTimer(); return }
            e.tick(now: Date())
            if !e.isBusy { self.stopTimer() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }

    private func publish() {
        let p = engine?.progress, err = engine?.lastError
        if transferring != p { transferring = p }
        if lastError != err { lastError = err }
    }

    // MARK: reports (UI)
    func reload() { reports = store.allReports() }
    func text(_ m: DiagReportMeta) -> String? { store.text(m) }
    func fileURL(_ m: DiagReportMeta) -> URL { store.textURL(m) }
    func delete(_ m: DiagReportMeta) { store.delete(m); savedThisSession.removeAll { $0.id == m.id }; reload() }
    func markSeen(_ m: DiagReportMeta) {
        guard var x = store.meta(m.boardId, m.reportId), !x.seen else { return }
        x.seen = true; store.save(x); reload()
    }
    /// The one Home banner: a crash report that arrived and has not been looked at yet.
    var unseenCrash: DiagReportMeta? { reports.first { $0.isCrash && !$0.seen } }
    func dismissCrashBanner() { for m in reports where m.isCrash && !m.seen { var x = m; x.seen = true; store.save(x) }; reload() }

    /// For "Export diagnostic report": list + crc only, never the report text, never the board address.
    func exportEntries() -> [DiagnosticReport.BoardReport] {
        reports.map { DiagnosticReport.BoardReport(reportId: $0.reportId, kind: $0.kindTitle, firmware: $0.firmware, createdAt: $0.created, receivedAt: $0.receivedAt,
                                                   sizeBytes: $0.size, crc32: $0.crcHex, summary: $0.summary, boardAcknowledged: $0.boardAcknowledged) }
    }
}

/// Upload of board reports to a server: NOT ACTIVE. A hook only, for a later version, behind both a release flag that
/// is off in this build (the consent toggle is hidden) and the owner's explicit consent, which defaults to off.
/// Nothing in this build calls a network API for reports; `upload` always returns false.
enum DiagUploadHook {
    static let consentKey = "cyclift.diagnostics.uploadConsent"
    static var consent: Bool {
        get { UserDefaults.standard.bool(forKey: consentKey) }          /* false unless the owner switched it on */
        set { UserDefaults.standard.set(newValue, forKey: consentKey) }
    }
    static func allowed(flag: Bool = ReleaseFlags.diagUploadEnabled, consent: Bool = DiagUploadHook.consent) -> Bool { flag && consent }
    /// Always false in this build: there is no upload destination.
    static func upload(_ m: DiagReportMeta) -> Bool {
        guard allowed() else { return false }
        return false
    }
}
