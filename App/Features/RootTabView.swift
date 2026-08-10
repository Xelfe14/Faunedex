import SwiftUI
import SwiftData
import FlaunedexCore

/// The app's tab shell. Faune / Flore / Capturer / Carte / Plus. The scan
/// coordinator is created once the model context is available and shared down
/// through the environment.
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(APIKeys.self) private var keys
    @Environment(Connectivity.self) private var connectivity

    @State private var scan: ScanCoordinator?

    #if DEBUG
    /// Debug-only preview routing so any screen can be inspected directly:
    /// `-previewSpeciesDetail`, or `-previewScreen <faune|flore|carte|journal|stats|decouvertes>`.
    @Query(sort: \Species.dexNumber) private var previewSpecies: [Species]

    private var previewScreen: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-previewScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    private var wantsDetailPreview: Bool {
        CommandLine.arguments.contains("-previewSpeciesDetail")
    }
    #endif

    var body: some View {
        Group {
            #if DEBUG
            if wantsDetailPreview, let first = previewSpecies.first {
                NavigationStack { SpeciesDetailView(species: first) }
            } else if let screen = previewScreen {
                previewDestination(screen)
            } else {
                mainInterface
            }
            #else
            mainInterface
            #endif
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
        default: DexView(realm: .animal)
        }
    }
    #endif

    @ViewBuilder private var mainInterface: some View {
        Group {
            if let scan {
                TabView {
                    DexView(realm: .animal)
                        .tabItem { Label("Faune", systemImage: "pawprint.fill") }
                    DexView(realm: .plant)
                        .tabItem { Label("Flore", systemImage: "leaf.fill") }
                    CaptureView()
                        .tabItem { Label("Capturer", systemImage: "camera.fill") }
                    SightingsMapView()
                        .tabItem { Label("Carte", systemImage: "map.fill") }
                    MoreView()
                        .tabItem { Label("Plus", systemImage: "ellipsis.circle.fill") }
                }
                .environment(scan)
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
                    .task { scan = ScanCoordinator(context: context, keys: keys) }
            }
        }
    }
}

/// The "Plus" tab: everything that doesn't warrant a permanent tab.
struct MoreView: View {
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
                NavigationLink { SettingsView() } label: {
                    Label("Réglages", systemImage: "gearshape.fill")
                }
            }
            .navigationTitle("Plus")
        }
    }
}
