import Testing
import Foundation
@testable import FlaunedexCore

/// The seasonal calendar: which months each fruit and vegetable is French,
/// European, a far import or out of season, and how that is put into words.
struct SaisonsTests {

    private func produce(_ id: String) throws -> Produce {
        try #require(ProduceCatalog.produce(id: id), "\(id) missing from the catalogue")
    }

    @Test func catalogueCoversAdemesCalendar() {
        #expect(ProduceCatalog.all.count >= 70)
        #expect(Set(ProduceCatalog.all.map(\.id)).count == ProduceCatalog.all.count, "ids are unique")
        for item in ProduceCatalog.all {
            #expect(item.kgCO2ePerKg > 0, "\(item.name) has a footprint")
            for months in [item.franceMonths, item.europeMonths, item.availableMonths] {
                #expect(months.allSatisfy { (1...12).contains($0) }, "\(item.name) months are 1...12")
            }
        }
    }

    @Test func tomatoIsFrenchInSummerAndSpanishInWinter() throws {
        let tomato = try produce("tomate")
        #expect(tomato.status(in: 7) == .france)
        #expect(tomato.status(in: 1) == .europe)
        #expect(tomato.status(in: 1).isSeasonal)
    }

    @Test func frenchSeasonWinsOverEurope() throws {
        // Strawberries come from Spain from January and from France in May:
        // in May and June the French harvest is what the calendar shows.
        let strawberry = try produce("fraise")
        #expect(strawberry.status(in: 2) == .europe)
        #expect(strawberry.status(in: 5) == .france)
        #expect(strawberry.status(in: 10) == .outOfSeason)
    }

    @Test func farImportsAreNeverCalledSeasonal() throws {
        let pineapple = try produce("ananas")
        #expect(pineapple.franceMonths.isEmpty)
        #expect(pineapple.status(in: 3) == .farImport)
        #expect(!pineapple.status(in: 3).isSeasonal)
        #expect(try produce("mangue").status(in: 9) == .farImport, "a flown mango is always far")
    }

    @Test func avocadoIsSpanishInWinterAndFarInSummer() throws {
        let avocado = try produce("avocat")
        #expect(avocado.status(in: 1) == .europe)
        #expect(avocado.status(in: 7) == .farImport)
    }

    @Test func bananasComeFromTheCanariesAllYear() throws {
        let banana = try produce("banane")
        #expect(banana.franceMonths.isEmpty)
        #expect((1...12).allSatisfy { banana.status(in: $0) == .europe })
    }

    @Test func seasonalListFollowsTheMonth() {
        let october = ProduceCatalog.seasonal(in: 10).map(\.id)
        #expect(october.contains("potiron"))
        #expect(october.contains("poireau"))
        #expect(!october.contains("fraise"))
        #expect(!october.contains("ananas"), "far imports are not seasonal")
        let statuses = ProduceCatalog.seasonal(in: 10).map { $0.status(in: 10) }
        #expect(statuses == statuses.sorted(), "French produce first")
    }

    @Test func plainNameDropsAdemesPrecision() throws {
        #expect(try produce("haricotvert").plainName == "Haricot vert")
        #expect(try produce("tomate").plainName == "Tomate")
    }

    // MARK: Calendar arithmetic

    @Test func runsWrapAroundNewYear() {
        let runs = SeasonCalendar.runs(of: [9, 10, 11, 12, 1, 2, 3])
        #expect(runs.count == 1)
        #expect(runs.first?.start == 9)
        #expect(runs.first?.length == 7)
    }

    @Test func runsSplitSeparateSeasons() {
        let runs = SeasonCalendar.runs(of: [4, 6, 7, 8, 9, 10, 11])
        #expect(runs.map(\.start) == [4, 6])
        #expect(runs.map(\.length) == [1, 6])
    }

