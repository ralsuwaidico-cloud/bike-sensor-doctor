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
    /// Checkpoint E: one sample per kind per day over the last `days` days (sleep = one per night), for the history log.
    func history(_ kinds: [HealthSample.Kind], days: Int, _ done: @escaping ([HealthSample]) -> Void)
}
extension HealthMetricsProviding {
    func history(_ kinds: [HealthSample.Kind], days: Int, _ done: @escaping ([HealthSample]) -> Void) { latest(kinds, done) }
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
        recordRecoveryHistory(samples, now: now)
        return changed
    }
    /// Checkpoint E: folds a history read into the per-day log without touching the profile's latest values.
    func recordRecoveryHistory(_ samples: [HealthSample], now: Date = Date()) {
        var log = recoveryLog
        if log.merge(samples.filter { settings.healthReads.enabled($0.kind) }, now: now) > 0 { recoveryLog = log }
    }
    /// Which reads are on — the Recovery page shows only these.
    var enabledHealthReads: [HealthSample.Kind] { HealthSample.Kind.allCases.filter { settings.healthReads.enabled($0) } }
    /// The Recovery page model: per-reading explanations and the one recommendation, from the log and today's plan.
    func recoveryReport(now: Date = Date()) -> (metrics: [RecoveryMetric], advice: RecoveryAdvice) {
        let ms = RecoveryAnalysis.metrics(log: recoveryLog, enabled: enabledHealthReads, now: now)
        let today = plan.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }
        let rest = today.isEmpty || today.allSatisfy { $0.kind == .rest || $0.kind == .recoveryDay }
        return (ms, RecoveryAnalysis.advice(ms, trainingAllowed: profile.readiness.trainingAllowed, todayIsRest: rest, now: now))
    }
    /// Reads the enabled kinds from the provider and applies them. Safe to call on every launch / foreground.
    func refreshHealthReads(from provider: HealthMetricsProviding, _ done: (([HealthSample.Kind]) -> Void)? = nil) {
        let kinds = HealthSample.Kind.allCases.filter { settings.healthReads.enabled($0) }
        guard provider.available, !kinds.isEmpty else { done?([]); return }
        provider.latest(kinds) { [weak self] samples in
            guard let self else { done?([]); return }
            let changed = self.applyHealthSamples(samples)
            provider.history(kinds, days: RecoveryAnalysis.baselineDays + 2) { [weak self] hist in self?.recordRecoveryHistory(hist); done?(changed) }
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
            case .sleep: lastNightSleepHours { r in if let r { lock.lock(); out.append(HealthSample(kind: .sleep, value: r.hours, date: r.end, source: r.sourceName)); lock.unlock() }; group.leave() }
            default:
                guard let qt = objectType(k) as? HKQuantityType else { group.leave(); continue }
                let unit: HKUnit = k == .weight ? .gramUnit(with: .kilo) : k == .hrv ? .secondUnit(with: .milli) : HKUnit.count().unitDivided(by: .minute())
                let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
                let q = HKSampleQuery(sampleType: qt, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                    if let s = samples?.first as? HKQuantitySample {
                        lock.lock(); out.append(HealthSample(kind: k, value: s.quantity.doubleValue(for: unit), date: s.endDate, source: s.sourceRevision.source.name)); lock.unlock()
                    }
                    group.leave()
                }
                store.execute(q)
            }
        }
        group.notify(queue: .main) { done(out) }
    }

    /// Checkpoint E: one reading per kind per day for the log. Quantity kinds keep the last sample of each day; sleep is
    /// aggregated per night with the same one-source rule as last night (APP-031), nights keyed by the day they end.
    func history(_ kinds: [HealthSample.Kind], days: Int, _ done: @escaping ([HealthSample]) -> Void) {
        guard available else { done([]); return }
        let now = Date(), cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -days, to: now) ?? now
        let pred = HKQuery.predicateForSamples(withStart: from, end: now, options: .strictEndDate)
        let group = DispatchGroup(); var out: [HealthSample] = []; let lock = NSLock()
        for k in kinds {
            group.enter()
            switch k {
            case .sleep:
                sleepIntervals(pred) { xs in
                    let byNight = Dictionary(grouping: xs) { RecoveryLog.dayKey($0.end, calendar: cal) }
                    for (_, list) in byNight { if let r = SleepAggregation.lastNight(list) { lock.lock(); out.append(HealthSample(kind: .sleep, value: r.hours, date: r.end, source: r.sourceName)); lock.unlock() } }
                    group.leave()
                }
            default:
                guard let qt = objectType(k) as? HKQuantityType else { group.leave(); continue }
                let unit: HKUnit = k == .weight ? .gramUnit(with: .kilo) : k == .hrv ? .secondUnit(with: .milli) : HKUnit.count().unitDivided(by: .minute())
                let q = HKSampleQuery(sampleType: qt, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, _ in
                    var perDay: [String: HealthSample] = [:]
                    for s in (samples as? [HKQuantitySample]) ?? [] {
                        perDay[RecoveryLog.dayKey(s.endDate, calendar: cal)] = HealthSample(kind: k, value: s.quantity.doubleValue(for: unit), date: s.endDate, source: s.sourceRevision.source.name)
                    }
                    lock.lock(); out.append(contentsOf: perDay.values); lock.unlock(); group.leave()
                }
                store.execute(q)
            }
        }
        group.notify(queue: .main) { done(out) }
    }

    /// Asleep intervals (any asleep stage) matching the predicate, each with its source bundle id and display name.
    private func sleepIntervals(_ pred: NSPredicate, _ done: @escaping ([SleepInterval]) -> Void) {
        guard let st = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { done([]); return }
        let q = HKSampleQuery(sampleType: st, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            var intervals: [SleepInterval] = []
            for s in (samples as? [HKCategorySample]) ?? [] {
                let asleep: Bool
                if #available(iOS 16.0, *) { asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue).contains(s.value) }
                else { asleep = s.value == HKCategoryValueSleepAnalysis.asleep.rawValue }
                guard asleep else { continue }
                intervals.append(SleepInterval(source: s.sourceRevision.source.bundleIdentifier, start: s.startDate, end: s.endDate, sourceName: s.sourceRevision.source.name))
            }
            done(intervals)
        }
        store.execute(q)
    }

    /// Last night's sleep in hours — from ONE source (APP-031). Apple Health often holds the same night from the Apple
    /// Watch and a sleep app; summing every sample doubled the night. The source with the most asleep time wins, its
    /// overlapping intervals are merged, and the result carries that source's name so the UI can show it.
    private func lastNightSleepHours(_ done: @escaping (SleepAggregation.Result?) -> Void) {
        let now = Date()
        let from = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
        sleepIntervals(HKQuery.predicateForSamples(withStart: from, end: now, options: .strictEndDate)) { done(SleepAggregation.lastNight($0)) }
    }
}
#endif

