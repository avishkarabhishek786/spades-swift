import Foundation

/// Everything a match is. Pure value type: no references, no clocks, no RNG.
///
/// A match is fully described by its `seed`, its `rules`, its `seats` and an
/// ordered list of ``GameAction``. Everything in here is derived from those,
/// which is what buys free replay, free undo in practice mode, "attach the
/// action log" bug reports, and a trivially syncable multiplayer payload.
public struct GameState: Equatable, Codable, Sendable {
    /// Reactions and quick-chat phrases allowed per seat per hand. See §8.
    public static let socialBudgetPerHand = 5

    /// Drives every deal in the match. Never regenerated.
    public let seed: UInt64
    public var rules: RulesConfig
    public var seats: SeatMap<SeatOccupant>
    public var scores: TeamMap<Int>
    public var bags: TeamMap<Int>
    public var hand: HandState
    /// Zero-based. Also selects the dealer and salts the deal.
    public var handNumber: Int
    public var history: [HandSummary]
    /// Most recent social events, oldest first, capped at ``socialFeedLimit``.
    public var socialFeed: [SocialEvent]
    /// Total social events ever emitted; used to number them monotonically.
    public var socialSequence: Int
    /// Set once a team has won. No further actions are accepted.
    public var winner: Team?

    static let socialFeedLimit = 32

    /// Starts a match. The first dealer is seat 0; the dealer rotates clockwise
    /// each hand, so hand `n` is dealt by seat `n % 4`.
    public init(seed: UInt64, rules: RulesConfig = .standard, seats: SeatMap<SeatOccupant>) {
        self.seed = seed
        self.rules = rules
        self.seats = seats
        scores = TeamMap(repeating: 0)
        bags = TeamMap(repeating: 0)
        handNumber = 0
        history = []
        socialFeed = []
        socialSequence = 0
        winner = nil
        let dealer = Seat.zero
        hand = HandState(dealer: dealer, hands: Deck.deal(seed: seed, handNumber: 0, firstReceiver: dealer.next))
    }

    public var isFinished: Bool { winner != nil }

    /// The seat that must bid or play next, or `nil` if the hand is scored or
    /// the match is over.
    public var seatToAct: Seat? { isFinished ? nil : hand.seatToAct }

    /// True when the hand is scored and the match is waiting to deal the next one.
    public var isAwaitingNextHand: Bool { hand.phase == .complete && winner == nil }

    /// Deals the next hand. Deterministic — the seed and hand number decide
    /// everything — so replaying an action log reproduces it exactly.
    ///
    /// Returns `self` unchanged if the match is over or the current hand is
    /// still in progress.
    public func advancingToNextHand() -> GameState {
        guard isAwaitingNextHand else { return self }
        var next = self
        next.handNumber += 1
        let dealer = Seat.zero.advanced(by: next.handNumber)
        next.hand = HandState(
            dealer: dealer,
            hands: Deck.deal(seed: seed, handNumber: next.handNumber, firstReceiver: dealer.next)
        )
        return next
    }

    /// A stable digest of the match state, used by the multiplayer layer to
    /// detect divergence. A mismatch triggers a full resync rather than a
    /// desync limp-along.
    ///
    /// Deterministic because every collection in ``GameState`` is ordered —
    /// there is no dictionary anywhere in the type — and the encoder sorts keys.
    public func stateHash() throws -> UInt64 {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }
}

/// Every state transition in the game. This is also the multiplayer wire
/// format: JSON-encoded, paired with a monotonic sequence number.
public enum GameAction: Equatable, Codable, Sendable {
    case bid(seat: Seat, bid: Bid)
    case play(seat: Seat, card: Card)
    case reaction(from: Seat, to: Seat, kind: ReactionKind)
    case chat(from: Seat, phrase: QuickPhrase)

    /// The seat that produced this action.
    public var seat: Seat {
        switch self {
        case .bid(let seat, _): seat
        case .play(let seat, _): seat
        case .reaction(let from, _, _): from
        case .chat(let from, _): from
        }
    }

    /// True for actions that advance the game. Social actions do not, which is
    /// why they can be dropped without desyncing anything.
    public var isTurnAdvancing: Bool {
        switch self {
        case .bid, .play: true
        case .reaction, .chat: false
        }
    }
}

/// Why an action was rejected. These are programmer or protocol errors — the
/// UI should never be able to produce one, because it asks ``LegalMoves`` first.
public enum GameError: Error, Equatable, Sendable {
    case matchAlreadyFinished
    case notYourTurn(expected: Seat?, got: Seat)
    case wrongPhase(HandState.Phase)
    case illegalBid(Bid, seat: Seat)
    case illegalPlay(Card, seat: Seat)
    case cardNotHeld(Card, seat: Seat)
    case cannotReactToSelf(Seat)
}

