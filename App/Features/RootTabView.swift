import SwiftUI
import SwiftData
import FlaunedexCore

/// The worlds the app contains.
///
/// Flaunedex started as a field companion, then gained a recipe bank and a
/// set of knowledge cards. They share the storage and the design language, but
/// nothing else: a tab bar carrying Faune, Flore, Capturer, Carte, Recettes and
/// Dossiers would serve none of them. So the app switches wholesale between
/// worlds, and remembers which one you were in.
enum AppSection: String, CaseIterable {
    case nature
    case cuisine
    case knowledge

    var frenchLabel: String {
        switch self {
        case .nature: return "Faune & Flore"
        case .cuisine: return "Cuisine"
        case .knowledge: return "Savoirs"
        }
    }

    var symbolName: String {
        switch self {
        case .nature: return "leaf.fill"
        case .cuisine: return "fork.knife"
        case .knowledge: return "brain.head.profile"
        }
    }

    var tint: Color {
        switch self {
        case .nature: return Theme.brand
        case .cuisine: return Theme.cuisine
        case .knowledge: return Theme.knowledge
        }
    }

    var subtitle: String {
        switch self {
        case .nature: return "Votre collection d'espèces"
        case .cuisine: return "Votre banque de recettes"
        case .knowledge: return "Vos cartes à réviser"
        }
    }
}

/// The app shell. Creates the coordinators once the model context exists and
/// hands them to whichever world is on screen.
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(APIKeys.self) private var keys
    @Environment(Connectivity.self) private var connectivity

    @AppStorage("appSection") private var storedSection = AppSection.nature.rawValue

    @State private var scan: ScanCoordinator?
    @State private var recipes: RecipeStore?
    @State private var knowledge: KnowledgeStore?

    private var section: Binding<AppSection> {
        Binding(
            get: { AppSection(rawValue: storedSection) ?? .nature },
            set: { storedSection = $0.rawValue }
        )
    }

    #if DEBUG
    /// Debug-only preview routing so any screen can be inspected directly:
    /// `-previewSpeciesDetail`, `-previewRecipeDetail`, or `-previewScreen <route>`, where the route is one
    /// of faune, flore, carte, journal, stats, decouvertes, reglages, recettes (or cuisine), demander,
    /// savoirs, dossier-savoir, reviser, session-savoirs, carte-savoir, editeur-savoir. The Savoirs routes
    /// accept `-previewFolder <nom>` to narrow them to one folder; session-savoirs also accepts
    /// `-previewVersoFirst`.
    @Query(sort: \Species.dexNumber) private var previewSpecies: [Species]
    @Query(sort: \Recipe.sortIndex) private var previewRecipes: [Recipe]
    @Query(sort: \KnowledgeCard.createdAt) private var previewCards: [KnowledgeCard]
    @Query private var previewFolders: [KnowledgeFolder]

    private var previewFolder: KnowledgeFolder? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-previewFolder"), i + 1 < args.count else { return nil }
        return previewFolders.first { $0.name == args[i + 1] }
    }

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
            } else {
                ProgressView()
                    .canvasBackground()
                    .task {
                        scan = ScanCoordinator(context: context, keys: keys)
                        recipes = RecipeStore(context: context, keys: keys)
                        knowledge = KnowledgeStore(context: context)
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
        case .knowledge:
            KnowledgeTabs(section: section)
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
        case "savoirs": KnowledgeTabs(section: section)
        // The Savoirs screens get the tint the real tab bar gives them, so what
        // a preview shows is what the app shows.
        case "dossier-savoir":
            NavigationStack { FolderContentView(folder: previewFolder) }
                .tint(Theme.knowledge)
        case "reviser":
            NavigationStack {
                ReviewSetupView(initialScope: previewFolder.map { .folder($0.id) } ?? .all)
            }
            .tint(Theme.knowledge)
        case "session-savoirs": previewSession
        case "carte-savoir":
            if let card = previewCards.first(where: { previewFolder == nil || $0.folder?.id == previewFolder?.id }) {
                NavigationStack { CardDetailView(card: card) }
                    .tint(Theme.knowledge)
            }
        case "editeur-savoir":
            if let knowledge {
                let card = previewCards.first { previewFolder == nil || $0.folder?.id == previewFolder?.id }
                CardEditorView(card: card, folder: card?.folder, store: knowledge)
            }
        default: DexView(realm: .animal)
        }
    }

    /// A session dealt straight away, for inspecting the revision screen.
    @ViewBuilder private var previewSession: some View {
        if knowledge != nil {
            PreviewSessionHost(folder: previewFolder, cards: previewCards, folders: previewFolders)
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
                WorldSwitchSection(current: .nature, section: $section)
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
                WorldSwitchSection(current: .cuisine, section: $section)
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

// MARK: - Savoirs

/// The knowledge cards, as their own small app: folders to organise them, and
/// revision sessions to learn them.
private struct KnowledgeTabs: View {
    @Binding var section: AppSection

    var body: some View {
        TabView {
            NavigationStack { FolderContentView(folder: nil) }
                .tabItem { Label("Dossiers", systemImage: "folder.fill") }
            NavigationStack { ReviewSetupView() }
                .tabItem { Label("Réviser", systemImage: "rectangle.stack.fill") }
            KnowledgeMoreView(section: $section)
                .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
        }
        .tint(Theme.knowledge)
    }
}

private struct KnowledgeMoreView: View {
    @Binding var section: AppSection

    var body: some View {
        NavigationStack {
            List {
                WorldSwitchSection(current: .knowledge, section: $section)
                Section {
                    NavigationLink { SettingsView() } label: {
                        Label("Réglages", systemImage: "gearshape.fill")
                    }
                } footer: {
                    Text("Les cartes, leurs images et votre progression sont enregistrées avec le reste, et sauvegardées sur iCloud quand il est actif.")
                }
            }
            .navigationTitle("Plus")
        }
    }
}

/// One row per other world, in the same place on every side.
private struct WorldSwitchSection: View {
    let current: AppSection
    @Binding var section: AppSection

    var body: some View {
        Section {
            ForEach(AppSection.allCases.filter { $0 != current }, id: \.self) { target in
                SectionSwitchRow(target: target) {
                    withAnimation { section = target }
                }
            }
        }
    }
}

/// The row that moves to another world. Deliberately prominent.
private struct SectionSwitchRow: View {
    let target: AppSection
    let action: () -> Void

    private var tint: Color { target.tint }

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
                    Text(target.subtitle)
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

#if DEBUG
/// Deals a preview session once and keeps it. Dealing inside `body` would deal
/// a fresh session on every re-render and reshuffle the screen under the eye.
private struct PreviewSessionHost: View {
    let folder: KnowledgeFolder?
    let cards: [KnowledgeCard]
    let folders: [KnowledgeFolder]

    @Environment(KnowledgeStore.self) private var store
    @State private var session: ReviewSession?

    var body: some View {
        Group {
            if let session {
                ReviewSessionView(session: session)
            } else {
                ProgressView()
            }
        }
        .task {
            guard session == nil else { return }
            let scope = KnowledgeIndex.cards(in: folder, cards: cards, folders: folders)
            let dealt = store.deal(from: scope, count: 10, mode: .ordinary)
            guard !dealt.isEmpty else { return }
            session = ReviewSession(
                scope: folder,
                scopeLabel: KnowledgeIndex.pathLabel(of: folder, folders: folders),
                firstSide: CommandLine.arguments.contains("-previewVersoFirst") ? .verso : .recto,
                mode: .ordinary, requested: 10, cards: dealt
            )
        }
    }
}
#endif
