import Foundation

/// Career progress. Persisted by the app layer; the arithmetic lives here so it
/// is testable without a simulator, a filesystem or a clock.
///
/// Points are entertainment currency. They are never purchasable, never
/// cashable out and never transferable.
public struct CareerProfile: Codable, Equatable, Sendable {
    /// Career currency. Never below zero.
    public var points: Int
    public var lifetimePointsEarned: Int
    public var gamesPlayed: Int
    public var gamesWon: Int
    public var nilsMade: Int
    public var nilsFailed: Int
    public var currentStreak: Int
    public var bestStreak: Int

    /// When the last daily bonus was claimed, for display only. The grant
    /// decision never reads this — see ``lastDailyBonusDayKey`` and
    /// ``lastDailyBonusMonotonic``, which are what ``DailyBonus/evaluate``
    /// takes. The device clock is not trusted for grants.
    public var lastDailyBonusClaim: Date?
    /// "yyyy-MM-dd" in the user's local calendar, resolved by the app layer.
    public var lastDailyBonusDayKey: String?
    /// Reading of a continuous monotonic clock at the last claim, in seconds.
    public var lastDailyBonusMonotonic: UInt64?
    /// Consecutive days claimed. Day 1 is the first claim.
    public var dailyBonusStreak: Int

    public var adBonusesClaimedToday: Int
    /// "yyyy-MM-dd" in the user's local calendar, resolved by the app layer.
    public var adBonusDayKey: String

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
        lastDailyBonusDayKey: String? = nil,
        lastDailyBonusMonotonic: UInt64? = nil,
        dailyBonusStreak: Int = 0,
        adBonusesClaimedToday: Int = 0,
        adBonusDayKey: String = ""
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
        self.lastDailyBonusDayKey = lastDailyBonusDayKey
        self.lastDailyBonusMonotonic = lastDailyBonusMonotonic
        self.dailyBonusStreak = dailyBonusStreak
        self.adBonusesClaimedToday = adBonusesClaimedToday
        self.adBonusDayKey = adBonusDayKey
    }

    public static let new = CareerProfile()

    /// Decoding tolerates missing keys.
    ///
    /// Swift's synthesised decoder ignores property defaults and throws on any
    /// absent key, so without this the first field added to this struct makes
    /// every existing save unreadable — and this struct is the player's actual
    /// progress. `VersionedDocument`'s schema version covers reshaping; this
    /// covers merely growing.
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
        lastDailyBonusDayKey = try container.decodeIfPresent(String.self, forKey: .lastDailyBonusDayKey)
        lastDailyBonusMonotonic = try container.decodeIfPresent(UInt64.self, forKey: .lastDailyBonusMonotonic)
        dailyBonusStreak = try container.decodeIfPresent(Int.self, forKey: .dailyBonusStreak) ?? 0
        adBonusesClaimedToday = try container.decodeIfPresent(Int.self, forKey: .adBonusesClaimedToday) ?? 0
        adBonusDayKey = try container.decodeIfPresent(String.self, forKey: .adBonusDayKey) ?? ""
    }

    /// Adds points and keeps `lifetimePointsEarned` in step. Clamps at zero:
    /// a player at zero must always be able to sit at a Casual table.
    public mutating func award(_ delta: Int) {
        if delta > 0 { lifetimePointsEarned += delta }
        points = max(0, points + delta)
    }
}

/// Stakes, payouts and the record. Pure functions over ``CareerProfile``.
public enum PointsLedger {

    // MARK: - Tier availability

    /// Whether the lobby should show this tier at all.
    public static func isUnlocked(_ tier: StakeTier, profile: CareerProfile) -> Bool {
        tier == .casual || profile.lifetimePointsEarned >= tier.unlockThreshold
    }

    /// Whether the player can actually sit down at this tier right now.
    /// Casual is always selectable — never strand a player in an unplayable state.
    public static func isSelectable(
        _ tier: StakeTier,
        profile: CareerProfile,
        soloVsBots: Bool
    ) -> Bool {
        if tier == .casual { return true }
        return isUnlocked(tier, profile: profile) && profile.points >= tier.entry(soloVsBots: soloVsBots)
    }

    public static func selectableTiers(profile: CareerProfile, soloVsBots: Bool) -> [StakeTier] {
        StakeTier.allCases.filter { isSelectable($0, profile: profile, soloVsBots: soloVsBots) }
    }

    // MARK: - Settlement

    /// Streak points lost for abandoning a ranked match.
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
            profile.award(tier.winPayout(soloVsBots: soloVsBots))
        case .loss:
            profile.currentStreak = 0
            profile.award(-tier.entry(soloVsBots: soloVsBots))
        case .quit:
            profile.currentStreak = max(0, profile.currentStreak - quitStreakPenalty)
            profile.award(-tier.entry(soloVsBots: soloVsBots))
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
