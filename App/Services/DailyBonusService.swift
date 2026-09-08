import Foundation
import Observation
import SpadesEconomy

/// Awards the escalating login bonus on the first foreground of each local day.
///
/// The rule and the anti-cheat live in `SpadesEconomy`. This type's whole job is
/// the calendar boundary: turning `Calendar.current` and a monotonic clock into
/// the day-keys and readings that rule takes as inputs (§4).
@MainActor
@Observable
final class DailyBonusService {
    /// A granted claim the player has not yet been shown.
    private(set) var pendingAward: DailyBonusResult?

    private let career: CareerStore
    private let clock: CalendarClock

    init(career: CareerStore, clock: CalendarClock = CalendarClock()) {
        self.career = career
        self.clock = clock
    }

    /// Call on every foreground. Grants at most one bonus per local calendar day.
    @discardableResult
    func claimIfDue() -> DailyBonusResult {
        let profile = career.profile
        let dayKey = clock.dayKey
        let monotonic = clock.monotonicSeconds

        let result = evaluateDailyBonus(
            dayKey: dayKey,
            previousDayKey: clock.previousDayKey,
            lastClaimDayKey: profile.lastDailyBonusDayKey,
            currentStreak: profile.dailyBonusStreak,
            monotonicNow: monotonic,
            lastClaimMonotonic: profile.lastDailyBonusMonotonic
        )

        career.apply(
            applyDailyBonus(
                result,
                to: profile,
                dayKey: dayKey,
                monotonicNow: monotonic,
                claimedAt: clock.now
            )
        )
        pendingAward = result.granted ? result : nil
        return result
    }

    func acknowledgeAward() { pendingAward = nil }

    /// What the next claim would be worth, for the "come back tomorrow" line.
    var nextStreakDay: Int {
        let profile = career.profile
        let result = evaluateDailyBonus(
            dayKey: clock.dayKey,
            previousDayKey: clock.previousDayKey,
            lastClaimDayKey: profile.lastDailyBonusDayKey,
            currentStreak: profile.dailyBonusStreak,
            monotonicNow: clock.monotonicSeconds,
            lastClaimMonotonic: profile.lastDailyBonusMonotonic
        )
        return result.granted ? result.streakDay : profile.dailyBonusStreak + 1
    }

    var nextAmount: Int { DailyBonus.amount(forStreakDay: nextStreakDay) }
}
