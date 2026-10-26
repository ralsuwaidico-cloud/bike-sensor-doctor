import Foundation

// Pure decoders for the standard Bluetooth SIG sensor profiles used by direct BLE sensors (no CoreBluetooth here, so
// every byte rule is unit-tested in SourcesTests). References (Bluetooth SIG):
//  - Heart Rate Service 1.0, Heart Rate Measurement 0x2A37
//  - Cycling Power Service 1.1, Cycling Power Measurement 0x2A63
//  - Cycling Speed and Cadence Service 1.0, CSC Measurement 0x2A5B
// All multi-byte fields are little-endian. Nothing here invents a value: a malformed or implausible packet gives nil.

/// One "cumulative revolutions + last event time" pair as sent by CSC / Cycling Power sensors.
struct RevSample: Equatable {
    var revs: UInt32
    var eventTime: UInt16     // 1/1024 s (crank, CSC wheel) or 1/2048 s (Cycling Power wheel)
}

struct CyclingPowerMeasurement: Equatable {
    var powerW: Int
    var wheel: RevSample?      // event time base 1/2048 s
    var crank: RevSample?      // event time base 1/1024 s
}

struct CSCMeasurement: Equatable {
    var wheel: RevSample?      // event time base 1/1024 s
    var crank: RevSample?      // event time base 1/1024 s
}

enum BLEDecode {
    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }

    /// Heart Rate Measurement (0x2A37). Flags bit 0: value is UINT16 (else UINT8). Bits 1–2: sensor contact status —
    /// when contact is supported (bit 2) but not detected (bit 1 clear) the value is not a heart rate and is dropped.
    /// Energy expended (bit 3) and RR intervals (bit 4) follow the value and are ignored.
    static func heartRate(_ d: Data) -> Int? {
        let b = [UInt8](d)
        guard b.count >= 2 else { return nil }
        let flags = b[0]
        let bpm: Int
        if flags & 0x01 != 0 { guard b.count >= 3 else { return nil }; bpm = Int(u16(b, 1)) } else { bpm = Int(b[1]) }
        if flags & 0x04 != 0, flags & 0x02 == 0 { return nil }
        guard (25...250).contains(bpm) else { return nil }
        return bpm
    }

    /// Cycling Power Measurement (0x2A63): flags UINT16, instantaneous power SINT16 (W), then optional fields in order —
    /// bit 0 pedal power balance (1 byte), bit 2 accumulated torque (2), bit 4 wheel revolution data (UINT32 revs +
    /// UINT16 time, 1/2048 s), bit 5 crank revolution data (UINT16 revs + UINT16 time, 1/1024 s). Later fields ignored.
    static func cyclingPower(_ d: Data) -> CyclingPowerMeasurement? {
        let b = [UInt8](d)
        guard b.count >= 4 else { return nil }
        let flags = u16(b, 0)
        let raw = Int16(bitPattern: u16(b, 2))
        guard raw <= 3000 else { return nil }                    /* implausible spike */
        var m = CyclingPowerMeasurement(powerW: max(0, Int(raw)), wheel: nil, crank: nil)
        var i = 4
        if flags & 0x0001 != 0 { i += 1 }
        if flags & 0x0004 != 0 { i += 2 }
        if flags & 0x0010 != 0 {
            guard b.count >= i + 6 else { return m }
            m.wheel = RevSample(revs: u32(b, i), eventTime: u16(b, i + 4)); i += 6
        }
        if flags & 0x0020 != 0 {
            guard b.count >= i + 4 else { return m }
            m.crank = RevSample(revs: UInt32(u16(b, i)), eventTime: u16(b, i + 2)); i += 4
        }
        return m
    }

    /// CSC Measurement (0x2A5B): flags UINT8; bit 0 wheel revolution data (UINT32 revs + UINT16 time, 1/1024 s);
    /// bit 1 crank revolution data (UINT16 revs + UINT16 time, 1/1024 s).
    static func csc(_ d: Data) -> CSCMeasurement? {
        let b = [UInt8](d)
        guard b.count >= 1 else { return nil }
        let flags = b[0]
        var m = CSCMeasurement(wheel: nil, crank: nil)
        var i = 1
        if flags & 0x01 != 0 {
            guard b.count >= i + 6 else { return nil }
            m.wheel = RevSample(revs: u32(b, i), eventTime: u16(b, i + 4)); i += 6
        }
        if flags & 0x02 != 0 {
            guard b.count >= i + 4 else { return nil }
            m.crank = RevSample(revs: UInt32(u16(b, i)), eventTime: u16(b, i + 2)); i += 4
        }
        if m.wheel == nil && m.crank == nil { return nil }
        return m
    }
}

/// Revolutions per minute from successive cumulative samples (crank → cadence, wheel → speed). Handles the 16-bit event
/// time wrap (every 64 s at 1/1024 s) and the counter wrap (16-bit crank, 32-bit wheel). A repeated sample (same event
/// time) means "no new revolution"; after `timeout` seconds without a new event the rate is 0 — the sensor is connected
/// and nothing turns. Before the first event pair the rate is unknown (nil) for up to `timeout` seconds, then 0.
struct RevolutionRate: Equatable {
    let counterModulo: UInt64      // 1 << 16 for crank revolutions, 1 << 32 for wheel revolutions
    let ticksPerSecond: Double     // 1024, or 2048 for Cycling Power wheel data
    static let timeout: TimeInterval = 3
    /// A gap longer than this between two events is a restart after a stop, not a slow revolution.
    static let maxGap: Double = 4

    private(set) var last: RevSample?
    private(set) var lastEventAt: Date?
    private(set) var perMinute: Double?

    init(counterModulo: UInt64, ticksPerSecond: Double) { self.counterModulo = counterModulo; self.ticksPerSecond = ticksPerSecond }
    static func crank() -> RevolutionRate { RevolutionRate(counterModulo: 1 << 16, ticksPerSecond: 1024) }
    static func cscWheel() -> RevolutionRate { RevolutionRate(counterModulo: 1 << 32, ticksPerSecond: 1024) }
    static func powerWheel() -> RevolutionRate { RevolutionRate(counterModulo: 1 << 32, ticksPerSecond: 2048) }

    mutating func update(_ s: RevSample, at now: Date) {
        guard let p = last else { last = s; lastEventAt = now; return }
        let dRevs = (UInt64(s.revs) + counterModulo - UInt64(p.revs)) % counterModulo
        let dTicks = (Int(s.eventTime) + 65536 - Int(p.eventTime)) % 65536
        if dTicks == 0 {
            if dRevs != 0 { last = s }       /* counter moved without a new event time: inconsistent, re-baseline */
            return                           /* same event: nothing new */
        }
        last = s
        lastEventAt = now
        guard dRevs > 0 else { perMinute = 0; return }
        let dt = Double(dTicks) / ticksPerSecond
        if dt > RevolutionRate.maxGap { perMinute = 0; return }        /* first turn after a stop */
        let rpm = Double(dRevs) / dt * 60
        guard rpm <= 3000 else { return }                               /* implausible: keep the previous value */
        perMinute = rpm
    }

    /// Rate now, or nil while unknown. Zero once no new event arrived for `timeout` seconds.
    func rate(at now: Date) -> Double? {
        guard let t = lastEventAt else { return nil }
        if now.timeIntervalSince(t) >= RevolutionRate.timeout { return 0 }
        return perMinute
    }

    /// km/h for a wheel rate with the given circumference (mm).
    static func speedKmh(wheelRpm: Double, circumferenceMm: Int) -> Double { wheelRpm * Double(circumferenceMm) / 1000 * 60 / 1000 }
}
