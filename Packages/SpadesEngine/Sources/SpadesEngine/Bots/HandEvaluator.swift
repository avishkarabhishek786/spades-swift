import Foundation

/// Everything a bot is allowed to know.
///
/// Bots are handed one of these rather than the whole ``GameState`` so that
/// "the bot cheated" is a compile-time impossibility rather than a code-review
/// question — opponents' hands simply are not reachable from here.
public struct TableKnowledge: Sendable {
    public let seat: Seat
    public let rules: RulesConfig
    /// This bot's own cards.
    public let hand: [Card]
    public let bids: SeatMap<Bid?>
    public let tricksWon: SeatMap<Int>
    public let completedTricks: [Trick]
    public let currentTrick: Trick?
    public let spadesBroken: Bool
    public let scores: TeamMap<Int>
    public let bags: TeamMap<Int>

    /// Cards this bot has not seen, in suit-then-rank order.
    public let unseenCards: [Card]
    /// Highest rank still outstanding in each suit, indexed by `Suit.rawValue`.
    private let topOutstanding: [Rank?]
    /// One bit per suit, per seat, for suits that seat has shown a void in.
    private let voidMask: SeatMap<UInt8>

    public init(state: GameState, seat: Seat) {
        self.seat = seat
        rules = state.rules
        let held = state.hand.hands[seat]
        hand = held
        bids = state.hand.bids
        tricksWon = state.hand.tricksWon
        completedTricks = state.hand.completedTricks
        currentTrick = state.hand.currentTrick
        spadesBroken = state.hand.spadesBroken
        scores = state.scores
        bags = state.bags

        // These three are derived in one pass at construction rather than on
        // demand. Recomputing them per candidate card turned bot play into the
        // dominant cost of a simulated match, and a hard bot doing that on the
        // main actor is exactly the dropped-frame problem §15 warns about.
        var seen = [Bool](repeating: false, count: 52)
        for card in held { seen[card.id] = true }
        var voids = SeatMap<UInt8>(repeating: 0)

        func absorb(_ trick: Trick) {
            guard let led = trick.ledSuit else { return }
            for play in trick.plays {
                seen[play.card.id] = true
                if play.card.suit != led {
                    voids[play.seat] |= 1 << UInt8(led.rawValue)
                }
            }
        }
        for trick in state.hand.completedTricks { absorb(trick) }
        if let trick = state.hand.currentTrick { absorb(trick) }

        var unseen: [Card] = []
        unseen.reserveCapacity(52 - held.count)
        var tops = [Rank?](repeating: nil, count: Suit.allCases.count)
        for card in Deck.full.cards where !seen[card.id] {
            unseen.append(card)
            let index = card.suit.rawValue
            if let current = tops[index] {
                if card.rank > current { tops[index] = card.rank }
            } else {
                tops[index] = card.rank
            }
        }
        unseenCards = unseen
        topOutstanding = tops
        voidMask = voids
    }

    public var partner: Seat { seat.partner }
    public var opponents: [Seat] { [seat.next, seat.next.partner] }
    public var team: Team { seat.team }

    public var ownBid: Bid? { bids[seat] }
    public var partnerBid: Bid? { bids[partner] }

    /// Cards this bot has seen leave the table, including the trick in progress.
    public var playedCards: [Card] {
        completedTricks.flatMap(\.cards) + (currentTrick?.cards ?? [])
    }

    /// Cards of `suit` still outstanding somewhere other than this bot's hand.
    public func outstanding(in suit: Suit) -> [Card] {
        unseenCards.filter { $0.suit == suit }
    }

    /// True if `card` beats every outstanding card of its suit — the only
    /// honest definition of "this will win" without seeing other hands.
    public func isTopOfSuit(_ card: Card) -> Bool {
        guard let top = topOutstanding[card.suit.rawValue] else { return true }
        return card.rank > top
    }

