import SwiftUI

@main
struct BikeComputerWatchApp: App {
    @StateObject private var phone = PhoneLink()
    @StateObject private var workout = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(phone)
                .environmentObject(workout)
                .onAppear { phone.activate() }
        }
    }
}
