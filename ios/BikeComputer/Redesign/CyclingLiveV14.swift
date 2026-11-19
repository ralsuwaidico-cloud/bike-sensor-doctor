import SwiftUI
import CoreLocation
import UIKit

// Training Hub v1.4 — the cycling screen on the REAL ride recorder (redesigned main app only).
//
// This view owns nothing. It reads the existing objects — RideRecorder, SensorHub, LocationService, Store —
// builds the same `CyclingReadout` the Lab demonstration draws (rules: `CyclingSensorMap`, CyclingReadout.swift) and
// forwards taps to the existing recorder functions. It creates no recorder, no location manager and no Bluetooth
// object, and it writes to no Bluetooth characteristic.
//
// START POLICY (owner decision 16 Nov 2026, E1): unchanged and not bypassed. Start asks `recorder.startMode()` and, for
// a phone ride, `recorder.start()` — which checks the athlete's training status and location permission again itself.
// A hold, an unreadable status or missing location shows the reason and offers no Start.
//
// BIKECOMPUTER RIDES: starting, pausing, resuming and ending a ride the BikeComputer records means sending it a
// command. This file does not do that. The host may pass `sendBoard` to do it the way the existing Ride screen does;
// without it those controls are inactive here, the screen says so, and it offers the existing Ride screen instead.
//
// NOT REACHABLE IN CYCLIFT LAB: in the Lab build this view's body is a plain refusal; none of the code below exists.

/// The commands a BikeComputer-recorded ride needs. The host decides whether and how they are sent.
enum CyclingBoardAction { case start, pause, resume, stopRequest, stopConfirm }

struct CyclingLiveV14: View {
    /// Leaves the screen (nothing is recorded, or the ride goes on under the existing Ride screen).
    var onClose: () -> Void
    /// Closes this screen and shows the existing Ride screen.
    var onOpenRideScreen: () -> Void
    /// nil = this screen never commands the BikeComputer.
    var sendBoard: ((CyclingBoardAction) -> Void)? = nil

