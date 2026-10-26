import Foundation

/// Public contact details for Cyclift. The owner chose to publish his address as the support contact (1.0 decisions):
/// it is a static Info.plist value (CYCLIFT_SUPPORT_EMAIL in project.yml) and is written into the bundled privacy
/// policy and terms (Resources/*.md, mirrored in ios/legal and docs/site). `render` still replaces a `SUPPORT_EMAIL`
/// placeholder, so an older document or a build without the key never shows the raw placeholder.
enum SupportInfo {
    static let placeholder = "SUPPORT_EMAIL"
    /// The published support address (also in project.yml, the legal pages and docs/site).
    static let publicAddress = "ralsuwaidico@gmail.com"
    static let supportPage = URL(string: "https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/support.html")!
    static let privacyPage = URL(string: "https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/privacy.html")!
    static let termsPage = URL(string: "https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/terms.html")!

    /// The configured public support address, or nil (unset, empty, unexpanded build variable or not an address).
    static var email: String? { cleaned(Bundle.main.object(forInfoDictionaryKey: "CYCLIFT_SUPPORT_EMAIL") as? String) }
    /// "mailto:" link for the About section, or nil without an address.
    static var mailURL: URL? { email.flatMap { URL(string: "mailto:\($0)?subject=Cyclift%20support") } }

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
