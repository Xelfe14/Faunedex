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
        seedRecipes(into: context)
        try? context.save()
    }

    /// Three real recipes with real Wikimedia photographs, so the cooking
    /// section can be explored (and screenshotted) without an API key. The
    /// first is deliberately marked as edited and carries a cook's note, since
    /// that is the state most recipes end up in.
    static func seedRecipes(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        guard existing.isEmpty else { return }

        for (index, spec) in recipeSpecs.enumerated() {
            let recipe = Recipe(title: spec.title, source: spec.source)
            recipe.summaryFR = spec.summary
            recipe.servings = spec.servings
            recipe.prepMinutes = spec.prep
            recipe.cookMinutes = spec.cook
            recipe.difficulty = spec.difficulty
            recipe.course = spec.course
            recipe.cuisine = spec.cuisine
            recipe.ingredients = spec.ingredients
            recipe.steps = spec.steps
            recipe.chefTipFR = spec.tip
            recipe.allergens = spec.allergens
            recipe.tags = spec.tags
            recipe.notes = spec.notes
            recipe.isFavorite = spec.favorite
            recipe.timesCooked = spec.timesCooked
            recipe.sortIndex = index
            recipe.photoQuery = spec.title
            recipe.imageURLString = spec.imageURL
            recipe.thumbURLString = spec.imageURL
            recipe.imageArtist = spec.artist
            recipe.imageLicenseShort = "CC BY-SA 4.0"
            recipe.articleURLString = spec.articleURL
            recipe.originalPrompt = spec.prompt
            recipe.createdAt = Date().addingTimeInterval(-Double(index) * 172_800)
            context.insert(recipe)
        }
    }

    private struct RecipeSpec {
        let title: String
        let summary: String
        let servings: Int
        let prep: Int
        let cook: Int
        let difficulty: RecipeDifficulty
        let course: RecipeCourse
        let cuisine: String
        let ingredients: [RecipeIngredient]
        let steps: [RecipeStep]
        let tip: String
        let allergens: [String]
        let tags: [String]
        let notes: String?
        let favorite: Bool
        let timesCooked: Int
        let source: Recipe.Source
        let imageURL: String
        let artist: String
        let articleURL: String
        let prompt: String
    }

    private static let recipeSpecs: [RecipeSpec] = [
        RecipeSpec(
            title: "Tarte Tatin",
            summary: "Une tarte renversée aux pommes caramélisées, servie tiède.",
            servings: 6, prep: 30, cook: 45,
            difficulty: .moyen, course: .dessert, cuisine: "française",
            ingredients: [
                RecipeIngredient(quantity: 8, name: "pommes", note: "Reine des reinettes"),
                RecipeIngredient(quantity: 150, unit: .gram, name: "sucre"),
                RecipeIngredient(quantity: 100, unit: .gram, name: "beurre demi-sel"),
                RecipeIngredient(quantity: 1, name: "pâte feuilletée"),
                RecipeIngredient(quantity: 1, unit: .tablespoon, name: "eau"),
            ],
            steps: [
                RecipeStep(text: "Préchauffer le four à 180 °C."),
                RecipeStep(text: "Éplucher les pommes, les couper en quartiers et retirer les cœurs."),
                RecipeStep(text: "Faire un caramel à sec avec le sucre et l'eau, jusqu'à une couleur ambrée."),
                RecipeStep(text: "Hors du feu, ajouter le beurre en morceaux et mélanger."),
                RecipeStep(text: "Ranger les quartiers de pommes serrés sur le caramel, bombé vers le bas."),
                RecipeStep(text: "Recouvrir de pâte, rentrer les bords, piquer, puis enfourner.", minutes: 45),
                RecipeStep(text: "Laisser tiédir avant de démouler d'un geste franc.", minutes: 10),
            ],
            tip: "Attendre que le caramel prenne une vraie couleur ambrée avant d'ajouter le beurre : trop clair, il sera fade, et la tarte n'aura pas son amertume.",
            allergens: ["gluten", "lait"],
            tags: ["classique", "de saison", "dessert"],
            notes: "Testé avec des poires : bon aussi, mais il faut réduire la cuisson de 10 minutes.\nLe moule en fonte donne un bien meilleur caramel que le moule à manqué.",
            favorite: true, timesCooked: 3, source: .edited,
            imageURL: "https://upload.wikimedia.org/wikipedia/commons/e/e5/Tarte_Tatin_a_la_Michalak.jpg",
            artist: "Shani Evenstein",
            articleURL: "https://fr.wikipedia.org/wiki/Tarte_Tatin",
            prompt: "une tarte tatin comme à la maison"
        ),
        RecipeSpec(
            title: "Blanquette de veau à l'ancienne",
            summary: "Un ragoût de veau en sauce blanche, avec ses carottes et ses champignons.",
            servings: 6, prep: 30, cook: 90,
            difficulty: .moyen, course: .plat, cuisine: "française",
            ingredients: [
                RecipeIngredient(quantity: 1.2, unit: .kilogram, name: "épaule de veau", note: "en cubes"),
                RecipeIngredient(quantity: 3, name: "carottes"),
                RecipeIngredient(quantity: 1, name: "oignon", note: "piqué de 2 clous de girofle"),
                RecipeIngredient(quantity: 250, unit: .gram, name: "champignons de Paris"),
                RecipeIngredient(quantity: 50, unit: .gram, name: "beurre"),
                RecipeIngredient(quantity: 50, unit: .gram, name: "farine"),
                RecipeIngredient(quantity: 20, unit: .centiliter, name: "crème fraîche épaisse"),
                RecipeIngredient(quantity: 1, name: "jaune d'œuf"),
                RecipeIngredient(name: "Sel", note: "au goût"),
            ],
            steps: [
                RecipeStep(text: "Mettre le veau dans une cocotte, couvrir d'eau froide et porter à frémissement."),
                RecipeStep(text: "Écumer soigneusement, puis ajouter les carottes et l'oignon clouté."),
                RecipeStep(text: "Laisser mijoter à couvert, à tout petits bouillons.", minutes: 75),
                RecipeStep(text: "Faire un roux blanc avec le beurre et la farine, sans le colorer."),
                RecipeStep(text: "Détendre le roux avec le bouillon de cuisson filtré, jusqu'à une sauce nappante."),
                RecipeStep(text: "Ajouter les champignons et laisser cuire.", minutes: 10),
                RecipeStep(text: "Hors du feu, lier avec la crème mélangée au jaune d'œuf. Ne plus faire bouillir."),
            ],
            tip: "La liaison crème et jaune d'œuf se fait hors du feu : si la sauce rebout ensuite, le jaune coagule et la sauce tranche.",
            allergens: ["lait", "gluten", "œuf"],
            tags: ["plat mijoté", "dimanche"],
            notes: nil,
            favorite: false, timesCooked: 1, source: .gemini,
            imageURL: "https://upload.wikimedia.org/wikipedia/commons/c/c3/Blanquette_de_veau_%C3%A0_l%27ancienne_04.jpg",
            artist: "Wikimedia Commons",
            articleURL: "https://fr.wikipedia.org/wiki/Blanquette_de_veau",
            prompt: "une blanquette de veau traditionnelle"
        ),
        RecipeSpec(
            title: "Risotto aux champignons",
            summary: "Un risotto crémeux, monté au beurre et au parmesan.",
            servings: 4, prep: 15, cook: 25,
            difficulty: .facile, course: .plat, cuisine: "italienne",
            ingredients: [
                RecipeIngredient(quantity: 320, unit: .gram, name: "riz arborio"),
                RecipeIngredient(quantity: 1, unit: .liter, name: "bouillon de volaille", note: "maintenu chaud"),
                RecipeIngredient(quantity: 300, unit: .gram, name: "champignons de saison"),
                RecipeIngredient(quantity: 2, name: "échalotes"),
                RecipeIngredient(quantity: 10, unit: .centiliter, name: "vin blanc sec"),
                RecipeIngredient(quantity: 60, unit: .gram, name: "parmesan", note: "râpé"),
                RecipeIngredient(quantity: 40, unit: .gram, name: "beurre", note: "très froid"),
            ],
            steps: [
                RecipeStep(text: "Faire suer les échalotes ciselées dans un peu de beurre, sans coloration."),
                RecipeStep(text: "Ajouter le riz et le nacrer jusqu'à ce que les grains deviennent translucides.", minutes: 2),
                RecipeStep(text: "Déglacer au vin blanc et laisser évaporer complètement."),
                RecipeStep(text: "Verser le bouillon chaud louche par louche, en remuant, en attendant l'absorption à chaque fois.", minutes: 18),
                RecipeStep(text: "Faire sauter les champignons à part, à feu vif, puis les incorporer."),
                RecipeStep(text: "Hors du feu, monter avec le beurre froid et le parmesan. Couvrir et laisser reposer.", minutes: 2),
            ],
            tip: "Le bouillon doit rester chaud : versé froid, il stoppe la cuisson à chaque louche et le riz cuit de façon inégale.",
            allergens: ["lait", "sulfites"],
            tags: ["végétarien", "rapide"],
            notes: nil,
            favorite: false, timesCooked: 0, source: .gemini,
            imageURL: "https://upload.wikimedia.org/wikipedia/commons/c/cc/Flickr_-_cyclonebill_-_Risotto_med_citron_og_gr%C3%B8nne_b%C3%B8nner.jpg",
            artist: "cyclonebill",
            articleURL: "https://fr.wikipedia.org/wiki/Risotto",
            prompt: "un risotto aux champignons crémeux"
        ),
    ]

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
