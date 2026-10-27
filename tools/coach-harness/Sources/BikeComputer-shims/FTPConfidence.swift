import Foundation
// MARK: - FTP confidence (quality release)
enum FTPConfidence: String, Equatable {
    case verifiedTest, estimatedVerified, provisional, unverified
    var title: String {
        switch self {
        case .verifiedTest: return "Verified test"
        case .estimatedVerified: return "Estimated from verified power data"
        case .provisional: return "Provisional estimate"
        case .unverified: return "Unverified"
        }
    }
    var short: String {
        switch self { case .verifiedTest: return "verified test"; case .estimatedVerified: return "estimated · verified power"; case .provisional: return "provisional"; case .unverified: return "unverified" }
    }
    /// Only these drive confident (power-target) prescriptions.
    var isConfident: Bool { self == .verifiedTest || self == .estimatedVerified }
}

extension RiderProfile {
    var ftpConfidence: FTPConfidence {
        switch ftpHow {
        case .tested: return ftpVerifiedTest == true ? .verifiedTest : .unverified
        case .fromRides: return ftpPowerVerified == true ? .estimatedVerified : .unverified
        case .assumed: return .provisional
        case .entered: return .unverified
        }
    }
    /// Where the FTP came from, in one honest sentence.
    var ftpSourceText: String {
        switch (ftpHow, ftpConfidence) {
        case (.tested, .verifiedTest): return "From a completed FTP test ride with verified power (95 % of the 20-minute test effort)."
        case (.tested, _): return "Entered as a test result, but no test ride was recorded in Cyclift, so it is unverified."
        case (.fromRides, .estimatedVerified): return "Estimated as 95 % of the best 20-minute power of a ride with verified power. An estimate, not a test."
        case (.fromRides, _): return "Estimated as 95 % of the best 20-minute power of a recorded ride whose power was never verified. An estimate, not a test."
        case (.assumed, _): return "Starting assumption: \(String(format: "%.0f", weightKg)) kg × \(String(format: "%.2f", level.wkg)) W/kg for \(level.title.lowercased()) riders."
        case (.entered, _): return "Entered by you, without a recorded test."
        }
    }
    /// FTP used for power targets: the value itself when confident, else 5 % lower (conservative zones).
    var prescriptionFTP: Int { ftpConfidence.isConfident ? ftpW : Int((Double(ftpW) * 0.95).rounded()) }
    /// Power zones for prescriptions (targets): conservative when the FTP is not verified.
    var prescriptionZones: [(lo: Int, hi: Int?)] { var p = self; p.ftpW = prescriptionFTP; return p.powerZones }
    var ftpCaution: String? {
        ftpConfidence.isConfident ? nil : "FTP \(ftpConfidence.short): power targets are set 5 % lower and the ride coach does not claim zones from power. Ride by feel and heart rate; a verified FTP test replaces it."
    }
}
