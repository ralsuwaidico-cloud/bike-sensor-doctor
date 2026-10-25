import Foundation
import HealthKit

/// Apple Health workout import (0.6.0). Reads cycling and strength workouts and hands them to the Store, which
/// deduplicates against phone / board rides and quick logs (start ±2 min, similar duration; Health UUID). iOS never
/// tells an app whether reading was allowed: an empty result is reported as "nothing found or not allowed", never as a
/// failure, and nothing is ever invented.
struct HealthImportResult: Equatable {
    var ridesAdded = 0
    var strengthAdded = 0
    var seen = 0
    var message: String {
        if seen == 0 { return "No eligible workouts found in Apple Health (or reading is not allowed — check iOS Settings › Health › Athletics)." }
        return "\(seen) workout\(seen == 1 ? "" : "s") read · \(ridesAdded) ride\(ridesAdded == 1 ? "" : "s") and \(strengthAdded) strength session\(strengthAdded == 1 ? "" : "s") added · the rest were already here."
    }
}

/// The mapping from a Health workout to our records, pure so it can be unit-tested without HealthKit.
enum HealthWorkoutMapper {
    enum Kind: Equatable { case ride, strength, ignored }
    static func kind(for activity: HKWorkoutActivityType) -> Kind {
        switch activity {
        case .cycling: return .ride
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        default: return .ignored
        }
    }
    /// Applies one workout to the store. Returns what was added.
    @discardableResult
    static func apply(kind: Kind, start: Date, durationS: Int, distanceM: Int?, kj: Int?, uuid: String, to store: Store) -> (ride: Bool, strength: Bool) {
        guard durationS >= 60 else { return (false, false) }
        switch kind {
        case .ride: return (store.importHealthRide(start: start, durationS: durationS, distanceM: distanceM, kj: kj, avgHR: nil, healthUUID: uuid), false)
        case .strength:
            let s = StrengthSession(date: start, minutes: durationS / 60, focus: .custom, customName: "Strength training (Apple Health)", rpe: nil, notes: "", source: "Apple Health", healthUUID: uuid)
            return (false, store.addStrength(s))
        case .ignored: return (false, false)
        }
    }
}

extension HealthAccess {
    /// Imports the last `days` days of eligible workouts. Completion on the main queue.
    func importWorkouts(days: Int = 90, into store: Store, completion: @escaping (HealthImportResult) -> Void) {
        guard available else { completion(HealthImportResult()); return }
        let hk = HKHealthStore()
        let from = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: from, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: 500, sortDescriptors: [sort]) { _, samples, _ in
            let workouts = (samples as? [HKWorkout]) ?? []
            DispatchQueue.main.async {
                var r = HealthImportResult()
                for w in workouts {
                    let k = HealthWorkoutMapper.kind(for: w.workoutActivityType)
                    guard k != .ignored else { continue }
                    r.seen += 1
                    let dist = w.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity()?.doubleValue(for: .meter()).rounded()
                    let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
                    let kj = kcal.map { Int(($0 * 4.184).rounded()) }
                    let added = HealthWorkoutMapper.apply(kind: k, start: w.startDate, durationS: Int(w.duration), distanceM: dist.map(Int.init), kj: kj, uuid: w.uuid.uuidString, to: store)
                    if added.ride { r.ridesAdded += 1 }
                    if added.strength { r.strengthAdded += 1 }
                }
                completion(r)
            }
        }
        hk.execute(q)
    }
}
