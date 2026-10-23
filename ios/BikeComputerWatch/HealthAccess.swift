import Foundation
import HealthKit

/// Asks for the HealthKit permissions the live heart-rate workout (Phase 3) will need.
/// In this build it only checks that HealthKit is available and that the permission sheet appears;
/// it does not start a workout or read any heart-rate samples.
final class HealthAccess: ObservableObject {
    @Published private(set) var status = "Not requested yet"

    private let store = HKHealthStore()

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func request() {
        guard available else {
            status = "Health data is not available on this watch"
            return
        }
        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [heartRate, HKObjectType.workoutType()]
        status = "Waiting for your answer…"
        store.requestAuthorization(toShare: share, read: read) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error {
                    self?.status = "Error: \(error.localizedDescription)"
                } else {
                    // HealthKit never tells an app whether read access was granted (privacy), only that the sheet completed.
                    self?.status = success ? "Permission sheet completed" : "Not completed"
                }
            }
        }
    }
}
