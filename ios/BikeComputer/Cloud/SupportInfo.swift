import Foundation

/// Public contact details for Cyclift. The bundled privacy policy and terms (Resources/*.md, mirrored in ios/legal and
/// docs/site) carry the placeholder `SUPPORT_EMAIL`. The real address is never committed to the (public) repository:
/// CI writes it into Info.plist (key CYCLIFT_SUPPORT_EMAIL) from an optional secret. Without it the pages point to the
/// support web page instead.
enum SupportInfo {
    static let placeholder = "SUPPORT_EMAIL"
    static let supportPage = URL(string: "https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/support.html")!
    static let privacyPage = URL(string: "https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/privacy.html")!
    static let termsPage = URL(string: "https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/terms.html")!

    /// The configured public support address, or nil (unset, empty, unexpanded build variable or not an address).
    static var email: String? { cleaned(Bundle.main.object(forInfoDictionaryKey: "CYCLIFT_SUPPORT_EMAIL") as? String) }

    static func cleaned(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.hasPrefix("$("),
              t.contains("@"), !t.contains(" "), t != placeholder else { return nil }
        return t
    }

    /// Replaces the placeholder in a bundled legal document. With an address: the address. Without one:
    /// "Contact: see the support page" (linked), and a paragraph that is only the placeholder becomes that line too.
    static func render(_ text: String, email: String?) -> String {
        let page = "[support page](\(supportPage.absoluteString))"
        if let email {
            return text.replacingOccurrences(of: placeholder, with: email)
        }
        var paragraphs = text.components(separatedBy: "\n\n")
        for i in paragraphs.indices {
            let p = paragraphs[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if p == placeholder { paragraphs[i] = "Contact: see the \(page)." ; continue }
            var s = paragraphs[i]
            s = s.replacingOccurrences(of: "Contact: \(placeholder)", with: "Contact: see the \(page)")
            s = s.replacingOccurrences(of: "contact us: \(placeholder)", with: "contact us through the \(page)")
            s = s.replacingOccurrences(of: placeholder, with: "the \(page)")
            paragraphs[i] = s
        }
        return paragraphs.joined(separator: "\n\n")
    }
}
