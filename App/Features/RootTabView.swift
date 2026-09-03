import SwiftUI
import SwiftData
import FlaunedexCore

/// The two worlds the app contains.
///
/// Flaunedex started as a field companion and now also holds a recipe bank.
/// They share the storage, the API key and the design language, but nothing
/// else: a tab bar carrying Faune, Flore, Capturer, Carte and Recettes would
/// serve neither. So the app switches wholesale between them, and remembers
/// which one you were in.
enum AppSection: String, CaseIterable {
    case nature
    case cuisine

    var frenchLabel: String {
        switch self {
        case .nature: return "Faune & Flore"
        case .cuisine: return "Cuisine"
        }
    }

    var symbolName: String {
        switch self {
        case .nature: return "leaf.fill"
        case .cuisine: return "fork.knife"
        }
    }
}

/// The app shell. Creates the two coordinators once the model context exists
/// and hands them to whichever world is on screen.
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(APIKeys.self) private var keys
    @Environment(Connectivity.self) private var connectivity

    @AppStorage("appSection") private var storedSection = AppSection.nature.rawValue

    @State private var scan: ScanCoordinator?
    @State private var recipes: RecipeStore?

    private var section: Binding<AppSection> {
        Binding(
            get: { AppSection(rawValue: storedSection) ?? .nature },
            set: { storedSection = $0.rawValue }
        )
    }

    #if DEBUG
    /// Debug-only preview routing so any screen can be inspected directly:
    /// `-previewSpeciesDetail`, or `-previewScreen <faune|flore|carte|journal|stats|decouvertes|reglages|recettes>`.
    @Query(sort: \Species.dexNumber) private var previewSpecies: [Species]
    @Query(sort: \Recipe.sortIndex) private var previewRecipes: [Recipe]

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
            if let scan, let recipes {
                content
                    .environment(scan)
                    .environment(recipes)
            } else {
                ProgressView()
                    .canvasBackground()
                    .task {
                        scan = ScanCoordinator(context: context, keys: keys)
                        recipes = RecipeStore(context: context, keys: keys)
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
            worlds
        }
        #else
        worlds
        #endif
    }

    @ViewBuilder private var worlds: some View {
        switch section.wrappedValue {
        case .nature:
            NatureTabs(section: section)
                .transition(.opacity)
        case .cuisine:
            CuisineTabs(section: section)
                .transition(.opacity)
        }
    }

    #if DEBUG
    @ViewBuilder private func previewDestination(_ screen: String) -> some View {
        switch screen {
        case "flore": DexView(realm: .plant)
        case "carte": SightingsMapView()
        case "journal": NavigationStack { JournalView() }
        case "stats": NavigationStack { StatsView() }
        case "decouvertes": NavigationStack { DiscoverView() }
        case "reglages": NavigationStack { SettingsView() }
        case "recettes", "cuisine": CuisineTabs(section: section)
        case "demander": NavigationStack { RecipeAskView() }
        default: DexView(realm: .animal)
        }
    }
    #endif
}

// MARK: - Faune & Flore

/// The original app: capture, collection, map.
private struct NatureTabs: View {
    @Binding var section: AppSection

    @Environment(ScanCoordinator.self) private var scan
    @Environment(Connectivity.self) private var connectivity

    var body: some View {
        TabView {
            DexView(realm: .animal)
                .tabItem { Label("Faune", systemImage: "pawprint.fill") }
            DexView(realm: .plant)
                .tabItem { Label("Flore", systemImage: "leaf.fill") }
            CaptureView()
                .tabItem { Label("Capturer", systemImage: "camera.fill") }
            SightingsMapView()
                .tabItem { Label("Carte", systemImage: "map.fill") }
            NatureMoreView(section: $section)
                .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
        }
        .tint(Theme.brand)
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
    }
}

/// The "Plus" tab of the nature side.
private struct NatureMoreView: View {
    @Binding var section: AppSection

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SectionSwitchRow(target: .cuisine) {
                        withAnimation { section = .cuisine }
                    }
                }
                Section {
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
                Section {
                    NavigationLink { SettingsView() } label: {
                        Label("Réglages", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("Plus")
        }
    }
}

// MARK: - Cuisine

/// The recipe bank, as its own small app.
private struct CuisineTabs: View {
    @Binding var section: AppSection

    var body: some View {
        TabView {
            NavigationStack { RecipesView() }
                .tabItem { Label("Recettes", systemImage: "book.pages.fill") }
            NavigationStack { RecipeAskView() }
                .tabItem { Label("Demander", systemImage: "sparkles") }
            CuisineMoreView(section: $section)
                .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
        }
        .tint(Theme.cuisine)
    }
}

private struct CuisineMoreView: View {
    @Binding var section: AppSection

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SectionSwitchRow(target: .nature) {
                        withAnimation { section = .nature }
                    }
                }
                Section {
                    NavigationLink { SettingsView() } label: {
                        Label("Réglages", systemImage: "gearshape.fill")
                    }
                } footer: {
                    Text("La même clé Gemini sert à identifier les espèces et à écrire les recettes.")
                }
            }
            .navigationTitle("Plus")
        }
    }
}

/// The row that moves between the two worlds. Deliberately prominent, and
/// deliberately in the same place on both sides.
private struct SectionSwitchRow: View {
    let target: AppSection
    let action: () -> Void

    private var tint: Color { target == .cuisine ? Theme.cuisine : Theme.brand }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: target.symbolName).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aller dans \(target.frenchLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(target == .cuisine ? "Votre banque de recettes" : "Votre collection d'espèces")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.footnote.weight(.bold)).foregroundStyle(tint)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