    /// A seat is known void in a suit once it has failed to follow it.
    /// Only ``BotDifficulty/hard`` consults this.
    public func isKnownVoid(_ other: Seat, in suit: Suit) -> Bool {
        voidMask[other] & (1 << UInt8(suit.rawValue)) != 0
    }

    public func cards(in suit: Suit) -> [Card] {
        hand.filter { $0.suit == suit }.sorted()
    }

    /// Cards held in each suit, indexed by `Suit.rawValue`.
    public var suitLengths: [Int] {
        var lengths = [Int](repeating: 0, count: Suit.allCases.count)
        for card in hand { lengths[card.suit.rawValue] += 1 }
        return lengths
    }

    /// Tricks this bot's team still needs to make its contract, negative if over.
    public var tricksStillNeeded: Int { tricksStillNeeded(for: team) }

    /// Tricks a partnership still needs to make its contract, negative if over.
    ///
    /// A nil bidder's tricks are excluded: they never count toward the number.
    public func tricksStillNeeded(for team: Team) -> Int {
        let (a, b) = team.seats
        let contract = (bids[a]?.contractValue ?? 0) + (bids[b]?.contractValue ?? 0)
        var taken = 0
        for member in [a, b] where !(bids[member]?.isNil ?? false) {
            taken += tricksWon[member]
        }
        return contract - taken
    }

    /// How close the team is to a bag penalty. Zero means the next overtrick fires it.
    public var bagsBeforePenalty: Int {
        max(0, rules.bagPenaltyThreshold - bags[team])
    }
}

/// Shared hand-strength heuristics. All three difficulties bid through here;
/// they differ in how much of it they use.
public enum HandEvaluator {

    // MARK: - Bidding

    /// A crude count for ``BotDifficulty/easy``: high cards plus spade length.
    ///
    /// Weak on purpose, but not broken: four of these bid about eleven tricks
    /// between them against a real thirteen, so an easy table underbids and
    /// collects bags rather than failing to score at all.
    public static func crudeBid(hand: [Card]) -> Int {
        let honours = hand.filter { $0.rank >= .king }.count
        let spadeLength = hand.filter { $0.suit == .spades }.count
        return max(1, honours + max(0, spadeLength - 3))
    }

    /// Expected tricks, counting sure winners rather than raw high cards.
    ///
    /// Spades are counted as honours plus length, capped at the actual spade
    /// count so a long strong holding is not double-counted.
    public static func sureTricks(hand: [Card]) -> Int {
        let spades = hand.filter { $0.suit == .spades }.sorted()
        let spadeCount = spades.count

        var spadeTricks = 0
        if spades.contains(where: { $0.rank == .ace }) { spadeTricks += 1 }
        if spades.contains(where: { $0.rank == .king }), spadeCount >= 2 { spadeTricks += 1 }
        if spades.contains(where: { $0.rank == .queen }), spadeCount >= 3 { spadeTricks += 1 }
        // Length past three is worth a trick each: short suits elsewhere will
        // run out and the small spades start winning.
        spadeTricks = min(spadeCount, spadeTricks + max(0, spadeCount - 3))

        var sideTricks = 0
        for suit in Suit.allCases where suit != .spades {
            let cards = hand.filter { $0.suit == suit }
            if cards.contains(where: { $0.rank == .ace }) { sideTricks += 1 }
            // An unprotected king falls to the ace; a protected one usually stands.
            if cards.contains(where: { $0.rank == .king }), cards.count >= 2 { sideTricks += 1 }
            if cards.contains(where: { $0.rank == .queen }), cards.count >= 4 { sideTricks += 1 }
        }

        return min(13, spadeTricks + sideTricks)
    }

