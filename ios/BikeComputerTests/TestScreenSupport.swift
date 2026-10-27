import Foundation
@testable import BikeComputer

/// Coach remediation M-01: coaching tests model riders who completed the health check with all answers "no"
/// (a new install has not answered it, which restricts vigorous prescriptions — tested in CoachRemediationTests).
extension RiderProfile {
    static func screened() -> RiderProfile {
        var p = RiderProfile(); var s = HealthScreen(); s.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = s
        return p
    }
}
