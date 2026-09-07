import Foundation

/// One trick: up to four cards, played clockwise from the leader.
public struct Trick: Equatable, Codable, Sendable {
    /// A single card laid down by a seat.
    public struct Play: Equatable, Codable, Sendable {
        public let seat: Seat
        public let card: Card

        public init(seat: Seat, card: Card) {
            self.seat = seat
            self.card = card
        }
    }

    /// The seat that led. Play proceeds clockwise from here.
    public let leader: Seat
    /// Cards in the order they were played.
    public private(set) var plays: [Play]

    public init(leader: Seat, plays: [Play] = []) {
        self.leader = leader
        self.plays = plays
    }

    /// The suit that must be followed, or `nil` before anyone has led.
    public var ledSuit: Suit? { plays.first?.card.suit }

    public var isEmpty: Bool { plays.isEmpty }

    public var isComplete: Bool { plays.count == Seat.allCases.count }

    /// The seat whose turn it is within this trick, or `nil` if it is complete.
    public var seatToPlay: Seat? {
        isComplete ? nil : leader.advanced(by: plays.count)
    }

    public func card(playedBy seat: Seat) -> Card? {
        plays.first { $0.seat == seat }?.card
    }

    public mutating func append(_ play: Play) {
        plays.append(play)
    }

    /// The seat currently winning. Highest spade if any spade is present,
    /// otherwise the highest card of the led suit. `nil` only when empty.
    public var currentWinner: Seat? {
        guard let ledSuit else { return nil }
        let contenders = plays.filter { $0.card.suit == .spades }
        let relevant = contenders.isEmpty ? plays.filter { $0.card.suit == ledSuit } : contenders
        return relevant.max { $0.card.rank < $1.card.rank }?.seat
    }

    /// The winning seat, or `nil` if the trick is not yet complete.
    public var winner: Seat? { isComplete ? currentWinner : nil }

    public var cards: [Card] { plays.map(\.card) }
}