    @Test func describesSeasonsInFrench() {
        #expect(SeasonCalendar.describe([9, 10, 11, 12, 1, 2, 3]) == "de septembre à mars")
        #expect(SeasonCalendar.describe([8, 9, 10, 11, 12, 1, 2, 3, 4]) == "d'août à avril")
        #expect(SeasonCalendar.describe([10]) == "en octobre")
        #expect(SeasonCalendar.describe(Set(1...12)) == "toute l'année")
        #expect(SeasonCalendar.describe([4, 6, 7, 8]) == "en avril et de juin à août")
        #expect(SeasonCalendar.describe([]) == "")
    }

    @Test func seasonStartOrdersTheCascade() throws {
        #expect(try produce("asperge").seasonStart == 4)
        #expect(try produce("carotte").seasonStart == 9, "September to March opens in September")
        #expect(try produce("cresson").seasonStart == 0, "year-round sorts first")
        #expect(try produce("ananas").seasonStart == 13, "no season sorts last")
    }

    @Test func currentMonthIsParisTime() {
        // 31 December 23:30 UTC is already January in Paris.
        let newYearsEve = Date(timeIntervalSince1970: 1_798_759_800) // 2026-12-31T23:30:00Z
        #expect(SeasonCalendar.currentMonth(newYearsEve) == 1)
    }

    // MARK: Prompts

    @Test func seasonalInstructionNamesThisMonthsProduce() {
        let text = RecipeSchema.seasonalInstruction(month: 10)
        #expect(text.contains("octobre"))
        #expect(text.contains("Paris"))
        #expect(text.contains("potiron"))
        #expect(!text.contains("fraise"), "strawberries are out of season in October")
        #expect(!text.contains("("+"cru"+")"), "ADEME's precisions stay out of the prompt")
    }

    @Test func seasonalRequestCarriesTheInstruction() {
        let seasonal = RecipeSchema.userInstruction(request: RecipeRequest(query: "une soupe", seasonalMonth: 10))
        let free = RecipeSchema.userInstruction(request: RecipeRequest(query: "une soupe"))
        #expect(seasonal.contains("octobre"))
        #expect(!free.contains("saison"))
    }
}

/// The products completed from Interfel's calendar, each with a footprint
/// from Agribalyse: real data on both counts, and named as such.
struct InterfelAdditionsTests {

    @Test func kaleHasItsWinterSeasonAndRealSources() throws {
        let kale = try #require(ProduceCatalog.produce(id: "choukale"))
        #expect(kale.name == "Chou kale")
        #expect(kale.franceMonths == [1, 2, 3, 10, 11, 12])
        #expect(kale.status(in: 11) == .france)
        #expect(kale.status(in: 7) == .outOfSeason)
        #expect(kale.seasonSource == "Calendrier Interfel (Chou kale)")
        #expect(kale.footprintSource == "Agribalyse 3.2 : Chou frisé, cru")
        #expect(abs(kale.kgCO2ePerKg - 0.713) < 0.001)
    }

    @Test func theAddedProductsAreAllThere() {
        for id in ["choukale", "chourouge", "rutabaga", "butternut", "potimarron", "chicoreefrisee",
                   "scarole", "feve", "oseille", "patatedouce", "figuedebarbarie", "amandefraiche"] {
            #expect(ProduceCatalog.produce(id: id) != nil, "\(id)")
        }
        #expect(ProduceCatalog.all.count == 88)
    }

    @Test func everyProductNamesItsSources() {
        for produce in ProduceCatalog.all {
            #expect(!produce.seasonSource.isEmpty, "\(produce.id)")
            #expect(!produce.footprintSource.isEmpty, "\(produce.id)")
        }
        let fromInterfel = ProduceCatalog.all.filter { $0.seasonSource.contains("Interfel") }
        #expect(fromInterfel.count == 12)
        for produce in fromInterfel {
            #expect(!produce.farImport, "only products found in Europe were added: \(produce.id)")
            #expect(produce.footprintSource.hasPrefix("Agribalyse 3.2 : "), "\(produce.id)")
        }
    }

    @Test func pricklyPearsComeFromSouthernEuropeNotFrance() throws {
        let pear = try #require(ProduceCatalog.produce(id: "figuedebarbarie"))
        #expect(pear.franceMonths.isEmpty)
        #expect(pear.status(in: 9) == .europe)
    }
}
