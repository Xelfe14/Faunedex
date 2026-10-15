import SwiftUI
import SwiftData
import FlaunedexCore

/// The three apps Flaunedex holds.
///
/// They share the storage, the Gemini key and the design language, but each is
/// its own small app with its own tab bar. None is nested inside another: the
/// home screen shows all three side by side, and every app has the same
/// "Accueil" tab, first in its bar, to come back to it.
enum AppSection: String, CaseIterable, Identifiable {
    case nature
    case cuisine
    case savoirs

    var id: String { rawValue }

    var frenchLabel: String {
        switch self {
        case .nature: return "Faune & Flore"
        case .cuisine: return "Cuisine"
        case .savoirs: return "Savoirs"
        }
    }

    var tagline: String {
        switch self {
        case .nature: return "Identifier et collectionner les espèces"
        case .cuisine: return "Recettes, saisons et empreinte carbone"
        case .savoirs: return "Fiches de connaissances à réviser"
        }
    }

    var symbolName: String {
        switch self {
        case .nature: return "leaf.fill"
        case .cuisine: return "fork.knife"
        case .savoirs: return "lightbulb.fill"
        }
    }

    var tint: Color {
        switch self {
        case .nature: return Theme.brand
        case .cuisine: return Theme.cuisine
        case .savoirs: return Theme.savoirs
        }
    }

    /// Where the app opens when its card is tapped.
    var entry: AppDestination {
        switch self {
        case .nature: return .nature(.faune)
        case .cuisine: return .cuisine(.recettes)
        case .savoirs: return .savoirs(.fiches)
        }
    }
}

enum NatureTab: Hashable { case home, faune, flore, capture, carte }
enum CuisineTab: Hashable { case home, recettes, demander, saisons }
enum SavoirsTab: Hashable { case home, fiches, apprendre, reviser }

/// An app, and the tab it opens on, so the home screen's shortcuts ("Capturer",
/// "Réviser") land on the right screen.
enum AppDestination: Hashable {
    case nature(NatureTab)
    case cuisine(CuisineTab)
    case savoirs(SavoirsTab)

    var section: AppSection {
        switch self {
        case .nature: return .nature
        case .cuisine: return .cuisine
        case .savoirs: return .savoirs
        }
    }
}

