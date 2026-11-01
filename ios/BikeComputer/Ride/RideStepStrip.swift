import SwiftUI

/// RC3: "What do I do right now?" — the current step of today's planned ride in big type (name, target, time left) and
/// the next step underneath. Targets come from `RideStep.targetText`: watts only with a known FTP (ENG-E1), heart-rate
/// zones only when a heart-rate source is live, effort (RPE) always (ENG-E3). The steps add up to the session (ENG-E5).
struct RideStepStrip: View {
    let steps: [RideStep]
    /// Ride time so far (0 before the start).
    let elapsedS: Int
    /// `RiderProfile.targetFTP`: nil when the FTP is unknown → no watts.
    let ftp: Int?
    /// The athlete's heart-rate zones when a heart-rate source is live; nil otherwise.
    let hrZones: [(lo: Int, hi: Int?)]?

    /// Index of the step at `t` seconds and the seconds left in it; past the end → the last step with 0 left.
    static func position(_ steps: [RideStep], at t: Int) -> (index: Int, left: Int)? {
        guard !steps.isEmpty else { return nil }
        var start = 0
        for (i, s) in steps.enumerated() {
            let end = start + s.minutes * 60
            if t < end { return (i, end - max(0, t)) }
            start = end
        }
        return (steps.count - 1, 0)
    }

    var body: some View {
        if let p = Self.position(steps, at: elapsedS) {
            let s = steps[p.index]
            let next: RideStep? = p.index + 1 < steps.count ? steps[p.index + 1] : nil
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.name).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(D7.fg).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 4)
                    Text(p.left.asDuration).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(D7.cyan).lineLimit(1)
                        .accessibilityLabel("\(p.left / 60) minutes \(p.left % 60) seconds left in this step")
                }
                Text(s.targetText(ftp: ftp, hrZones: hrZones)).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(D7.fg)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("rideStepTarget")
                HStack(spacing: 6) {
                    if let n = next { Text("Next: \(n.name) · \(n.minutes) min").foregroundStyle(D7.mut) } else { Text("Last step").foregroundStyle(D7.mut) }
                    Spacer(minLength: 4)
                    if hrZones == nil { Text(RideSteps.pairHRHint).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.6) }
                }
                .font(D7.mono)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(D7.panel, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("rideStepStrip")
        }
    }
}
