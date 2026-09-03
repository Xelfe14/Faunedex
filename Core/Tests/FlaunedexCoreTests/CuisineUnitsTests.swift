import Testing
import Foundation
@testable import FlaunedexCore

/// The promise of the cooking section is that a quantity is always usable in a
/// European kitchen. That promise is only as good as these conversions, so each
/// factor is pinned rather than trusted.
struct MetricUnitTests {

    @Test func abbreviationsNeverTakeAPlural() {
        #expect(MetricUnit.gram.label(quantity: 150) == "g")
        #expect(MetricUnit.milliliter.label(quantity: 500) == "ml")
        #expect(MetricUnit.tablespoon.label(quantity: 3) == "c. à soupe")
        #expect(MetricUnit.teaspoon.label(quantity: 2) == "c. à café")
    }

    @Test func countableUnitsPluraliseAboveOne() {
        #expect(MetricUnit.clove.label(quantity: 1) == "gousse")
        #expect(MetricUnit.clove.label(quantity: 3) == "gousses")
        #expect(MetricUnit.slice.label(quantity: 2) == "tranches")
        #expect(MetricUnit.pinch.label(quantity: 1) == "pincée")
        #expect(MetricUnit.leaf.label(quantity: 4) == "feuilles")
    }

    @Test func fractionalQuantityStaysSingular() {
        #expect(MetricUnit.clove.label(quantity: 0.5) == "gousse")
        #expect(MetricUnit.piece.label(quantity: nil) == "pièce")
    }

    @Test func dimensionsSeparateMassFromVolume() {
        #expect(MetricUnit.gram.dimension == .mass)
        #expect(MetricUnit.kilogram.dimension == .mass)
        #expect(MetricUnit.milliliter.dimension == .volume)
        #expect(MetricUnit.tablespoon.dimension == .volume)
        #expect(MetricUnit.clove.dimension == .count)
    }
}

struct MetricConversionTests {

    // MARK: Recognising units

    @Test func frenchSpellingsResolveRegardlessOfAccentsAndCase() {
        #expect(MetricConversion.unit(for: "Cuillère à soupe") == .tablespoon)
        #expect(MetricConversion.unit(for: "cuillere a soupe") == .tablespoon)
        #expect(MetricConversion.unit(for: "c. à café") == .teaspoon)
        #expect(MetricConversion.unit(for: "C.A.C") == .teaspoon)
        #expect(MetricConversion.unit(for: "GRAMMES") == .gram)
        #expect(MetricConversion.unit(for: "pincées") == .pinch)
    }

    @Test func unknownUnitIsNotGuessed() {
        #expect(MetricConversion.unit(for: "poignée") == nil)
        #expect(MetricConversion.unit(for: "") == nil)
        #expect(MetricConversion.unit(for: nil) == nil)
    }

    // MARK: Imperial to metric

    @Test func ouncesBecomeGrams() {
        let converted = MetricConversion.toMetric(quantity: 8, unit: "oz")
        #expect(converted?.unit == .gram)
        // 8 oz is 226.796 g, rounded to the nearest 5 for a kitchen scale.
        #expect(converted?.quantity == 225)
    }

    @Test func poundsBecomeGrams() {
        let converted = MetricConversion.toMetric(quantity: 1, unit: "lb")
        #expect(converted?.unit == .gram)
        #expect(converted?.quantity == 455, "453.59 g rounds to the nearest 5")
    }

    @Test func cupsBecomeMillilitres() {
        let converted = MetricConversion.toMetric(quantity: 2, unit: "cups")
        #expect(converted?.unit == .milliliter)
        #expect(converted?.quantity == 475, "2 US cups is 473.18 ml")
    }

    @Test func spoonsMapToTheFrenchSpoonsRatherThanBeingConverted() {
        #expect(MetricConversion.toMetric(quantity: 2, unit: "tbsp")?.unit == .tablespoon)
        #expect(MetricConversion.toMetric(quantity: 2, unit: "tbsp")?.quantity == 2)
        #expect(MetricConversion.toMetric(quantity: 1, unit: "teaspoon")?.unit == .teaspoon)
    }

    @Test func aStickOfButterIsAWeight() {
        #expect(MetricConversion.toMetric(quantity: 1, unit: "stick")?.unit == .gram)
        #expect(MetricConversion.toMetric(quantity: 1, unit: "stick")?.quantity == 115)
    }

    @Test func metricInputPassesThroughUnchanged() {
        let converted = MetricConversion.toMetric(quantity: 150, unit: "g")
        #expect(converted?.unit == .gram)
        #expect(converted?.quantity == 150)
    }

