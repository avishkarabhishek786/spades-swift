import Foundation

/// Everything that happens between one deal and the next.
public struct HandState: Equatable, Codable, Sendable {
    /// Where a hand is in its lifecycle.
    public enum Phase: String, Codable, Sendable {
        case bidding
        case playing
        /// All 13 tricks are played; the hand is scored and awaiting the next deal.
        case complete
    }

    public var dealer: Seat
    /// Cards still held by each seat. Shrinks as cards are played.
    public var hands: SeatMap<[Card]>
    /// The 13 cards each seat started with. Kept for replay, review and bot inference.
    public var dealtHands: SeatMap<[Card]>
    public var bids: SeatMap<Bid?>
    public var tricksWon: SeatMap<Int>
    public var completedTricks: [Trick]
    /// The trick in progress. `nil` while bidding, and between the last trick and scoring.
    public var currentTrick: Trick?
    /// Set once a spade has been discarded on a trick its player could not follow.
    public var spadesBroken: Bool
    public var phase: Phase

    /// Reactions and quick-chat phrases each seat has spent this hand. See §8 rate limits.
    public var reactionsUsed: SeatMap<Int>
    public var phrasesUsed: SeatMap<Int>

    public init(dealer: Seat, hands: SeatMap<[Card]>) {
        self.dealer = dealer
        self.hands = hands
        dealtHands = hands
        bids = SeatMap(repeating: nil)
        tricksWon = SeatMap(repeating: 0)
        completedTricks = []
        currentTrick = nil
        spadesBroken = false
        phase = .bidding
        reactionsUsed = SeatMap(repeating: 0)
        phrasesUsed = SeatMap(repeating: 0)
    }

    /// The seat that bids or plays first. Bidding starts to the dealer's left.
    public var firstBidder: Seat { dealer.next }

    /// How many seats have bid so far. Bids are always placed in clockwise order.
    public var bidCount: Int { bids.values.reduce(0) { $0 + ($1 == nil ? 0 : 1) } }

    public var biddingIsComplete: Bool { bidCount == Seat.allCases.count }

    /// The seat that must act next, or `nil` when the hand is over.
    public var seatToAct: Seat? {
        switch phase {
        case .bidding:
            return biddingIsComplete ? nil : firstBidder.advanced(by: bidCount)
        case .playing:
            return currentTrick?.seatToPlay
        case .complete:
            return nil
        }
    }

    /// Combined numeric contract for a partnership. Nil bids contribute nothing.
    public func contract(for team: Team) -> Int {
        let (a, b) = team.seats
        return (bids[a]?.contractValue ?? 0) + (bids[b]?.contractValue ?? 0)
    }

    /// The bid a seat's partner has already made, if any. Used by bots and by
    /// the `minBidPerTeam` check.
    public func partnerBid(of seat: Seat) -> Bid? { bids[seat.partner] ?? nil }

    /// Every card played so far this hand, completed tricks first.
    public var playedCards: [Card] {
        completedTricks.flatMap(\.cards) + (currentTrick?.cards ?? [])
    }

    /// True when this seat holds nothing but spades — the one case where a
    /// spade may be led before spades are broken.
    public func holdsOnlySpades(_ seat: Seat) -> Bool {
        let hand = hands[seat]
        return !hand.isEmpty && hand.allSatisfy { $0.suit == .spades }
    }
}
