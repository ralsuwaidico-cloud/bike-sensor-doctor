import Foundation

// R-020 (master order §6.3): today's planned ride as Link 1.3 step messages. Targets are computed HERE from the phone's
// FTP state (ios/OWNERSHIP.md: FTP has one owner); an unknown FTP sends NO watt bands and an unverified one is already
// 5 % lower (profile.targetFTP, ENG-E1), so the board can never show a target the phone would not. Pure; DeviceLink sends the result only when the board reports cap 0x10000.
enum RideStepsSync {
    struct Bundle: Equatable { var header: BCLink.StepsHeader; var steps: [BCLink.StepMessage]; var version: UInt32 }

    static func role(_ r: RideStep.Role) -> Int { switch r { case .warmUp: return 0; case .steady: return 1; case .work: return 2; case .recover: return 3; case .easy: return 4; case .coolDown: return 5; case .test: return 6 } }
    static func ftpHowCode(_ p: RiderProfile) -> Int { p.ftpKnown ? p.ftpHow.linkCode : 0 }

    /// nil when the workout is not a ride or has no steps. `version` must increase whenever the plan changes (the
    /// caller passes the workout's edit counter or a timestamp-derived value).
    static func bundle(for w: Workout, profile p: RiderProfile, version: UInt32) -> Bundle? {
        guard w.kind.isRide else { return nil }
        let steps = w.rideSteps.prefix(BCLink.maxSteps)
        guard !steps.isEmpty else { return nil }
        let ftp = p.targetFTP           // nil unless the FTP may be used for targets (ENG-E1)
        let zones = p.hrZones?.map(\.lo)
        let header = BCLink.StepsHeader(version: version, workoutId: String(w.id.uuidString.prefix(24)), title: w.displayTitle, stepCount: steps.count,
                                        ftpW: ftp ?? 0, ftpHow: ftpHowCode(p), hrZones: zones?.count == 5 ? zones : nil, replace: true)
        let msgs = steps.enumerated().map { i, s -> BCLink.StepMessage in
            let band = s.watts(ftp: ftp)
            return BCLink.StepMessage(version: version, index: i, name: s.name, seconds: s.minutes * 60, role: role(s.role), rpeLo: s.rpe.lowerBound, rpeHi: s.rpe.upperBound,
                                      hrZone: (s.hrZone != nil && zones?.count == 5) ? s.hrZone! : 0, powerLoW: band?.lowerBound ?? 0, powerHiW: band?.upperBound ?? 0)
        }
        return Bundle(header: header, steps: msgs, version: version)
    }

    /// The Link messages in send order: BEGIN, STEP…, END. nil when any message does not fit (never a partial send).
    static func messages(_ b: Bundle, seq: UInt16, tMs: UInt32) -> [Data]? {
        var out: [Data] = []; var s = seq
        guard let begin = BCLink.encodeStepsBegin(b.header, seq: s, tMs: tMs) else { return nil }
        out.append(begin); s &+= 1
        for st in b.steps { guard let d = BCLink.encodeStep(st, seq: s, tMs: tMs) else { return nil }; out.append(d); s &+= 1 }
        guard let end = BCLink.encodeStepsEnd(version: b.version, steps: b.steps, seq: s, tMs: tMs) else { return nil }
        out.append(end)
        return out
    }
}

extension Store {
    /// Today's planned ride as a step bundle for the board, versioned by the plan's edit state; nil when none is planned.
    func todayRideSteps(now: Date = Date()) -> RideStepsSync.Bundle? {
        guard let w = plan.first(where: { Calendar.current.isDate($0.date, inSameDayAs: now) && $0.kind.isRide && !$0.done }) else { return nil }
        let version = UInt32(truncatingIfNeeded: max(1, Int(w.date.timeIntervalSince1970) / 60 + (planVersions.count * 7919)))
        return RideStepsSync.bundle(for: w, profile: profile, version: version)
    }
}
