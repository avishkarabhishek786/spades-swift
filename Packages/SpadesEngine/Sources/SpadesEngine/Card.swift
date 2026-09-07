import Foundation

/// The four suits, ordered clubs < diamonds < hearts < spades.
///
/// The ordering is *not* a trick-taking ordering — spades beat everything only
/// because ``Trick`` says so. It exists to give hands a stable sort order.
public enum Suit: Int, CaseIterable, Codable, Sendable, Comparable, Hashable {
    case clubs = 0
    case diamonds
    case hearts
    case spades

    public static func < (lhs: Suit, rhs: Suit) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Single-character glyph used by the renderer. No image assets exist for suits.
    public var glyph: String {
        switch self {
        case .clubs: "\u{2663}"
        case .diamonds: "\u{2666}"
        case .hearts: "\u{2665}"
        case .spades: "\u{2660}"
        }
    }

    /// Untranslated English name, used to build VoiceOver labels in the app layer.
    public var name: String {
        switch self {
        case .clubs: "Clubs"
        case .diamonds: "Diamonds"
        case .hearts: "Hearts"
        case .spades: "Spades"
        }
    }
}

/// Card ranks. Aces are high; there is no low-ace in Spades.
public enum Rank: Int, CaseIterable, Codable, Sendable, Comparable, Hashable {
    case two = 2, three, four, five, six, seven, eight, nine, ten
    case jack, queen, king, ace

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Short label drawn on the card face.
    public var label: String {
        switch self {
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .ten: "10"
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        case .ace: "A"
        }
    }

    /// Untranslated English name, used to build VoiceOver labels in the app layer.
    public var name: String {
        switch self {
        case .two: "Two"
        case .three: "Three"
        case .four: "Four"
        case .five: "Five"
        case .six: "Six"
        case .seven: "Seven"
        case .eight: "Eight"
        case .nine: "Nine"
        case .ten: "Ten"
        case .jack: "Jack"
        case .queen: "Queen"
        case .king: "King"
        case .ace: "Ace"
        }
    }

    /// True for J, Q, K — the ranks ``CardView`` draws as a monogram rather than pips.
    public var isFace: Bool { self >= .jack }
}

/// A playing card. Value type, `Identifiable` with a stable id so
/// `matchedGeometryEffect` can track a card from hand to table.
public struct Card: Equatable, Hashable, Codable, Sendable, Comparable, Identifiable, CustomStringConvertible {
    public let rank: Rank
    public let suit: Suit

    public init(_ rank: Rank, of suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// A dense index in `0..<52`, stable across shuffles, deals and
    /// encode/decode round-trips: a card is identified by what it is, and a
    /// deck holds exactly one of each. Callers index 52-element tables by it.
    public var id: Int { suit.rawValue * Rank.allCases.count + (rank.rawValue - Rank.two.rawValue) }

    /// Sorts by suit, then rank. Used for the default hand layout.
    public static func < (lhs: Card, rhs: Card) -> Bool {
        lhs.suit == rhs.suit ? lhs.rank < rhs.rank : lhs.suit < rhs.suit
    }

    /// Untranslated English label, e.g. "Queen of Spades". The app localises
    /// its own display strings; this is the accessibility fallback.
    public var accessibilityName: String { "\(rank.name) of \(suit.name)" }

    public var description: String { "\(rank.label)\(suit.glyph)" }

    /// The card that must lead the first trick when `RulesConfig.mustLeadTwoOfClubs` is on.
    public static let twoOfClubs = Card(.two, of: .clubs)
}
