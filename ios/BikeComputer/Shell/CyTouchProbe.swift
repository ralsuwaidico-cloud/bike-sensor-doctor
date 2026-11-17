import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// Diagnosis tool for the screen tests — simulator only, and only when the test launches the app with CY_DIAG_TOUCHES=1.
// Lab runs 20–25: on Home v2.3 the controls in the upper part of the page do not run their actions although the page
// scrolls, on a fresh launch, with no native view over them (run 25 measured the graph's touch layer exactly on the
// chart, and the taps failed with the layer left out as well). What is not known is which view UIKit delivers those
// touches to. This records, for every touch that begins, the point and the chain of views UIKit's own hit-test returns,
// and shows the last record in a text element ("touchProbe") a test can read. It never changes where a touch goes: the
// recogniser fails at once and neither cancels nor delays touches.
enum CyTouchProbe {
    // Lab run 26: with the probe on, the same taps DID open their pages; in run 25, same check without the probe, they did
    // not. The probe has two parts, so each can now be switched on alone: CY_DIAG_TOUCHES = "recognizer" (the window
    // recogniser only), "label" (the redrawn text element only), "1" (both). And because the on-screen counter read by the
    // tests turned out not to update, the stages are written to a file the test names (CY_DIAG_FILE): the handler ran,
    // the route list changed, the destination was built.
    #if targetEnvironment(simulator)
    private static let mode = ProcessInfo.processInfo.environment["CY_DIAG_TOUCHES"] ?? ""
    private static let file = ProcessInfo.processInfo.environment["CY_DIAG_FILE"] ?? ""
    #else
    private static let mode = ""
    private static let file = ""
    #endif
    static var recogniserOn: Bool { mode == "1" || mode == "recognizer" }
    static var isOn: Bool { mode == "1" || mode == "label" }          // the text element
    static var last = "no touch yet"
    private static var installed = false
    private static let started = Date()

    /// One line per stage, appended to the file the test named. Does nothing unless a test asked for it on a simulator.
    static func note(_ s: String) {
        guard !file.isEmpty else { return }
        let line = String(format: "%.2f ", Date().timeIntervalSince(started)) + s + "\n"
        if let h = FileHandle(forWritingAtPath: file) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(toFile: file, atomically: true, encoding: .utf8) }
    }

    static func installIfAsked() {
        note("app shell appeared; mode '\(mode)'")
        guard recogniserOn, !installed else { return }
        guard let w = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).first else { return }
        let g = Recorder(target: nil, action: nil)
        g.cancelsTouchesInView = false; g.delaysTouchesBegan = false; g.delaysTouchesEnded = false
        w.addGestureRecognizer(g)
        installed = true
    }

    static func describe(_ v: UIView?) -> String {
        var parts: [String] = []
        var cur = v
        var n = 0
        while let x = cur, n < 9 {
            let f = x.convert(x.bounds, to: nil)
            var s = "\(type(of: x))[\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))]"
            if !x.isUserInteractionEnabled { s += "(no-interaction)" }
            if x.isHidden || x.alpha < 0.02 { s += "(hidden)" }
            if let gs = x.gestureRecognizers, !gs.isEmpty { s += "{" + gs.map { String(describing: type(of: $0)) }.joined(separator: ",") + "}" }
            if let vc = x.next as? UIViewController { s += "<\(type(of: vc))>" }
            parts.append(s)
            cur = x.superview; n += 1
        }
        return parts.joined(separator: " < ")
    }

    private final class Recorder: UIGestureRecognizer {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let t = touches.first, let w = view as? UIWindow {
                let p = t.location(in: w)
                CyTouchProbe.last = "touch (\(Int(p.x)),\(Int(p.y))) -> " + CyTouchProbe.describe(w.hitTest(p, with: event))
                CyTouchProbe.note("touch began at (\(Int(p.x)),\(Int(p.y)))")
            }
            state = .failed
        }
    }
}

/// The last recorded touch as a readable element; drawn only when the probe is on.
struct CyTouchProbeLabel: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { _ in
            Text(CyTouchProbe.last).font(.system(size: 4)).lineLimit(1).frame(width: 40, height: 4).opacity(0.02)
                .accessibilityIdentifier("touchProbe")
        }
        .allowsHitTesting(false)
    }
}
