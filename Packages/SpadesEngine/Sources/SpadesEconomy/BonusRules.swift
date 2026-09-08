import Foundation

/// The outcome of a daily bonus evaluation.
public struct DailyBonusResult: Equatable, Sendable {
    public let granted: Bool
    public let points: Int
    /// The streak day this claim represents, or the streak left standing if
    /// nothing was granted. Zero when the streak was broken.
    public let streakDay: Int
    /// True when the clock looks tampered with. No grant, and the streak breaks.
    public let clockRolledBack: Bool

    public init(granted: Bool, points: Int, streakDay: Int, clockRolledBack: Bool) {
        self.granted = granted
        self.points = points
        self.streakDay = streakDay
        self.clockRolledBack = clockRolledBack
    }
}

/// The escalating login bonus.
public enum DailyBonus {
    /// Days 1 through 7, then held at the last value.
    public static let ladder = [50, 75, 100, 150, 200, 300, 500]

    public static func amount(forStreakDay day: Int) -> Int {
        guard day >= 1 else { return 0 }
        return ladder[min(day, ladder.count) - 1]
    }

    /// Minimum advance of the continuous clock between two granted bonuses.
    ///
    /// A genuine midnight crossing while the app is in use can be only seconds
    /// of wall time, but the monotonic clock keeps running while the device is
    /// asleep, so between two real foregrounds a day apart it will have moved
    /// far more than this. Winding the date forward repeatedly in one sitting
    /// moves it barely at all.
    ///
    /// This is a speed bump, not a wall: without a server clock there is no way
    /// to make it one, and v1 deliberately has no backend. It costs a cheater
    /// time and costs an honest player at most one skipped bonus in the rare
    /// case they foreground within a minute either side of local midnight.
    public static let minimumMonotonicSecondsBetweenClaims: UInt64 = 60
}

/// Decides whether a daily bonus is owed.
///
/// Every calendar decision has already been made by the caller. `dayKey` and
/// `previousDayKey` come from `Calendar.current` in the app layer, and the
/// monotonic reading comes from a continuous clock there too. Keeping
/// `Calendar` out of this module is what makes the clock-rollback case testable
/// without a device, and what stops the suite passing in one CI region and
/// failing in another.
///
/// - Parameters:
///   - dayKey: Today in the user's calendar, "yyyy-MM-dd".
///   - previousDayKey: The day before `dayKey` in the user's calendar. Needed
///     because deciding whether two day-keys are consecutive is calendar
///     arithmetic — month lengths, leap years — and that cannot happen here.
///     (Spec §4's signature omits this; see the note in §17 of CLAUDE.md.)
///   - lastClaimDayKey: The day-key stored at the last granted claim.
///   - currentStreak: The streak standing before this evaluation.
///   - monotonicNow: A continuous monotonic clock reading in seconds. Must
///     advance while the device sleeps and may reset on reboot.
///   - lastClaimMonotonic: The reading stored at the last granted claim.
public func evaluateDailyBonus(
    dayKey: String,
    previousDayKey: String,
    lastClaimDayKey: String?,
    currentStreak: Int,
    monotonicNow: UInt64,
    lastClaimMonotonic: UInt64?
) -> DailyBonusResult {
    guard let lastClaimDayKey else {
        return DailyBonusResult(
            granted: true,
            points: DailyBonus.amount(forStreakDay: 1),
            streakDay: 1,
            clockRolledBack: false
        )
    }

    // Day-keys are "yyyy-MM-dd", so lexicographic order is chronological order
    // and no date parsing is needed to compare them.
    if dayKey < lastClaimDayKey {
        // Wall time moved backwards. Break the streak rather than paying out;
        // the device clock is not trustworthy for grants.
        return DailyBonusResult(granted: false, points: 0, streakDay: 0, clockRolledBack: true)
    }

    if dayKey == lastClaimDayKey {
        return DailyBonusResult(granted: false, points: 0, streakDay: currentStreak, clockRolledBack: false)
    }

    // The day advanced. If the monotonic clock barely moved, the date was
    // wound forward rather than lived through. A monotonic reading *lower*
    // than the stored one means a reboot, which is normal and not evidence of
    // anything, so it is deliberately not treated as tampering.
    if let lastClaimMonotonic, monotonicNow >= lastClaimMonotonic,
       monotonicNow - lastClaimMonotonic < DailyBonus.minimumMonotonicSecondsBetweenClaims {
        return DailyBonusResult(granted: false, points: 0, streakDay: 0, clockRolledBack: true)
    }

    let streakDay = lastClaimDayKey == previousDayKey ? max(1, currentStreak) + 1 : 1
    return DailyBonusResult(
        granted: true,
        points: DailyBonus.amount(forStreakDay: streakDay),
        streakDay: streakDay,
        clockRolledBack: false
    )
}

/// Applies a granted daily bonus to a profile.
///
/// Returns the profile unchanged when nothing is owed, and clears the streak
/// without touching the stored claim markers when the clock looks rolled back —
/// those markers must never move backwards.
public func applyDailyBonus(
    _ result: DailyBonusResult,
    to profile: CareerProfile,
    dayKey: String,
    monotonicNow: UInt64,
    claimedAt: Date?
) -> CareerProfile {
    var profile = profile

    if result.clockRolledBack {
        profile.dailyBonusStreak = 0
        return profile
    }
    guard result.granted else { return profile }

    profile.award(result.points)
    profile.dailyBonusStreak = result.streakDay
    profile.lastDailyBonusDayKey = dayKey
    profile.lastDailyBonusMonotonic = monotonicNow
    profile.lastDailyBonusClaim = claimedAt
    return profile
}

/// Rewarded video. The SDK lives behind `AdProviding` in the app layer; this is
/// only the accounting.
public enum AdReward {
    public static let pointsPerView = 100
    public static let dailyCap = 5

    /// Views still available on `dayKey`. Rolls over on the local calendar day.
    public static func remainingToday(profile: CareerProfile, dayKey: String) -> Int {
        guard profile.adBonusDayKey == dayKey else { return dailyCap }
        return max(0, dailyCap - profile.adBonusesClaimedToday)
    }

    public static func canWatch(profile: CareerProfile, dayKey: String) -> Bool {
        remainingToday(profile: profile, dayKey: dayKey) > 0
    }

    /// Grants one reward. Call this from the SDK's reward callback only — never
    /// from the dismissal callback. Returns the profile unchanged if the daily
    /// cap is already spent.
    public static func grant(profile: CareerProfile, dayKey: String) -> CareerProfile {
        guard canWatch(profile: profile, dayKey: dayKey) else { return profile }
        var updated = profile
        if updated.adBonusDayKey != dayKey {
            updated.adBonusDayKey = dayKey
            updated.adBonusesClaimedToday = 0
        }
        updated.adBonusesClaimedToday += 1
        updated.award(pointsPerView)
        return updated
    }
}
