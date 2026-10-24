import Foundation
import CoreLocation
import Combine

/// Phone GPS for the cycling computer. Sends one fix per second to the board while enabled, with accuracy and timestamp.
/// The board integrates distance itself; this class never computes or sends a distance total.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var authorized = false
    @Published private(set) var status = "Not started"
    @Published private(set) var last: CLLocation?
    @Published private(set) var sent = 0
    @Published var sharing = false { didSet { sharing ? start() : stop() } }

    private let mgr = CLLocationManager()
    private weak var device: DeviceLink?

    init(device: DeviceLink) {
        self.device = device
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        mgr.activityType = .fitness
        mgr.distanceFilter = kCLDistanceFilterNone
        mgr.pausesLocationUpdatesAutomatically = false
    }

    func requestPermission() { mgr.requestWhenInUseAuthorization() }

    private func start() {
        if mgr.authorizationStatus == .notDetermined { mgr.requestWhenInUseAuthorization() }
        mgr.allowsBackgroundLocationUpdates = true     /* keeps GPS flowing with the screen locked (UIBackgroundModes: location) */
        mgr.showsBackgroundLocationIndicator = true
        mgr.startUpdatingLocation()
        status = "GPS on"
    }

    private func stop() { mgr.stopUpdatingLocation(); status = "GPS off" }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        authorized = m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways
        if !authorized, sharing { status = "Location permission denied" }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        last = l
        // a fix older than 2 s or without a horizontal accuracy is not a live position
        guard l.horizontalAccuracy >= 0, Date().timeIntervalSince(l.timestamp) < 2 else { status = "waiting for a fresh fix"; return }
        let fix = BCLink.GPSFix(
            latE7: Int32((l.coordinate.latitude * 1e7).rounded()),
            lonE7: Int32((l.coordinate.longitude * 1e7).rounded()),
            altDm: l.verticalAccuracy >= 0 ? Int32((l.altitude * 10).rounded()) : nil,
            haccDm: UInt16(min(65534, max(0, l.horizontalAccuracy * 10))),
            vaccDm: l.verticalAccuracy >= 0 ? UInt16(min(65534, l.verticalAccuracy * 10)) : 0xFFFF,
            speedCms: l.speed >= 0 ? UInt16(min(65534, l.speed * 100)) : nil,
            courseCdeg: l.course >= 0 ? UInt16(min(35999, l.course * 100)) : nil,
            fixEpochMs: UInt64(l.timestamp.timeIntervalSince1970 * 1000),
            source: .phoneGPS)
        device?.send(gps: fix)
        sent += 1
        status = String(format: "±%.0f m · %@", l.horizontalAccuracy, l.speed >= 0 ? String(format: "%.1f km/h", l.speed * 3.6) : "speed n/a")
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { status = "GPS error: \(error.localizedDescription)" }
}
