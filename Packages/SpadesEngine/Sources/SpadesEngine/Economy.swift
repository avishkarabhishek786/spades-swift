import Foundation

/// Career progress. Persisted by the app layer; the maths lives here so it is
/// testable without a simulator, a filesystem or a clock.
///
/// Points are entertainment currency. They are never purchasable, never
/// cashable out and never transferable — see the compliance note in §9.
public struct CareerProfile: Codable, Equatable, Sendable {
    /// Career currency. Never below zero; see ``Economy/settle(profile:tier:outcome:soloVsBots:)``.
    public var points: Int
    public var lifetimePointsEarned: Int
    public var gamesPlayed: Int
    public var gamesWon: Int
    public var nilsMade: Int
    public var nilsFailed: Int
    public var currentStreak: Int
    public var bestStreak: Int
    public var lastDailyBonusClaim: Date?
    public var adBonusesClaimedToday: Int
    /// "yyyy-MM-dd" in the user's local calendar.
    public var adBonusDayKey: String
    /// Consecutive days the daily bonus has been claimed. Day 1 is the first claim.
    public var dailyBonusStreak: Int

    public init(
        points: Int = 0,
        lifetimePointsEarned: Int = 0,
        gamesPlayed: Int = 0,
        gamesWon: Int = 0,
        nilsMade: Int = 0,
        nilsFailed: Int = 0,
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        lastDailyBonusClaim: Date? = nil,
        adBonusesClaimedToday: Int = 0,
        adBonusDayKey: String = "",
        dailyBonusStreak: Int = 0
    ) {
        self.points = max(0, points)
        self.lifetimePointsEarned = lifetimePointsEarned
        self.gamesPlayed = gamesPlayed
        self.gamesWon = gamesWon
        self.nilsMade = nilsMade
        self.nilsFailed = nilsFailed
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.lastDailyBonusClaim = lastDailyBonusClaim
        self.adBonusesClaimedToday = adBonusesClaimedToday
        self.adBonusDayKey = adBonusDayKey
        self.dailyBonusStreak = dailyBonusStreak
    }

    public static let new = CareerProfile()

    /// Decoding tolerates missing keys.
    ///
    /// Swift's synthesised decoder ignores property defaults and throws on any
    /// absent key, so without this the first field added to this struct makes
    /// every existing save unreadable — and this struct is the player's actual
    /// progress. The schema version in `VersionedDocument` covers reshaping;
    /// this covers merely growing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = max(0, try container.decodeIfPresent(Int.self, forKey: .points) ?? 0)
        lifetimePointsEarned = try container.decodeIfPresent(Int.self, forKey: .lifetimePointsEarned) ?? 0
        gamesPlayed = try container.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        gamesWon = try container.decodeIfPresent(Int.self, forKey: .gamesWon) ?? 0
        nilsMade = try container.decodeIfPresent(Int.self, forKey: .nilsMade) ?? 0
        nilsFailed = try container.decodeIfPresent(Int.self, forKey: .nilsFailed) ?? 0
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak = try container.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        lastDailyBonusClaim = try container.decodeIfPresent(Date.self, forKey: .lastDailyBonusClaim)
        adBonusesClaimedToday = try container.decodeIfPresent(Int.self, forKey: .adBonusesClaimedToday) ?? 0
        adBonusDayKey = try container.decodeIfPresent(String.self, forKey: .adBonusDayKey) ?? ""
        dailyBonusStreak = try container.decodeIfPresent(Int.self, forKey: .dailyBonusStreak) ?? 0
    }

    /// Adds points and keeps `lifetimePointsEarned` in step. Clamps at zero:
    /// a player at zero must always be able to sit at a Casual table.
    mutating func award(_ delta: Int) {
        if delta > 0 { lifetimePointsEarned += delta }
        points = max(0, points + delta)
    }
}

/// The lobby's stake tiers.
public enum StakeTier: String, CaseIterable, Codable, Sendable, Identifiable {
    case casual, bronze, silver, gold, elite

    public var id: String { rawValue }

    /// Points staked to enter a match at this tier.
    public var entry: Int {
        switch self {
        case .casual: 0
        case .bronze: 50
        case .silver: 200
        case .gold: 750
        case .elite: 2_500
        }
    }