/// Applies one action to a state, returning the new state.
///
/// The reducer does not know or care whether a seat is occupied by a human or a
/// bot; only the app layer's session routes turns. Keeping that knowledge out
/// of here is what makes solo, pass-and-play and online share one code path.
///
/// When a hand has been scored and the match is not over, a ``GameAction/bid``
/// implicitly deals the next hand first. That keeps "seed plus action list" a
/// complete description of a match while still letting the UI dwell on the
/// score screen — it calls ``GameState/advancingToNextHand()`` when the player
/// is ready, and replaying the log reaches the identical state either way.
public func reduce(_ state: GameState, _ action: GameAction) throws -> GameState {
    guard !state.isFinished else { throw GameError.matchAlreadyFinished }

    switch action {
    case .bid(let seat, let bid):
        var state = state.isAwaitingNextHand ? state.advancingToNextHand() : state
        guard state.hand.phase == .bidding else { throw GameError.wrongPhase(state.hand.phase) }
        guard state.hand.seatToAct == seat else {
            throw GameError.notYourTurn(expected: state.hand.seatToAct, got: seat)
        }
        guard LegalMoves.isLegal(bid: bid, state: state, seat: seat) else {
            throw GameError.illegalBid(bid, seat: seat)
        }
        state.hand.bids[seat] = bid
        if state.hand.biddingIsComplete { startPlay(&state) }
        return state

    case .play(let seat, let card):
        var state = state
        guard state.hand.phase == .playing else { throw GameError.wrongPhase(state.hand.phase) }
        guard state.hand.seatToAct == seat else {
            throw GameError.notYourTurn(expected: state.hand.seatToAct, got: seat)
        }
        guard state.hand.hands[seat].contains(card) else { throw GameError.cardNotHeld(card, seat: seat) }
        guard LegalMoves.isLegal(play: card, state: state, seat: seat) else {
            throw GameError.illegalPlay(card, seat: seat)
        }
        apply(play: card, by: seat, to: &state)
        return state

    case .reaction(let from, let to, let kind):
        guard from != to else { throw GameError.cannotReactToSelf(from) }
        // Over-budget social actions are dropped silently, not rejected: a rate
        // limit that throws is a rate limit that desyncs multiplayer clients.
        guard LegalMoves.canSendReaction(state: state, from: from) else { return state }
        var state = state
        state.hand.reactionsUsed[from] += 1
        state.append(SocialEvent(sequence: state.socialSequence, from: from, to: to, kind: .reaction(kind)))
        return state

    case .chat(let from, let phrase):
        guard LegalMoves.canSendPhrase(state: state, from: from) else { return state }
        var state = state
        state.hand.phrasesUsed[from] += 1
        state.append(SocialEvent(sequence: state.socialSequence, from: from, to: nil, kind: .phrase(phrase)))
        return state
    }
}

// MARK: - Transitions

private func startPlay(_ state: inout GameState) {
    state.hand.phase = .playing
    state.hand.currentTrick = Trick(leader: openingLeader(state))
}

/// Play opens to the dealer's left, unless the table forces the two of clubs,
/// in which case whoever holds it leads.
private func openingLeader(_ state: GameState) -> Seat {
    guard state.rules.mustLeadTwoOfClubs else { return state.hand.dealer.next }
    let holder = Seat.allCases.first { state.hand.hands[$0].contains(Card.twoOfClubs) }
    return holder ?? state.hand.dealer.next
}

private func apply(play card: Card, by seat: Seat, to state: inout GameState) {
    guard var trick = state.hand.currentTrick else { return }

    let isLead = trick.isEmpty
    let couldFollow = trick.ledSuit.map { led in state.hand.hands[seat].contains { $0.suit == led } } ?? true

    state.hand.hands[seat].removeAll { $0 == card }
    trick.append(Trick.Play(seat: seat, card: card))

    // Spades break when one is discarded on a trick its player could not
    // follow — or when one is legally led, which only happens under the
    // holds-only-spades exception.
    if card.suit == .spades, isLead || !couldFollow {
        state.hand.spadesBroken = true
    }

    guard trick.isComplete, let winner = trick.winner else {
        state.hand.currentTrick = trick
        return
    }

    state.hand.completedTricks.append(trick)
    state.hand.tricksWon[winner] += 1

    if state.hand.completedTricks.count == HandState.tricksPerHand {
        state.hand.currentTrick = nil
        finishHand(&state)
    } else {
        state.hand.currentTrick = Trick(leader: winner)
    }
}

private func finishHand(_ state: inout GameState) {
    state.hand.phase = .complete

    let results = Scoring.score(hand: state.hand, rules: state.rules, bags: state.bags)
    for team in Team.allCases {
        state.scores[team] += results[team].points
        state.bags[team] = results[team].bagsAfter
    }

    state.history.append(
        HandSummary(
            handNumber: state.handNumber,
            dealer: state.hand.dealer,
            bids: state.hand.bids,
            tricksWon: state.hand.tricksWon,
            results: results,
            scoresAfter: state.scores,
            bagsAfter: state.bags
        )
    )

    state.winner = Scoring.matchWinner(scores: state.scores, rules: state.rules)
}

extension GameState {
    mutating func append(_ event: SocialEvent) {
        socialSequence += 1
        socialFeed.append(event)
        if socialFeed.count > Self.socialFeedLimit {
            socialFeed.removeFirst(socialFeed.count - Self.socialFeedLimit)
        }
    }
}

extension HandState {
    /// Thirteen tricks per hand, always.
    public static let tricksPerHand = 13
}
