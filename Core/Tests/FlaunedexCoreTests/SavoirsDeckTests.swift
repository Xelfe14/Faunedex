import Testing
import Foundation
@testable import FlaunedexCore

/// The shuffled-deck rule. The promise made to the learner is concrete: with
/// 100 cards dealt 20 at a time, every card appears exactly once in the first
/// five sessions. These tests hold the dealer to it, and check that the
/// randomness inside that rule is real.
struct DeckDealerTests {

    private let now = Paris.date(2026, 9, 23, 12)

    private func freshCards(_ count: Int) -> [DeckEntry] {
        (0..<count).map { _ in DeckEntry(id: UUID()) }
    }

    // MARK: The pack promise

    @Test func everyCardComesOnceBeforeAnyCardComesTwice() {
        var generator = SeededGenerator(seed: 2026)
        var cards = freshCards(100)

        for session in 1...10 {
            let dealt = DeckDealer.deal(from: cards, count: 20, using: &generator)
            #expect(dealt.count == 20)
            #expect(Set(dealt).count == 20, "no card twice in one session")
            for id in dealt {
                let index = cards.firstIndex { $0.id == id }!
                cards[index].timesDealt += 1
            }
            if session == 5 {
                #expect(cards.allSatisfy { $0.timesDealt == 1 }, "five sessions of 20 show all 100 exactly once")
            }
        }
        #expect(cards.allSatisfy { $0.timesDealt == 2 }, "ten sessions show all 100 exactly twice")
    }

    @Test func theLeastDealtCardsAreTakenFirst() {
        var generator = SeededGenerator(seed: 7)
        let behind = (0..<5).map { _ in DeckEntry(id: UUID(), timesDealt: 0) }
        let ahead = (0..<10).map { _ in DeckEntry(id: UUID(), timesDealt: 3) }
        let dealt = Set(DeckDealer.deal(from: ahead + behind, count: 8, using: &generator))
        #expect(Set(behind.map(\.id)).isSubset(of: dealt), "all five cards seen least must be in")
        #expect(dealt.count == 8)
    }

    @Test func aNewCardComesUpInTheNextSession() {
        var generator = SeededGenerator(seed: 11)
        let seasoned = (0..<40).map { _ in DeckEntry(id: UUID(), timesDealt: 6) }
        let newcomer = DeckEntry(id: UUID(), timesDealt: 0)
        let dealt = DeckDealer.deal(from: seasoned + [newcomer], count: 5, using: &generator)
        #expect(dealt.contains(newcomer.id))
    }

    // MARK: Limits

    @Test func aSmallFolderGivesAShorterSession() {
        var generator = SeededGenerator(seed: 3)
        let cards = freshCards(7)
        let dealt = DeckDealer.deal(from: cards, count: 20, using: &generator)
        #expect(dealt.count == 7)
        #expect(Set(dealt) == Set(cards.map(\.id)))
    }

    @Test func nothingIsDealtFromNothing() {
        var generator = SeededGenerator(seed: 3)
        #expect(DeckDealer.deal(from: [], count: 10, using: &generator).isEmpty)
        #expect(DeckDealer.deal(from: freshCards(5), count: 0, using: &generator).isEmpty)
        #expect(DeckDealer.deal(from: freshCards(5), count: -2, using: &generator).isEmpty)
    }

    @Test func retiredAndRestingCardsStayOutOfOrdinarySessions() {
        let ordinary = DeckEntry(id: UUID())
        let retired = DeckEntry(id: UUID(), isRetired: true)
        let resting = DeckEntry(id: UUID(), mastery: MasteryState(level: 1, restUntil: Paris.date(2026, 10, 23)))
        let back = DeckEntry(id: UUID(), mastery: MasteryState(level: 1, restUntil: Paris.date(2026, 9, 1)))

        let pool = DeckDealer.dealable([ordinary, retired, resting, back], at: now)
        #expect(Set(pool.map(\.id)) == [ordinary.id, back.id], "a card whose rest is over is back in play")

        let asleep = DeckDealer.resting([ordinary, retired, resting, back], at: now)
        #expect(asleep.map(\.id) == [resting.id])
    }

    @Test func aRetiredCardIsNeverCountedAsResting() {
        let both = DeckEntry(id: UUID(), mastery: MasteryState(level: 1, restUntil: Paris.date(2026, 10, 23)), isRetired: true)
        #expect(DeckDealer.resting([both], at: now).isEmpty)
        #expect(DeckDealer.dealable([both], at: now).isEmpty)
    }

