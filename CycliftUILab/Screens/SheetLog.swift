import SwiftUI
import UIKit

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
