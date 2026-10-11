import Foundation

/// Where a card stands in the "Maîtrisée" cycle.
///
/// `level` counts how many times in a row the card was confirmed as mastered
/// when it came due. `restUntil` is the first instant the card may be dealt
/// again: while it lies in the future the card is "au repos" and no ordinary
/// session will show it.
public struct MasteryState: Sendable, Equatable, Codable {
    public var level: Int
    public var restUntil: Date?

    public init(level: Int = 0, restUntil: Date? = nil) {
        self.level = max(0, level)
        self.restUntil = restUntil
    }

    /// A card that was never marked, or whose marks were wiped.
    public static let fresh = MasteryState()
}

/// The "Maîtrisée" rule.
///
/// This is the Leitner system (Sebastian Leitner, 1972) expressed in calendar
/// days instead of cardboard boxes:
///
/// - Pressing "Maîtrisée" on a card that is due sends it to rest: 30 days the
///   first time, then twice as long at each consecutive confirmation (60, 120,
///   240), never more than a year.
/// - Showing a card and moving on without pressing "Maîtrisée" wipes its
///   history completely, so it behaves as if it had never been marked. That is
///   Leitner's "back to box 1".
///
/// Rests are counted in calendar days, not in sessions, because one card can be
/// dealt by sessions on several folders (its own, or any folder above it), and
/// a count of sessions would mean something different in each.
public enum MasteryRule {

    /// Length of the first rest, in days.
    public static let baseRestDays = 30
    /// Longest possible rest, in days, however often the card is confirmed.
    public static let maximumRestDays = 365

    /// The rest that `level` earns: 30, 60, 120, 240, then 365 from level 5 on.
    /// Level 0 earns no rest. Computed by doubling with an early stop, so a
    /// corrupt, enormous level cannot overflow.
    public static func restDays(forLevel level: Int) -> Int {
        guard level >= 1 else { return 0 }
        var days = baseRestDays
        var reached = 1
        while reached < level && days < maximumRestDays {
            days *= 2
            reached += 1
        }
        return min(days, maximumRestDays)
    }

    /// Whether the card is resting at `now`. The boundary is exclusive: a card
    /// resting "until 23 October" is back at the first instant of that day.
    public static func isResting(_ state: MasteryState, at now: Date) -> Bool {
        guard let until = state.restUntil else { return false }
        return now < until
    }

    /// The learner pressed "Maîtrisée".
    ///
    /// On a card that is due, the level goes up by one and a rest of the new
    /// level's length starts. On a card pressed while still resting (possible
    /// only through "Réviser quand même"), the rest restarts from today at the
    /// same level: the confirmation came early, so it is not rewarded with a
    /// longer rest, which is meant to prove the card survived its full absence.
    public static func afterMastered(_ state: MasteryState, at now: Date, calendar: Calendar) -> MasteryState {
        let early = isResting(state, at: now)
        let level = early ? max(state.level, 1) : state.level + 1
        let until = firstDayBack(after: now, restingDays: restDays(forLevel: level), calendar: calendar)
        return MasteryState(level: level, restUntil: until)
    }

    /// The card was shown and the learner moved on without pressing
    /// "Maîtrisée". Whatever its history, it is an ordinary card again.
    public static func afterNotMastered(_ state: MasteryState) -> MasteryState {
        .fresh
    }

    /// Midnight at the start of the day the card comes back, `days` calendar
    /// days after the day of `now`.
    ///
    /// Aligning on midnight makes the promise the app displays exact: "Prochaine
    /// carte le 23 octobre" means the card is dealable from the first instant of
    /// the 23rd, not from 21:14 because that is when it was pressed a month
    /// before. Calendar arithmetic, not 86,400-second arithmetic, keeps this
    /// right across daylight-saving changes.
    public static func firstDayBack(after now: Date, restingDays days: Int, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let day = calendar.date(byAdding: .day, value: days, to: today) else {
            return today.addingTimeInterval(TimeInterval(days) * 86_400)
        }
        return calendar.startOfDay(for: day)
    }
}
