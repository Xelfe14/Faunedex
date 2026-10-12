import SwiftUI
import FlaunedexCore

/// Layout constants shared by the header and the rows, so the twelve month
/// columns line up from top to bottom.
enum SeasonGrid {
    static let nameWidth: CGFloat = 112
    static let spacing: CGFloat = 2
}

/// The seasonal calendar: every fruit and vegetable ADEME tracks, one row each,
/// twelve months across, coloured by where it comes from in each month.
///
/// Nothing is hidden by default: far imports stay in, greyed, because the
/// choice at the market is the cook's. The month starts on today in Paris and
/// can be moved by tapping a letter in the header, to plan ahead.
struct SeasonsView: View {
    @State private var month = SeasonCalendar.currentMonth()
    @State private var category: ProduceCategory?
    @State private var onlySeasonal = false
    @State private var sortByName = false
    @State private var search = ""

    private let thisMonth = SeasonCalendar.currentMonth()

    /// Names ADEME uses twice ("Mangue" by air and by sea), which therefore
    /// keep their precision in the row.
    private let ambiguousNames: Set<String> = {
        let names = ProduceCatalog.all.map(\.plainName)
        return Set(names.filter { name in names.filter { $0 == name }.count > 1 })
    }()

    private var items: [Produce] {
        var list = ProduceCatalog.all
        if let category { list = list.filter { $0.category == category } }
        if onlySeasonal { list = list.filter { $0.status(in: month).isSeasonal } }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { list = list.filter { $0.name.localizedStandardContains(query) } }
        if sortByName {
            return list.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        return list.sorted { ($0.seasonStart, $0.name) < ($1.seasonStart, $1.name) }
    }

    private var groups: [(category: ProduceCategory, rows: [Produce])] {
        let current = items
        return ProduceCategory.allCases.compactMap { category in
            let rows = current.filter { $0.category == category }
            return rows.isEmpty ? nil : (category: category, rows: rows)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                controls
                SeasonLegend()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.category) { group in
                    Section {
                        ForEach(group.rows) { produce in
                            NavigationLink(value: produce) {
                                ProduceRow(produce: produce, month: month,
                                           showsPrecision: ambiguousNames.contains(produce.plainName))
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    } header: {
                        MonthHeader(title: group.category.frenchLabel, month: $month, thisMonth: thisMonth)
                    }
                }
            }

            if groups.isEmpty {
                ContentUnavailableView("Rien ne correspond", systemImage: "leaf",
                                       description: Text("Changez de mois ou de filtre."))
                    .padding(.top, 40)
            }

            Text("Saison en France : calendrier de l'ADEME (Impact CO2). Europe du Sud, imports et origines : estimation indicative. Empreinte par kilo : Agribalyse 3.2.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding()
        }
        .canvasBackground()
        .navigationTitle("Saisons")
        .searchable(text: $search, prompt: "Un fruit, un légume…")
        .navigationDestination(for: Produce.self) { ProduceDetailView(produce: $0) }
        .tint(Theme.cuisine)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Catégorie", selection: $category) {
                Text("Tout").tag(ProduceCategory?.none)
                ForEach(ProduceCategory.allCases, id: \.self) { category in
                    // "Fruits à coque" doesn't fit a quarter of an iPhone XS.
                    Text(category == .nut ? "À coque" : category.frenchLabel)
                        .tag(ProduceCategory?.some(category))
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $onlySeasonal) {
                Text("Seulement ce qui est de saison en \(SeasonCalendar.monthName(month))")
                    .font(.subheadline)
            }

            HStack {
                Menu {
                    Picker("Trier", selection: $sortByName) {
                        Text("Par début de saison").tag(false)
                        Text("Par nom").tag(true)
                    }
                } label: {
                    Label(sortByName ? "Par nom" : "Par début de saison",
                          systemImage: "arrow.up.arrow.down")
                        .font(.subheadline)
                }
                Spacer()
                if month != thisMonth {
                    Button("Revenir en \(SeasonCalendar.monthName(thisMonth))") { month = thisMonth }
                        .font(.subheadline)
                }
            }
        }
    }
}

/// The pinned header of a calendar section: the shelf's name, then one letter
/// per month. Tapping a letter moves the highlighted month.
struct MonthHeader: View {
    let title: String
    @Binding var month: Int
    let thisMonth: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(width: SeasonGrid.nameWidth, alignment: .leading)
            HStack(spacing: SeasonGrid.spacing) {
                ForEach(1...12, id: \.self) { m in
                    Button {
                        month = m
                    } label: {
                        Text(SeasonCalendar.monthInitials[m - 1])
                            .font(.caption2.weight(m == month ? .heavy : (m == thisMonth ? .semibold : .regular)))
                            .foregroundStyle(m == month ? Theme.cuisine : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background {
                                if m == month { Capsule().fill(Theme.cuisine.opacity(0.15)) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SeasonCalendar.monthName(m))
                    .accessibilityAddTraits(m == month ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Theme.canvas)
    }
}

/// One line of the calendar: the name and its footprint per kilo, then the
/// twelve months.
struct ProduceRow: View {
    let produce: Produce
    let month: Int
    var showsPrecision = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(produce.plainName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if showsPrecision, produce.name != produce.plainName {
                    Text(produce.name.dropFirst(produce.plainName.count)
                        .trimmingCharacters(in: CharacterSet(charactersIn: " ()")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(CarbonComparison.formatPerKilo(produce.kgCO2ePerKg))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.impact(.perKilo(produce.kgCO2ePerKg)))
            }
            .frame(width: SeasonGrid.nameWidth, alignment: .leading)
            SeasonBar(produce: produce, highlight: month)
        }
        .padding(.horizontal)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

/// Twelve cells, one per month, coloured by season status.
struct SeasonBar: View {
    let produce: Produce
    var highlight: Int?
    var height: CGFloat = 16

    var body: some View {
        HStack(spacing: SeasonGrid.spacing) {
            ForEach(1...12, id: \.self) { m in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.seasonFill(produce.status(in: m)))
                    .frame(height: height)
                    .overlay {
                        if m == highlight {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SeasonSummary.sentence(for: produce))
    }
}

/// What the colours mean.
struct SeasonLegend: View {
    var body: some View {
        FlowRow(spacing: 10) {
            ForEach([SeasonStatus.france, .europe, .farImport, .outOfSeason], id: \.self) { status in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.seasonFill(status))
                        .frame(width: 14, height: 10)
                    Text(SeasonSummary.shortLabel(status))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small pictogram for an ingredient's season this month.
struct SeasonBadge: View {
    let status: SeasonStatus
    var showsLabel = false

    var body: some View {
        Label(status.frenchLabel, systemImage: SeasonSummary.symbol(status))
            .labelStyle(BadgeLabelStyle(showsTitle: showsLabel))
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.seasonInk(status))
            .accessibilityLabel(status.frenchLabel)
    }

    private struct BadgeLabelStyle: LabelStyle {
        let showsTitle: Bool
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 4) {
                configuration.icon
                if showsTitle { configuration.title }
            }
        }
    }
}

/// Words and symbols for season statuses, shared by the calendar, the detail
/// screen and the recipe card.
enum SeasonSummary {
    static func shortLabel(_ status: SeasonStatus) -> String {
        switch status {
        case .france: return "France"
        case .europe: return "Europe du Sud"
        case .farImport: return "Import lointain"
        case .outOfSeason: return "Hors saison"
        }
    }

    static func symbol(_ status: SeasonStatus) -> String {
        switch status {
        case .france: return "leaf.fill"
        case .europe: return "sun.max.fill"
        case .farImport: return "airplane"
        case .outOfSeason: return "calendar.badge.exclamationmark"
        }
    }

    /// "En France de septembre à mars ; en Europe du Sud d'octobre à mai."
    static func sentence(for produce: Produce) -> String {
        var parts: [String] = []
        let france = SeasonCalendar.describe(produce.franceMonths)
        if !france.isEmpty { parts.append("En France \(france)") }
        let europe = SeasonCalendar.describe(produce.europeMonths.subtracting(produce.franceMonths))
        if !europe.isEmpty { parts.append("en Europe du Sud \(europe)") }
        if produce.farImport { parts.append("sinon importé de loin") }
        return parts.isEmpty ? "Pas de saison connue" : parts.joined(separator: " ; ")
    }
}