    /// Points paid to each member of the winning partnership.
    public var winPayout: Int {
        switch self {
        case .casual: 25
        case .bronze: 100
        case .silver: 425
        case .gold: 1_600
        case .elite: 5_500
        }
    }

    /// Lifetime points needed before this tier appears in the lobby at all.
    public var unlockThreshold: Int {
        switch self {
        case .casual: 0
        case .bronze: 100
        case .silver: 500
        case .gold: 2_000
        case .elite: 10_000
        }
    }

    public var displayNameKey: String { "stake.\(rawValue)" }
}

/// Points, stakes and bonuses. Pure functions over ``CareerProfile``; the app
/// layer supplies the clock and the storage.
public enum Economy {
    /// Solo matches against bots pay — and cost — 40% of the listed figures,
    /// so farming bots does not trivialise the ladder.
    public static let soloNumerator = 2
    public static let soloDenominator = 5

    /// How much a match at this tier stakes, for this opponent mix.
    public static func entry(for tier: StakeTier, soloVsBots: Bool) -> Int {
        soloVsBots ? tier.entry * soloNumerator / soloDenominator : tier.entry
    }

    /// How much a win at this tier pays, for this opponent mix.
    public static func payout(for tier: StakeTier, soloVsBots: Bool) -> Int {
        soloVsBots ? tier.winPayout * soloNumerator / soloDenominator : tier.winPayout
    }

    /// Whether the lobby should show this tier at all.
    public static func isUnlocked(_ tier: StakeTier, profile: CareerProfile) -> Bool {
        tier == .casual || profile.lifetimePointsEarned >= tier.unlockThreshold
    }

    /// Whether the player can actually sit down at this tier right now.
    /// Casual is always selectable — never trap a player in an unplayable state.
    public static func isSelectable(_ tier: StakeTier, profile: CareerProfile, soloVsBots: Bool) -> Bool {
        if tier == .casual { return true }
        return isUnlocked(tier, profile: profile) && profile.points >= entry(for: tier, soloVsBots: soloVsBots)
    }

    public static func selectableTiers(profile: CareerProfile, soloVsBots: Bool) -> [StakeTier] {
        StakeTier.allCases.filter { isSelectable($0, profile: profile, soloVsBots: soloVsBots) }
    }

    /// How a match ended for the local player.
    public enum MatchOutcome: String, Codable, Sendable {
        case win
        case loss
        /// Left a ranked match in progress. Forfeits the stake and dents the streak.
        case quit
    }

    /// Streak points lost for abandoning a ranked match. A reconnect inside the
    /// 90-second window is not a quit and never reaches here.
    public static let quitStreakPenalty = 1

    /// Settles a finished match. Applied once, when the game concludes — never per hand.
    public static func settle(
        profile: CareerProfile,
        tier: StakeTier,
        outcome: MatchOutcome,
        soloVsBots: Bool
    ) -> CareerProfile {
        var profile = profile
        profile.gamesPlayed += 1

        switch outcome {
        case .win:
            profile.gamesWon += 1
            profile.currentStreak += 1
            profile.bestStreak = max(profile.bestStreak, profile.currentStreak)
            profile.award(payout(for: tier, soloVsBots: soloVsBots))
        case .loss:
            profile.currentStreak = 0
            profile.award(-entry(for: tier, soloVsBots: soloVsBots))
        case .quit:
            profile.currentStreak = max(0, profile.currentStreak - quitStreakPenalty)
            profile.award(-entry(for: tier, soloVsBots: soloVsBots))
        }

        return profile
    }

    /// Records nil outcomes for the career screen.
    public static func recordNils(profile: CareerProfile, made: Int, failed: Int) -> CareerProfile {
        var profile = profile
        profile.nilsMade += made
        profile.nilsFailed += failed
        return profile
    }
}

/// The escalating login bonus.
///
/// Awarded on the first foreground of each **calendar day in the user's own
/// timezone**, not after a rolling 24 hours. A player in IST who opens the app
/// at 23:00 and again at 08:00 has earned two bonuses.
public enum DailyBonus {
    /// Days 1 through 7, then held at the last value.
    public static let ladder = [50, 75, 100, 150, 200, 300, 500]

