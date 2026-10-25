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

    init() {
        let s = Store()
        let d = DeviceLink()
        let w = WatchLink(); w.device = d
        let l = LocationService(device: d)
        let r = RideRecorder(); r.device = d; r.location = l; r.watch = w; r.phoneOnlyMode = s.settings.phoneOnlyMode
        d.autoConnect = s.settings.autoConnectBoard
        let ps = ProfileSync(store: s, device: d)
        d.onBoardRide = { [weak s] summary, boardId in s?.importBoardRide(summary, boardId: boardId) }
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
                .onAppear {
                    watchLink.activate()
                    // Apple Health import on launch, only while the rider keeps it on (dedupe makes it idempotent)
                    if store.settings.appleHealthImportWorkouts, store.onboarded, health.available {
                        let s = store
                        health.importWorkouts(days: 30, into: s) { _ in s.settings.lastHealthImport = Date() }
                    }
                }
        }
    }
}
