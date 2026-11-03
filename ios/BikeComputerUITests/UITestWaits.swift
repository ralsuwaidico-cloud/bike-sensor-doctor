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
        while Date() < end {
            if hasUsableFrame {
                let f = frame
                if let l = last, l == f { return true }
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
}
