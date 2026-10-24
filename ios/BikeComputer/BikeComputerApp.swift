import SwiftUI

@main
struct BikeComputerApp: App {
    @StateObject private var store: Store
    @StateObject private var device: DeviceLink
    @StateObject private var watchLink: WatchLink
    @StateObject private var location: LocationService
    @StateObject private var recorder: RideRecorder

    init() {
        let s = Store()
        let d = DeviceLink()
        let w = WatchLink(); w.device = d
        let l = LocationService(device: d)
        let r = RideRecorder(); r.device = d; r.location = l; r.watch = w; r.phoneOnlyMode = s.settings.phoneOnlyMode
        _store = StateObject(wrappedValue: s)
        _device = StateObject(wrappedValue: d)
        _watchLink = StateObject(wrappedValue: w)
        _location = StateObject(wrappedValue: l)
        _recorder = StateObject(wrappedValue: r)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(device)
                .environmentObject(watchLink)
                .environmentObject(location)
                .environmentObject(recorder)
                .onAppear { watchLink.activate() }
        }
    }
}
