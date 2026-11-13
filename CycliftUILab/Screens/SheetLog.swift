import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// Cyclift UI Lab — diagnostic log for sheet presentation (prototype only; nothing leaves the simulator).
// Every request, state change and lifecycle event of a sheet is appended, with a time stamp and with what UIKit
// itself reports at that instant, to "sheet-log.txt" in the prototype's own Documents folder. The build script copies
// the file out after the interaction tests. The log changes no behaviour.
enum SheetLog {
    private static let start = Date()
    private static let url: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("sheet-log.txt")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// One marker per app launch, with the launch options that select the scenario.
    static func launch() {
        let env = ProcessInfo.processInfo.environment
        let keys = ["LAB_SCREEN", "LAB_SCENARIO", "LAB_STRESS", "LAB_SHEET", "LAB_THEME"]
        let opts = keys.compactMap { k in env[k].map { "\(k)=\($0)" } }.joined(separator: " ")
        write("==== launch \(opts)")
    }

    static func note(_ text: String) { write("\(text) | \(uikit())") }

    /// What UIKit reports right now: the chain of presented view controllers and whether a transition is running.
    static func uikit() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first else { return "uikit: no scene" }
        let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        guard let root = window?.rootViewController else { return "uikit: no window" }
        var parts: [String] = []
        var vc: UIViewController? = root.presentedViewController
        var depth = 0
        while let v = vc, depth < 4 {
            var s = "presented(style \(v.modalPresentationStyle.rawValue)"
            if v.isBeingPresented { s += ", appearing" }
            if v.isBeingDismissed { s += ", disappearing" }
            s += ")"
            parts.append(s)
            vc = v.presentedViewController
            depth += 1
        }
        let chain = parts.isEmpty ? "nothing presented" : parts.joined(separator: " > ")
        let moving = root.transitionCoordinator != nil ? ", transition running" : ""
        return "uikit: \(chain)\(moving)"
    }

    // MARK: Touch log (diagnostic for the Coach preview double tap, run 43279857878)

    /// Adds a passive recogniser to every window. It never recognises anything, cancels nothing and delays nothing;
    /// it only writes where each touch went down and came up, which view UIKit would deliver it to, and whether a
    /// scroll view under the finger was still moving.
    static func installTouchLog() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var added = 0
        for w in scenes.flatMap({ $0.windows }) {
            if (w.gestureRecognizers ?? []).contains(where: { $0 is TouchLogRecognizer }) { continue }
            let g = TouchLogRecognizer(target: nil, action: nil)
            g.cancelsTouchesInView = false
            g.delaysTouchesBegan = false
            g.delaysTouchesEnded = false
            w.addGestureRecognizer(g)
            added += 1
        }
        if added > 0 { note("touch log installed on \(added) window(s)") }
    }

    static func touch(_ what: String, _ t: UITouch, _ host: UIView?) {
        let window: UIWindow? = (host as? UIWindow) ?? host?.window
        let p = t.location(in: window)
        var s = "touch \(what) at (\(Int(p.x)), \(Int(p.y))), tap count \(t.tapCount)"
        if let w = window {
            let hit = w.hitTest(p, with: nil)
            s += ", would hit " + (hit.map { String(describing: type(of: $0)) } ?? "nothing")
            var v: UIView? = hit
            var scroll: UIScrollView?
            while let x = v {
                if let sc = x as? UIScrollView { scroll = sc; break }
                v = x.superview
            }
            if let sc = scroll {
                s += ", scroll view under it: dragging \(sc.isDragging), decelerating \(sc.isDecelerating), tracking \(sc.isTracking)"
            } else {
                s += ", no scroll view under it"
            }
            s += ", delivered to " + (t.view.map { String(describing: type(of: $0)) } ?? "no view")
            s += ", window accepts touches \(w.isUserInteractionEnabled)"
        }
        note(s)
    }

    private static func write(_ line: String) {
        guard let url else { return }
        let now = Date()
        let ms = Int(now.timeIntervalSince(start) * 1000)
        let text = "\(stamp.string(from: now)) +\(ms)ms \(line)\n"
        guard let data = text.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Passive: stays "possible" while a finger is down, then fails. It prevents no other recogniser and is prevented by none.
final class TouchLogRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { SheetLog.touch("down", t, view) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { SheetLog.touch("up", t, view) }
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for t in touches { SheetLog.touch("cancelled", t, view) }
        state = .failed
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