    // MARK: "Dossier maîtrisé !"

    @Test func statusCountsEachStateAndFindsTheNextReturn() {
        let entries = [
            DeckEntry(id: UUID()),
            DeckEntry(id: UUID()),
            DeckEntry(id: UUID(), mastery: MasteryState(level: 1, restUntil: Paris.date(2026, 11, 5))),
            DeckEntry(id: UUID(), mastery: MasteryState(level: 2, restUntil: Paris.date(2026, 10, 23))),
            DeckEntry(id: UUID(), isRetired: true),
        ]
        let status = DeckDealer.status(of: entries, at: now)
        #expect(status.dealable == 2)
        #expect(status.resting == 2)
        #expect(status.retired == 1)
        #expect(status.total == 5)
        #expect(status.nextReturn == Paris.date(2026, 10, 23), "the earliest return wins")
        #expect(!status.isMastered)
    }

    @Test func aFolderWithOnlyRestingCardsIsMastered() {
        let entries = [
            DeckEntry(id: UUID(), mastery: MasteryState(level: 1, restUntil: Paris.date(2026, 10, 23))),
            DeckEntry(id: UUID(), isRetired: true),
        ]
        let status = DeckDealer.status(of: entries, at: now)
        #expect(status.isMastered)
        #expect(status.nextReturn == Paris.date(2026, 10, 23))
    }

    @Test func aFolderOfRetiredCardsIsNotMastered() {
        let status = DeckDealer.status(of: [DeckEntry(id: UUID(), isRetired: true)], at: now)
        #expect(!status.isMastered, "nothing was learned, everything was put away")
        #expect(status.nextReturn == nil)
    }

    // MARK: Randomness

    @Test func theSameSeedDealsTheSameSession() {
        let cards = freshCards(50)
        var first = SeededGenerator(seed: 99)
        var second = SeededGenerator(seed: 99)
        #expect(DeckDealer.deal(from: cards, count: 12, using: &first)
                == DeckDealer.deal(from: cards, count: 12, using: &second))
    }

    /// Chi-square test of uniformity. Deal one card out of ten, 100,000 times:
    /// each card should come up about 10,000 times. The statistic sums the
    /// squared gaps relative to that expectation; for a fair deal with 9 degrees
    /// of freedom it exceeds 27.88 only 1 time in 1,000. The seed is fixed, so
    /// the test is deterministic rather than flaky.
    @Test func withinATierEveryCardIsEquallyLikely() {
        var generator = SeededGenerator(seed: 1789)
        let cards = freshCards(10)
        var counts: [UUID: Int] = [:]
        let trials = 100_000
        for _ in 0..<trials {
            let dealt = DeckDealer.deal(from: cards, count: 1, using: &generator)
            counts[dealt[0], default: 0] += 1
        }
        let expected = Double(trials) / 10
        let chiSquare = cards.reduce(0.0) { sum, card in
            let gap = Double(counts[card.id, default: 0]) - expected
            return sum + gap * gap / expected
        }
        #expect(chiSquare < 27.88, "chi-square \(chiSquare)")
    }

    /// When a session straddles two rounds of the pack, the old round's cards
    /// must not all come first. Five of the ten dealt cards are from the older
    /// round, so the first card should be one of them about half the time.
    @Test func aSessionIsShuffledAsAWhole() {
        var generator = SeededGenerator(seed: 1515)
        let older = (0..<5).map { _ in DeckEntry(id: UUID(), timesDealt: 0) }
        let newer = (0..<50).map { _ in DeckEntry(id: UUID(), timesDealt: 1) }
        let olderIDs = Set(older.map(\.id))
        let trials = 20_000
        var olderFirst = 0
        for _ in 0..<trials {
            let dealt = DeckDealer.deal(from: newer + older, count: 10, using: &generator)
            if olderIDs.contains(dealt[0]) { olderFirst += 1 }
        }
        let share = Double(olderFirst) / Double(trials)
        #expect(share > 0.45 && share < 0.55, "share \(share)")
    }

    @Test func theSystemGeneratorDealsTooWithoutRepeats() {
        let cards = freshCards(30)
        let dealt = DeckDealer.deal(from: cards, count: 30)
        #expect(Set(dealt) == Set(cards.map(\.id)))
    }
}