    @Test func unrecognisedUnitConvertsToNothing() {
        #expect(MetricConversion.toMetric(quantity: 1, unit: "poignée") == nil)
        #expect(MetricConversion.toMetric(quantity: 1, unit: nil) == nil)
    }

    // MARK: Rounding

    @Test func roundingFollowsTheSizeOfTheNumber() {
        #expect(MetricConversion.cookingRounded(453.59237) == 455, "nearest 5 above 100")
        #expect(MetricConversion.cookingRounded(28.35) == 28, "nearest whole between 10 and 100")
        #expect(MetricConversion.cookingRounded(2.47) == 2.5, "one decimal below 10")
        #expect(MetricConversion.cookingRounded(0.5) == 0.5)
    }

    // MARK: Temperature

    @Test func fahrenheitBecomesAnOvenSettableCelsius() {
        #expect(MetricConversion.celsius(fromFahrenheit: 350) == 175)
        #expect(MetricConversion.celsius(fromFahrenheit: 400) == 205)
        #expect(MetricConversion.celsius(fromFahrenheit: 212) == 100)
        #expect(MetricConversion.celsius(fromFahrenheit: 32) == 0)
    }

    @Test func fahrenheitInsideAStepIsRewritten() {
        let rewritten = MetricConversion.normalizeTemperatures(in: "Preheat the oven to 350°F and bake.")
        #expect(rewritten == "Preheat the oven to 175 °C and bake.")
    }

    @Test func severalTemperaturesInOneStepAreAllRewritten() {
        let rewritten = MetricConversion.normalizeTemperatures(
            in: "Start at 450 °F, then lower to 325 degrees F."
        )
        #expect(rewritten.contains("230 °C"))
        #expect(rewritten.contains("165 °C"))
        #expect(!rewritten.lowercased().contains("f."), "no Fahrenheit marker survives")
    }

    @Test func celsiusIsLeftAlone() {
        let text = "Préchauffer le four à 180 °C."
        #expect(MetricConversion.normalizeTemperatures(in: text) == text)
    }

    @Test func aBareNumberIsNotMistakenForATemperature() {
        let text = "Ajouter 150 g de farine."
        #expect(MetricConversion.normalizeTemperatures(in: text) == text)
    }
}

struct FormattingTests {

    @Test func numbersAreWrittenTheFrenchWay() {
        #expect(Formatting.number(150) == "150")
        #expect(Formatting.number(0.5) == "0,5")
        #expect(Formatting.number(1.25) == "1,25")
        #expect(Formatting.number(2.0) == "2")
    }

    @Test func numbersAreReadBackFromEveryFormAPersonMightType() {
        #expect(Formatting.parseNumber("150") == 150)
        #expect(Formatting.parseNumber("0,5") == 0.5)
        #expect(Formatting.parseNumber("0.5") == 0.5)
        #expect(Formatting.parseNumber("1/2") == 0.5)
        #expect(Formatting.parseNumber("1 1/2") == 1.5)
        #expect(Formatting.parseNumber("sucre") == nil)
        #expect(Formatting.parseNumber("") == nil)
    }

    @Test func durationsRenderAsHoursAndMinutes() {
        #expect(Formatting.duration(minutes: 45) == "45 min")
        #expect(Formatting.duration(minutes: 60) == "1 h")
        #expect(Formatting.duration(minutes: 80) == "1 h 20")
        #expect(Formatting.duration(minutes: 120) == "2 h")
    }

    @Test func durationsRoundTripThroughTheirOwnText() {
        for minutes in [5, 45, 60, 80, 90, 120, 155] {
            let text = Formatting.duration(minutes: minutes)
            #expect(Formatting.parseDuration(text) == minutes, "\(text) should read back as \(minutes)")
        }
    }

    @Test func durationParsingRequiresATimeUnit() {
        #expect(Formatting.parseDuration("100 g") == nil, "a weight is not a duration")
        #expect(Formatting.parseDuration("chocolat") == nil)
        #expect(Formatting.parseDuration("100 g de chocolat") == nil,
                "the h inside 'chocolat' must not read as hours")
        #expect(Formatting.parseDuration("90") == nil, "a bare number carries no unit")
    }

    @Test func durationParsingAcceptsTheSpellingsPeopleUse() {
        #expect(Formatting.parseDuration("30 minutes") == 30)
        #expect(Formatting.parseDuration("30 mn") == 30)
        #expect(Formatting.parseDuration("1h20") == 80)
        #expect(Formatting.parseDuration("2 heures") == 120)
        #expect(Formatting.parseDuration("1 heure 30") == 90)
    }
}
