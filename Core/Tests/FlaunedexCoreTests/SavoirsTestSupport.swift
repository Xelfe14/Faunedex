import Foundation

/// A repeatable random number generator for tests (SplitMix64).
///
/// The same seed always produces the same sequence, so a test that deals cards
/// "at random" deals exactly the same cards on every run, and any failure can
/// be replayed. SplitMix64 passes the standard statistical batteries, which
/// matters here because some tests measure uniformity.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Dates on the Paris calendar, which is the one the app's user lives in and
/// the one with a daylight-saving change worth testing across.
enum Paris {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
