#if DEBUG
import Foundation
import SwiftData
import FlaunedexCore

/// Debug-only demo content so the app can be explored (and screenshotted)
/// without an API key or a walk outside. Launch with `-seedSampleData` — the
/// scheme's Run action passes it in Debug builds.
///
/// The species below are real, with real Wikimedia images and French Wikipedia
/// links; the two plants are the ones from the original design brief.
enum SampleData {

    static var isRequested: Bool {
        CommandLine.arguments.contains("-seedSampleData")
    }

    static func seed(into context: ModelContext) {
        // Only seed an empty store, so a real collection is never polluted.
        let existing = (try? context.fetch(FetchDescriptor<Species>())) ?? []
        guard existing.isEmpty else { return }

        for (index, spec) in specs.enumerated() {
            let species = Species(gbifKey: spec.gbifKey,
                                  scientificName: spec.scientificName,
                                  realm: spec.realm)
            species.dexNumber = index + 1
            species.frenchName = spec.frenchName
            species.englishName = spec.englishName
            species.family = spec.family
            species.animalGroupRaw = spec.animalGroup?.rawValue
            species.rangeCountries = spec.range
            species.nativeCountries = spec.range
            species.conservationGlobal = spec.conservation
            species.referenceImageURLString = spec.imageURL
            species.referenceThumbURLString = spec.imageURL
            species.imageArtist = "Wikimedia Commons"
            species.imageLicenseShort = "CC BY-SA"
            species.wikipediaURLString = spec.wikipediaURL
            species.wikipediaTitle = spec.frenchName
            species.specificiteFR = spec.specificite
            species.funFactFR = spec.funFact
            species.seasonMonths = spec.months
            species.toxicityDangerFR = spec.toxicity
            species.enrichmentStatus = .complete
            species.firstUnlockedAt = Date().addingTimeInterval(-Double(index) * 86_400)
            context.insert(species)

            for (offset, place) in spec.places.enumerated() {
                let sighting = Sighting(
                    photoRelativePath: "",
                    latitude: place.lat, longitude: place.lon,
                    horizontalAccuracy: 12,
                    capturedAt: Date().addingTimeInterval(-Double(index * 2 + offset) * 86_400)
                )
                sighting.countryISO = place.country
                sighting.speciesKey = spec.gbifKey
                sighting.species = species
                sighting.status = .complete
                context.insert(sighting)
            }
        }
        try? context.save()
    }

    // MARK: - Content

    private struct Place { let lat: Double; let lon: Double; let country: String }

    private struct Spec {
        let gbifKey: Int
        let scientificName: String
        let frenchName: String
        let englishName: String
        let family: String
        let realm: Realm
        let animalGroup: AnimalGroup?
        let range: [String]
        let conservation: String?
        let imageURL: String
        let wikipediaURL: String
        let specificite: String
        let funFact: String
        let months: [Int]
        let toxicity: String?
        let places: [Place]
    }

