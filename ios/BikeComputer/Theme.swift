import SwiftUI

/// One colour system for the whole app, matching the board's round screen: accent = action, green = live,
/// amber = stale / provisional, red = warning, orange = simulated.
enum BC {
    static let accent = Color(light: Color(red: 0.055, green: 0.62, blue: 0.608), dark: Color(red: 0.204, green: 0.906, blue: 0.894))
    static let live = Color(light: Color(red: 0.12, green: 0.616, blue: 0.36), dark: Color(red: 0.337, green: 0.878, blue: 0.549))
    static let stale = Color(light: Color(red: 0.78, green: 0.494, blue: 0.07), dark: Color(red: 1, green: 0.714, blue: 0.302))
    static let warn = Color(light: Color(red: 0.84, green: 0.24, blue: 0.24), dark: Color(red: 1, green: 0.353, blue: 0.353))
    static let sim = Color(light: Color(red: 0.88, green: 0.478, blue: 0.1), dark: Color(red: 1, green: 0.54, blue: 0.12))
    static let zones: [Color] = [Color(red: 0.5, green: 0.655, blue: 0.72), Color(red: 0.243, green: 0.659, blue: 0.42), Color(red: 0.85, green: 0.71, blue: 0.17), Color(red: 0.91, green: 0.51, blue: 0.165), Color(red: 0.82, green: 0.27, blue: 0.27), Color(red: 0.557, green: 0.267, blue: 0.678), Color.primary]
    static func zone(_ z: Int) -> Color { z >= 1 && z <= 7 ? zones[z - 1] : .secondary }
    static let numFont = Font.system(size: 34, weight: .bold, design: .rounded)
    static let bigNum = Font.system(size: 48, weight: .bold, design: .rounded)
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

struct Card<Content: View>: View {
    var accent = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent ? BC.accent : Color.clear, lineWidth: 1.5))
    }
}

struct Eyebrow: View { let t: String; var body: some View { Text(t.uppercased()).font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(.secondary) } }

struct Pill: View {
    let text: String; var color: Color = .secondary
    var body: some View { Text(text).font(.caption2.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.18), in: Capsule()).foregroundStyle(color) }
}

struct ZonePill: View { let z: Int; var body: some View { z > 0 ? AnyView(Text("Z\(z)").font(.caption2.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 3).background(BC.zone(z), in: Capsule()).foregroundStyle(.white)) : AnyView(Pill(text: "off bike")) } }

struct ZoneBar: View {
    var current: Int = 0
    var body: some View {
        HStack(spacing: 2) { ForEach(1...7, id: \.self) { z in RoundedRectangle(cornerRadius: 3).fill(BC.zone(z).opacity(current == z ? 1 : 0.55)).frame(height: 12).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: current == z ? 2 : 0)) } }
    }
}

/// A metric tile: value or "--", unit, and the source line (green live / orange "no data").
struct MetricTile: View {
    let title: String; let value: String?; let unit: String; let source: String; var big = false; var onHide: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Eyebrow(t: title); Spacer(); if let h = onHide { Button("hide", action: h).font(.caption2.bold()).buttonStyle(.bordered).controlSize(.mini) } }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "--").font(big ? BC.bigNum : BC.numFont).monospacedDigit().foregroundStyle(value == nil ? .secondary : .primary).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(value == nil ? "no data" : source).font(.caption2.weight(.heavy)).foregroundStyle(value == nil ? BC.stale : BC.live)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatusDot: View { let color: Color; var body: some View { Circle().fill(color).frame(width: 9, height: 9) } }

extension Int { var asDuration: String { self >= 3600 ? String(format: "%d:%02d:%02d", self / 3600, self / 60 % 60, self % 60) : String(format: "%d:%02d", self / 60, self % 60) } }
extension Date {
    var shortDay: String { let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: self) }
    var dayAndDate: String { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: self) }
}
