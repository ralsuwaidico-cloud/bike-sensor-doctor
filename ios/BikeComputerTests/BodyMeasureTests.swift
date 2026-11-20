import XCTest
@testable import BikeComputer

/// Screen 2 (owner decision 20 Nov 2026): height, BMI and the typed date of birth.
final class BodyMeasureTests: XCTestCase {
    // MARK: BMI

    func testBMIIsKilogramsOverMetresSquared() {
        XCTAssertEqual(BodyMeasure.bmi(weightKg: 70, heightCm: 175), 22.9)        // 70 / 1.75² = 22.857
        XCTAssertEqual(BodyMeasure.bmi(weightKg: 74.5, heightCm: 180), 23.0)      // 74.5 / 3.24 = 22.994
        XCTAssertEqual(BodyMeasure.bmi(weightKg: 100, heightCm: 200), 25.0)
    }
    func testNoBMIWithoutBothMeasurements() {
        XCTAssertNil(BodyMeasure.bmi(weightKg: nil, heightCm: 175))
        XCTAssertNil(BodyMeasure.bmi(weightKg: 70, heightCm: nil))
        XCTAssertNil(BodyMeasure.bmi(weightKg: nil, heightCm: nil))
    }
    func testNoBMIFromOutOfRangeMeasurements() {
        XCTAssertNil(BodyMeasure.bmi(weightKg: 70, heightCm: 0))
        XCTAssertNil(BodyMeasure.bmi(weightKg: 70, heightCm: 119))
        XCTAssertNil(BodyMeasure.bmi(weightKg: 29.9, heightCm: 175))
        XCTAssertNil(BodyMeasure.bmi(weightKg: 250, heightCm: 175))
    }
    /// The same athlete entered in pounds and feet/inches gets the BMI of the stored metric values.
    func testBMIFromImperialEntryUsesTheStoredMetricValues() {
        let kg = BodyMeasure.parseWeightKg("154", imperial: true)             // 69.9 kg
        let cm = BodyMeasure.heightCm(feet: "5", inches: "9")                    // 175 cm
        XCTAssertEqual(kg, 69.9); XCTAssertEqual(cm, 175)
        XCTAssertEqual(BodyMeasure.bmi(weightKg: kg, heightCm: cm), 22.8)         // 69.9 / 3.0625 = 22.82
    }

    // MARK: height

    func testMetricHeight() {
        XCTAssertEqual(BodyMeasure.parseHeightCm("178"), 178)
        XCTAssertEqual(BodyMeasure.parseHeightCm(" 178,4 "), 178)
        XCTAssertEqual(BodyMeasure.parseHeightCm("178.6"), 179)
        XCTAssertEqual(BodyMeasure.parseHeightCm("120"), 120)
        XCTAssertEqual(BodyMeasure.parseHeightCm("230"), 230)
        for bad in ["", "abc", "119", "231", "1.78", "-178", "17800"] { XCTAssertNil(BodyMeasure.parseHeightCm(bad), bad) }
    }
    func testImperialHeight() {
        XCTAssertEqual(BodyMeasure.heightCm(feet: "5", inches: "11"), 180)
        XCTAssertEqual(BodyMeasure.heightCm(feet: "6", inches: ""), 183)
        XCTAssertEqual(BodyMeasure.heightCm(feet: "6", inches: "0"), 183)
        XCTAssertNil(BodyMeasure.heightCm(feet: "", inches: "11"), "feet are required")
        XCTAssertNil(BodyMeasure.heightCm(feet: "5", inches: "12"), "inches run 0–11")
        XCTAssertNil(BodyMeasure.heightCm(feet: "3", inches: "0"), "91 cm is below the accepted range")
        XCTAssertNil(BodyMeasure.heightCm(feet: "8", inches: "0"), "244 cm is above the accepted range")
        XCTAssertNil(BodyMeasure.heightCm(feet: "five", inches: "1"))
    }
    /// Feet/inches → cm → feet/inches gives back what was typed, for every accepted height.
    func testFeetInchesRoundTrip() {
        for ft in 4...7 { for inch in 0...11 {
            guard let cm = BodyMeasure.heightCm(feet: "\(ft)", inches: "\(inch)") else { continue }
            let back = BodyMeasure.feetInches(cm)
            XCTAssertEqual(back.feet, ft, "\(ft) ft \(inch) in"); XCTAssertEqual(back.inches, inch, "\(ft) ft \(inch) in")
        } }
        XCTAssertEqual(BodyMeasure.heightText(180, imperial: false), "180 cm")
        XCTAssertEqual(BodyMeasure.heightText(180, imperial: true), "5 ft 11 in")
    }

