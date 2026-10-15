import SwiftUI
import FlaunedexCore

/// Where the user pastes their API keys (stored in the Keychain) and reads the
/// app's data credits. Only the Gemini key is required.
struct SettingsView: View {
    @Environment(APIKeys.self) private var keys
    @Environment(\.storageMode) private var storageMode

    var body: some View {
        @Bindable var keys = keys
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(storageMode.frenchLabel).font(.subheadline.weight(.medium))
                        Text(storageMode.frenchDetail)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: storageMode.symbolName)
                        .foregroundStyle(storageMode == .cloudKit ? Theme.flora : .secondary)
                }
            } header: {
                Text("Sauvegarde")
            }

            Section {
                SecureField("Clé API Gemini", text: $keys.geminiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Gemini (obligatoire)")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("La même clé sert aux trois apps : identifier les espèces, écrire les recettes, rédiger les fiches.")
                    Link("Obtenir une clé sur Google AI Studio",
                         destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                }
            }

            Section {
                SecureField("Jeton IUCN (optionnel)", text: $keys.iucnToken)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("IUCN Red List")
            } footer: {
                Text("Sans jeton, le statut de conservation vient de Wikidata.")
            }

            Section {
                SecureField("Clé Xeno-canto (optionnel)", text: $keys.xenoCantoKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Xeno-canto")
            } footer: {
                Text("Nécessaire pour écouter le chant des oiseaux.")
            }

            Section("À propos des données") {
                Text("Identification : Google Gemini (\(FlaunedexConfig.geminiModel)).")
                Text("Taxonomie & répartition : GBIF.")
                Text("Noms & statut : Wikidata. Images : Wikimedia Commons. Chants : Xeno-canto.")
                Text("Recettes et fiches : Google Gemini. Photos des plats et images des fiches : Wikipédia et Wikimedia Commons.")
                Text("Saisons et empreinte carbone : ADEME (Impact CO2, Agribalyse 3.2), Licence Ouverte 2.0.")
                Text("Les identifications, recettes et fiches écrites par IA peuvent se tromper ; ne consommez ou ne manipulez jamais une espèce sur cette seule base.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Réglages")
    }
}
