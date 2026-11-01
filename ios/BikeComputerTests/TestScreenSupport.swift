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

/// RC3 fixtures. Build 121 treated "equipment not set" as owning everything and copied the cycling level into lifting
/// experience; RC3 does neither (ENG-H1 / ENG-A1). Tests written for loaded progression state that equipment explicitly.
extension Store {
    func rc3FullGym(experience: StrengthPrefs.Experience? = nil) {
        equipment = EquipmentProfile(owned: Set(EquipmentProfile.allOptions))
        if strengthPrefs.experience == nil {
            strengthPrefs.experience = experience ?? { switch profile.level { case .beginner: return .beginner; case .intermediate: return .intermediate; case .advanced: return .advanced } }()
        }
    }
}