    /// Whether a hand is safe enough to declare nil.
    ///
    /// The three ways a nil dies: a high spade you cannot duck, an ace you are
    /// forced to lead, and a king with nothing under it.
    public static func isNilSafe(hand: [Card]) -> Bool {
        let spades = hand.filter { $0.suit == .spades }
        guard spades.count <= 3 else { return false }
        guard spades.allSatisfy({ $0.rank <= .nine }) else { return false }
        guard !hand.contains(where: { $0.rank == .ace }) else { return false }

        for suit in Suit.allCases where suit != .spades {
            let cards = hand.filter { $0.suit == suit }
            guard let top = cards.max(by: { $0.rank < $1.rank }) else { continue }
            // A king needs three low cards beneath it before it is duckable.
            if top.rank == .king, cards.count < 4 { return false }
            if top.rank == .queen, cards.count < 2 { return false }
        }
        return true
    }

    /// The bid a bot of this difficulty makes with this hand.
    ///
    /// `legal` is ``LegalMoves/legalBids(state:seat:)`` — the result is always
    /// drawn from it, so a team minimum or a blind-nil restriction is respected
    /// without the evaluator knowing the rule exists.
    static func chooseBid(
        knowledge: TableKnowledge,
        traits: BotTraits,
        difficulty: BotDifficulty,
        legal: [Bid]
    ) -> Bid {
        guard !legal.isEmpty else { return .tricks(1) }

        if difficulty > .easy, legal.contains(.nilBid), isNilSafe(hand: knowledge.hand) {
            // Do not stack two nils on one team; someone has to take tricks.
            if !(knowledge.partnerBid?.isNil ?? false) { return .nilBid }
        }

        var target = difficulty == .easy
            ? crudeBid(hand: knowledge.hand)
            : sureTricks(hand: knowledge.hand)

        if traits.contains(.tableAwareBidding) {
            target = adjustForTable(target, knowledge: knowledge)
        }

        return closestLegalBid(to: max(1, target), among: legal)
    }

    /// Hard bots shade their bid by reading the rest of the table.
    ///
    /// Only thirteen tricks exist. If the seats that have already bid have
    /// claimed most of them, one of the remaining seats is getting set, and it
    /// should not be this one — so shade down. If the table has underbid,
    /// there are free tricks lying around and the bags they become are worth
    /// less than the contract they could be.
    ///
    /// Two tempting variants of this function are both wrong, and both were
    /// here: shading up because the team is behind is a feedback loop that
    /// overbids, gets set, falls further behind and bids higher still; and
    /// shading up to dodge bags doubles because *both* partners apply it. Bag
    /// avoidance is a play decision — see `BotPlayer.shouldAvoidTricks`.
    private static func adjustForTable(_ target: Int, knowledge: TableKnowledge) -> Int {
        var target = target

        // Covering a nil means taking the tricks partner must not, so the
        // partner of a nil bidder expects one more than the hand is worth alone.
        if knowledge.partnerBid?.isNil == true { target += 1 }

        var declared = 0
        var yetToBid = 0
        for seat in Seat.allCases where seat != knowledge.seat {
            if let bid = knowledge.bids[seat] {
                declared += bid.contractValue
            } else {
                yetToBid += 1
            }
        }

        // Seats that have not bid are assumed average; the evaluator rates a
        // random hand at a little over three tricks.
        let projected = declared + target + yetToBid * 3
        if projected > 14 {
            target -= 1
        } else if projected < 11 {
            target += 1
        }

        return max(1, target)
    }

    private static func closestLegalBid(to target: Int, among legal: [Bid]) -> Bid {
        let numeric = legal.filter { if case .tricks = $0 { true } else { false } }
        guard !numeric.isEmpty else { return legal[0] }
        return numeric.min {
            let da = abs($0.contractValue - target)
            let db = abs($1.contractValue - target)
            // Ties break upward: being set costs 10× the bid, bags cost 1 each
            // until the threshold, so under-bidding is the cheaper mistake only
            // when it is not close.
            return da == db ? $0.contractValue > $1.contractValue : da < db
        } ?? numeric[0]
    }
}
