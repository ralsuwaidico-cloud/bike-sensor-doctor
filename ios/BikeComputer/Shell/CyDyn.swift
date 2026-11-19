import SwiftUI
import UIKit

/// Text sizes taken from the design sheets (drawn at the standard iPhone text size) that still follow the athlete's
/// iPhone text-size setting: the sheet's size is the size at the standard setting and grows or shrinks with it.
enum CyDyn {
    static func f(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .body).scaledValue(for: size), weight: weight)
    }
}
