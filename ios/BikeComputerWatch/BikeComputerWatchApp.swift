import SwiftUI
import HealthKit
import WatchKit

/// Receives the iPhone's request to start a workout (HKHealthStore.startWatchApp on the phone) and starts the
/// cycling workout, so live heart rate flows without touching the watch.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        DispatchQueue.main.async { WorkoutManager.shared.start() }
    }
}

@main
struct BikeComputerWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var phone = PhoneLink()
    @StateObject private var workout = WorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(phone)
                .environmentObject(workout)
                .onAppear { phone.activate() }
        }
    }
}
