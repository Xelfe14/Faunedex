import Foundation

/// What the dealer needs to know about one card. A plain value, so the dealing
/// rule is tested without SwiftData, and the app projects its stored cards
/// into these before every session.
public struct DeckEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// How many times the card has been dealt and passed, over its whole life.
    public var timesDealt: Int
    public var mastery: MasteryState
    /// "Retirée": out of every session for good, until restored.
    public var isRetired: Bool

    public init(id: UUID, timesDealt: Int = 0, mastery: MasteryState = .fresh, isRetired: Bool = false) {
        self.id = id
        self.timesDealt = max(0, timesDealt)
        self.mastery = mastery
        self.isRetired = isRetired
    }
}

/// How a folder's cards divide up at a given moment.
public struct DeckStatus: Sendable, Equatable {
    /// Cards an ordinary session may deal right now.
    public let dealable: Int
    /// Cards resting after a "Maîtrisée".
    public let resting: Int
    /// Cards taken out of the rotation.
    public let retired: Int
    /// The day the earliest resting card comes back, if any card is resting.
    public let nextReturn: Date?

    public init(dealable: Int, resting: Int, retired: Int, nextReturn: Date?) {
        self.dealable = dealable
        self.resting = resting
        self.retired = retired
        self.nextReturn = nextReturn
    }

    public var total: Int { dealable + resting + retired }

    /// Nothing left to deal because everything still in play is resting.
    /// This is the "Dossier maîtrisé !" state. A folder whose cards are all
    /// retired is not mastered, it is empty of play, so it does not count.
    public var isMastered: Bool { dealable == 0 && resting > 0 }
}

/// Deals a session's cards like a real, shuffled pack.
///
/// The obvious reading of "fully random" (pick N cards afresh every session)
/// behaves badly over time: with 100 cards and 20 per session, after five
/// sessions about 33 cards have never appeared while others have come up two or
/// three times, and it takes about 24 sessions on average before every card has
/// appeared once. A pack of cards does not do that. Dealt from the top and only
/// reshuffled when empty, it shows every card once before any card twice.
///
/// The rule that reproduces a pack, whichever folder a session is drawn from:
/// every card records how many times it has been dealt; a session takes the
/// cards with the lowest count first, choosing uniformly at random among cards
/// that share a count, and only moves up to the next count when it needs more.
/// Two useful consequences fall out of it. A new card (count 0) comes up in the
/// very next session of its folder. A card back from its rest has fallen behind
/// the others, so it too comes up soon, which is exactly the moment to check it.
public enum DeckDealer {

    /// Cards an ordinary session may deal: neither retired nor resting.
    public static func dealable(_ entries: [DeckEntry], at now: Date) -> [DeckEntry] {
        entries.filter { !$0.isRetired && !MasteryRule.isResting($0.mastery, at: now) }
    }

    /// Cards resting right now. Only "Réviser quand même" deals these.
    public static func resting(_ entries: [DeckEntry], at now: Date) -> [DeckEntry] {
        entries.filter { !$0.isRetired && MasteryRule.isResting($0.mastery, at: now) }
    }

    public static func status(of entries: [DeckEntry], at now: Date) -> DeckStatus {
        let resting = resting(entries, at: now)
        return DeckStatus(
            dealable: dealable(entries, at: now).count,
            resting: resting.count,
            retired: entries.filter(\.isRetired).count,
            nextReturn: resting.compactMap(\.mastery.restUntil).min()
        )
    }

    /// Deal up to `count` cards from `pool`, returned in session order.
    ///
    /// The selection follows the pack rule above. The order is then shuffled
    /// again as a whole, so a session that finishes one round of the pack and
    /// starts the next does not present the old cards first and the new ones
    /// after: the learner cannot tell where the round ended.
    ///
    /// The generator is a parameter so tests can use a seeded one and replay
    /// the exact same "random" deal; the app uses the system's secure one.
    public static func deal<G: RandomNumberGenerator>(
        from pool: [DeckEntry],
        count: Int,
        using generator: inout G
    ) -> [UUID] {
        guard count > 0, !pool.isEmpty else { return [] }

        // Grouping keeps each tier in the pool's original order, and the tiers
        // are visited by ascending count, so the only randomness is the
        // generator's. That is what makes a seeded deal replayable.
        let tiers = Dictionary(grouping: pool, by: \.timesDealt).sorted { $0.key < $1.key }
        var chosen: [DeckEntry] = []
        for (_, tier) in tiers {
            let needed = count - chosen.count
            guard needed > 0 else { break }
            chosen.append(contentsOf: tier.shuffled(using: &generator).prefix(needed))
        }
        return chosen.shuffled(using: &generator).map(\.id)
    }

    /// Deal with the system's cryptographically secure generator.
    public static func deal(from pool: [DeckEntry], count: Int) -> [UUID] {
        var generator = SystemRandomNumberGenerator()
        return deal(from: pool, count: count, using: &generator)
    }
}
