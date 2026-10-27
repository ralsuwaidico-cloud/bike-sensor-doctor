import Foundation
protocol ObservableObject: AnyObject {}
@propertyWrapper struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
final class DeviceLink {}
struct PairedSensor: Codable, Equatable {}
extension Date {
    var shortDay: String { let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: self) }
    var dayAndDate: String { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: self) }
}
enum RideLayout: String, Codable { case coach }
enum TemplateEditor {
    static func apply(name: String, focus: StrengthFocus, entries: [ExerciseEntry], minutes: Int?, to old: WorkoutTemplate?, now: Date = Date()) -> WorkoutTemplate {
        var t = old ?? WorkoutTemplate(name: "", entries: [], updatedAt: now)
        let changed = old == nil || old!.entries != entries || old!.focus != focus || old!.minutesEstimate != minutes
        t.name = name.trimmingCharacters(in: .whitespaces); t.focus = focus; t.entries = entries; t.minutesEstimate = minutes
        if changed { t.updatedAt = now }
        return t
    }
}
