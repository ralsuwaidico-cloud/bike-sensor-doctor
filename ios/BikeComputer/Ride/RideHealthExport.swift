import Foundation
import HealthKit

/// Checkpoint F slice 3 — owner decision 7 Nov (RA-25): a ride recorded without an Apple Watch workout may be written
/// to Apple Health by the phone, at most once per ride, only when the rider turned "Export rides" on and iOS granted
/// workout write permission. The decision itself is `RideHealthWriter.decide` (pure, unit-tested); this class performs
/// the write and reports back the workout UUID so the Store can record it (`RideRecord.healthExportUUID`).
///
/// Rules: never for a demo ride · never a second time · never when the Watch recorded its own workout (the Watch is
/// the writer) · a denied permission is respected silently — the ride is already saved in Cyclift and nothing retries.
/// Only measured totals are written: start/end, distance when GPS or the board measured it. No energy is written
/// (work from power in kJ is not Apple's active-energy kcal) and nothing is estimated.
final class RideHealthExport {
    private let store = HKHealthStore()
    private(set) var lastMessage: String?

    /// Whether the phone may write a workout right now (permission, not the rider's setting).
    var workoutWriteAuthorized: Bool {
        HKHealthStore.isHealthDataAvailable() && store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    /// Writes one cycling workout for `ride`. `done` receives the new workout UUID, or nil when nothing was written
    /// (and `lastMessage` says why). Runs its completion on the main queue.
    func write(_ ride: RideRecord, done: @escaping (String?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { lastMessage = "Health is not available on this device"; done(nil); return }
        guard workoutWriteAuthorized else { lastMessage = "Health write permission not granted"; done(nil); return }
        guard !ride.demo, ride.healthExportUUID == nil, ride.recorder != .health, ride.durationS > 0 else { lastMessage = "nothing to write"; done(nil); return }
        let start = ride.start, end = ride.start.addingTimeInterval(TimeInterval(ride.durationS))
        let config = HKWorkoutConfiguration(); config.activityType = .cycling; config.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceCycling)
        let canWriteDistance = distanceType.map { store.authorizationStatus(for: $0) == .sharingAuthorized } ?? false
        builder.beginCollection(withStart: start) { [weak self] ok, err in
            guard ok else { DispatchQueue.main.async { self?.lastMessage = err?.localizedDescription ?? "could not start the workout"; done(nil) }; return }
            let finish: () -> Void = {
                builder.endCollection(withEnd: end) { ok, err in
                    guard ok else { DispatchQueue.main.async { self?.lastMessage = err?.localizedDescription ?? "could not end the workout"; done(nil) }; return }
                    builder.finishWorkout { workout, err in
                        DispatchQueue.main.async {
                            if let w = workout { self?.lastMessage = "written to Apple Health"; done(w.uuid.uuidString) }
                            else { self?.lastMessage = err?.localizedDescription ?? "Health did not save the workout"; done(nil) }
                        }
                    }
                }
            }
            if canWriteDistance, let dt = distanceType, ride.distanceM > 0 {
                let q = HKQuantitySample(type: dt, quantity: HKQuantity(unit: .meter(), doubleValue: Double(ride.distanceM)), start: start, end: end)
                builder.add([q]) { _, _ in finish() }     // a refused distance sample still leaves a valid workout
            } else { finish() }
        }
    }
}