/// The app shell. Creates the coordinators once the model context exists, then
/// shows the home screen or whichever app is open.
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(APIKeys.self) private var keys
    @Environment(Connectivity.self) private var connectivity

    /// The open app, kept across a relaunch by the system (not across a
    /// force-quit, which lands on the home screen as a fresh start should).
    @SceneStorage("openApp") private var storedApp = ""
    @State private var open: AppDestination?

    @State private var scan: ScanCoordinator?
    @State private var recipes: RecipeStore?
    @State private var knowledge: KnowledgeStore?

    #if DEBUG
    /// Debug-only preview routing so any screen can be inspected directly:
    /// `-previewSpeciesDetail`, `-previewRecipeDetail`, or `-previewScreen <name>`
    /// with a name from `previewDestination` below.
    @Query(sort: \Species.dexNumber) private var previewSpecies: [Species]
    @Query(sort: \Recipe.sortIndex) private var previewRecipes: [Recipe]
    @Query(sort: \KnowledgeCard.createdAt, order: .reverse) private var previewCards: [KnowledgeCard]

    private var previewScreen: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-previewScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private var wantsDetailPreview: Bool {
        CommandLine.arguments.contains("-previewSpeciesDetail")
    }
    private var wantsRecipePreview: Bool {
        CommandLine.arguments.contains("-previewRecipeDetail")
    }
    #endif

    var body: some View {
        Group {
            if let scan, let recipes, let knowledge {
                content
                    .environment(scan)
                    .environment(recipes)
                    .environment(knowledge)
                    // Captures queued offline are identified whichever app is
                    // on screen when the connection comes back.
                    .task(id: connectivity.becameOnlineTick) { await scan.processQueue() }
                    .overlay {
                        if let species = scan.newlyUnlocked {
                            NewSpeciesCelebration(species: species) {
                                withAnimation { scan.newlyUnlocked = nil }
                            }
                            .transition(.opacity)
                            .zIndex(10)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: scan.newlyUnlocked == nil)
            } else {
                ProgressView()
                    .canvasBackground()
                    .task {
                        open = AppSection(rawValue: storedApp)?.entry
                        scan = ScanCoordinator(context: context, keys: keys)
                        recipes = RecipeStore(context: context, keys: keys)
                        knowledge = KnowledgeStore(context: context, keys: keys)
                    }
            }
        }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if wantsRecipePreview, let first = previewRecipes.first {
            NavigationStack { RecipeDetailView(recipe: first) }
        } else if wantsDetailPreview, let first = previewSpecies.first {
            NavigationStack { SpeciesDetailView(species: first) }
        } else if let screen = previewScreen {
            previewDestination(screen)
        } else {
            apps
        }
        #else
        apps
        #endif
    }

    @ViewBuilder private var apps: some View {
        Group {
            switch open {
            case nil:
                AppsHomeView(open: show)
            case .nature(let tab):
                NatureTabs(start: tab, goHome: goHome)
            case .cuisine(let tab):
                CuisineTabs(start: tab, goHome: goHome)
            case .savoirs(let tab):
                SavoirsTabs(start: tab, goHome: goHome)
            }
        }
        .transition(.opacity)
    }

    private func show(_ destination: AppDestination) {
        withAnimation(.easeInOut(duration: 0.2)) { open = destination }
        storedApp = destination.section.rawValue
    }

    private func goHome() {
        withAnimation(.easeInOut(duration: 0.2)) { open = nil }
        storedApp = ""
    }

    #if DEBUG
    @ViewBuilder private func previewDestination(_ screen: String) -> some View {
        switch screen {
        case "accueil": AppsHomeView(open: { _ in })
        case "nature": NatureTabs(start: .faune, goHome: {})
        case "flore": DexView(realm: .plant)
        case "carte": SightingsMapView()
        case "journal": NavigationStack { JournalView() }
        case "stats": NavigationStack { StatsView() }
        case "decouvertes": NavigationStack { DiscoverView() }
        case "reglages": NavigationStack { SettingsView() }
        case "recettes", "cuisine": CuisineTabs(start: .recettes, goHome: {})
        case "demander": NavigationStack { RecipeAskView() }
        case "saisons": NavigationStack { SeasonsView() }
        case "produit":
            if let tomato = ProduceCatalog.produce(id: "tomate") {
                NavigationStack { ProduceDetailView(produce: tomato) }
            }
        case "impact":
            // The footprint section alone, on the sample recipe with the most
            // to say: a heavy meat, and an ingredient with no data.
            if let recipe = previewRecipes.first(where: { $0.title.contains("Blanquette") }) ?? previewRecipes.first {
                NavigationStack {
                    List {
                        RecipeImpactSection(
                            footprint: RecipeFootprint(ingredients: recipe.ingredients),
                            servings: recipe.servings, canAskLighter: true, isWorking: false,
                            askLighter: {}
                        )
                    }
                    .navigationTitle(recipe.title)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        case "savoirs", "fiches": SavoirsTabs(start: .fiches, goHome: {})
        case "apprendre": NavigationStack { KnowledgeAskView() }
        case "reviser": SavoirsTabs(start: .reviser, goHome: {})
        case "fiche":
            if let card = previewCards.first(where: { $0.title == "Photosynthèse" }) ?? previewCards.first {
                NavigationStack { KnowledgeCardView(card: card) }
            }
        default: DexView(realm: .animal)
        }
    }
    #endif
}

// MARK: - The way home

/// The first tab of every app. Selecting it doesn't show a page: it returns to
/// the home screen, so the three apps are always one tap from each other.
private struct HomeTabContent: View {
    var body: some View {
        Theme.canvas.ignoresSafeArea()
    }
}

private extension View {
    func homeTabItem() -> some View {
        tabItem { Label("Accueil", systemImage: "house.fill") }
    }
}

/// A tab selection that sends the "Accueil" tab home instead of selecting it.
private func homeAware<Tab: Hashable>(_ tab: Binding<Tab>, home: Tab, goHome: @escaping () -> Void) -> Binding<Tab> {
    Binding(
        get: { tab.wrappedValue },
        set: { newValue in
            if newValue == home { goHome() } else { tab.wrappedValue = newValue }
        }
    )
}

// MARK: - Faune & Flore

/// The field companion: collection, capture, map.
private struct NatureTabs: View {
    let goHome: () -> Void
    @State private var tab: NatureTab

    init(start: NatureTab, goHome: @escaping () -> Void) {
        _tab = State(initialValue: start == .home ? .faune : start)
        self.goHome = goHome
    }

    var body: some View {
        TabView(selection: homeAware($tab, home: .home, goHome: goHome)) {
            HomeTabContent()
                .homeTabItem()
                .tag(NatureTab.home)
            DexView(realm: .animal)
                .tabItem { Label("Faune", systemImage: "pawprint.fill") }
                .tag(NatureTab.faune)
            DexView(realm: .plant)
                .tabItem { Label("Flore", systemImage: "leaf.fill") }
                .tag(NatureTab.flore)
            CaptureView()
                .tabItem { Label("Capturer", systemImage: "camera.fill") }
                .tag(NatureTab.capture)
            SightingsMapView()
                .tabItem { Label("Carte", systemImage: "map.fill") }
                .tag(NatureTab.carte)
        }
        .tint(Theme.brand)
    }
}

// MARK: - Cuisine

/// The recipe bank and the seasonal calendar.
private struct CuisineTabs: View {
    let goHome: () -> Void
    @State private var tab: CuisineTab

    init(start: CuisineTab, goHome: @escaping () -> Void) {
        _tab = State(initialValue: start == .home ? .recettes : start)
        self.goHome = goHome
    }

    var body: some View {
        TabView(selection: homeAware($tab, home: .home, goHome: goHome)) {
            HomeTabContent()
                .homeTabItem()
                .tag(CuisineTab.home)
            NavigationStack { RecipesView() }
                .tabItem { Label("Recettes", systemImage: "book.pages.fill") }
                .tag(CuisineTab.recettes)
            NavigationStack { RecipeAskView() }
                .tabItem { Label("Demander", systemImage: "sparkles") }
                .tag(CuisineTab.demander)
            NavigationStack { SeasonsView() }
                .tabItem { Label("Saisons", systemImage: "calendar") }
                .tag(CuisineTab.saisons)
        }
        .tint(Theme.cuisine)
    }
}

// MARK: - Savoirs

/// The knowledge cards: the collection, asking for a new one, and review.
private struct SavoirsTabs: View {
    let goHome: () -> Void
    @State private var tab: SavoirsTab
    @Query private var cards: [KnowledgeCard]

    init(start: SavoirsTab, goHome: @escaping () -> Void) {
        _tab = State(initialValue: start == .home ? .fiches : start)
        self.goHome = goHome
    }

    private var dueCount: Int {
        let now = Date.now
        return cards.filter { $0.isDue(at: now) }.count
    }

    var body: some View {
        TabView(selection: homeAware($tab, home: .home, goHome: goHome)) {
            HomeTabContent()
                .homeTabItem()
                .tag(SavoirsTab.home)
            NavigationStack { KnowledgeListView() }
                .tabItem { Label("Fiches", systemImage: "rectangle.stack.fill") }
                .tag(SavoirsTab.fiches)
            NavigationStack { KnowledgeAskView() }
                .tabItem { Label("Apprendre", systemImage: "sparkles") }
                .tag(SavoirsTab.apprendre)
            NavigationStack { KnowledgeReviewView() }
                .tabItem { Label("Réviser", systemImage: "rectangle.on.rectangle.angled") }
                .badge(dueCount)
                .tag(SavoirsTab.reviser)
        }
        .tint(Theme.savoirs)
    }
}
