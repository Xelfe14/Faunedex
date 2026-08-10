import SwiftUI
import FlaunedexCore

/// Where the user pastes their API keys (stored in the Keychain) and reads the
/// app's data credits. Only the Gemini key is required.
struct SettingsView: View {
    @Environment(APIKeys.self) private var keys

    var body: some View {
        @Bindable var keys = keys
        Form {
            Section {
                SecureField("Clé API Gemini", text: $keys.geminiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Gemini (obligatoire)")
            } footer: {
                Link("Obtenir une clé sur Google AI Studio",
                     destination: URL(string: "https://aistudio.google.com/app/apikey")!)
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
                Text("Les identifications par IA peuvent se tromper ; ne consommez ou ne manipulez jamais une espèce sur cette seule base.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Réglages")
    }
}
