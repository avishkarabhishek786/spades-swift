import Foundation

/// The single source of truth for what a seat is allowed to do.
///
/// Nothing else — not the UI, not the bots, not the transport layer — may
/// reimplement these checks. Two implementations of follow-suit means two
/// behaviours, and the one the player sees will be the wrong one.
public enum LegalMoves {

    // MARK: - Playing

    /// Cards this seat may legally play right now.
    ///
    /// Returns an empty array when it is not this seat's turn, which is exactly
    /// what the table view wants: everything greyed out.
    public static func legalPlays(state: GameState, seat: Seat) -> [Card] {
        let hand = state.hand
        guard hand.phase == .playing, hand.seatToAct == seat else { return [] }
        guard let trick = hand.currentTrick else { return [] }
        let held = hand.hands[seat]
        guard !held.isEmpty else { return [] }

        // The opening lead of the hand is forced when the table plays that rule.
        if state.rules.mustLeadTwoOfClubs, hand.completedTricks.isEmpty, trick.isEmpty {
            if held.contains(Card.twoOfClubs) { return [Card.twoOfClubs] }
        }

        guard let ledSuit = trick.ledSuit else {
            // Leading. A spade may not be led until spades are broken, unless
            // spades are all this seat has left.
            if hand.spadesBroken || hand.holdsOnlySpades(seat) { return held }
            return held.filter { $0.suit != .spades }
        }

        let followers = held.filter { $0.suit == ledSuit }
        return followers.isEmpty ? held : followers
    }

    /// Whether a specific card may be played by a specific seat right now.
    public static func isLegal(play card: Card, state: GameState, seat: Seat) -> Bool {
        legalPlays(state: state, seat: seat).contains(card)
    }

    // MARK: - Bidding

    /// Bids this seat may legally make right now, in ascending order with
    /// nil variants last. Empty when it is not this seat's turn to bid.
    public static func legalBids(state: GameState, seat: Seat) -> [Bid] {
        let hand = state.hand
        guard hand.phase == .bidding, hand.seatToAct == seat else { return [] }

        var bids: [Bid] = (1...13).compactMap { Bid(tricks: $0) }

        // A team minimum binds the last of the pair to bid; the first partner
        // still has a free hand because their partner can make up the shortfall.
        if let minimum = state.rules.minBidPerTeam, let partnerBid = hand.partnerBid(of: seat) {
            let shortfall = minimum - partnerBid.contractValue
            if shortfall > 0 {
                bids = bids.filter { $0.contractValue >= shortfall }
            }
        }

        // Nil is exempt from a team minimum. The minimum exists to stop
        // sandbagging, and nil is the opposite of a safe bid.
        bids.append(.nilBid)
        if isBlindNilAvailable(state: state, seat: seat) { bids.append(.blindNil) }
        return bids
    }

    /// Whether this seat may declare blind nil.
    ///
    /// The app layer is responsible for the other half of the rule: a blind nil
    /// must be offered *before* the hand is revealed. The engine has no notion
    /// of who has looked at their cards, so it cannot enforce that.
    public static func isBlindNilAvailable(state: GameState, seat: Seat) -> Bool {
        guard state.rules.allowBlindNil else { return false }
        guard let deficit = state.rules.blindNilRequiresDeficit else { return true }
        let team = seat.team
        return state.scores[team.opponent] - state.scores[team] >= deficit
    }

    public static func isLegal(bid: Bid, state: GameState, seat: Seat) -> Bool {
        legalBids(state: state, seat: seat).contains(bid)
    }

    // MARK: - Social

    /// Whether this seat has social budget left this hand. See §8: five
    /// reactions and five phrases per player per hand, excess dropped silently.
    public static func canSendReaction(state: GameState, from seat: Seat) -> Bool {
        state.hand.reactionsUsed[seat] < GameState.socialBudgetPerHand
    }

    public static func canSendPhrase(state: GameState, from seat: Seat) -> Bool {
        state.hand.phrasesUsed[seat] < GameState.socialBudgetPerHand
    }
}
