import XCTest
@testable import BikeComputer

/// The phone side of protocol v1 without Bluetooth: frames split across notifications are reassembled, a corrupted
/// frame is dropped and counted, every event is acknowledged cumulatively, duplicates after a reconnect are never
/// re-applied, and watch events change the Store under the one-owner rules.
final class CyWatchSessionTests: XCTestCase {
    private func eventFrame(seq: UInt32, kind: CyWatchWire.Event.Kind, workout: String = "W1", a: Int32 = 0, b: Int32 = 0, c: Int32 = 0, device: String = "cyw-1") -> [UInt8] {
        var w = CyWatchWire.Writer(); w.str(device); w.u32(seq); w.u32(1_794_130_900); w.u8(kind.rawValue); w.str(workout); w.i32(a); w.i32(b); w.i32(c); w.bool(true)
        return CyWatchWire.encode(.init(type: .event, seq: UInt16(seq), payload: w.b))
    }

    func testReassemblyDedupAndCumulativeAck() {
        var saved: [String: UInt32] = [:]
        let s = CyWatchSession(acked: [:], saveAcked: { saved = $0 })
        var got: [UInt32] = []
        s.onEvent = { got.append($0.seq) }
        let f1 = eventFrame(seq: 1, kind: .start), f2 = eventFrame(seq: 2, kind: .pause)
        // two frames arrive split across three notifications
        let all = f1 + f2
        s.receive(Array(all[0..<10])); XCTAssertEqual(got, [])
        s.receive(Array(all[10..<(f1.count + 3)])); XCTAssertEqual(got, [1])
        s.receive(Array(all[(f1.count + 3)...])); XCTAssertEqual(got, [1, 2])
        XCTAssertEqual(saved["cyw-1"], 2)
        let acks = s.takeOutbox()
        XCTAssertEqual(acks.count, 2)
        XCTAssertEqual(CyWatchWire.decode(acks[1])?.type, .ack); XCTAssertEqual(CyWatchWire.decode(acks[1])?.payload, CyWatchWire.encodeAck(2))
        // the watch resends 1 and 2 after a reconnect: nothing is re-applied, but the ack is repeated
        s.receive(f1); s.receive(f2)
        XCTAssertEqual(got, [1, 2]); XCTAssertEqual(s.takeOutbox().count, 2)
        // a corrupted frame is dropped and counted; the stream resynchronises on the next good frame
        var bad = eventFrame(seq: 3, kind: .resume); bad[12] ^= 0xFF
        s.receive(bad + eventFrame(seq: 4, kind: .lap))
        XCTAssertEqual(got, [1, 2, 4]); XCTAssertGreaterThan(s.dropped, 0)
        // a second device has its own sequence space
        s.receive(eventFrame(seq: 1, kind: .start, device: "cyw-2")); XCTAssertEqual(got, [1, 2, 4, 1]); XCTAssertEqual(saved["cyw-2"], 1)
        // persisted acks survive a new session
        let s2 = CyWatchSession(acked: saved); var got2 = 0; s2.onEvent = { _ in got2 += 1 }
        s2.receive(eventFrame(seq: 4, kind: .lap)); XCTAssertEqual(got2, 0, "an already-acknowledged event is not re-applied after relaunch")
        XCTAssertEqual(s2.takeOutbox().count, 1, "…but it is acknowledged again")
        // outbound frames carry increasing sequence numbers
        s2.send(.timeSync, CyWatchWire.TimeSync(unixS: 1, ms: 0, tzOffsetMin: 0).encode()); s2.send(.live, CyWatchWire.Live().encode())
        let out = s2.takeOutbox().compactMap(CyWatchWire.decode)
        XCTAssertEqual(out.map(\.seq), [out[0].seq, out[0].seq + 1])
    }

    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("cyw-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        var p = RiderProfile.screened(); p.trainingMode = .hybrid; s.profile = p
        return s
    }
    private func ev(_ kind: CyWatchWire.Event.Kind, _ workout: String, a: Int32 = 0, b: Int32 = 0, c: Int32 = 0, manual: Bool = true) -> CyWatchWire.Event {
        CyWatchWire.Event(deviceId: "cyw-1", seq: 1, watchUnixS: 0, kindRaw: kind.rawValue, workoutId: workout, a: a, b: b, c: c, manual: manual)
    }

