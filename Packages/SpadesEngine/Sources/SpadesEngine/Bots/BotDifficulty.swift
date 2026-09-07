import Foundation

/// How hard a bot plays. Every difficulty shares ``HandEvaluator`` and every
/// difficulty picks only from ``LegalMoves/legalPlays(state:seat:)``.
public enum BotDifficulty: String, Codable, CaseIterable, Sendable, Comparable {
    /// Crude high-card bid; plays a random legal card, weakly preferring a low follow.
    case easy
    /// Counts sure tricks, tracks played cards, leads long suits, ducks to
    /// partner, covers partner's nil.
    case medium
    /// Medium plus void tracking, inference from bids, bag avoidance near the
    /// threshold, and active nil-setting.
    case hard

    public static func < (lhs: BotDifficulty, rhs: BotDifficulty) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .easy: 0
        case .medium: 1
        case .hard: 2
        }
    }

    /// The behaviours this difficulty switches on.
    var traits: BotTraits {
        switch self {
        case .easy: []
        case .medium: [.cardCounting]
        case .hard: [.cardCounting, .voidInference, .bagAvoidance, .nilSetting, .shortSuitDiscard, .tableAwareBidding]
        }
    }
}

/// The individual behaviours that make one difficulty stronger than another.
///
/// Split out so each can be switched on alone. A difficulty ladder is only
/// honest if every rung actually beats the one below it, and the only way to
/// find the trait that is quietly costing tricks is to play it against a table
/// without it — see the head-to-head suite in the tests.
struct BotTraits: OptionSet, Sendable, Equatable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    /// Reads which cards have already been played to tell a winner from a hope.
    static let cardCounting = BotTraits(rawValue: 1 << 0)
    /// Remembers which seat failed to follow which suit.
    static let voidInference = BotTraits(rawValue: 1 << 1)
    /// Ducks tricks it does not need when the bag penalty is one bag away.
    static let bagAvoidance = BotTraits(rawValue: 1 << 2)
    /// Leads low into a nil bidder's live suits to force a trick on them.
    static let nilSetting = BotTraits(rawValue: 1 << 3)
    /// Breaks discard ties toward the shortest side suit to create a void.
    static let shortSuitDiscard = BotTraits(rawValue: 1 << 4)
    /// Shades the bid when the score situation genuinely calls for it.
    static let tableAwareBidding = BotTraits(rawValue: 1 << 5)
}

/// Flavour only. A persona changes a bot's display name and how chatty it is;
/// it never changes card play, so difficulty stays an honest promise.
public enum BotPersona: String, Codable, CaseIterable, Sendable {
    case ace, bea, cass, dex, eli, fern, gus, hana

    /// Untranslated display name. The lobby localises these.
    public var displayName: String {
        switch self {
        case .ace: "Ace"
        case .bea: "Bea"
        case .cass: "Cass"
        case .dex: "Dex"
        case .eli: "Eli"
        case .fern: "Fern"
        case .gus: "Gus"
        case .hana: "Hana"
        }
    }

    /// Probability this persona takes an offered chat opportunity. Kept low on
    /// purpose — roughly one line per bot per hand, or it reads as spam.
    public var chattiness: Double {
        switch self {
        case .ace, .dex, .gus: 0.15
        case .bea, .eli: 0.35
        case .cass, .fern, .hana: 0.25
        }
    }

    /// Deterministic persona assignment, so a replayed match seats the same bots.
    public static func forSeat(_ seat: Seat, salt: Int = 0) -> BotPersona {
        let all = BotPersona.allCases
        let index = ((seat.rawValue + salt) % all.count + all.count) % all.count
        return all[index]
    }
}
