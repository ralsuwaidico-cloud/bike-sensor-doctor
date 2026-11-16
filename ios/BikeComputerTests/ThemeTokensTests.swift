import XCTest
@testable import BikeComputer

/// UX1 theme foundation. Foundation only, so the file runs in the Linux logic tests and in the iOS unit tests.
/// These tests check the token data and the stored preference. They do not look at any screen: no screen uses the
/// tokens yet.
final class ThemeTokensTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "theme-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: the six themes

    func testThereAreExactlyTheSixApprovedThemesAndObsidianIsTheDefault() {
        XCTAssertEqual(CyThemeID.allCases.map { $0.title }, ["Obsidian", "Arctic", "Ocean", "Forest", "Sandstone", "High Contrast"])
        XCTAssertEqual(CyThemeID.newAthleteDefault, .obsidian)
        XCTAssertEqual(CyThemePreference.newAthleteDefault.resolved(systemIsDark: false), .obsidian)
        XCTAssertEqual(CyThemePreference.newAthleteDefault.resolved(systemIsDark: true), .obsidian)
        for id in CyThemeID.allCases { XCTAssertEqual(CyThemeTokens.tokens(for: id).id, id) }
    }

    func testTheValuesAreStillMarkedProvisional() {
        XCTAssertFalse(CyThemeTokens.valuesApproved, "approving the colour values must be a deliberate, reviewed change")
    }

    func testContrastMathsAgainstKnownValues() {
        let black = CyRGBA(hex: 0x000000), white = CyRGBA(hex: 0xFFFFFF)
        XCTAssertEqual(black.contrast(with: white), 21, accuracy: 0.001)
        XCTAssertEqual(white.contrast(with: black), 21, accuracy: 0.001)
        XCTAssertEqual(white.contrast(with: white), 1, accuracy: 0.001)
        XCTAssertEqual(CyRGBA(hex: 0x777777).contrast(with: white), 4.48, accuracy: 0.01)     // the well-known "just under 4.5" grey
        let c = CyRGBA(hex: 0x1B63C2)
        XCTAssertEqual(c.r, 27.0 / 255, accuracy: 1e-9); XCTAssertEqual(c.g, 99.0 / 255, accuracy: 1e-9); XCTAssertEqual(c.b, 194.0 / 255, accuracy: 1e-9); XCTAssertEqual(c.a, 1)
    }

    /// Text must reach 4.5:1 on every ground of its theme; High Contrast must reach 7:1.
    func testEveryTextTokenIsReadableOnEveryGround() {
        for id in CyThemeID.allCases {
            let t = CyThemeTokens.tokens(for: id); let need = id == .highContrast ? 7.0 : 4.5
            for (name, color) in t.textTokens { XCTAssertGreaterThanOrEqual(t.lowestContrast(of: color), need, "\(id.title) \(name)") }
        }
    }

    /// Colours that carry meaning in icons, charts and rings must reach 3:1 on every ground (the threshold for graphics).
    /// Several are below 4.5:1 in the light themes, so they are not suitable as small text; that is recorded for the
    /// colour review rather than hidden by a lower bar here.
    func testEveryMeaningColourIsVisibleOnEveryGround() {
        for id in CyThemeID.allCases {
            let t = CyThemeTokens.tokens(for: id)
            for (name, color) in t.markTokens { XCTAssertGreaterThanOrEqual(t.lowestContrast(of: color), 3.0, "\(id.title) \(name)") }
        }
    }

    func testDisciplineColoursAreDistinctFromEachOtherInEveryTheme() {
        for id in CyThemeID.allCases {
            let t = CyThemeTokens.tokens(for: id)
            XCTAssertNotEqual(t.endurance, t.strength, id.title); XCTAssertNotEqual(t.endurance, t.recovery, id.title); XCTAssertNotEqual(t.strength, t.recovery, id.title)
        }
    }

    func testGroundsMatchTheKindOfThemeAndHighContrastUsesBordersNotShadows() {
        for id in CyThemeID.allCases {
            let t = CyThemeTokens.tokens(for: id)
            XCTAssertEqual(t.background.luminance < 0.5, id.isDark, "\(id.title): background lightness matches the kind of theme")
            XCTAssertEqual(t.textPrimary.luminance > 0.5, id.isDark, "\(id.title): primary text is the opposite of the background")
        }
        let hc = CyThemeTokens.tokens(for: .highContrast)
        XCTAssertFalse(hc.usesShadows); XCTAssertGreaterThanOrEqual(hc.borderWidth, 1.5)
        XCTAssertGreaterThanOrEqual(hc.border.contrast(with: hc.surface), 7, "High Contrast borders are clearly visible")
    }

    // MARK: the athlete's choice

    func testAFixedChoiceIgnoresTheSystemAppearance() {
        for id in CyThemeID.allCases {
            let p = CyThemePreference.always(id)
            XCTAssertEqual(p.resolved(systemIsDark: true), id); XCTAssertEqual(p.resolved(systemIsDark: false), id)
        }
    }

    func testFollowingTheSystemShowsTheAthletesOwnLightAndDarkChoices() throws {
        let p = try XCTUnwrap(CyThemePreference.followSystem(light: .sandstone, dark: .forest))
        XCTAssertEqual(p.resolved(systemIsDark: false), .sandstone); XCTAssertEqual(p.resolved(systemIsDark: true), .forest)
        let d = try XCTUnwrap(CyThemePreference.followSystem())
        XCTAssertEqual(d.resolved(systemIsDark: false), .arctic); XCTAssertEqual(d.resolved(systemIsDark: true), .obsidian)
        // every theme can be chosen for the slot of its own kind, and for no other
        for id in CyThemeID.allCases {
            XCTAssertEqual(CyThemePreference.followSystem(light: id, dark: .obsidian) != nil, !id.isDark, "\(id.title) in the light slot")
            XCTAssertEqual(CyThemePreference.followSystem(light: .arctic, dark: id) != nil, id.isDark, "\(id.title) in the dark slot")
        }
    }

    func testReturningAthletesKeepTheKindOfAppearanceTheyHad() {
        XCTAssertEqual(CyThemePreference.forReturningAthlete(legacyAppearance: "light"), .always(.arctic))
        XCTAssertEqual(CyThemePreference.forReturningAthlete(legacyAppearance: "dark"), .always(.obsidian))
        XCTAssertEqual(CyThemePreference.forReturningAthlete(legacyAppearance: "system"), CyThemePreference.followSystem())
        XCTAssertEqual(CyThemePreference.forReturningAthlete(legacyAppearance: nil), .newAthleteDefault)
        XCTAssertEqual(CyThemePreference.forReturningAthlete(legacyAppearance: "something-else"), .newAthleteDefault)
    }

    // MARK: storage

    func testTheChoiceSurvivesARelaunch() throws {
        let d = freshDefaults()
        XCTAssertFalse(CyThemePreferenceStore(defaults: d).hasStoredChoice)
        XCTAssertEqual(CyThemePreferenceStore(defaults: d).load(legacyAppearance: nil), .newAthleteDefault)
        for p in [CyThemePreference.always(.ocean), try XCTUnwrap(CyThemePreference.followSystem(light: .sandstone, dark: .highContrast))] {
            XCTAssertTrue(CyThemePreferenceStore(defaults: d).save(p))
            // a new store object over the same preferences, as after a relaunch; the legacy setting no longer matters
            XCTAssertEqual(CyThemePreferenceStore(defaults: d).load(legacyAppearance: "light"), p)
        }
        XCTAssertTrue(CyThemePreferenceStore(defaults: d).hasStoredChoice)
        CyThemePreferenceStore(defaults: d).clear()
        XCTAssertEqual(CyThemePreferenceStore(defaults: d).load(legacyAppearance: "dark"), .always(.obsidian))
    }

    func testDamagedOrNewerStoredChoicesFallBackWithoutBeingOverwritten() throws {
        let d = freshDefaults(); let store = CyThemePreferenceStore(defaults: d)
        let cases: [Data] = [Data("not json".utf8),
                             Data(#"{"mode":"fixed","fixed":"aurora","systemLight":"arctic","systemDark":"obsidian"}"#.utf8),     // a theme a newer version might add
                             Data(#"{"mode":"system","fixed":"obsidian","systemLight":"ocean","systemDark":"arctic"}"#.utf8)]    // slots of the wrong kind
        for bytes in cases {
            d.set(bytes, forKey: CyThemePreferenceStore.key)
            XCTAssertEqual(store.load(legacyAppearance: "light"), .always(.arctic))
            XCTAssertEqual(d.data(forKey: CyThemePreferenceStore.key), bytes, "the stored bytes are left alone")
        }
    }

    func testTheChoiceIsNotPartOfTheAthleteRecord() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("theme-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = Store(directory: dir, generatePlan: false); s.onboarded = true
        let url = dir.appendingPathComponent("store.json"); let before = try Data(contentsOf: url)
        let d = freshDefaults(); let prefs = CyThemePreferenceStore(defaults: d)
        for id in CyThemeID.allCases { XCTAssertTrue(prefs.save(.always(id))) }
        XCTAssertEqual(try Data(contentsOf: url), before, "choosing a theme does not touch store.json")
        XCTAssertFalse(String(decoding: before, as: UTF8.self).contains("cyclift.theme"), "the athlete record has no theme field")
    }
}
