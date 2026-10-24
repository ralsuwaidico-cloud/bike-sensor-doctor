import SwiftUI

@main
struct BikeComputerApp: App {
    @StateObject private var device: DeviceLink
    @StateObject private var watchLink: WatchLink
    @StateObject private var location: LocationService

    init() {
        let d = DeviceLink()
        let w = WatchLink(); w.device = d
        _device = StateObject(wrappedValue: d)
        _watchLink = StateObject(wrappedValue: w)
        _location = StateObject(wrappedValue: LocationService(device: d))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(device)
                .environmentObject(watchLink)
                .environmentObject(location)
                .preferredColorScheme(.dark)
                .onAppear { watchLink.activate() }
        }
    }
}
