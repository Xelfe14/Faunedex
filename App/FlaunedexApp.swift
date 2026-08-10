import SwiftUI
import SwiftData

@main
struct FlaunedexApp: App {
    @State private var apiKeys = APIKeys()
    @State private var connectivity = Connectivity()

    let container: ModelContainer

    init() {
        let schema = Schema([Species.self, Sighting.self])
        // `.automatic` uses the CloudKit container from the app's entitlements,
        // giving free single-user backup + cross-device sync.
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Impossible de créer le ModelContainer : \(error)")
        }

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
                .tint(.green)
        }
        .modelContainer(container)
    }
}