    #if CYCLIFT_LAB
    var body: some View {
        VStack(spacing: CySpace.l) {
            Text("Not available in Cyclift Lab").font(CyFont.title)
            Text("Cyclift Lab does not record rides.").font(CyFont.callout)
            Button("Close", action: onClose).accessibilityIdentifier("cyclingLiveRefusedClose")
        }
        .padding(CySpace.xl)
        .accessibilityIdentifier("cyclingLiveRefused")
    }
    #else
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var hub: SensorHub
    @State private var now = Date()
    @State private var finishing = false
    @State private var pausedSince: Date? = nil
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if finishing, recorder.state == .paused { finishPage } else { recorderPage }
        }
        .onReceive(timer) { now = $0 }
        .onChange(of: recorder.state) { _, s in
            pausedSince = s == .paused ? Date() : nil
            if s != .paused { finishing = false }
            if s == .idle { CyclingMinimise.shared.set(nil) }
        }
        .onDisappear { CyclingMinimise.shared.set(nil) }
        // the existing review: Save and Discard live there, with the existing save, Apple Health and check-in rules
        .sheet(item: $recorder.pendingResult) { r in RideResultSheet(ride: r) }
    }

    // MARK: the readout, from the existing objects

    private var ride: Workout? { if let w = store.today, w.kind.isRide { return w }; return nil }
    /// The same hub readings and rules as the existing Ride screen's details (RideLive).
    private var rideLive: RideLive {
        RideLive(power: hub.reading(.power), hr: hub.reading(.heartRate), cadence: hub.reading(.cadence), speed: hub.reading(.speed),
                 profile: store.profile, imperial: store.settings.units == .imperial, targetZone: min(5, max(1, ride?.kind.zone ?? 2)), missing: hub.missingReason)
    }
    private var gps: RideGPSState {
        RideGPSState.make(sharing: location.sharing, lastFixAgeS: location.last.map { now.timeIntervalSince($0.timestamp) }, authorized: location.authorized)
    }
    private var phase: CyclingPhase {
        switch recorder.state { case .idle: return .ready; case .running: return .recording; case .paused: return .paused; case .ended: return .ended }
    }
    private var boardOwnsLive: Bool { recorder.owner == .board && recorder.isActive && !recorder.boardLinkLost }
    /// This screen cannot pause or finish a ride the BikeComputer records unless the host gave it a way to ask.
    private var locked: Bool { boardOwnsLive && sendBoard == nil }

    /// The hub's sources that could give this metric, as plain states. A connected BikeComputer does not mean its
    /// power meter or strap is connected, so for those the board's own sensor state is used instead of the link's.
    private func link(_ kind: MetricKind) -> CyclingLink {
        var states: [CyclingSourceStatus] = []
        for s in hub.sources where s.isLive && s.metrics.contains(kind) {
            if s.id == SensorHub.bikeComputer.id {
                if store.settings.phoneOnlyMode { continue }
                if s.state == .connected, kind != .speed {
                    states.append(Self.boardSensor(hub.deviceState(kind == .heartRate ? "board.strap" : "board.meter")))
                    continue
                }
            }
            states.append(CyclingSourceStatus(state: s.state.rawValue, configured: s.configured))
        }
        return CyclingSensorMap.link(states)
    }
    private static func boardSensor(_ d: DeviceState?) -> CyclingSourceStatus {
        guard let d else { return CyclingSourceStatus(state: "notConfigured", configured: false) }
        switch d {
        case .notPaired: return CyclingSourceStatus(state: "notConfigured", configured: false)
        case .paired: return CyclingSourceStatus(state: "connecting", configured: true)
        case .connected, .receivingData, .stale: return CyclingSourceStatus(state: "connected", configured: true)
        case .problem: return CyclingSourceStatus(state: "disconnected", configured: true)
        }
    }
    private func truth(_ kind: MetricKind, _ m: RideMetric) -> SensorTruth {
        let last = (hub.candidates[kind] ?? [:]).values.max { $0.at < $1.at }
        let age = last.map { Int(now.timeIntervalSince($0.at).rounded()) }
        return CyclingSensorMap.truth(CyclingSensorInput(fresh: m.value, last: last?.intValue, lastAgeSeconds: age, link: link(kind)))
    }

    private var readout: CyclingReadout {
        let l = rideLive
        let counted = recorder.isActive || recorder.state == .ended
        let moving = counted ? CyclingSensorMap.movingSeconds(speedsCms: recorder.samples.map { $0.speedCms }) : nil
        let band: (Int, Int?)? = ride != nil && l.ftpKnown ? l.powerBandW : nil
        var r = CyclingReadout(title: ride?.displayTitle ?? "Free ride", phase: phase, elapsedSeconds: counted ? recorder.elapsedS : 0, movingSeconds: moving ?? 0,
                               power: truth(.power, l.power), heartRate: truth(.heartRate, l.hr), cadence: truth(.cadence, l.cadence),
                               speedKmh: l.speedKmh, distanceKm: Double(recorder.distanceM) / 1000,
                               targetLow: band?.0, targetHigh: band.flatMap { $0.1 }, laps: max(0, recorder.lapCount - 1))
        r.imperial = l.imperial
        r.movingKnown = moving != nil
        r.distanceKnown = counted
        r.powerAverageSeconds = nil                                   // the hub gives the latest reading, not a 3-second mean
        r.powerQuality = l.power.unverified ? .unverified : (l.power.reading?.quality == .estimated ? .estimated : .good)
        r.powerStored = recorder.owner != .phone                      // a phone-recorded ride stores no power or cadence
        r.speedEstimated = l.speed.usable && l.speed.reading?.quality == .estimated
        r.speedReason = CyclingSensorMap.speedReason(gps: Self.name(gps))
        if recorder.state == .paused, let p = pausedSince { r.pausedSeconds = max(0, Int(now.timeIntervalSince(p))) }
        r.sourceNames = CyclingSensorMap.sourceNames([l.power.usable ? l.power.reading?.sourceLabel : nil, l.hr.usable ? l.hr.reading?.sourceLabel : nil,
                                                      l.cadence.usable ? l.cadence.reading?.sourceLabel : nil, l.speed.usable ? l.speed.reading?.sourceLabel : nil,
                                                      recorder.owner == .phone && recorder.isActive && gps == .good ? SensorHub.phoneGPS.name : nil])
        r.recorderNotes = notes(l)
        return r
    }
    private static func name(_ g: RideGPSState) -> String { switch g { case .off: return "off"; case .searching: return "searching"; case .good: return "good"; case .lost: return "lost" } }
    private func notes(_ l: RideLive) -> [String] {
        guard recorder.isActive else { return [] }
        var out: [String] = []
        if recorder.externalDuringHold { out.append(RideRecorder.externalHoldNote) }                 // E1: said as soon as the phone sees the ride
        if recorder.owner == .board, recorder.boardLinkLost { out.append("BikeComputer link lost. It keeps recording; its values return here when the link does.") }
        if recorder.owner == .phone {
            var live: [String] = []
            if l.power.usable { live.append("power") }
            if l.cadence.usable { live.append("cadence") }
            if l.hr.usable, l.hr.reading?.source.method != .appleWatch { live.append("heart rate from this sensor") }
            if let n = CyclingSensorMap.notStoredNote(live) { out.append(n) }
            if recorder.gapSeconds > 0 { out.append("\(recorder.gapSeconds) s passed while the app was suspended. They are stored empty, not filled in.") }
        }
        return out
    }
    private var mapContent: CyclingMapContent {
        let pts: [CLLocationCoordinate2D] = recorder.samples.compactMap { s in
            if let la = s.lat, let lo = s.lon { return CLLocationCoordinate2D(latitude: la, longitude: lo) }
            return nil
        }
        return .route(points: pts, gps: gps)
    }

    // MARK: start — the existing policy, asked at the moment of the tap as well

    private var startControl: CyclingStartControl {
        // defence in depth, as on the existing Ride screen: the health check pauses training — no Start here either
        if !store.profile.readiness.trainingAllowed { return CyclingStartControl(message: "Training is paused by your health check, so a ride cannot be started.") }
        switch recorder.startMode() {
        case .blockedByHealthHold: return CyclingStartControl(message: "Training is paused by your health check, so a ride cannot be started.")
        case .blockedStatusUnavailable: return CyclingStartControl(message: "Cyclift could not read your training status, so a ride cannot be started here.")
        case .blockedByBoardRide: return CyclingStartControl(message: "The BikeComputer has a ride running — it is the recorder.")
        case .blockedNoGPSPermission:
            if location.denied {
                return CyclingStartControl(message: "Location is turned off for Cyclift, so this phone cannot record a GPS ride. Turn it on in Settings › Cyclift › Location.",
                                           buttonTitle: "Open Settings", buttonID: "cyclingOpenSettings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
            }
            return CyclingStartControl(message: "Cyclift needs your location to record a ride on this phone.", buttonTitle: "Allow location", buttonID: "cyclingAllowLocation") { location.requestPermission() }
        case .board:
            if let send = sendBoard {
                return CyclingStartControl(message: "The BikeComputer records this ride; the phone adds GPS.", buttonTitle: "Start on BikeComputer", buttonID: "cyclingStartBoard") {
                    if recorder.startMode() == .board { send(.start) }
                }
            }
            return CyclingStartControl(message: "The BikeComputer records this ride. Start it on the BikeComputer or from the Ride screen; this screen follows it.",
                                       buttonTitle: "Open the Ride screen", buttonID: "cyclingOpenRideScreen", action: onOpenRideScreen)
        case .phone:
            return CyclingStartControl(message: "This phone records time, GPS distance and Apple Watch heart rate.", buttonTitle: "Start ride", buttonID: "cyclingStart") {
                if recorder.startMode() == .phone { _ = recorder.start() }
            }
        }
    }

    // MARK: pages

    private var recorderPage: some View {
        CyclingRecorderV14(readout: readout, map: mapContent, start: startControl,
                           lockedNote: locked ? "The BikeComputer is the recorder of this ride. Pause and finish it on the BikeComputer, or close this screen and use the Ride screen." : nil,
                           onClose: locked ? onOpenRideScreen : onClose,
                           onLap: { recorder.lap() },
                           onPause: { if boardOwnsLive { sendBoard?(.pause) } else { recorder.pause() } },
                           onResume: { if boardOwnsLive { sendBoard?(.resume) } else { recorder.resume() } },
                           onFinish: { if boardOwnsLive { sendBoard?(.stopRequest) }; finishing = true })
    }
    private var finishPage: some View {
        let r = readout
        let summary = CyclingFinishSummary.make(elapsedSeconds: recorder.elapsedS, movingSeconds: r.movingKnown ? r.movingSeconds : nil,
                                                distanceKm: Double(recorder.distanceM) / 1000, imperial: r.imperial,
                                                power: recorder.samples.map { $0.w }, heartRate: recorder.samples.map { $0.hr })
        return CyclingFinishV14(title: r.title, stateLine: "Cycling · paused while you decide",
                                headline: "Ending the ride opens its review. Nothing is saved until you choose Save there.",
                                summary: summary, outcomeLabel: "Next", outcome: "Review, then Save or Discard",
                                primaryTitle: "End ride and review", primaryID: "cyclingEndReview",
                                onPrimary: { endRide() }, onBack: { finishing = false })
    }
    /// The existing three ways a ride ends (RideView's End): the phone's own ride, the BikeComputer's, or the phone's
    /// copy when the BikeComputer cannot be reached.
    private func endRide() {
        if recorder.owner == .board {
            if recorder.boardLinkLost { recorder.endWithoutBoard() } else { sendBoard?(.stopConfirm) }
        } else { recorder.end() }
        finishing = false
    }
    #endif
}
