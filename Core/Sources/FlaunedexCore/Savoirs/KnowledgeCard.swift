import Foundation

/// The shelf a knowledge card sits on. French raw values, because they are what
/// the model is asked to produce and what the UI displays, as for recipes.
public enum KnowledgeTheme: String, Codable, Sendable, CaseIterable, Hashable {
    case sciences
    case histoire
    case nature
    case cuisine
    case langues
    case arts
    case geographie = "géographie"
    case societe = "société"
    case sante = "santé"
    case techniques
    case divers

    public var frenchLabel: String {
        switch self {
        case .sciences: return "Sciences"
        case .histoire: return "Histoire"
        case .nature: return "Nature"
        case .cuisine: return "Cuisine"
        case .langues: return "Langues"
        case .arts: return "Arts & culture"
        case .geographie: return "Géographie"
        case .societe: return "Société"
        case .sante: return "Santé"
        case .techniques: return "Techniques"
        case .divers: return "Divers"
        }
    }

    public var symbolName: String {
        switch self {
        case .sciences: return "atom"
        case .histoire: return "building.columns"
        case .nature: return "leaf"
        case .cuisine: return "fork.knife"
        case .langues: return "character.bubble"
        case .arts: return "paintpalette"
        case .geographie: return "globe.europe.africa"
        case .societe: return "person.3"
        case .sante: return "heart.text.square"
        case .techniques: return "gearshape.2"
        case .divers: return "lightbulb"
        }
    }

    /// Read a theme leniently: the raw value, the label, any casing or accents.
    /// Anything unknown lands in Divers rather than losing the card.
    public static func resolve(_ raw: String?) -> KnowledgeTheme {
        guard let raw else { return .divers }
        let key = fold(raw)
        return allCases.first { fold($0.rawValue) == key || fold($0.frenchLabel) == key } ?? .divers
    }

    private static func fold(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

/// How much the card should say.
public enum KnowledgeDepth: String, Codable, Sendable, CaseIterable, Hashable {
    case essentiel
    case approfondi

    public var frenchLabel: String {
        switch self {
        case .essentiel: return "L'essentiel"
        case .approfondi: return "Approfondi"
        }
    }
}

/// A knowledge card as a value: what Gemini returns, what the editor writes,
/// and what the app stores. Framework-free, like `RecipeDraft`, so all of it is
/// testable with `swift test`.
public struct KnowledgeDraft: Codable, Sendable, Equatable {
    public var title: String
    public var theme: KnowledgeTheme
    /// The one sentence to remember.
    public var summaryFR: String?
    /// The explanation, in short paragraphs separated by a blank line.
    public var bodyFR: String
    public var keyPointsFR: [String]
    /// The flashcard: a question whose answer is on the card.
    public var questionFR: String?
    public var answerFR: String?
    public var funFactFR: String?
    /// The French Wikipedia article that best matches, used for the picture
    /// and the "en savoir plus" link. Never shown as a source of the text.
    public var wikipediaQuery: String?
    public var tags: [String]

    public init(title: String, theme: KnowledgeTheme = .divers, summaryFR: String? = nil,
                bodyFR: String = "", keyPointsFR: [String] = [], questionFR: String? = nil,
                answerFR: String? = nil, funFactFR: String? = nil, wikipediaQuery: String? = nil,
                tags: [String] = []) {
        self.title = title
        self.theme = theme
        self.summaryFR = summaryFR
        self.bodyFR = bodyFR
        self.keyPointsFR = keyPointsFR
        self.questionFR = questionFR
        self.answerFR = answerFR
        self.funFactFR = funFactFR
        self.wikipediaQuery = wikipediaQuery
        self.tags = tags
    }

    public func normalized() -> KnowledgeDraft {
        var copy = self
        copy.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.summaryFR = Self.cleaned(summaryFR)
        copy.bodyFR = Self.paragraphs(bodyFR)
        copy.keyPointsFR = RecipeDraft.uniqueTrimmed(keyPointsFR.map(Self.withoutBullet))
        copy.questionFR = Self.cleaned(questionFR)
        copy.answerFR = Self.cleaned(answerFR)
        copy.funFactFR = Self.cleaned(funFactFR)
        copy.wikipediaQuery = Self.cleaned(wikipediaQuery)
        copy.tags = RecipeDraft.uniqueTrimmed(tags)
        return copy
    }

    /// Key points typed one per line, the way the editor shows them.
    public static func keyPoints(fromLines text: String) -> [String] {
        RecipeDraft.uniqueTrimmed(text.components(separatedBy: .newlines).map(withoutBullet))
    }

    private static func cleaned(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Trim each paragraph and keep exactly one blank line between them, so a
    /// model that pads with empty lines and a person who doesn't read the same.
    private static func paragraphs(_ text: String) -> String {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// "- Point", "• Point", "* Point" and "2. Point" all become "Point": the
    /// app draws its own bullets. "1.5 million" is left alone, since a number
    /// marker is only one when a space follows it.
    static func withoutBullet(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        if let first = s.first, "-•*–—·".contains(first) {
            s.removeFirst()
        } else if let dot = s.firstIndex(where: { $0 == "." || $0 == ")" }),
                  dot != s.startIndex,
                  s.distance(from: s.startIndex, to: dot) <= 2,
                  s[s.startIndex..<dot].allSatisfy(\.isNumber) {
            let rest = s.index(after: dot)
            if rest == s.endIndex || s[rest] == " " {
                s = String(s[rest...])
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

/// What the learner asked for.
public struct KnowledgeRequest: Sendable, Equatable {
    /// Free text: "la photosynthèse", "pourquoi le ciel est bleu".
    public var subject: String
    public var depth: KnowledgeDepth
    /// An angle to insist on: "les dates clés", "expliqué à un enfant".
    public var focus: String?

    public init(subject: String, depth: KnowledgeDepth = .essentiel, focus: String? = nil) {
        self.subject = subject
        self.depth = depth
        self.focus = focus
    }
}