    private static let specs: [Spec] = [
        Spec(
            gbifKey: 3033157,
            scientificName: "Hepatica nobilis",
            frenchName: "Hépatique à trois lobes",
            englishName: "Liverleaf",
            family: "Ranunculaceae",
            realm: .plant, animalGroup: nil,
            range: ["FR", "IT", "DE", "AT", "CH", "SE", "NO", "FI", "PL", "ES"],
            conservation: "LC",
            imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/9/9b/Hepatica_nobilis_plant.JPG/500px-Hepatica_nobilis_plant.JPG",
            wikipediaURL: "https://fr.wikipedia.org/wiki/Hepatica_nobilis",
            specificite: "C'est l'une des toutes premières fleurs à percer le tapis de feuilles mortes des sous-bois à la sortie de l'hiver. Ses fleurs d'un bleu-violet très vif contrastent fortement avec les couleurs ternes de la fin d'hiver. Ses feuilles épaisses, d'un vert sombre, sont découpées en trois lobes caractéristiques.",
            funFact: "Son nom vient d'une ancienne croyance médicale, la « théorie des signatures » : on pensait au Moyen Âge que Dieu avait donné aux plantes la forme des organes qu'elles devaient soigner. Sa feuille à trois lobes, parfois violacée en dessous, ressemblant à un foie humain, on l'utilisait — à tort — contre les maladies hépatiques.",
            months: [2, 3, 4],
            toxicity: "Légèrement toxique à l'état frais comme la plupart des renoncules.",
            places: [Place(lat: 45.9237, lon: 6.8694, country: "FR"),
                     Place(lat: 46.4983, lon: 11.3548, country: "IT")]
        ),
        Spec(
            gbifKey: 3120060,
            scientificName: "Petasites albus",
            frenchName: "Pétasite blanc",
            englishName: "White Butterbur",
            family: "Asteraceae",
            realm: .plant, animalGroup: nil,
            range: ["FR", "DE", "AT", "CH", "IT", "PL", "CZ", "SK", "SI"],
            conservation: "LC",
            imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/2/22/Petasites_albus_a1.jpg/500px-Petasites_albus_a1.jpg",
            wikipediaURL: "https://fr.wikipedia.org/wiki/P%C3%A9tasite_blanc",
            specificite: "Cette plante affectionne les milieux humides, les bords de ruisseaux et les ravins montagneux. Sa grande particularité est de fleurir très tôt au printemps, avant même que ses feuilles ne poussent : on ne voit d'abord que des tiges florales dressées portant des capitules blanchâtres.",
            funFact: "Le nom Petasites vient du grec petasos, un chapeau à larges bords porté par les bergers de l'Antiquité — car plus tard dans la saison, les feuilles deviennent si gigantesques qu'elles pourraient servir de parapluie. On s'en servait autrefois pour envelopper les mottes de beurre et les garder au frais.",
            months: [3, 4, 5],
            toxicity: nil,
            places: [Place(lat: 45.8992, lon: 6.6889, country: "FR")]
        ),
        Spec(
            gbifKey: 1898286,
            scientificName: "Vanessa atalanta",
            frenchName: "Vulcain",
            englishName: "Red Admiral",
            family: "Nymphalidae",
            realm: .animal, animalGroup: .insect,
            range: ["FR", "ES", "IT", "DE", "GB", "BE", "NL", "CH", "AT", "PT", "SE"],
            conservation: "LC",
            imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/2/24/VanessaAtalanta_Closeup.jpg/500px-VanessaAtalanta_Closeup.jpg",
            wikipediaURL: "https://fr.wikipedia.org/wiki/Vulcain_(papillon)",
            specificite: "Reconnaissable entre tous à ses ailes noir velouté barrées d'une bande orange vif et ponctuées de blanc à l'apex. On le rencontre dans les jardins, les lisières et les vergers, souvent posé sur les fruits tombés dont il aspire le jus fermenté à l'automne.",
            funFact: "C'est un grand migrateur : chaque printemps, des vagues de vulcains remontent d'Afrique du Nord et du bassin méditerranéen jusqu'en Scandinavie. Un papillon de deux grammes peut ainsi parcourir plusieurs milliers de kilomètres au cours de sa vie.",
            months: [4, 5, 6, 7, 8, 9, 10],
            toxicity: nil,
            places: [Place(lat: 48.8566, lon: 2.3522, country: "FR"),
                     Place(lat: 50.8503, lon: 4.3517, country: "BE")]
        ),
        Spec(
            gbifKey: 5219243,
            scientificName: "Vulpes vulpes",
            frenchName: "Renard roux",
            englishName: "Red Fox",
            family: "Canidae",
            realm: .animal, animalGroup: .mammal,
            range: ["FR", "ES", "IT", "DE", "GB", "IE", "SE", "NO", "FI", "PL", "AT", "CH", "PT", "GR"],
            conservation: "LC",
            imageURL: "https://upload.wikimedia.org/wikipedia/commons/thumb/d/d2/Portrait_of_a_red_fox_in_Rautas_fj%C3%A4llurskog_%28cropped%29.jpg/500px-Portrait_of_a_red_fox_in_Rautas_fj%C3%A4llurskog_%28cropped%29.jpg",
            wikipediaURL: "https://fr.wikipedia.org/wiki/Renard_roux",
            specificite: "Le plus répandu des carnivores sauvages d'Europe, aussi à l'aise en forêt qu'en pleine ville. Son pelage roux, son ventre clair et sa longue queue touffue à bout blanc le rendent inconfondable. Surtout actif au crépuscule et la nuit.",
            funFact: "Le renard chasse à l'oreille : il détecte un campagnol sous trente centimètres de neige, puis bondit à la verticale pour retomber dessus. Des études suggèrent qu'il oriente ses sauts selon le champ magnétique terrestre, comme une boussole vivante.",
            months: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
            toxicity: "Ne jamais approcher ni nourrir un animal sauvage.",
            places: [Place(lat: 45.7640, lon: 4.8357, country: "FR")]
        ),
    ]
}
#endif
