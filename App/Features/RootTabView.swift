import SwiftUI
import SwiftData
import FlaunedexCore

/// The three apps Flaunedex holds.
///
/// They share the storage, the Gemini key and the design language, but each is
/// its own small app with its own tab bar. A bar across the top of every
/// screen switches between them in one tap, each in its own colour.
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
}

enum NatureTab: Hashable { case faune, flore, capture, carte, plus }
enum CuisineTab: Hashable { case recettes, demander, saisons }
enum SavoirsTab: Hashable { case fiches, apprendre, reviser }

private struct ActiveAppKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False for an app kept alive behind the one on screen, so it can pause
    /// what shouldn't run unseen (the camera, the GPS).
    var isActiveApp: Bool {
        get { self[ActiveAppKey.self] }
        set { self[ActiveAppKey.self] = newValue }
    }
}

/// The app shell. Creates the coordinators once the model context exists, then
/// shows the app switcher above whichever app is open.
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(APIKeys.self) private var keys
    @Environment(Connectivity.self) private var connectivity

    /// The app on screen, kept across launches.
    @AppStorage("currentApp") private var storedApp = AppSection.nature.rawValue
    /// Apps opened since launch. They stay alive behind the current one, so
    /// coming back to a recipe or a card finds it where it was left.
    @State private var opened: Set<AppSection> = []
    @State private var showingSettings = false

    @State private var scan: ScanCoordinator?
    @State private var recipes: RecipeStore?
    @State private var knowledge: KnowledgeStore?

    private var current: AppSection {
        #if DEBUG
        if let screen = previewScreen, let app = Self.previewApps[screen] { return app }
        #endif
        return AppSection(rawValue: storedApp) ?? .nature
    }

    #if DEBUG
    /// Debug-only preview routing so any screen can be inspected directly:
    /// `-previewSpeciesDetail`, `-previewRecipeDetail`, or `-previewScreen <name>`
    /// with a name from `previewApps` (the whole shell) or `previewDestination`.
    @Query(sort: \Species.dexNumber) private var previewSpecies: [Species]
    @Query(sort: \Recipe.sortIndex) private var previewRecipes: [Recipe]
    @Query(sort: \KnowledgeCard.createdAt, order: .reverse) private var previewCards: [KnowledgeCard]

    private static let previewApps: [String: AppSection] = [
        "nature": .nature, "pastille": .nature,
        "cuisine": .cuisine,
        "savoirs": .savoirs, "reviser": .savoirs,
    ]

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
                        let scan = ScanCoordinator(context: context, keys: keys)
                        #if DEBUG
                        if previewScreen == "pastille" {
                            let sightings = (try? context.fetch(FetchDescriptor<Sighting>())) ?? []
                            scan.lastCapture = sightings.first { $0.status == .complete && $0.hasCoordinate }
                        }
                        #endif
                        self.scan = scan
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
        } else if let screen = previewScreen, Self.previewApps[screen] == nil {
            previewDestination(screen)
        } else {
            shell
        }
        #else
        shell
        #endif
    }

    private var shell: some View {
        VStack(spacing: 0) {
            AppSwitcherBar(current: current, select: select) {
                showingSettings = true
            }
            ZStack {
                ForEach(AppSection.allCases) { section in
                    if section == current || opened.contains(section) {
                        app(section)
                            .opacity(section == current ? 1 : 0)
                            .allowsHitTesting(section == current)
                            .accessibilityHidden(section != current)
                            .environment(\.isActiveApp, section == current)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                CaptureStatusPill()
                    .padding(.bottom, Self.tabBarClearance)
            }
        }
        .onAppear { opened.insert(current) }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") { showingSettings = false }
                        }
                    }
            }
        }
    }

    /// Height to keep free above the bottom edge for the tab bar, so the
    /// status pill floats just over it.
    private static var tabBarClearance: CGFloat {
        if #available(iOS 26.0, *) { return 70 }
        return 57
    }

    @ViewBuilder private func app(_ section: AppSection) -> some View {
        switch section {
        case .nature:
            NatureTabs(start: .faune)
        case .cuisine:
            CuisineTabs(start: .recettes)
        case .savoirs:
            #if DEBUG
            SavoirsTabs(start: previewScreen == "reviser" ? .reviser : .fiches)
            #else
            SavoirsTabs(start: .fiches)
            #endif
        }
    }

    private func select(_ section: AppSection) {
        opened.insert(section)
        withAnimation(.easeInOut(duration: 0.15)) { storedApp = section.rawValue }
    }

    #if DEBUG
    @ViewBuilder private func previewDestination(_ screen: String) -> some View {
        switch screen {
        case "flore": DexView(realm: .plant)
        case "carte": SightingsMapView()
        case "sans-position": UnlocatedSightingsView()
        case "journal": NavigationStack { JournalView() }
        case "stats": NavigationStack { StatsView() }
        case "decouvertes": NavigationStack { DiscoverView() }
        case "reglages": NavigationStack { SettingsView() }
        case "demander": NavigationStack { RecipeAskView() }
        case "saisons": NavigationStack { SeasonsView() }
        case "produit":
            if let tomato = ProduceCatalog.produce(id: "tomate") {
                NavigationStack { ProduceDetailView(produce: tomato) }
            }
        case "kale":
            if let kale = ProduceCatalog.produce(id: "choukale") {
                NavigationStack { ProduceDetailView(produce: kale) }
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
        case "fiches": NavigationStack { KnowledgeListView() }
        case "rubriques": KnowledgeCategoriesView()
        case "nouvelle-rubrique": CategoryEditorView(category: nil)
        case "apprendre": NavigationStack { KnowledgeAskView() }
        case "fiche":
            if let card = previewCards.first(where: { $0.title == "Photosynthèse" }) ?? previewCards.first {
                NavigationStack { KnowledgeCardView(card: card) }
            }
        default: DexView(realm: .animal)
        }
    }
    #endif
}

