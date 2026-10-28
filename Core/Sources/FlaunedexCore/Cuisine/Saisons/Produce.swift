import Foundation

/// The three shelves of the seasonal calendar.
public enum ProduceCategory: String, Sendable, CaseIterable, Hashable {
    case vegetable
    case fruit
    case nut

    public var frenchLabel: String {
        switch self {
        case .vegetable: return "Légumes"
        case .fruit: return "Fruits"
        case .nut: return "Fruits à coque"
        }
    }
}

/// Where a fruit or vegetable comes from in a given month, seen from Paris.
///
/// Ordered from closest to farthest, which is also the order the calendar
/// prefers: a month counts as French before it counts as Spanish.
public enum SeasonStatus: Int, Sendable, CaseIterable, Comparable {
    /// Harvested in metropolitan France this month.
    case france
    /// Not from France this month, but from Spain, Italy, Portugal or Greece.
    case europe
    /// On sale, but only because it is shipped or flown from outside Europe.
    case farImport
    /// Not in season anywhere close.
    case outOfSeason

    public static func < (lhs: SeasonStatus, rhs: SeasonStatus) -> Bool { lhs.rawValue < rhs.rawValue }

    public var frenchLabel: String {
        switch self {
        case .france: return "De saison en France"
        case .europe: return "De saison en Europe du Sud"
        case .farImport: return "Importé de loin"
        case .outOfSeason: return "Hors saison"
        }
    }

    /// In season somewhere within reach: France or Southern Europe.
    public var isSeasonal: Bool { self == .france || self == .europe }
}

/// One fruit or vegetable of the seasonal calendar.
///
/// The French months and the footprint come from ADEME's Impact CO2 calendar,
/// or, for the products it lacks, from Interfel's calendar and Agribalyse; each
/// row names its own sources. The Southern Europe months, the far-import flag,
/// the origins and the note are curated by hand and only indicative, and the
/// app says so.
public struct Produce: Sendable, Identifiable, Hashable {
    /// The Impact CO2 slug, stable across releases.
    public let id: String
    public let name: String
    public let category: ProduceCategory
    /// Months harvested in metropolitan France (1 = January).
    public let franceMonths: Set<Int>
    /// Months Southern Europe supplies it in quantity.
    public let europeMonths: Set<Int>
    /// Months ADEME lists it as available at all. For a far import, the months
    /// outside `europeMonths` where it is still sold.
    public let availableMonths: Set<Int>
    /// Essentially only reaches Paris from outside Europe.
    public let farImport: Bool
    public let origins: String?
    public let note: String?
    /// Carbon footprint as sold in France, kg CO2e per kg.
    public let kgCO2ePerKg: Double
    /// Where the French months come from.
    public let seasonSource: String
    /// Where the footprint comes from.
    public let footprintSource: String

    public init(id: String, name: String, category: ProduceCategory,
                franceMonths: Set<Int>, europeMonths: Set<Int>, availableMonths: Set<Int>,
                farImport: Bool, origins: String?, note: String?, kgCO2ePerKg: Double,
                seasonSource: String = "Calendrier de l’ADEME (Impact CO2)",
                footprintSource: String = "Impact CO2 (ADEME), Agribalyse 3.2") {
        self.id = id
        self.name = name
        self.category = category
        self.franceMonths = franceMonths
        self.europeMonths = europeMonths
        self.availableMonths = availableMonths
        self.farImport = farImport
        self.origins = origins
        self.note = note
        self.kgCO2ePerKg = kgCO2ePerKg
        self.seasonSource = seasonSource
        self.footprintSource = footprintSource
    }

    public static func == (lhs: Produce, rhs: Produce) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Where it comes from in `month` (1...12).
    public func status(in month: Int) -> SeasonStatus {
        if franceMonths.contains(month) { return .france }
        if europeMonths.contains(month) { return .europe }
        if farImport && availableMonths.contains(month) { return .farImport }
        return .outOfSeason
    }

    /// The name without ADEME's precision in brackets: "Haricot vert" rather
    /// than "Haricot vert (cru)". What a prompt or a sentence should say.
    public var plainName: String {
        guard let bracket = name.firstIndex(of: "(") else { return name }
        return name[..<bracket].trimmingCharacters(in: .whitespaces)
    }

    /// The month the main season opens, for sorting the calendar into a
    /// cascade. French season first, then the European one; a year-round item
    /// sorts first and one with no season at all sorts last.
    public var seasonStart: Int {
        let months = franceMonths.isEmpty ? europeMonths : franceMonths
        if months.count == 12 { return 0 }
        return SeasonCalendar.runs(of: months).max { $0.length < $1.length }?.start ?? 13
    }
}

/// The seasonal calendar: every fruit and vegetable ADEME tracks.
public enum ProduceCatalog {
    private static let byID: [String: Produce] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func produce(id: String) -> Produce? { byID[id] }

    /// What is in season within reach this month, French first.
    public static func seasonal(in month: Int) -> [Produce] {
        all.filter { $0.status(in: month).isSeasonal }
            .sorted { ($0.status(in: month), $0.name) < ($1.status(in: month), $1.name) }
    }
}

/// French month names and the arithmetic of seasons that wrap around New Year.
public enum SeasonCalendar {
    public static let monthNames = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre",
    ]
    /// One letter per month, for the calendar's header row.
    public static let monthInitials = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]

    public static func monthName(_ month: Int) -> String {
        monthNames[(month - 1 + 120) % 12]
    }

    /// The current month in Paris, 1...12.
    public static func currentMonth(_ date: Date = .now) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar.component(.month, from: date)
    }

    /// Contiguous stretches of months, wrapping from December into January:
    /// September to March is one season, not two.
    public static func runs(of months: Set<Int>) -> [(start: Int, length: Int)] {
        let valid = months.filter { (1...12).contains($0) }
        if valid.count == 12 { return [(1, 12)] }
        let previous = { (m: Int) in m == 1 ? 12 : m - 1 }
        let next = { (m: Int) in m == 12 ? 1 : m + 1 }
        return valid.sorted()
            .filter { !valid.contains(previous($0)) }
            .map { start in
                var length = 1
                var month = start
                while valid.contains(next(month)) && length < 12 {
                    month = next(month)
                    length += 1
                }
                return (start, length)
            }
    }

    /// "de septembre à mars", "en octobre", "d'avril à juin et d'août à
    /// octobre", "toute l'année". Empty when there are no months.
    public static func describe(_ months: Set<Int>) -> String {
        let runs = runs(of: months)
        guard !runs.isEmpty else { return "" }
        if runs.count == 1 && runs[0].length == 12 { return "toute l'année" }
        return runs.map { run in
            let start = monthName(run.start)
            guard run.length > 1 else { return "en \(start)" }
            let end = monthName(run.start + run.length - 1)
            return "\(elidedDe(start)) à \(end)"
        }.joined(separator: " et ")
    }

    /// "de mars" but "d'avril", "d'août", "d'octobre".
    static func elidedDe(_ word: String) -> String {
        guard let first = word.first else { return "de" }
        return "aeiouyâéè".contains(first) ? "d'\(word)" : "de \(word)"
    }
}
