import Foundation

/// The five reactions any player may send to any specific player, including
/// their partner and including bots.
public enum ReactionKind: String, Codable, CaseIterable, Sendable {
    case thumbsUp, thumbsDown, laughing, crying, angry

    /// SF Symbol name used by the app. Drawn from the system font — §8 forbids
    /// shipping image assets for these.
    public var symbolName: String {
        switch self {
        case .thumbsUp: "hand.thumbsup.fill"
        case .thumbsDown: "hand.thumbsdown.fill"
        case .laughing: "face.smiling.inverse"
        case .crying: "drop.fill"
        case .angry: "flame.fill"
        }
    }

    /// The two that get abused. The mute control ships before these do.
    public var isAbuseProne: Bool { self == .thumbsDown || self == .angry }
}

/// The fixed quick-chat vocabulary. There is no free text in v1 — free text
/// means owing users moderation, reporting and blocking infrastructure.
public enum QuickPhrase: String, Codable, CaseIterable, Sendable {
    case hi, hello, goodLuck, niceHand, wellPlayed, sorry
    case yourTurn, goodGame, thanks, oops, close, rematch

    /// Localisation key. The enum case is what goes over the wire; the display
    /// string is looked up in the app's string catalog.
    public var localizationKey: String { "quickphrase.\(rawValue)" }

    /// Untranslated fallback, used only if a translation is missing.
    public var englishFallback: String {
        switch self {
        case .hi: "Hi!"
        case .hello: "Hello"
        case .goodLuck: "Good luck"
        case .niceHand: "Nice hand"
        case .wellPlayed: "Well played"
        case .sorry: "Sorry"
        case .yourTurn: "Your turn"
        case .goodGame: "Good game"
        case .thanks: "Thanks"
        case .oops: "Oops"
        case .close: "So close"
        case .rematch: "Rematch?"
        }
    }
}

/// A social event recorded in the game state so every client renders the same
/// feed. Muting is a local presentation decision and is deliberately not here.
public struct SocialEvent: Equatable, Codable, Sendable, Identifiable {
    public enum Kind: Equatable, Codable, Sendable {
        case reaction(ReactionKind)
        case phrase(QuickPhrase)
    }

    /// Monotonic within a match; lets the app animate only what it has not seen.
    public let sequence: Int
    public let from: Seat
    /// The target seat for a reaction. Quick chat is addressed to the table.
    public let to: Seat?
    public let kind: Kind

    public var id: Int { sequence }

    public init(sequence: Int, from: Seat, to: Seat?, kind: Kind) {
        self.sequence = sequence
        self.from = from
        self.to = to
        self.kind = kind
    }
}