    public static func amount(forStreakDay day: Int) -> Int {
        guard day >= 1 else { return 0 }
        return ladder[min(day, ladder.count) - 1]
    }

    /// Local calendar day key, e.g. "2026-09-07".
    ///
    /// Built from `DateComponents` rather than a `DateFormatter` so it cannot
    /// pick up a locale's alternate calendar and silently change shape.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// What a claim attempt would do, without doing it.
    public struct Evaluation: Equatable, Sendable {
        public let granted: Bool
        public let points: Int
        /// Streak day this claim represents, or the streak left intact if not granted.
        public let streakDay: Int
        /// True when the device clock moved backwards, which voids the streak.
        public let clockRolledBack: Bool
    }

    public static func evaluate(
        profile: CareerProfile,
        now: Date,
        calendar: Calendar = .current
    ) -> Evaluation {
        guard let last = profile.lastDailyBonusClaim else {
            return Evaluation(granted: true, points: amount(forStreakDay: 1), streakDay: 1, clockRolledBack: false)
        }

        // Anti-cheat: never grant on a backwards clock. Break the streak instead
        // of paying out — the device clock is not trustworthy for grants.
        if now < last {
            return Evaluation(granted: false, points: 0, streakDay: 0, clockRolledBack: true)
        }

        let lastKey = dayKey(for: last, calendar: calendar)
        let nowKey = dayKey(for: now, calendar: calendar)
        if lastKey == nowKey {
            return Evaluation(granted: false, points: 0, streakDay: profile.dailyBonusStreak, clockRolledBack: false)
        }

        let lastDay = calendar.startOfDay(for: last)
        let today = calendar.startOfDay(for: now)
        let gap = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        let streakDay = gap == 1 ? max(1, profile.dailyBonusStreak) + 1 : 1

        return Evaluation(granted: true, points: amount(forStreakDay: streakDay), streakDay: streakDay, clockRolledBack: false)
    }

    /// Applies a claim. Returns the profile unchanged if nothing is owed.
    public static func claim(
        profile: CareerProfile,
        now: Date,
        calendar: Calendar = .current
    ) -> (profile: CareerProfile, evaluation: Evaluation) {
        let evaluation = evaluate(profile: profile, now: now, calendar: calendar)
        var updated = profile

        if evaluation.clockRolledBack {
            updated.dailyBonusStreak = 0
            return (updated, evaluation)
        }
        guard evaluation.granted else { return (updated, evaluation) }

        updated.award(evaluation.points)
        updated.dailyBonusStreak = evaluation.streakDay
        updated.lastDailyBonusClaim = now
        return (updated, evaluation)
    }
}

/// Rewarded video. The SDK lives behind `AdProviding` in the app layer; this is
/// only the accounting.
public enum AdReward {
    public static let pointsPerView = 100
    public static let dailyCap = 5

    /// Views still available today. Rolls over on the local calendar day.
    public static func remainingToday(profile: CareerProfile, now: Date, calendar: Calendar = .current) -> Int {
        let key = DailyBonus.dayKey(for: now, calendar: calendar)
        guard profile.adBonusDayKey == key else { return dailyCap }
        return max(0, dailyCap - profile.adBonusesClaimedToday)
    }

    public static func canWatch(profile: CareerProfile, now: Date, calendar: Calendar = .current) -> Bool {
        remainingToday(profile: profile, now: now, calendar: calendar) > 0
    }

    /// Grants one reward. Call this from the SDK's reward callback only —
    /// never from the dismissal callback. Returns the profile unchanged if the
    /// daily cap is already spent.
    public static func grant(profile: CareerProfile, now: Date, calendar: Calendar = .current) -> CareerProfile {
        guard canWatch(profile: profile, now: now, calendar: calendar) else { return profile }
        var updated = profile
        let key = DailyBonus.dayKey(for: now, calendar: calendar)
        if updated.adBonusDayKey != key {
            updated.adBonusDayKey = key
            updated.adBonusesClaimedToday = 0
        }
        updated.adBonusesClaimedToday += 1
        updated.award(pointsPerView)
        return updated
    }
}
