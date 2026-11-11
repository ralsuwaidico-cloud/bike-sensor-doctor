import XCTest

// Waits for UI tests (CI speed-up, 1 Nov 2026; ios/CI_PIPELINE.md).
//
// Why these exist: XCUI's own `isHittable` raises an Objective-C exception ("Failed to determine hittability") while a
// SwiftUI menu or sheet is still animating, and a fixed `sleep` is either too short on a slow runner or wastes time on a
// fast one. These helpers find elements by accessibility identifier / label (never by screen position) and wait until
// the element has a real, finite frame that has stopped moving. Only then is it tapped — at its own centre, which is
// the element itself, not a guessed screen position.

extension XCUIElement {
    /// Exists and has a real, finite, non-empty frame (a menu item that is in the tree but not on screen has none).
    var hasUsableFrame: Bool {
        guard exists else { return false }
        let f = frame
        return f.width > 0 && f.height > 0 && f.minX.isFinite && f.minY.isFinite && f.maxX.isFinite && f.maxY.isFinite
    }

    /// Waits until the element exists and its frame is the same on two polls 0.2 s apart (an animating element moves).
    @discardableResult
    func waitUntilSettled(timeout: TimeInterval = 5) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        var last: CGRect? = nil
        // run 220 (hub, cycle 4): on a slow runner one frame query took seconds, so a 5 s budget allowed a single poll and
        // a perfectly still Close "never settled" and was never tapped. Two polls are needed to compare; the deadline
        // cannot end the wait before the element has been read at least three times.
        var polls = 0
        while Date() < end || polls < 3 {
            polls += 1
            if hasUsableFrame {
                let f = frame
                // run 212: a frame reported as x = 19.999999999999996 on one poll and 20.0 on the next never "settled" under
                // exact equality, so the Close was never tapped — frames within half a point are the same frame
                if let l = last, abs(l.minX - f.minX) < 0.5, abs(l.minY - f.minY) < 0.5, abs(l.width - f.width) < 0.5, abs(l.height - f.height) < 0.5 { return true }
                last = f
            } else {
                last = nil
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Taps the element once it has settled. Returns false (and taps nothing) when it never got a usable frame.
    @discardableResult
    func tapWhenSettled(timeout: TimeInterval = 5) -> Bool {
        guard waitUntilSettled(timeout: timeout) else { return false }
        // run 150 (owner size): a menu item settled, then re-resolved to an infinite frame when tapped through the
        // element — tap the settled point through the app instead, so the frame is read once.
        let f = frame
        guard f.minX.isFinite, f.minY.isFinite, f.width > 0, f.height > 0 else { return false }
        XCUIApplication().coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        return true
    }

    /// Waits until the element is gone (a sheet or menu closed).
    @discardableResult
    func waitUntilGone(timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}

extension XCUIApplication {
    /// Waits for whichever navigation bar / static text first shows `title` (replaces a fixed sleep after navigation).
    @discardableResult
    func waitForScreen(_ title: String, timeout: TimeInterval = 5) -> Bool {
        navigationBars[title].waitForExistence(timeout: timeout) || staticTexts[title].firstMatch.waitForExistence(timeout: 1)
    }

    /// Short pause before a screenshot so animations and charts have finished drawing. Screenshots only — never used to
    /// wait for an element (use `waitForExistence` / `waitUntilSettled` for that).
    func settleForScreenshot(_ seconds: TimeInterval = 1) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Checkpoint C: Home's greeting ("Good morning, Rashed") carries the rider's name; waits for it.
    @discardableResult
    func waitForHome(name: String, timeout: TimeInterval = 25) -> Bool {
        let g = descendants(matching: .any)["homeGreeting"].firstMatch
        guard g.waitForExistence(timeout: timeout) else { return false }
        return g.label.contains(name)
    }

    /// Checkpoint C: the centre button opens the Training Hub; today's one action (Start / Resume / Results, or the
    /// first row's) is on the hub card. Taps it when the hub is up, so the flows that used to open directly still do.
    /// Returns false when no hub action exists (a rest day, a hold).
    @discardableResult
    func openFromHub(timeout: TimeInterval = 10) -> Bool {
        guard descendants(matching: .any)["trainingHub"].firstMatch.waitForExistence(timeout: timeout) else { return false }
        let primary = ["homePrimary", "homeRow-0"].map { buttons[$0].firstMatch }.first { $0.waitForExistence(timeout: 3) }
        guard let p = primary, p.isHittable else { return false }
        p.tap()
        return true
    }

    /// Closes the Training Hub if it is showing.
    func closeHub() {
        let c = buttons["hubClose"].firstMatch
        if c.exists && c.isHittable { c.tap() }
    }
}

extension XCTestCase {
    /// Run 205: assertion text alone could not explain the smoke failures. `expect` is XCTAssertTrue plus, on failure, a
    /// full-screen screenshot kept as an attachment named `FAIL-<test>-<tag>` — ios/ci/build.sh exports those into the
    /// published ci-logs layout folder. Use it for every step whose failure needs to be seen, not just read.
    @discardableResult
    func expect(_ condition: @autoclosure () -> Bool, _ message: String, tag: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ok = condition()
        if !ok {
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            a.name = "FAIL-\(name.replacingOccurrences(of: "-[", with: "").replacingOccurrences(of: "]", with: "").replacingOccurrences(of: " ", with: "."))-\(tag)"
            a.lifetime = .keepAlways
            add(a)
            XCTFail(message, file: file, line: line)
        }
        return ok
    }
}

extension XCUIElement {
    /// Run 210 (screenshots): after a sheet or the hub was dismissed, its elements stayed in the test driver's tree for
    /// several seconds although the screen showed them gone. "Dismissed" is judged by what a person sees: the element is
    /// either no longer in the tree or can no longer be hit.
    func waitUntilDismissed(timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if !exists || !isHittable { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !exists || !isHittable
    }
    /// Positive evidence that a screen is back on top: the element exists AND can be hit (nothing covers it).
    func waitUntilHittable(timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if exists && isHittable { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return exists && isHittable
    }
    /// Wait until the element exists and can be hit (an overlay or a dismissal animation may still cover it), then tap once.
    @discardableResult
    func tapWhenHittable(timeout: TimeInterval = 8) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if exists && isHittable { tap(); return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
}