    func testStrengthEventsLogSetsIntoThePhonesSession() {
        let s = store()
        var w = Workout(date: Date(), kind: .strength, minutes: 30)
        w.plannedEntries = [ExerciseEntry(exercise: Exercise(id: "goblet-squat", name: "Goblet squat", pattern: .squat), sets: [SetEntry(reps: 10, weightKg: 24), SetEntry(reps: 10, weightKg: 24)]),
                            ExerciseEntry(exercise: Exercise(id: "row", name: "Row", pattern: .pull), sets: [SetEntry(reps: 8, weightKg: 40)])]
        s.plan = [w]
        // a logged set with no session open starts the planned session, then marks set 1 of exercise 1 done with the watch's reps / weight
        let o = CyWatchEvents.apply(ev(.setLogged, w.id.uuidString, a: 0, b: 9, c: 260), store: s)
        XCTAssertNotNil(s.activeSession); XCTAssertTrue(o.note.contains("Set 1 of exercise 1"), o.note)
        let st = s.activeSession!.exercises![0].sets[0]
        XCTAssertTrue(st.done); XCTAssertEqual(st.reps, 9); XCTAssertEqual(st.weightKg, 26.0)
        XCTAssertFalse(s.activeSession!.exercises![0].sets[1].done, "only the logged set changes")
        // exercise 2 (a = 100 + set 0), bodyweight → weight untouched
        CyWatchEvents.apply(ev(.setLogged, w.id.uuidString, a: 100, b: 8, c: 0), store: s)
        XCTAssertTrue(s.activeSession!.exercises![1].sets[0].done); XCTAssertEqual(s.activeSession!.exercises![1].sets[0].weightKg, 40)
        // a set index beyond the plan appends a set rather than being lost
        CyWatchEvents.apply(ev(.setLogged, w.id.uuidString, a: 2, b: 7, c: 240), store: s)
        XCTAssertEqual(s.activeSession!.exercises![0].sets.count, 3)
        // end on the watch waits; save finishes the phone's session and marks the plan done
        XCTAssertNil(CyWatchEvents.apply(ev(.end, w.id.uuidString), store: s).ride)
        XCTAssertNotNil(s.activeSession)
        CyWatchEvents.apply(ev(.save, w.id.uuidString), store: s)
        XCTAssertNil(s.activeSession); XCTAssertEqual(s.strength.count, 1); XCTAssertEqual(s.strength[0].notes, "Logged on Cyclift Watch")
        XCTAssertEqual(s.strength[0].exercises?.flatMap(\.sets).count, 3, "only done sets are kept")
        XCTAssertTrue(s.plan[0].done || s.ledger.status(s.plan[0]).isCompleted)
        // a set for an unknown workout with nothing open is ignored, never invents a session
        XCTAssertNil(s.activeSession)
        let ig = CyWatchEvents.apply(ev(.setLogged, UUID().uuidString, a: 0, b: 5, c: 0), store: s)
        XCTAssertTrue(ig.note.contains("ignored"), ig.note); XCTAssertNil(s.activeSession)
    }

    func testRideEventsBecomeRecorderCommandsNotRecords() {
        let s = store()
        let w = Workout(date: Date(), kind: .endurance, minutes: 60); s.plan = [w]
        XCTAssertEqual(CyWatchEvents.apply(ev(.start, w.id.uuidString), store: s).ride, .start)
        XCTAssertEqual(CyWatchEvents.apply(ev(.pause, w.id.uuidString), store: s).ride, .pause)
        XCTAssertEqual(CyWatchEvents.apply(ev(.resume, w.id.uuidString), store: s).ride, .resume)
        XCTAssertEqual(CyWatchEvents.apply(ev(.lap, w.id.uuidString), store: s).ride, .lap)
        XCTAssertEqual(CyWatchEvents.apply(ev(.end, w.id.uuidString), store: s).ride, .end)
        XCTAssertEqual(s.rides.count, 0, "the watch never creates a ride record; the phone's recorder does")
        XCTAssertNil(s.activeSession)
        // discard with nothing open is harmless
        XCTAssertNil(CyWatchEvents.apply(ev(.discard, w.id.uuidString), store: s).ride)
    }

    func testPlanTodayAndCachedFramesAreHonest() {
        let s = store()
        XCTAssertEqual(CyWatchFrames.planToday(store: s)?.kind, 0, "nothing planned → kind 0, not an invented session")
        var w = Workout(date: Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: Date())!, kind: .strength, minutes: 40)
        var row = ExerciseEntry(exercise: Exercise(id: "row", name: "Row", pattern: .pull), sets: [SetEntry(reps: 8, weightKg: 40.5)], superset: "A"); row.restSeconds = 90
        w.plannedEntries = [row]
        s.plan = [w]
        let p = try! XCTUnwrap(CyWatchFrames.planToday(store: s))
        XCTAssertEqual(p.kind, 2); XCTAssertEqual(p.workoutId, w.id.uuidString); XCTAssertEqual(p.startMin, 18 * 60 + 30); XCTAssertEqual(p.durationMin, 40)
        XCTAssertEqual(p.exercises.first.map { ($0.id, $0.sets, $0.reps, $0.weightKg10, $0.restS, $0.superset) }.map { "\($0)" }, "(\"row\", 1, 8, 405, 90, 65)")
        let c = CyWatchFrames.cached(store: s)
        XCTAssertNil(c.sleepMin); XCTAssertNil(c.hrvMs); XCTAssertNil(c.recoveryPct, "there is no recovery score to send"); XCTAssertEqual(c.recoveryWord, "", "no fresh readings → no word")
        s.settings.healthReads.sleep = true
        s.applyHealthSamples([HealthSample(kind: .sleep, value: 7.4, date: Date().addingTimeInterval(-3600), source: "Apple Watch")])
        let c2 = CyWatchFrames.cached(store: s)
        XCTAssertEqual(c2.sleepMin, 444); XCTAssertEqual(c2.sleepSource, "Apple Watch"); XCTAssertEqual(c2.recoveryWord, "Train as planned")
    }
}
