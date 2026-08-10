import SwiftUI
import UIKit
import FlaunedexCore

/// Shown when Gemini wasn't confident. Rather than assert a possibly-wrong
/// answer, the app surfaces the candidates and lets the user decide — or asks
/// the model to look again, harder.
struct ReviewSheet: View {
    let sighting: Sighting

    @Environment(ScanCoordinator.self) private var scan
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    private let store = PhotoStore()

    private var candidates: [GeminiIdentification.Candidate] { scan.candidates(for: sighting) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let data = store.load(sighting.photoRelativePath), let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable().aspectRatio(contentMode: .fill)
                            .frame(height: 210)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                            .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    Text("L'identification n'est pas certaine. Choisissez l'espèce qui correspond, ou demandez une nouvelle analyse plus poussée.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if candidates.isEmpty {
                    Section {
                        Text("Aucune hypothèse proposée.").foregroundStyle(.secondary)
                    }
                } else {
                    Section("Hypothèses") {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                            Button {
                                Task { await choose(candidate.scientificName) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(candidate.commonNameFR ?? candidate.scientificName)
                                            .font(.subheadline.weight(.semibold))
                                        Text(candidate.scientificName)
                                            .font(.caption).italic().foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let p = candidate.probability {
                                        Text("\(Int(p * 100)) %")
                                            .font(.caption.weight(.bold)).monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(isWorking)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await choose(nil) }
                    } label: {
                        Label("Analyser à nouveau, plus en profondeur", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(isWorking)
                }

                if isWorking {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Analyse en cours…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("À vérifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func choose(_ scientificName: String?) async {
        isWorking = true
        await scan.retryIdentification(for: sighting, choosing: scientificName)
        isWorking = false
        if sighting.status == .complete { dismiss() }
    }
}
