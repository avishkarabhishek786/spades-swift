import Foundation

/// A deterministic, seedable random number generator.
///
/// The engine never touches the system RNG. A match is reproducible from its
/// seed plus its action log, which is what makes replay, bug reports and
/// multiplayer resync possible — see `GameState.seed`.
///
/// Implementation is SplitMix64: tiny, fast, and identical on every platform,
/// which matters because host and client must derive the same deal.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the all-zero state, which SplitMix64 handles but which makes
        // low seeds produce visibly correlated first outputs.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A full 52-card deck.
public struct Deck: Equatable, Codable, Sendable {
    public private(set) var cards: [Card]

    /// A deck in canonical order: clubs 2→A, diamonds, hearts, spades.
    public init() {
        cards = Suit.allCases.flatMap { suit in Rank.allCases.map { Card($0, of: suit) } }
    }

    public init(cards: [Card]) { self.cards = cards }

    public static let full = Deck()

    /// Fisher–Yates using the injected generator. Deterministic for a given generator state.
    public mutating func shuffle(using generator: inout some RandomNumberGenerator) {
        cards.shuffle(using: &generator)
    }

    public func shuffled(using generator: inout some RandomNumberGenerator) -> Deck {
        var copy = self
        copy.shuffle(using: &generator)
        return copy
    }

    /// Deals 13 cards to each seat, clockwise from the dealer's left.
    ///
    /// Cards are dealt one at a time in table order, matching how a physical
    /// deal looks — the staggered deal animation in the app follows this order.
    /// Hands come back sorted; nothing downstream depends on deal order within a hand.
    public func deal(startingAt first: Seat) -> SeatMap<[Card]> {
        precondition(cards.count == 52, "A deal needs a full 52-card deck")
        var hands = SeatMap<[Card]>(repeating: [])
        for (index, card) in cards.enumerated() {
            hands[first.advanced(by: index)].append(card)
        }
        return hands.mapValues { $0.sorted() }
    }

    /// The deal for one hand of a match, derived purely from the match seed.
    ///
    /// Mixing in the hand number means every hand of a match is independent but
    /// still reproducible from the single seed carried in ``GameState``.
    public static func deal(seed: UInt64, handNumber: Int, firstReceiver: Seat) -> SeatMap<[Card]> {
        var generator = SeededGenerator(seed: seed &+ UInt64(bitPattern: Int64(handNumber)) &* 0x2545_F491_4F6C_DD1D)
        return Deck.full.shuffled(using: &generator).deal(startingAt: firstReceiver)
    }
}
