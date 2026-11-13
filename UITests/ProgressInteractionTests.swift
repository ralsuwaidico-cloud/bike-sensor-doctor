import XCTest

// Progress proof of concept — automated checks for the UI Lab PROTOTYPE (flat placeholder singularity, sample data).
// These tests drive the prototype in the iOS Simulator. A pass is evidence about layout, scrolling, hit testing,
// navigation and accessibility structure on a simulator. It is NOT validation of the production Cyclift app, NOT a
// real-device test, and says nothing about GPU performance, battery or heat.
// Rule: an assertion is never loosened to get a pass — a failure means the prototype is fixed or the defect reported.

final class ProgressInteractionTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = false }

    // MARK: helpers

    @discardableResult
    private func launch(_ env: [String: String] = [:], args: [String] = []) -> XCUIApplication {
        app = XCUIApplication()
        var e = ["LAB_THEME": "obsidian", "LAB_SCREEN": "progress", "LAB_PROBE": "1"]
        env.forEach { e[$0.key] = $0.value }
        app.launchEnvironment = e
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(el("evolutionTrack").waitForExistence(timeout: 25), "Progress did not appear")
        XCTAssertTrue(el("progressProbe").waitForExistence(timeout: 5), "Layout probe missing")
        usleep(600_000)
        return app
    }

    private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func count(_ id: String) -> Int { app.descendants(matching: .any).matching(identifier: id).count }
    private var window: CGRect { app.windows.firstMatch.frame }
    private var dockTop: CGFloat { let d = el("dockCentre"); return d.exists ? d.frame.minY : window.maxY - 100 }

    private func probe() -> [String: String] {
        let raw = (el("progressProbe").value as? String) ?? ""
        var out: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }
    private func num(_ p: [String: String], _ k: String) -> CGFloat { CGFloat(Double(p[k] ?? "") ?? -999) }

    /// Slow finger drag. Positive = the page content moves up.
    private func drag(_ dy: CGFloat) {
        let x = window.minX + 12
        let y0 = window.midY + 110
        let a = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y0))
        let b = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y0 - dy))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.4)
        usleep(250_000)
    }
    private func scrollToTop() {
        for _ in 0..<12 { if num(probe(), "offset") <= 0.5 { return }; drag(-90) }
    }
    private func goBack() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(b.waitForExistence(timeout: 5), "No back button on the details screen")
        b.tap()
        XCTAssertTrue(el("evolutionTrack").waitForExistence(timeout: 6), "Did not return to Progress")
        usleep(500_000)
    }
    private func r(_ f: CGRect) -> String { "x \(Int(f.minX)) y \(Int(f.minY)) w \(Int(f.width)) h \(Int(f.height))" }

    // MARK: 1 — expanded layout and measurements

    func test01_expandedLayoutAndMeasurements() {
        launch()
        let p = probe()
        let title = el("progressTitle"), hole = el("singularity"), id = el("heroIdentity"), track = el("evolutionTrack")
        let value = el("metricValue-endurance"), name = el("metricName-endurance")
        for (n, e) in [("title", title), ("singularity", hole), ("identity", id), ("track", track), ("first metric value", value)] {
            XCTAssertTrue(e.exists, "Missing \(n)")
        }
        XCTAssertEqual(num(p, "p"), 0, accuracy: 0.001, "The page did not open in the expanded state")
        XCTAssertEqual(count("singularity"), 1, "There must be exactly one singularity")
        XCTAssertTrue(id.label.contains("G2"), "Identity does not state the generation: \(id.label)")
        XCTAssertGreaterThanOrEqual(track.frame.height, 44, "Evolution Track is shorter than the 44 pt minimum target")
        XCTAssertGreaterThanOrEqual(track.frame.width, window.width - 1, "Evolution Track is not a full-width target")
        XCTAssertLessThanOrEqual(track.frame.maxY, dockTop, "Evolution Track is partly behind the dock on the first screen")
        XCTAssertGreaterThanOrEqual(title.frame.minY, num(p, "safeTop") - 1, "Title is inside the status-bar area")
        XCTAssertGreaterThan(id.frame.minY, hole.frame.midY, "Identity is not below the singularity")
        XCTAssertGreaterThanOrEqual(track.frame.minY, id.frame.maxY - 1, "Evolution Track is not directly beneath the identity")
        let visible = value.frame.maxY <= dockTop
        print("LABNOTE [\(Int(window.width))×\(Int(window.height))] expanded: singularity \(r(hole.frame)) · identity \(r(id.frame)) · track \(r(track.frame)) · hero height \(p["hero"] ?? "?") pt · track height \(p["track"] ?? "?") pt · dock top y \(Int(dockTop))")
        print("LABNOTE [\(Int(window.width))×\(Int(window.height))] first metric: name \(r(name.frame)) · key value \(r(value.frame)) · key value fully above the dock: \(visible ? "yes" : "no") (\(Int(dockTop - value.frame.maxY)) pt clearance)")
        if window.width >= 390 {
            XCTAssertTrue(visible, "Standard iPhone: the Endurance key value is not visible on the first screen")
        }
    }

    // MARK: 2 — the transformation follows the scroll position, reverses, and never jumps

    func test02_scrollTransformIsMonotonicReversibleAndJumpFree() {
        launch()
        let track = el("evolutionTrack"), hole = el("singularity")
        let trackRest = track.frame.minY, holeRest = hole.frame, p0 = probe()
        let body = num(p0, "hole")
        var lastP: CGFloat = 0, lastHole = body, log: [String] = []
        var steps: [CGFloat] = Array(repeating: 18, count: 10); steps += Array(repeating: 40, count: 5)
        for s in steps {
            drag(s)
            let p = probe()
            let off = num(p, "offset"), pp = num(p, "p"), h = num(p, "hole")
            XCTAssertGreaterThanOrEqual(pp, lastP - 0.001, "Progress went backwards while scrolling up")
            XCTAssertLessThanOrEqual(h, lastHole + 0.1, "Singularity grew while scrolling up")
            XCTAssertEqual(trackRest - track.frame.minY, off, accuracy: 2.0, "Content position does not match the scroll offset (content jump)")
            XCTAssertEqual(count("singularity"), 1, "More than one singularity at offset \(off)")
            log.append("\(Int(off))→p \(String(format: "%.2f", Double(pp))) hole \(Int(h))")
            lastP = pp; lastHole = h
        }
        print("LABNOTE [\(Int(window.width))] scroll up (offset → progress, singularity diameter): \(log.joined(separator: " · "))")
        let end = probe()
        XCTAssertEqual(num(end, "p"), 1, accuracy: 0.001, "Did not reach the collapsed state")
        XCTAssertEqual(num(end, "hole"), 30, accuracy: 0.5, "Collapsed symbol is not 30 pt")
        let safeTop = num(end, "safeTop")
        XCTAssertEqual(hole.frame.midY, safeTop + 24, accuracy: 3, "Collapsed symbol is not centred in the header")
        XCTAssertEqual(hole.frame.midX, 31, accuracy: 3, "Collapsed symbol is not at the leading edge of the header")
        XCTAssertTrue(el("headerGeneration").exists, "Collapsed header does not show the generation text")
        XCTAssertGreaterThanOrEqual(el("progressTitle").frame.minY, safeTop - 1, "Collapsed title is inside the status-bar area")
        XCTAssertGreaterThan(el("progressTitle").frame.minX, hole.frame.maxX - 1, "Collapsed title overlaps the symbol")
        XCTAssertTrue(el("progressMore").isHittable, "More button is not reachable in the collapsed header")
        print("LABNOTE [\(Int(window.width))] collapsed: symbol \(r(hole.frame)) · title \(r(el("progressTitle").frame)) · collapse distance ≈ \(Int(holeRest.midY - (safeTop + 24))) pt of scrolling")

        // back down: the same states in reverse, ending exactly where it started
        var back: [String] = []
        var prev: CGFloat = 1
        for _ in 0..<14 {
            drag(-45)
            let p = probe(); let pp = num(p, "p")
            XCTAssertLessThanOrEqual(pp, prev + 0.001, "Progress went forwards while scrolling down")
            XCTAssertEqual(trackRest - track.frame.minY, num(p, "offset"), accuracy: 2.0, "Content jump while scrolling down")
            back.append(String(format: "%.2f", Double(pp))); prev = pp
            if num(p, "offset") <= 0.5 { break }
        }
        scrollToTop(); usleep(600_000)
        let fin = probe()
        print("LABNOTE [\(Int(window.width))] scroll down (progress): \(back.joined(separator: " · "))")
        XCTAssertEqual(num(fin, "p"), 0, accuracy: 0.001, "Did not return to the expanded state")
        XCTAssertEqual(num(fin, "hole"), body, accuracy: 0.5, "Singularity did not return to its expanded size")
        XCTAssertEqual(track.frame.minY, trackRest, accuracy: 1.5, "Track did not return to its original position")
        XCTAssertEqual(hole.frame.midY, holeRest.midY, accuracy: 1.5, "Singularity did not return to its original position")
        XCTAssertEqual(hole.frame.midX, holeRest.midX, accuracy: 1.5, "Singularity did not return to the centre")
    }

    // MARK: 3 — the whole track is the navigation target

    func test03_trackOpensDetailsFromAnyPoint() {
        launch()
        let track = el("evolutionTrack")
        for dx in [0.5, 0.06, 0.94] {
            track.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            XCTAssertTrue(el("evolutionDetailsTitle").waitForExistence(timeout: 6), "Tapping the track at \(Int(dx * 100)) % of its width did not open the details")
            goBack()
            XCTAssertEqual(num(probe(), "offset"), 0, accuracy: 1.5, "Returning from the details changed the scroll position")
        }
        // scrolled part-way: still opens, and the scroll position is kept on return
        drag(30)
        let before = num(probe(), "offset")
        XCTAssertTrue(track.isHittable, "Track is not hittable after a small scroll")
        track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(el("evolutionDetailsTitle").waitForExistence(timeout: 6), "Track did not open the details when scrolled part-way")
        goBack()
        let after = num(probe(), "offset")
        print("LABNOTE [\(Int(window.width))] details opened from the centre, the leading edge and the trailing edge of the track · scroll offset before \(Int(before)) pt, after returning \(Int(after)) pt")
        XCTAssertEqual(after, before, accuracy: 3, "Scroll position was not kept after returning from the details")
        XCTAssertEqual(count("singularity"), 1, "More than one singularity after returning")
    }

    // MARK: 4 — one accessible element

    func test04_trackIsOneAccessibleElement() {
        launch()
        let track = el("evolutionTrack")
        XCTAssertEqual(count("evolutionTrack"), 1)
        XCTAssertEqual(track.elementType, .button, "Evolution Track is not exposed as a button")
        for part in ["Current generation G2", "The Ascendant", "Highest achieved G2", "Previous G1", "Next G3"] {
            XCTAssertTrue(track.label.contains(part), "Track description lacks \"\(part)\": \(track.label)")
        }
        XCTAssertFalse(app.staticTexts["YOU ARE HERE"].exists, "Track text is exposed as a separate element")
        XCTAssertFalse(app.staticTexts["G3"].exists, "A generation label is exposed as a separate element")
        XCTAssertGreaterThanOrEqual(track.frame.height, 44)
        let id = el("heroIdentity")
        XCTAssertTrue(id.label.contains("Evidence-supported"), "Identity description lacks the evidence confidence: \(id.label)")
        print("LABNOTE [\(Int(window.width))] track spoken description: \"\(track.label)\" · identity: \"\(id.label)\"")
    }

    // MARK: 5 — special states

    func test05_trackStates() {
        var notes: [String] = []
        func show(_ s: String) -> (track: String, id: String, h: String) {
            launch(["LAB_PROGRESS": s])
            let t = el("evolutionTrack")
            notes.append("\(s): track \(Int(t.frame.height)) pt, hero \(probe()["hero"] ?? "?") pt")
            return (t.label, el("heroIdentity").label, probe()["track"] ?? "")
        }
        var s = show("g0")
        XCTAssertTrue(s.track.contains("Current generation G0"), s.track)
        XCTAssertFalse(s.track.contains("Previous"), "G0 must not show an earlier stage: \(s.track)")
        XCTAssertTrue(s.track.contains("Next G1"), s.track)

        s = show("g2prov")
        XCTAssertTrue(s.track.contains("provisional"), "Provisional is not stated: \(s.track)")
        XCTAssertTrue(s.id.contains("Provisional"), s.id)

        s = show("g5")
        XCTAssertTrue(s.track.contains("Current generation G5"), s.track)
        XCTAssertFalse(s.track.contains("Next G"), "G5 must not show a later stage: \(s.track)")
        XCTAssertFalse(s.track.contains("G6"), s.track)
        XCTAssertTrue(s.track.contains("Development continues"), s.track)

        s = show("first")
        XCTAssertTrue(s.track.contains("Establishing your baseline"), s.track)
        XCTAssertFalse(s.track.contains("Current generation"), "A first-time athlete must not be given a generation: \(s.track)")
        XCTAssertFalse(s.id.contains("G0"), "A first-time athlete must not be shown G0: \(s.id)")
        XCTAssertFalse(el("headerGeneration").exists, "Header shows a generation without an evaluation")

        s = show("returning")
        XCTAssertTrue(s.track.contains("Not currently evaluated"), s.track)
        XCTAssertTrue(s.track.contains("Highest achieved G3"), s.track)
        XCTAssertFalse(s.track.contains("Current generation"), "A returning athlete must not be shown a current generation: \(s.track)")
        XCTAssertFalse(el("headerGeneration").exists, "Header shows a generation without an evaluation")
        el("evolutionTrack").tap()
        XCTAssertTrue(el("evolutionDetailsTitle").waitForExistence(timeout: 6), "Track did not open the details in the returning state")
        print("LABNOTE [\(Int(window.width))] state sizes — \(notes.joined(separator: " · "))")
    }

    // MARK: 6 — Dynamic Type

    func test06_dynamicType() {
        launch()
        let baseTrack = el("evolutionTrack").frame.height, baseHero = num(probe(), "hero")
        var notes = ["default: track \(Int(baseTrack)) pt, hero \(Int(baseHero)) pt"]
        for (name, cat) in [("xxxLarge", "UICTContentSizeCategoryXXXL"), ("accessibility L", "UICTContentSizeCategoryAccessibilityL"), ("accessibility XXXL", "UICTContentSizeCategoryAccessibilityXXXL")] {
            launch(args: ["-UIPreferredContentSizeCategoryName", cat])
            let track = el("evolutionTrack"), id = el("heroIdentity")
            XCTAssertGreaterThanOrEqual(track.frame.height, baseTrack - 0.5, "\(name): the track got shorter instead of growing")
            XCTAssertGreaterThanOrEqual(track.frame.minX, window.minX - 0.5, "\(name): track runs off the leading edge")
            XCTAssertLessThanOrEqual(track.frame.maxX, window.maxX + 0.5, "\(name): track runs off the trailing edge")
            XCTAssertLessThanOrEqual(id.frame.maxX, window.maxX + 0.5, "\(name): identity runs off the screen")
            XCTAssertGreaterThanOrEqual(track.frame.minY, id.frame.maxY - 1, "\(name): track overlaps the identity")
            XCTAssertTrue(track.label.contains("Current generation G2"), "\(name): description changed")
            XCTAssertEqual(count("singularity"), 1)
            notes.append("\(name): track \(Int(track.frame.height)) pt, hero \(probe()["hero"] ?? "?") pt, track top y \(Int(track.frame.minY)), dock top y \(Int(dockTop))")
            if name == "accessibility XXXL" {
                // the transformation and the navigation must still work at the largest size
                for _ in 0..<8 { drag(40) }
                XCTAssertEqual(num(probe(), "p"), 1, accuracy: 0.001, "\(name): did not collapse")
                scrollToTop(); usleep(500_000)
                XCTAssertEqual(num(probe(), "p"), 0, accuracy: 0.001, "\(name): did not expand again")
                if !track.isHittable { drag(track.frame.midY - (window.midY - 40)) }
                track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                XCTAssertTrue(el("evolutionDetailsTitle").waitForExistence(timeout: 6), "\(name): track did not open the details")
            }
        }
        print("LABNOTE [\(Int(window.width))] Dynamic Type — \(notes.joined(separator: " · "))")
    }

    // MARK: 7 — Reduce Motion (prototype override of the same code path the system setting uses)

    func test07_reduceMotionHasTwoStatesOnly() {
        launch(["LAB_REDUCE_MOTION": "1"])
        let p0 = probe()
        XCTAssertEqual(p0["mode"], "reduceMotion", "Reduce Motion path is not active")
        let body = el("singularity").frame.width
        var sizes: [String] = []
        var collapsed = false
        for _ in 0..<16 {
            drag(30)
            XCTAssertLessThanOrEqual(count("singularity"), 1, "Two singularities are exposed at once")
            let p = probe()
            let pp = num(p, "p")
            XCTAssertTrue(abs(pp) < 0.001 || abs(pp - 1) < 0.001, "Reduce Motion showed an in-between state (p \(pp))")
            if el("singularity").exists {
                let w = el("singularity").frame.width
                XCTAssertTrue(abs(w - body) < 1 || abs(w - 30) < 1, "Reduce Motion showed an in-between size (\(w) pt)")
                sizes.append("\(Int(num(p, "offset")))→\(Int(w))")
            } else { sizes.append("\(Int(num(p, "offset")))→none") }
            collapsed = p["collapsed"] == "1"
        }
        XCTAssertTrue(collapsed, "Reduce Motion never reached the compact state")
        XCTAssertEqual(el("singularity").frame.width, 30, accuracy: 1, "Compact symbol is not shown")
        scrollToTop(); usleep(500_000)
        XCTAssertEqual(probe()["collapsed"], "0", "Reduce Motion did not return to the expanded state")
        XCTAssertEqual(el("singularity").frame.width, body, accuracy: 1, "Expanded singularity did not return")
        print("LABNOTE [\(Int(window.width))] Reduce Motion (offset → singularity width): \(sizes.joined(separator: " · ")) — only \(Int(body)) pt and 30 pt occur")
    }

    // MARK: 8 — safe area and hit testing under the header

    func test08_headerProtectsContentBeneathIt() {
        launch()
        let track = el("evolutionTrack")
        let safeTop = num(probe(), "safeTop")
        for _ in 0..<40 {
            if track.frame.midY < safeTop + 40 { break }
            drag(min(max(track.frame.midY - (safeTop + 26), 22), 60))
        }
        let y = track.frame.midY
        XCTAssertTrue(y > safeTop && y < safeTop + 48, "Could not place the track under the header (track mid y \(y), header \(safeTop)…\(safeTop + 48))")
        XCTAssertEqual(num(probe(), "p"), 1, accuracy: 0.001)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.midX, dy: y)).tap()
        XCTAssertFalse(el("evolutionDetailsTitle").waitForExistence(timeout: 2), "A tap on the header reached the track hidden beneath it")
        XCTAssertTrue(el("progressMore").isHittable, "More button is not reachable")
        XCTAssertGreaterThanOrEqual(el("progressTitle").frame.minY, safeTop - 1)
        print("LABNOTE [\(Int(window.width))] header hit test: track centre at y \(Int(y)) under the header (\(Int(safeTop))…\(Int(safeTop + 48))); tap did not pass through · safe-area top \(Int(safeTop)) pt")
    }
}
