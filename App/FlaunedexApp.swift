import SwiftUI
import SwiftData

@main
struct FlaunedexApp: App {
    @State private var apiKeys = APIKeys()
    @State private var connectivity = Connectivity()

    let container: ModelContainer
    let storageMode: StorageMode

    init() {
        // Opens CloudKit-backed storage when possible and falls back rather than
        // crashing — see Persistence for why each level exists.
        let opened = Persistence.makeContainer()
        container = opened.container
        storageMode = opened.mode

        #if DEBUG
        if SampleData.isRequested {
            SampleData.seed(into: container.mainContext)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(apiKeys)
                .environment(connectivity)
                .environment(\.storageMode, storageMode)
                .tint(Theme.brand)
        }
        .modelContainer(container)
    }
}

private struct StorageModeKey: EnvironmentKey {
    static let defaultValue: StorageMode = .localOnly
}

extension EnvironmentValues {
    /// Which storage mode the app actually opened with, so Réglages can be
    /// honest about whether iCloud backup is really running.
    var storageMode: StorageMode {
        get { self[StorageModeKey.self] }
        set { self[StorageModeKey.self] = newValue }
    }
}
