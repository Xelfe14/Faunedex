import Testing
import Foundation
@testable import FlaunedexCore

/// The "Maîtrisée" rule, pinned date by date. The first test is the worked
/// example Taddeo approved, replayed literally.
struct MasteryRuleTests {

    private let calendar = Paris.calendar

    @Test func theApprovedExampleHappensExactlyAsDescribed() {
        // 23 September, 21:00: Maîtrisée. The card rests until 23 October.
        let first = MasteryRule.afterMastered(.fresh, at: Paris.date(2026, 9, 23, 21), calendar: calendar)
        #expect(first.level == 1)
        #expect(first.restUntil == Paris.date(2026, 10, 23))

        // 28 October: it came back, still known: Maîtrisée. 60 days, to 27 December.
        let second = MasteryRule.afterMastered(first, at: Paris.date(2026, 10, 28, 18), calendar: calendar)
        #expect(second.level == 2)
        #expect(second.restUntil == Paris.date(2026, 12, 27))

        // 5 January: hesitation, Suivante. An ordinary card again.
        let third = MasteryRule.afterNotMastered(second)
        #expect(third == .fresh)
        #expect(third.restUntil == nil)
    }

    @Test func restsDoubleThenStopAtOneYear() {
        #expect(MasteryRule.restDays(forLevel: 0) == 0)
        #expect(MasteryRule.restDays(forLevel: -3) == 0)
        #expect(MasteryRule.restDays(forLevel: 1) == 30)
        #expect(MasteryRule.restDays(forLevel: 2) == 60)
        #expect(MasteryRule.restDays(forLevel: 3) == 120)
        #expect(MasteryRule.restDays(forLevel: 4) == 240)
        #expect(MasteryRule.restDays(forLevel: 5) == 365, "480 would exceed the one-year cap")
        #expect(MasteryRule.restDays(forLevel: 6) == 365)
    }

    @Test func anAbsurdLevelCannotOverflow() {
        #expect(MasteryRule.restDays(forLevel: Int.max) == 365)
    }

    @Test func theCardIsBackAtTheFirstInstantOfItsDay() {
        let state = MasteryRule.afterMastered(.fresh, at: Paris.date(2026, 9, 23, 21), calendar: calendar)
        #expect(MasteryRule.isResting(state, at: Paris.date(2026, 10, 22, 23, 59)))
        #expect(!MasteryRule.isResting(state, at: Paris.date(2026, 10, 23)))
        #expect(!MasteryRule.isResting(state, at: Paris.date(2026, 10, 23, 0, 1)))
    }

    @Test func theTimeOfDayOfThePressDoesNotMatter() {
        let morning = MasteryRule.afterMastered(.fresh, at: Paris.date(2026, 9, 23, 6), calendar: calendar)
        let night = MasteryRule.afterMastered(.fresh, at: Paris.date(2026, 9, 23, 23, 59), calendar: calendar)
        #expect(morning.restUntil == night.restUntil)
    }

    @Test func daylightSavingDoesNotShiftTheReturnDay() throws {
        // Summer time ends on 25 October 2026. A month counted in seconds would
        // land at 23:00 on 8 November; counted in days it lands at midnight on
        // the 9th, which is what "30 days" means to a person.
        let state = MasteryRule.afterMastered(.fresh, at: Paris.date(2026, 10, 10, 21), calendar: calendar)
        let until = try #require(state.restUntil)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: until)
        #expect(parts.month == 11 && parts.day == 9 && parts.hour == 0 && parts.minute == 0)
        let elapsed = until.timeIntervalSince(Paris.date(2026, 10, 10))
        #expect(elapsed == 30 * 86_400 + 3_600, "the clock went back one hour on the way")
    }

    @Test func masteringWhileStillRestingRestartsTheRestWithoutPromotion() {
        // Only "Réviser quand même" can show a resting card.
        let resting = MasteryState(level: 2, restUntil: Paris.date(2026, 12, 27))
        let now = Paris.date(2026, 11, 1, 10)
        #expect(MasteryRule.isResting(resting, at: now))

        let after = MasteryRule.afterMastered(resting, at: now, calendar: calendar)
        #expect(after.level == 2, "an early confirmation does not earn a longer rest")
        #expect(after.restUntil == Paris.date(2026, 12, 31), "60 days from 1 November")
    }

    @Test func notMasteringWipesAnyHistory() {
        let states = [
            MasteryState.fresh,
            MasteryState(level: 1, restUntil: Paris.date(2026, 10, 23)),
            MasteryState(level: 7, restUntil: nil),
        ]
        for state in states {
            #expect(MasteryRule.afterNotMastered(state) == .fresh)
        }
    }

    @Test func aDueCardClimbsOneLevelPerConfirmation() throws {
        var state = MasteryState.fresh
        var now = Paris.date(2026, 1, 1, 12)
        var rests: [Int] = []
        for _ in 0..<6 {
            state = MasteryRule.afterMastered(state, at: now, calendar: calendar)
            let until = try #require(state.restUntil)
            rests.append(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: until).day!)
            now = until.addingTimeInterval(3_600)
        }
        #expect(rests == [30, 60, 120, 240, 365, 365])
        #expect(state.level == 6)
    }

    @Test func aNegativeLevelIsClampedToFresh() {
        #expect(MasteryState(level: -4).level == 0)
    }
}
