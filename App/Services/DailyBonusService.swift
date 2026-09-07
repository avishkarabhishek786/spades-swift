import Foundation
import Observation
import SpadesEngine

/// Awards the escalating login bonus on the first foreground of each local day.
///
/// The rule and the anti-cheat both live in `SpadesEngine.DailyBonus`, which
/// takes the clock as a parameter. This type supplies the clock and nothing else.
@MainActor
@Observable
final class DailyBonusService {
    /// The claim the player has not yet been shown.
    private(set) var pendingAward: DailyBonus.Evaluation?

    private let career: CareerStore
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(career: CareerStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.career = career
        self.calendar = calendar
        self.now = now
    }

    /// Call on every foreground. Grants at most one bonus per local calendar day.
    @discardableResult
    func claimIfDue() -> DailyBonus.Evaluation {
        let (updated, evaluation) = DailyBonus.claim(
            profile: career.profile,
            now: now(),
            calendar: calendar
        )
        career.apply(updated)
        pendingAward = evaluation.granted ? evaluation : nil
        return evaluation
    }

    func acknowledgeAward() { pendingAward = nil }

    /// What the next claim would be worth, for the "come back tomorrow" line.
    var nextStreakDay: Int {
        let evaluation = DailyBonus.evaluate(profile: career.profile, now: now(), calendar: calendar)
        return evaluation.granted ? evaluation.streakDay : career.profile.dailyBonusStreak + 1
    }

    var nextAmount: Int { DailyBonus.amount(forStreakDay: nextStreakDay) }
}
