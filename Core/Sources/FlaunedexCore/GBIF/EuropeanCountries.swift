import Foundation

/// The canonical set of European ISO 3166-1 alpha-2 country codes the app
/// recognizes, plus French display names for the country filter.
///
/// GBIF's `continent=EUROPE` filter is not trustworthy on its own (it leaks
/// overseas territories and edge records), so every distribution result is
/// **intersected with this whitelist**. Transcontinental countries with a
/// substantial European portion and shared species ranges (Russia, Turkey,
/// Cyprus, Georgia, Kazakhstan, Armenia, Azerbaijan) are included on purpose.
public enum EuropeanCountries {

    /// ISO alpha-2 → French country name. The keys are the whitelist.
    public static let frenchNames: [String: String] = [
        "AL": "Albanie",
        "AD": "Andorre",
        "AT": "Autriche",
        "AM": "Arménie",
        "AZ": "Azerbaïdjan",
        "BY": "Biélorussie",
        "BE": "Belgique",
        "BA": "Bosnie-Herzégovine",
        "BG": "Bulgarie",
        "HR": "Croatie",
        "CY": "Chypre",
        "CZ": "Tchéquie",
        "DK": "Danemark",
        "EE": "Estonie",
        "FO": "Îles Féroé",
        "FI": "Finlande",
        "FR": "France",
        "GE": "Géorgie",
        "DE": "Allemagne",
        "GI": "Gibraltar",
        "GR": "Grèce",
        "GG": "Guernesey",
        "HU": "Hongrie",
        "IS": "Islande",
        "IE": "Irlande",
        "IM": "Île de Man",
        "IT": "Italie",
        "JE": "Jersey",
        "KZ": "Kazakhstan",
        "XK": "Kosovo",
        "LV": "Lettonie",
        "LI": "Liechtenstein",
        "LT": "Lituanie",
        "LU": "Luxembourg",
        "MT": "Malte",
        "MD": "Moldavie",
        "MC": "Monaco",
        "ME": "Monténégro",
        "NL": "Pays-Bas",
        "MK": "Macédoine du Nord",
        "NO": "Norvège",
        "PL": "Pologne",
        "PT": "Portugal",
        "RO": "Roumanie",
        "RU": "Russie",
        "SM": "Saint-Marin",
        "RS": "Serbie",
        "SK": "Slovaquie",
        "SI": "Slovénie",
        "ES": "Espagne",
        "SE": "Suède",
        "CH": "Suisse",
        "TR": "Turquie",
        "UA": "Ukraine",
        "GB": "Royaume-Uni",
        "VA": "Vatican",
    ]

    /// The whitelist as a set of uppercase alpha-2 codes.
    public static let codes: Set<String> = Set(frenchNames.keys)

    /// Whether a code (case-insensitive) is a recognized European country.
    public static func contains(_ code: String) -> Bool {
        codes.contains(code.uppercased())
    }

    /// French display name for a code, or the code itself if unknown.
    public static func frenchName(for code: String) -> String {
        frenchNames[code.uppercased()] ?? code.uppercased()
    }

    /// Keep only recognized European codes, uppercased, de-duplicated, and
    /// sorted for stable output.
    public static func filterToEurope<S: Sequence>(_ input: S) -> [String] where S.Element == String {
        var seen = Set<String>()
        var result: [String] = []
        for raw in input {
            let code = raw.uppercased()
            guard codes.contains(code), !seen.contains(code) else { continue }
            seen.insert(code)
            result.append(code)
        }
        return result.sorted()
    }
}
