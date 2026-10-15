import Foundation

/// How a review went, as the learner judges it.
public enum ReviewRating: String, Codable, Sendable, CaseIterable, Hashable {
    /// Didn't know it: the card comes back in this session and starts over.
    case again
    /// Knew it: the card moves up one box.
    case good
    /// Knew it without thinking: the card skips a box.
    case easy

    public var frenchLabel: String {
        switch self {
        case .again: return "À revoir"
        case .good: return "Je sais"
        case .easy: return "Facile"
        }
    }
}

/// Where a card stands in the review cycle.
public struct ReviewState: Sendable, Equatable {
    /// 0 for a card never learned or just forgotten, then 1...`maxBox`.
    public var box: Int
    /// When the card is next due. Nil until its first review: a new card is
    /// always due.
    public var dueAt: Date?
    public var reviewCount: Int
    /// Times a card that had been learned was forgotten.
    public var lapseCount: Int
    public var lastReviewedAt: Date?

    public init(box: Int = 0, dueAt: Date? = nil, reviewCount: Int = 0, lapseCount: Int = 0,
                lastReviewedAt: Date? = nil) {
        self.box = box
        self.dueAt = dueAt
        self.reviewCount = reviewCount
        self.lapseCount = lapseCount
        self.lastReviewedAt = lastReviewedAt
    }

    public var isNew: Bool { reviewCount == 0 }

    public func isDue(at now: Date) -> Bool {
        guard let dueAt else { return true }
        return dueAt <= now
    }
}

/// Spaced repetition with Leitner boxes: each correct answer moves a card to a
/// box reviewed less often, a miss sends it back to the start.
///
/// Deliberately simpler than Anki's algorithm. A handful of fixed intervals is
/// easy to reason about ("Je sais" on a card in box 3 means two weeks), and for
/// a personal deck of a few hundred cards it schedules just as well.
public enum ReviewScheduler {

    /// Days until the next review once a card reaches each box, box 1 first.
    public static let intervals = [1, 3, 7, 14, 30, 60, 120]

    public static var maxBox: Int { intervals.count }

    public static func days(forBox box: Int) -> Int {
        guard box >= 1 else { return 0 }
        return intervals[min(box, maxBox) - 1]
    }

    public static func nextBox(from box: Int, rating: ReviewRating) -> Int {
        switch rating {
        case .again: return 0
        case .good: return min(max(box, 0) + 1, maxBox)
        case .easy: return min(max(box, 0) + 2, maxBox)
        }
    }

    /// The state after a review. A card that comes due lands at the start of
    /// its day, so one reviewed late in the evening is due first thing on the
    /// day it is scheduled for, not at 23:00.
    public static func review(_ state: ReviewState, rating: ReviewRating, now: Date,
                              calendar: Calendar = .current) -> ReviewState {
        var next = state
        next.reviewCount += 1
        next.lastReviewedAt = now
        next.box = nextBox(from: state.box, rating: rating)
        if rating == .again {
            if state.box > 0 { next.lapseCount += 1 }
            next.dueAt = now
        } else {
            next.dueAt = dueDate(inDays: days(forBox: next.box), from: now, calendar: calendar)
        }
        return next
    }

    public static func dueDate(inDays days: Int, from now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400)
    }

    /// Whole days from today to the day of `date`; 0 or less when it is due.
    public static func daysUntil(_ date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// "demain", "dans 3 jours", "dans 2 semaines", "dans 4 mois".
    public static func frenchDelay(days: Int) -> String {
        switch days {
        case ..<1: return "aujourd'hui"
        case 1: return "demain"
        case 2..<14: return "dans \(days) jours"
        case 14..<30: return "dans \(days / 7) semaines"
        default:
            let months = days / 30
            return "dans \(months) mois"
        }
    }

    /// What pressing a rating would schedule, for the caption under each button.
    public static func preview(_ state: ReviewState, rating: ReviewRating) -> String {
        rating == .again ? "tout de suite" : frenchDelay(days: days(forBox: nextBox(from: state.box, rating: rating)))
    }
}