// MARK: - Switching apps

/// The bar across the top of every screen: one tab per app, in that app's
/// colour, filled for the app on screen, and the shared Réglages.
private struct AppSwitcherBar: View {
    let current: AppSection
    let select: (AppSection) -> Void
    let openSettings: () -> Void

    @Query private var cards: [KnowledgeCard]

    private var dueCount: Int {
        let now = Date.now
        return cards.filter { $0.isDue(at: now) }.count
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppSection.allCases) { section in
                Button {
                    select(section)
                } label: {
                    segment(section)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.frenchLabel)
                .accessibilityAddTraits(section == current ? .isSelected : [])
            }
            Button(action: openSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Réglages")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func segment(_ section: AppSection) -> some View {
        let selected = section == current
        return HStack(spacing: 4) {
            Image(systemName: section.symbolName)
                .font(.caption.weight(.bold))
            Text(section.frenchLabel)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .foregroundStyle(selected ? Color.white : section.tint)
        .background(selected ? section.tint : section.tint.opacity(0.12), in: Capsule())
        .overlay(alignment: .topTrailing) {
            if section == .savoirs, dueCount > 0 {
                Text("\(dueCount)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color.red, in: Capsule())
                    .offset(x: 4, y: -5)
                    .accessibilityLabel("\(dueCount) à réviser")
            }
        }
        .contentShape(Capsule())
    }
}

// MARK: - Faune & Flore

/// The field companion: collection, capture, map.
private struct NatureTabs: View {
    @Environment(ScanCoordinator.self) private var scan
    @Environment(\.isActiveApp) private var isActiveApp

    @State private var tab: NatureTab
    /// Where the shutter sends the user back to once the photo is saved.
    @State private var beforeCapture: NatureTab = .faune

    /// The camera is in front of the user, which only the tab bar knows.
    private var cameraVisible: Bool { tab == .capture && isActiveApp }

    init(start: NatureTab) {
        _tab = State(initialValue: start)
    }

    var body: some View {
        TabView(selection: $tab) {
            DexView(realm: .animal)
                .tabItem { Label("Faune", systemImage: "pawprint.fill") }
                .tag(NatureTab.faune)
            DexView(realm: .plant)
                .tabItem { Label("Flore", systemImage: "leaf.fill") }
                .tag(NatureTab.flore)
            CaptureView(isVisible: cameraVisible, onCaptured: { tab = beforeCapture })
                .tabItem { Label("Capturer", systemImage: "camera.fill") }
                .tag(NatureTab.capture)
            SightingsMapView()
                .tabItem { Label("Carte", systemImage: "map.fill") }
                .tag(NatureTab.carte)
            NatureMoreView()
                .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
                .tag(NatureTab.plus)
        }
        .tint(Theme.brand)
        .onChange(of: tab) { old, new in
            if new == .capture && old != .capture { beforeCapture = old }
        }
        .onChange(of: cameraVisible, initial: true) { _, visible in
            scan.cameraOnScreen = visible
        }
    }
}

/// The collection's pages that have no tab of their own.
private struct NatureMoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { DiscoverView() } label: {
                    Label("Découvertes", systemImage: "sparkle.magnifyingglass")
                }
                NavigationLink { JournalView() } label: {
                    Label("Journal", systemImage: "book.closed.fill")
                }
                NavigationLink { StatsView() } label: {
                    Label("Statistiques", systemImage: "chart.bar.fill")
                }
            }
            .navigationTitle("Plus")
        }
    }
}

// MARK: - Cuisine

/// The recipe bank and the seasonal calendar.
private struct CuisineTabs: View {
    @State private var tab: CuisineTab

    init(start: CuisineTab) {
        _tab = State(initialValue: start)
    }

    var body: some View {
        TabView(selection: $tab) {
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
    @State private var tab: SavoirsTab
    @Query private var cards: [KnowledgeCard]

    init(start: SavoirsTab) {
        _tab = State(initialValue: start)
    }

    private var dueCount: Int {
        let now = Date.now
        return cards.filter { $0.isDue(at: now) }.count
    }

    var body: some View {
        TabView(selection: $tab) {
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
