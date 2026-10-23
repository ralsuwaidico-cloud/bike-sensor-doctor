import SwiftUI

@main
struct BikeComputerWatchApp: App {
    @StateObject private var phone = PhoneLink()
    @StateObject private var health = HealthAccess()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(phone)
                .environmentObject(health)
                .onAppear { phone.activate() }
        }
    }
}