    // MARK: date of birth

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        return BodyMeasure.gregorian.date(from: c)!
    }
    func testValidBirthDate() {
        let now = day(2026, 11, 20)
        XCTAssertEqual(BodyMeasure.birthDate(day: "12", month: "3", year: "1990", now: now), .date(day(1990, 3, 12)))
        XCTAssertEqual(BodyMeasure.birthDate(day: "07", month: "08", year: "1985", now: now), .date(day(1985, 8, 7)))
        let p = BodyMeasure.birthParts(day(1990, 3, 12))
        XCTAssertEqual(p.day, "12"); XCTAssertEqual(p.month, "3"); XCTAssertEqual(p.year, "1990")
    }
    func testLeapYears() {
        let now = day(2026, 11, 20)
        XCTAssertEqual(BodyMeasure.birthDate(day: "29", month: "2", year: "2000", now: now), .date(day(2000, 2, 29)))
        XCTAssertEqual(BodyMeasure.birthDate(day: "29", month: "2", year: "1996", now: now), .date(day(1996, 2, 29)))
        XCTAssertEqual(BodyMeasure.birthDate(day: "29", month: "2", year: "1999", now: now), .issue(.notADate))
        XCTAssertEqual(BodyMeasure.birthDate(day: "29", month: "2", year: "2001", now: now), .issue(.notADate))
    }
    func testImpossibleDates() {
        let now = day(2026, 11, 20)
        XCTAssertEqual(BodyMeasure.birthDate(day: "31", month: "4", year: "1990", now: now), .issue(.notADate))
        XCTAssertEqual(BodyMeasure.birthDate(day: "0", month: "5", year: "1990", now: now), .issue(.notADate))
        XCTAssertEqual(BodyMeasure.birthDate(day: "12", month: "13", year: "1990", now: now), .issue(.notADate))
        XCTAssertEqual(BodyMeasure.birthDate(day: "", month: "3", year: "1990", now: now), .issue(.incomplete))
        XCTAssertEqual(BodyMeasure.birthDate(day: "12", month: "3", year: "90", now: now), .issue(.incomplete))
        XCTAssertEqual(BodyMeasure.birthDate(day: "x", month: "3", year: "1990", now: now), .issue(.incomplete))
    }
    func testFutureAndAgeLimits() {
        let now = day(2026, 11, 20)
        XCTAssertEqual(BodyMeasure.birthDate(day: "21", month: "11", year: "2026", now: now), .issue(.future))
        XCTAssertEqual(BodyMeasure.birthDate(day: "1", month: "1", year: "2030", now: now), .issue(.future))
        XCTAssertEqual(BodyMeasure.birthDate(day: "21", month: "11", year: "2013", now: now), .issue(.tooYoung))     // turns 13 tomorrow
        XCTAssertEqual(BodyMeasure.birthDate(day: "20", month: "11", year: "2013", now: now), .date(day(2013, 11, 20)))
        XCTAssertEqual(BodyMeasure.birthDate(day: "1", month: "1", year: "1920", now: now), .issue(.tooOld))
    }

    func testWeightRuleIsUnchanged() {
        XCTAssertEqual(BodyMeasure.parseWeightKg("70", imperial: false), 70)
        XCTAssertEqual(BodyMeasure.parseWeightKg("74,5", imperial: false), 74.5)
        XCTAssertEqual(BodyMeasure.parseWeightKg("154", imperial: true), 69.9)
        for bad in ["", "abc", "29", "201"] { XCTAssertNil(BodyMeasure.parseWeightKg(bad, imperial: false), bad) }
        XCTAssertNil(BodyMeasure.parseWeightKg("60", imperial: true), "60 lb is 27 kg, below the accepted range")
    }

    // MARK: the athlete record

    /// Onboarding writes a given height into the athlete record; a blank one leaves the record alone; height never
    /// changes what is planned.
    func testAnswersWriteHeightAndNeverTouchThePlan() {
        let before = PlanInputs(profile: RiderProfile(), availability: nil, equipment: EquipmentProfile(), strengthPrefs: StrengthPrefs())
        var x = before
        var a = OnboardingAnswers(); a.heightCm = 178
        a.apply(to: &x)
        XCTAssertEqual(x.profile.heightCm, 178)
        XCTAssertFalse(x.planningDiffers(from: before), "height is not a planning input")
        var blank = OnboardingAnswers(); blank.name = "Sam"
        blank.apply(to: &x)
        XCTAssertEqual(x.profile.heightCm, 178, "an unanswered height leaves the stored one untouched")
        var bad = OnboardingAnswers(); bad.heightCm = 500
        bad.apply(to: &x)
        XCTAssertEqual(x.profile.heightCm, 178, "an out-of-range height is never stored")
    }

    /// A record written before height could be entered still reads, with no height and every other value intact.
    func testAnOlderRecordWithoutHeightStillReads() throws {
        var old = RiderProfile(); old.name = "Sam"; old.setWeight(72.5)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "heightCm")
        let read = try JSONDecoder().decode(RiderProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.heightCm); XCTAssertEqual(read.name, "Sam"); XCTAssertEqual(read.weightKg, 72.5)
        XCTAssertNil(BodyMeasure.bmi(weightKg: read.weightKg, heightCm: read.heightCm), "no height, no BMI")
    }
    func testHeightIsStoredAndReadBack() throws {
        var p = RiderProfile(); p.name = "Sam"; p.setWeight(70); p.heightCm = 175
        let read = try JSONDecoder().decode(RiderProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(read.heightCm, 175); XCTAssertEqual(read.weightKg, 70)
        XCTAssertEqual(BodyMeasure.bmi(weightKg: read.weightKg, heightCm: read.heightCm), 22.9)
    }
}