// MARK: - APP-031 pure sleep aggregation (unit-tested; no HealthKit)
struct SleepInterval: Equatable { var source: String; var start: Date; var end: Date; var sourceName: String? = nil }
enum SleepAggregation {
    struct Result: Equatable { var hours: Double; var end: Date; var source: String; var sourcesSeen: Int; var sourceName: String? = nil }
    /// One night from one source: pick the source with the most merged asleep time; merge overlapping / touching
    /// intervals inside it (a Watch that writes core + REM + deep as separate samples never double-counts a minute).
    static func lastNight(_ xs: [SleepInterval]) -> Result? {
        guard !xs.isEmpty else { return nil }
        var best: Result? = nil
        let bySource = Dictionary(grouping: xs, by: \.source)
        for (src, list) in bySource {
            let merged = merge(list)
            let total = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
            guard total > 0, let end = merged.map(\.end).max() else { continue }
            let r = Result(hours: total / 3600, end: end, source: src, sourcesSeen: bySource.count, sourceName: list.first?.sourceName)
            if best == nil || r.hours > best!.hours || (r.hours == best!.hours && r.source < best!.source) { best = r }
        }
        return best
    }
    static func merge(_ xs: [SleepInterval]) -> [SleepInterval] {
        let sorted = xs.sorted { $0.start < $1.start }; var out: [SleepInterval] = []
        for i in sorted { if var l = out.last, i.start <= l.end { l.end = max(l.end, i.end); out[out.count - 1] = l } else { out.append(i) } }
        return out
    }
}
