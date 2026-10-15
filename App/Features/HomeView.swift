import SwiftUI
import SwiftData
import FlaunedexCore

/// The home screen: the three apps side by side, each with what is new in it
/// and a shortcut to the thing you most often open it for.
struct AppsHomeView: View {
    let open: (AppDestination) -> Void

    @Query(sort: \Species.firstUnlockedAt, order: .reverse) private var species: [Species]
    @Query private var sightings: [Sighting]
    @Query private var recipes: [Recipe]
    @Query private var cards: [KnowledgeCard]

    /// Pages of the home stack: Réglages, shared by the three apps, and the
    /// collection's own pages that have no tab of their own.
    enum Page: Hashable { case settings, journal, discoveries, stats }

    private let month = SeasonCalendar.currentMonth()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(today)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    natureCard
                    cuisineCard
                    savoirsCard
                }
                .padding()
            }
            .canvasBackground()
            .navigationTitle("Flaunedex")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Page.settings) {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Réglages")
                }
            }
            .navigationDestination(for: Page.self) { page in
                switch page {
                case .settings: SettingsView()
                case .journal: JournalView().tint(Theme.brand)
                case .discoveries: DiscoverView().tint(Theme.brand)
                case .stats: StatsView().tint(Theme.brand)
                }
            }
        }
        .tint(Theme.brand)
    }

    private var today: String {
        let text = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)
            .locale(Locale(identifier: "fr_FR")))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: Faune & Flore

    private var natureCard: some View {
        let latest = species.first
        return AppCard(
            section: .nature,
            stat: "\(plural(species.count, "espèce")) · \(plural(sightings.count, "observation"))",
            glimpse: latest.map { "Dernière découverte : \($0.displayName)" }
                ?? "Photographiez un animal ou une plante pour commencer.",
            primary: AppAction(title: "Capturer", symbol: "camera.fill") { open(.nature(.capture)) },
            open: { open(AppSection.nature.entry) }
        ) {
            NavigationLink(value: Page.journal) { ShortcutLabel(title: "Journal", symbol: "book.closed") }
            NavigationLink(value: Page.discoveries) { ShortcutLabel(title: "Découvertes", symbol: "sparkle.magnifyingglass") }
            NavigationLink(value: Page.stats) { ShortcutLabel(title: "Statistiques", symbol: "chart.bar") }
        }
    }

    // MARK: Cuisine

    /// What comes into season in France this month, or failing that what is
    /// in season: the reason to open the calendar today.
    private var seasonGlimpse: String {
        let previous = month == 1 ? 12 : month - 1
        let inSeason = ProduceCatalog.all.filter { $0.status(in: month) == .france }
        let arriving = inSeason.filter { $0.status(in: previous) != .france }
        let names = (arriving.isEmpty ? inSeason : arriving)
            .map(\.plainName)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard !names.isEmpty else { return "Le calendrier des fruits et légumes de saison." }
        let shown = names.prefix(4).joined(separator: ", ")
        let lead = arriving.isEmpty ? "De saison" : "Arrivent"
        return "\(lead) en \(SeasonCalendar.monthName(month)) : \(shown)\(names.count > 4 ? "…" : "")"
    }

    private var cuisineCard: some View {
        let inSeason = ProduceCatalog.all.filter { $0.status(in: month) == .france }.count
        return AppCard(
            section: .cuisine,
            stat: "\(plural(recipes.count, "recette")) · \(inSeason) fruits et légumes de saison",
            glimpse: seasonGlimpse,
            primary: AppAction(title: "Demander une recette", symbol: "sparkles") { open(.cuisine(.demander)) },
            open: { open(AppSection.cuisine.entry) }
        ) {
            Button { open(.cuisine(.saisons)) } label: { ShortcutLabel(title: "Saisons", symbol: "calendar") }
        }
    }

    // MARK: Savoirs

    private var savoirsCard: some View {
        let now = Date.now
        let due = cards.filter { $0.isDue(at: now) }.count
        let glimpse: String
        if cards.isEmpty {
            glimpse = "Demandez une fiche sur n'importe quel sujet pour commencer."
        } else if due == 0 {
            glimpse = "Tout est révisé pour aujourd'hui."
        } else {
            glimpse = "\(plural(due, "fiche")) à réviser aujourd'hui."
        }
        let primary = due > 0
            ? AppAction(title: "Réviser", symbol: "rectangle.on.rectangle.angled", perform: { open(.savoirs(.reviser)) })
            : AppAction(title: "Apprendre", symbol: "sparkles", perform: { open(.savoirs(.apprendre)) })
        return AppCard(
            section: .savoirs,
            stat: "\(plural(cards.count, "fiche")) · \(due) à réviser",
            glimpse: glimpse,
            primary: primary,
            open: { open(AppSection.savoirs.entry) }
        ) {
            if due > 0 {
                Button { open(.savoirs(.apprendre)) } label: { ShortcutLabel(title: "Apprendre", symbol: "sparkles") }
            } else {
                Button { open(.savoirs(.reviser)) } label: { ShortcutLabel(title: "Réviser", symbol: "rectangle.on.rectangle.angled") }
            }
        }
    }

    private func plural(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count > 1 ? "s" : "")"
    }
}

/// One app on the home screen. Every app gets the same card, so none reads as
/// the main one: the icon and name, a count, one line of what's new, the main
/// action, and a few shortcuts.
private struct AppCard<Shortcuts: View>: View {
    let section: AppSection
    let stat: String
    let glimpse: String
    let primary: AppAction
    let open: () -> Void
    @ViewBuilder let shortcuts: () -> Shortcuts

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(section.tint.gradient)
                                .frame(width: 46, height: 46)
                            Image(systemName: section.symbolName)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.frenchLabel)
                                .font(Theme.display(20))
                                .foregroundStyle(.primary)
                            Text(section.tagline)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(section.tint)
                    }
                    Text(stat)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(section.tint)
                    Text(glimpse)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ouvrir \(section.frenchLabel)")
            .accessibilityHint(stat)

            HStack(spacing: 8) {
                Button(action: primary.perform) {
                    Label(primary.title, systemImage: primary.symbol)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(section.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { shortcuts() }
                }
                .tint(section.tint)
            }
        }
        .padding(16)
        .cardSurface()
    }
}

/// The main action on an app card.
private struct AppAction {
    let title: String
    let symbol: String
    let perform: () -> Void
}

/// A small secondary shortcut on an app card.
private struct ShortcutLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .foregroundStyle(.tint)
    }
}
