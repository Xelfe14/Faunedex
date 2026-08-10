import Foundation
import Observation

/// Observable holder for the three API keys the app can use. The Gemini key is
/// required; the IUCN and Xeno-canto keys are optional (the app degrades to the
/// keyless fallbacks — Wikidata for status, no birdsong — when they're absent).
@Observable
final class APIKeys {
    private let keychain = KeychainStore()

    enum Account: String { case gemini, iucn, xenoCanto }

    var geminiKey: String {
        didSet { keychain.set(geminiKey, for: Account.gemini.rawValue) }
    }
    var iucnToken: String {
        didSet { keychain.set(iucnToken, for: Account.iucn.rawValue) }
    }
    var xenoCantoKey: String {
        didSet { keychain.set(xenoCantoKey, for: Account.xenoCanto.rawValue) }
    }

    init() {
        geminiKey = keychain.get(Account.gemini.rawValue) ?? ""
        iucnToken = keychain.get(Account.iucn.rawValue) ?? ""
        xenoCantoKey = keychain.get(Account.xenoCanto.rawValue) ?? ""
    }

    var hasGeminiKey: Bool { !geminiKey.isEmpty }
}
