import Foundation
import SwiftData

/// How the store ended up being opened.
enum StorageMode: String {
    /// Local store backed by the private CloudKit database, with an iCloud
    /// account actually signed in — the intended mode.
    case cloudKit
    /// CloudKit is configured, but no iCloud account is signed in on this
    /// device, so nothing is syncing yet. Data is safe locally.
    case cloudKitWaitingForAccount
    /// Local store only. Used when CloudKit isn't available (no iCloud account,
    /// container not provisioned yet, entitlement missing). Everything still
    /// works; sightings simply aren't backed up until iCloud is reachable.
    case localOnly
    /// Last-resort scratch store so the app can always start and explain itself.
    case inMemory

    var frenchLabel: String {
        switch self {
        case .cloudKit: return "Sauvegarde iCloud active"
        case .cloudKitWaitingForAccount: return "iCloud non connecté"
        case .localOnly: return "Stockage local uniquement"
        case .inMemory: return "Stockage temporaire (erreur)"
        }
    }

    var frenchDetail: String {
        switch self {
        case .cloudKit:
            return "Vos espèces et observations sont sauvegardées sur votre compte iCloud privé."
        case .cloudKitWaitingForAccount:
            return "Connectez-vous à iCloud dans les Réglages de l'iPhone pour activer la sauvegarde. Vos données restent enregistrées sur cet appareil."
        case .localOnly:
            return "Vos données sont enregistrées sur cet appareil. Connectez-vous à iCloud pour activer la sauvegarde."
        case .inMemory:
            return "Le stockage n'a pas pu être ouvert. Les données de cette session ne seront pas conservées."
        }
    }
}

/// Opens the SwiftData store, degrading gracefully instead of crashing.
///
/// CloudKit is the goal, but it fails for ordinary reasons — no iCloud account
/// on the device, the container not yet provisioned, or a schema that hasn't
/// been deployed to Production. None of those should stop a field app from
/// opening, so each failure falls back one level and the active mode is shown
/// in Réglages.
enum Persistence {

    static func makeContainer() -> (container: ModelContainer, mode: StorageMode) {
        let schema = Schema([Species.self, Sighting.self, Recipe.self])

        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)]
        ) {
            // Creating the container succeeds even when CloudKit can't actually
            // sync, so don't claim backup is running without an iCloud account.
            let signedIn = FileManager.default.ubiquityIdentityToken != nil
            return (container, signedIn ? .cloudKit : .cloudKitWaitingForAccount)
        }

        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]
        ) {
            return (container, .localOnly)
        }

        // A corrupt or unreadable store shouldn't be a dead end either.
        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) {
            return (container, .inMemory)
        }

        // Nothing left to try — the schema itself is invalid, which is a
        // programming error rather than an environment one.
        fatalError("Schéma SwiftData invalide : impossible d'ouvrir le moindre stockage.")
    }
}

extension StorageMode {
    var symbolName: String {
        switch self {
        case .cloudKit: return "icloud.fill"
        case .cloudKitWaitingForAccount: return "icloud.slash"
        case .localOnly: return "internaldrive.fill"
        case .inMemory: return "exclamationmark.triangle.fill"
        }
    }
}
