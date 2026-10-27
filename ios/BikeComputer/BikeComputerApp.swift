import SwiftUI

@main
struct BikeComputerApp: App {
    @StateObject private var store: Store
    @StateObject private var device: DeviceLink
    @StateObject private var watchLink: WatchLink
    @StateObject private var location: LocationService
    @StateObject private var recorder: RideRecorder
    @StateObject private var sync: ProfileSync
    @StateObject private var reach = Reachability()
    @StateObject private var health = HealthAccess()
    @StateObject private var account: AccountService
    @StateObject private var cloud: SyncEngine
    @StateObject private var hub: SensorHub
    @StateObject private var monitor: PipelineMonitor
    @StateObject private var diag: DiagReportCenter
    @StateObject private var link13: Link13Center

    init() {
        let s = Store()
        let d = DeviceLink()
        let w = WatchLink(); w.device = d
        let l = LocationService(device: d)
        let r = RideRecorder(); r.device = d; r.location = l; r.watch = w; r.phoneOnlyMode = s.settings.phoneOnlyMode
        d.autoConnect = s.settings.autoConnectBoard
        let ps = ProfileSync(store: s, device: d)
        // board ride summaries (SYNC_RIDE) reach the history through BoardSummaryIngest, wired by Link13Center below
        d.highestStoredRideId = { [weak s] boardId in s?.highestBoardRideId(for: boardId) ?? 0 }
        // Apple Watch: ride mirror out, wrist commands in — same one-owner rules as the phone buttons
        r.onTick = { [weak r, weak d, weak w, weak s] in
            guard let r, let d, let w, let s else { return }
            let live = d.state == .ready && d.liveIsFresh ? d.live : nil
            let watchHR = w.hrIsFresh ? w.hrBpm : nil
            let hr = s.settings.hrPref == .watch ? (watchHR ?? live?.hrBpm) : (live?.hrBpm ?? watchHR)
            var src: String? = nil
            if hr != nil {
                if s.settings.hrPref == .watch, watchHR != nil { src = "watch" }
                else if let l = live, l.hrBpm != nil { src = l.hrSource.label }
                else { src = "watch" }
            }
            let zone: Int? = live?.powerW.map { s.profile.zone(forWatts: $0) }
            w.sendRide(WatchMessage.makeRide(state: r.state.rawValue, owner: r.owner.rawValue, elapsed: r.elapsedS, dist: r.distanceM, power: live?.powerW, cad: live?.cadenceRpm, hr: hr, hrSrc: src, zone: zone, boardReady: live != nil && !s.settings.phoneOnlyMode))
        }
        w.onCommand = { [weak r, weak d] c in
            guard let r, let d else { return }
            switch c {
            case WatchMessage.cmdStart:
                guard !r.isActive else { return }
                switch r.startMode(locationAuthorized: true) { case .board: d.control(.start); case .phone: _ = r.start(); default: break }
            case WatchMessage.cmdPause: if r.owner == .board { d.control(.pause) } else { r.pause() }
            case WatchMessage.cmdResume: if r.owner == .board { d.control(.resume) } else { r.resume() }
            case WatchMessage.cmdEnd: if r.owner == .board { d.control(.stopRequest) }           /* the watch asks for confirmation first */
            case WatchMessage.cmdEndConfirm: if r.owner == .board { d.control(.stopConfirm) } else { r.end() }
            default: break
            }
        }
        _store = StateObject(wrappedValue: s)
        _device = StateObject(wrappedValue: d)
        _watchLink = StateObject(wrappedValue: w)
        _location = StateObject(wrappedValue: l)
        _recorder = StateObject(wrappedValue: r)
        _sync = StateObject(wrappedValue: ps)
        let h = SensorHub(); h.hrWatchFirst = { [weak s] in s?.settings.hrPref == .watch }
        h.attach(store: s)      /* direct Bluetooth sensors paired on this phone reconnect from launch (A3) */
        _hub = StateObject(wrappedValue: h)
        // automatic pipeline diagnostics + safe recovery (ios/PIPELINE_HEALTH.md); the watch's mirrored workout handler
        // is registered by WatchLink above, at every launch, as HealthKit requires
        let m = PipelineMonitor(); m.attach(device: d, watch: w, hub: h, recorder: r, store: s)
        _monitor = StateObject(wrappedValue: m)
        // BikeComputer diagnostic reports (Link 1.2.3, firmware 0.7.3+): pulled, verified and kept on this phone
        let dc = DiagReportCenter(); dc.attach(device: d, recorder: r)
        dc.onLog = { [weak m] t in m?.log("board", t) }
        m.diagCenter = dc
        _diag = StateObject(wrappedValue: dc)
        // Link 1.3 (BLE_CONTRACT.md v1): coach mirroring, offline ride import, storage status — only with a board that
        // advertises cap 0x0800 and confirms each feature in its HELLO_ACK; nothing changes with 0.7.3 boards
        let l13 = Link13Center(); l13.attach(device: d, store: s, recorder: r, diag: dc)
        l13.onLog = { [weak m] t in m?.log("board", t) }
        _link13 = StateObject(wrappedValue: l13)
        let acc = AccountService()
        _account = StateObject(wrappedValue: acc)
        _cloud = StateObject(wrappedValue: SyncEngine(store: s, account: acc))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(device)
                .environmentObject(watchLink)
                .environmentObject(location)
                .environmentObject(recorder)
                .environmentObject(sync)
                .environmentObject(reach)
                .environmentObject(health)
                .environmentObject(account)
                .environmentObject(cloud)
                .environmentObject(hub)
                .environmentObject(monitor)
                .environmentObject(diag)
                .environmentObject(link13)
                .onOpenURL { url in if ReleaseFlags.accountsEnabled { _ = account.handle(url: url) } }
                .sheet(isPresented: $account.recoveryPending) { SetNewPasswordSheet().environmentObject(account) }
                .onAppear {
                    watchLink.activate()
                    hub.health = health
                    // Apple Health import on launch, only while the rider keeps it on (dedupe makes it idempotent)
                    if store.settings.appleHealthImportWorkouts, store.onboarded, health.available {
                        let s = store
                        health.importWorkouts(days: 30, into: s) { _ in s.settings.lastHealthImport = Date() }
                    }
                }
        }
    }
}
