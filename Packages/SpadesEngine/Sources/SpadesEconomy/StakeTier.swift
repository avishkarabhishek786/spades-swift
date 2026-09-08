import Foundation

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

    /// Localisation key. The app owns the display strings.
    public var displayNameKey: String { "stake.\(rawValue)" }

    // MARK: - Solo pricing

    /// Solo matches against bots pay — and cost — 40% of the listed figures, so
    /// farming bots does not trivialise the ladder.
    public static let soloNumerator = 2
    public static let soloDenominator = 5

    public func entry(soloVsBots: Bool) -> Int {
        soloVsBots ? entry * Self.soloNumerator / Self.soloDenominator : entry
    }

    public func winPayout(soloVsBots: Bool) -> Int {
        soloVsBots ? winPayout * Self.soloNumerator / Self.soloDenominator : winPayout
    }
}
