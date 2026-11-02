import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - S2-0 / owner §5: optional, permission-based Apple Health reads (weight, resting HR, HRV, sleep)
// The athlete turns each read on in Settings; the first time, iOS asks for that permission. Values are stored with
// `.appleHealth` provenance and the sample date, under the precedence rule in `HealthPrecedence`. Nothing is derived
// from them: no readiness score, no diagnosis, no training conclusion (ios/S20_DATA_INTEGRITY.md).

/// What a Health reader must provide — a protocol so the precedence and store logic are tested with injected samples.
protocol HealthMetricsProviding: AnyObject {
    var available: Bool { get }
    /// Asks iOS for read permission for these kinds (no-op when nothing is requested).
    func requestRead(_ kinds: [HealthSample.Kind], _ done: @escaping (Bool) -> Void)
    /// The newest sample per kind (sleep = last night's total in hours). Only kinds the athlete enabled are read.
    func latest(_ kinds: [HealthSample.Kind], _ done: @escaping ([HealthSample]) -> Void)
}

extension Store {
    /// Applies samples under the precedence rule; returns the kinds that changed the profile. Pure apart from the profile write.
    @discardableResult
    func applyHealthSamples(_ samples: [HealthSample], now: Date = Date()) -> [HealthSample.Kind] {
        var changed: [HealthSample.Kind] = []
        updateProfile { p in
            for s in samples where settings.healthReads.enabled(s.kind) { if p.apply(healthSample: s) { changed.append(s.kind) } }
        }
        settings.lastHealthRead = now
        return changed
    }
    /// Reads the enabled kinds from the provider and applies them. Safe to call on every launch / foreground.
    func refreshHealthReads(from provider: HealthMetricsProviding, _ done: (([HealthSample.Kind]) -> Void)? = nil) {
        let kinds = HealthSample.Kind.allCases.filter { settings.healthReads.enabled($0) }
        guard provider.available, !kinds.isEmpty else { done?([]); return }
        provider.latest(kinds) { [weak self] samples in
            guard let self else { done?([]); return }
            done?(self.applyHealthSamples(samples))
        }
    }
}

#if canImport(HealthKit)
/// HealthKit-backed reader. Read authorization is never disclosed by iOS, so "authorized" is inferred only from a
/// successful request; a denied permission simply yields no samples (the UI shows "No data from Apple Health").
final class HealthMetricsReader: HealthMetricsProviding {
    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private func objectType(_ k: HealthSample.Kind) -> HKObjectType? {
        switch k {
        case .weight: return HKObjectType.quantityType(forIdentifier: .bodyMass)
        case .restingHR: return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .hrv: return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .sleep: return HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        }
    }

    func requestRead(_ kinds: [HealthSample.Kind], _ done: @escaping (Bool) -> Void) {
        let types = Set(kinds.compactMap(objectType))
        guard available, !types.isEmpty else { done(false); return }
        store.requestAuthorization(toShare: [], read: types) { ok, _ in DispatchQueue.main.async { done(ok) } }
    }

    func latest(_ kinds: [HealthSample.Kind], _ done: @escaping ([HealthSample]) -> Void) {
        guard available else { done([]); return }
        let group = DispatchGroup()
        var out: [HealthSample] = []
        let lock = NSLock()
        for k in kinds {
            group.enter()
            switch k {
            case .sleep: lastNightSleepHours { h, date in if let h, let date { lock.lock(); out.append(HealthSample(kind: .sleep, value: h, date: date)); lock.unlock() }; group.leave() }
            default:
                guard let qt = objectType(k) as? HKQuantityType else { group.leave(); continue }
                let unit: HKUnit = k == .weight ? .gramUnit(with: .kilo) : k == .hrv ? .secondUnit(with: .milli) : HKUnit.count().unitDivided(by: .minute())
                let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
                let q = HKSampleQuery(sampleType: qt, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                    if let s = samples?.first as? HKQuantitySample {
                        lock.lock(); out.append(HealthSample(kind: k, value: s.quantity.doubleValue(for: unit), date: s.endDate)); lock.unlock()
                    }
                    group.leave()
                }
                store.execute(q)
            }
        }
        group.notify(queue: .main) { done(out) }
    }

    /// Total asleep time (all "asleep" categories) of the night ending today, in hours; nil when there is no sleep sample.
    private func lastNightSleepHours(_ done: @escaping (Double?, Date?) -> Void) {
        guard let st = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { done(nil, nil); return }
        let now = Date()
        let from = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
        let pred = HKQuery.predicateForSamples(withStart: from, end: now, options: .strictEndDate)
        let q = HKSampleQuery(sampleType: st, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var total: TimeInterval = 0; var end: Date? = nil
            for s in (samples as? [HKCategorySample]) ?? [] {
                let asleep: Bool
                if #available(iOS 16.0, *) { asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue).contains(s.value) }
                else { asleep = s.value == HKCategoryValueSleepAnalysis.asleep.rawValue }
                guard asleep else { continue }
                total += s.endDate.timeIntervalSince(s.startDate); end = max(end ?? s.endDate, s.endDate)
            }
            done(total > 0 ? total / 3600 : nil, end)
        }
        store.execute(q)
    }
}
#endif
