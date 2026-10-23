import SwiftUI

@main
struct BikeComputerApp: App {
    @StateObject private var watchLink = WatchLink()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(watchLink)
                .preferredColorScheme(.dark)
                .onAppear { watchLink.activate() }
        }
    }
}
