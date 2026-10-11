#if DEBUG
import Foundation
import SwiftData
import UIKit
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
        // Each section seeds only when it is empty, independently of the
        // others, so a real collection is never polluted and a section added
        // later still gets its samples on a device already seeded before.
        let existing = (try? context.fetch(FetchDescriptor<Species>())) ?? []
        if existing.isEmpty { seedSpecies(into: context) }
        seedRecipes(into: context)
        seedKnowledge(into: context)
        try? context.save()
    }

    private static func seedSpecies(into context: ModelContext) {
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


    // MARK: - Savoirs

    /// Real content in nested folders: vocabulary, quotations, dates with links
    /// and lists, flags drawn as pictures, one card retired, some resting, one
    /// back from its rest and awaiting confirmation, and a folder fully mastered
    /// so the "Dossier maîtrisé !" state can be seen.
    static func seedKnowledge(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<KnowledgeFolder>())) ?? []
        guard existing.isEmpty else { return }
        let calendar = Calendar.current
        let now = Date()

        func folder(_ name: String, _ emoji: String, _ color: FolderColor, _ index: Int,
                    in parent: KnowledgeFolder? = nil) -> KnowledgeFolder {
            let folder = KnowledgeFolder(name: name, emoji: emoji, color: color)
            folder.sortIndex = index
            context.insert(folder)
            folder.parent = parent
            return folder
        }

        func card(_ folder: KnowledgeFolder, _ recto: RichDocument, _ verso: RichDocument,
                  image: (id: UUID, data: Data)? = nil, mastery: MasteryState = .fresh,
                  retired: Bool = false, dealt: Int = 0, hoursAgo: Int = 0) {
            let card = KnowledgeCard()
            card.rectoData = try? recto.jsonData()
            card.versoData = try? verso.jsonData()
            card.rectoText = recto.plainText
            card.versoText = verso.plainText
            card.mastery = mastery
            card.retiredAt = retired ? now : nil
            card.timesDealt = dealt
            card.createdAt = now.addingTimeInterval(-Double(hoursAgo) * 3_600)
            if mastery.level > 0 { card.lastMasteredAt = now.addingTimeInterval(-10 * 86_400) }
            context.insert(card)
            card.folder = folder
            if let image {
                let record = KnowledgeImage(id: image.id, data: image.data, pixelWidth: 900, pixelHeight: 600)
                context.insert(record)
                record.card = card
            }
        }

        /// Resting since ten days ago, so back in about twenty.
        let resting = MasteryState(level: 1, restUntil: MasteryRule.firstDayBack(
            after: now.addingTimeInterval(-10 * 86_400), restingDays: 30, calendar: calendar))
        /// Rest over yesterday: dealt again, waiting for confirmation.
        let backForConfirmation = MasteryState(level: 1, restUntil: calendar.date(
            byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))

        // Langues
        let langues = folder("Langues", "🗣️", .blue, 0)
        let anglais = folder("Anglais", "🇬🇧", .indigo, 0, in: langues)
        let italien = folder("Italien", "🇮🇹", .green, 1, in: langues)

        card(anglais, doc(para(.body, run("la bouilloire", bold))),
             doc(para(.body, run("the kettle", bold)),
                 para(.quote, run("Mets la bouilloire en route. Put the kettle on."))), hoursAgo: 1)
        card(anglais, doc(para(.body, run("s'épanouir", bold))),
             doc(para(.body, run("to thrive, to blossom", bold)),
                 para(.quote, run("Elle s'épanouit dans son nouveau travail. She is thriving in her new job."))), hoursAgo: 2)
        card(anglais, doc(para(.body, run("une aubaine", bold))),
             doc(para(.body, run("a godsend, a windfall", bold))),
             mastery: backForConfirmation, dealt: 2, hoursAgo: 3)
        card(anglais, doc(para(.body, run("tergiverser", bold))),
             doc(para(.body, run("to dither, to beat around the bush", bold))), hoursAgo: 4)
        card(anglais, doc(para(.body, run("le lendemain", bold))),
             doc(para(.body, run("the next day", bold))), dealt: 1, hoursAgo: 5)
        card(anglais, doc(para(.body, run("un casse-tête", bold))),
             doc(para(.body, run("a puzzle", bold), run(" ; au figuré : "), run("a headache", italic))), hoursAgo: 6)

        card(italien, doc(para(.body, run("la bouilloire", bold))), doc(para(.body, run("il bollitore", bold))), hoursAgo: 7)
        card(italien, doc(para(.body, run("le lendemain", bold))), doc(para(.body, run("l'indomani", bold))), hoursAgo: 8)

        // Citations
        let citations = folder("Citations", "📜", .amber, 1)
        card(citations, doc(para(.quote, run("« Je pense, donc je suis. »"))),
             doc(para(.heading, run("René Descartes")),
                 para(.body, run("Discours de la méthode", italic), run(", 1637"))), hoursAgo: 9)
        card(citations, doc(para(.quote, run("« Carpe diem. »"))),
             doc(para(.heading, run("Horace")), para(.body, run("Odes", italic), run(", livre I, 11"))),
             mastery: resting, dealt: 3, hoursAgo: 10)
        card(citations, doc(para(.quote, run("« L'essentiel est invisible pour les yeux. »"))),
             doc(para(.heading, run("Antoine de Saint-Exupéry")), para(.body, run("Le Petit Prince", italic), run(", 1943"))),
             hoursAgo: 11)
        card(citations, doc(para(.quote, run("« Le cœur a ses raisons que la raison ne connaît point. »"))),
             doc(para(.heading, run("Blaise Pascal")), para(.body, run("Pensées", italic), run(", 1670"))),
             retired: true, hoursAgo: 12)

        // Histoire
        let histoire = folder("Histoire", "🏛️", .red, 2)
        let dates = folder("Dates", "📅", .orange, 0, in: histoire)
        let bastille = "https://fr.wikipedia.org/wiki/Prise_de_la_Bastille"
        card(dates, doc(para(.heading, run("Prise de la Bastille"))),
             doc(para(.body, run("14 juillet 1789", RichFormat(bold: true, color: .red))),
                 para(.body, run("Le début symbolique de la Révolution française.")),
                 para(.body, run("En savoir plus", RichFormat(link: bastille)))), hoursAgo: 13)
        card(dates, doc(para(.heading, run("Couronnement de Charlemagne"))),
             doc(para(.body, run("25 décembre 800", bold), run(", à Rome, par le pape Léon III."))), hoursAgo: 14)
        card(dates, doc(para(.heading, run("Armistice de la Grande Guerre"))),
             doc(para(.body, run("11 novembre 1918", bold)),
                 para(.body, run("Signé à Rethondes, dans la forêt de Compiègne."))), hoursAgo: 15)
        card(dates, doc(para(.heading, run("Chute du mur de Berlin"))),
             doc(para(.body, run("9 novembre 1989", bold))), dealt: 1, hoursAgo: 16)
        card(dates, doc(para(.heading, run("Alunissage d'Apollo 11"))),
             doc(para(.body, run("20 juillet 1969", bold)),
                 para(.body, run("L'équipage :")),
                 para(.bullet, run("Neil Armstrong")),
                 para(.bullet, run("Buzz Aldrin")),
                 para(.bullet, run("Michael Collins", italic), run(", resté en orbite"))), hoursAgo: 17)

        // Géographie
        let geographie = folder("Géographie", "🌍", .teal, 3)
        let drapeaux = folder("Drapeaux", "🚩", .pink, 0, in: geographie)
        let flags: [(String, [UIColor], String)] = [
            ("La France", [rgb(0x0055A4), .white, rgb(0xEF4135)], "Bleu, blanc, rouge."),
            ("L'Italie", [rgb(0x009246), .white, rgb(0xCE2B37)], "Vert, blanc, rouge."),
            ("La Belgique", [.black, rgb(0xFDDA24), rgb(0xEF3340)], "Noir, jaune, rouge."),
        ]
        for (index, flag) in flags.enumerated() {
            let id = UUID()
            card(drapeaux,
                 doc(.image(RichImage(id: id, width: 900, height: 600)), para(.body, run("Quel pays ?", italic))),
                 doc(para(.heading, run(flag.0)), para(.body, run(flag.2))),
                 image: (id: id, data: flagImage(flag.1)), hoursAgo: 18 + index)
        }

        // Philosophie: everything resting, so the folder shows as mastered.
        let philosophie = folder("Philosophie", "🧠", .purple, 4)
        card(philosophie, doc(para(.body, run("Qu'est-ce que l'"), run("épistémologie", bold), run(" ?"))),
             doc(para(.body, run("L'étude critique des sciences et de la connaissance."))),
             mastery: resting, dealt: 4, hoursAgo: 21)
        card(philosophie, doc(para(.body, run("Qui a écrit "), run("Du contrat social", italic), run(" ?"))),
             doc(para(.heading, run("Jean-Jacques Rousseau")), para(.body, run("1762"))),
             mastery: MasteryState(level: 2, restUntil: calendar.date(byAdding: .day, value: 45, to: calendar.startOfDay(for: now))),
             dealt: 6, hoursAgo: 22)
    }

    private static let bold = RichFormat(bold: true)
    private static let italic = RichFormat(italic: true)

    private static func run(_ text: String, _ format: RichFormat = .plain) -> RichRun {
        RichRun(text: text, format: format)
    }

    private static func para(_ style: RichParagraphStyle, _ runs: RichRun...) -> RichBlock {
        .paragraph(RichParagraph(style: style, runs: runs))
    }

    private static func doc(_ blocks: RichBlock...) -> RichDocument {
        RichDocument(blocks: blocks)
    }

    private static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// A vertical tricolour, drawn rather than downloaded so the sample works
    /// offline and needs no licence.
    private static func flagImage(_ colors: [UIColor]) -> Data {
        let size = CGSize(width: 900, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let stripe = size.width / CGFloat(colors.count)
            for (index, color) in colors.enumerated() {
                color.setFill()
                context.fill(CGRect(x: CGFloat(index) * stripe, y: 0, width: stripe, height: size.height))
            }
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
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
