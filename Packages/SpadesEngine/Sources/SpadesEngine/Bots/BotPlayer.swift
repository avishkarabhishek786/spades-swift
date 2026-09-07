import Foundation

/// A bot seat's decision-making. Pure and deterministic: same knowledge plus
/// same generator state gives the same action, every time, on every platform.
///
/// Nothing here reads another seat's cards — a bot only ever sees a
/// ``TableKnowledge``. Every card it returns comes out of
/// ``LegalMoves/legalPlays(state:seat:)``, so an illegal bot action is not
/// something the strategy code can express.
public struct BotPlayer: Sendable, Equatable {
    public let difficulty: BotDifficulty
    public let persona: BotPersona
    /// Which strategy behaviours are switched on. Derived from ``difficulty``
    /// in normal use; overridable so the head-to-head tests can isolate one.
    let traits: BotTraits

    public init(difficulty: BotDifficulty, persona: BotPersona) {
        self.init(difficulty: difficulty, persona: persona, traits: difficulty.traits)
    }

    init(difficulty: BotDifficulty, persona: BotPersona, traits: BotTraits) {
        self.difficulty = difficulty
        self.persona = persona
        self.traits = traits
    }

    /// The moment a bot is being offered a chance to say something.
    public enum ChatMoment: Sendable {
        case handStart
        case partnerMadeNil
        case handComplete
    }

    // MARK: - Turn taking

    /// The action for this seat's current turn, or `nil` if it is not its turn.
    public func act(
        in state: GameState,
        seat: Seat,
        using generator: inout some RandomNumberGenerator
    ) -> GameAction? {
        guard state.seatToAct == seat else { return nil }
        switch state.hand.phase {
        case .bidding:
            return .bid(seat: seat, bid: chooseBid(state: state, seat: seat, using: &generator))
        case .playing:
            guard let card = chooseCard(state: state, seat: seat, using: &generator) else { return nil }
            return .play(seat: seat, card: card)
        case .complete:
            return nil
        }
    }

    public func chooseBid(
        state: GameState,
        seat: Seat,
        using generator: inout some RandomNumberGenerator
    ) -> Bid {
        let legal = LegalMoves.legalBids(state: state, seat: seat)
        let knowledge = TableKnowledge(state: state, seat: seat)
        var bid = HandEvaluator.chooseBid(knowledge: knowledge, traits: traits, difficulty: difficulty, legal: legal)

        // Easy bots misjudge by a trick now and then; a bot that always bids its
        // own evaluation is more predictable than a beginner should be. The
        // jitter is deliberately +/-1 — a uniformly random bid is not a weak
        // player, it is a broken one, and a table of them never reaches the
        // target score because every hand sets somebody.
        if difficulty == .easy, case .tricks(let count) = bid,
           Int.random(in: 0..<3, using: &generator) == 0 {
            let drift = Bool.random(using: &generator) ? 1 : -1
            if let jittered = Bid(tricks: count + drift), legal.contains(jittered) {
                bid = jittered
            }
        }

        return legal.contains(bid) ? bid : (legal.first ?? .tricks(1))
    }

    /// The card to play, or `nil` if this seat has no legal play (which only
    /// happens when it is not its turn).
    public func chooseCard(
        state: GameState,
        seat: Seat,
        using generator: inout some RandomNumberGenerator
    ) -> Card? {
        let legal = LegalMoves.legalPlays(state: state, seat: seat)
        guard !legal.isEmpty else { return nil }
        guard let trick = state.hand.currentTrick else { return legal.first }

        let knowledge = TableKnowledge(state: state, seat: seat)

        if difficulty == .easy {
            return easyChoice(legal: legal, trick: trick, using: &generator)
        }

        return trick.isEmpty
            ? lead(from: legal, knowledge: knowledge)
            : follow(from: legal, trick: trick, knowledge: knowledge)
    }

    // MARK: - Easy

    private func easyChoice(
        legal: [Card],
        trick: Trick,
        using generator: inout some RandomNumberGenerator
    ) -> Card {
        // Weak preference for following suit low; otherwise anything goes.
        if !trick.isEmpty, Int.random(in: 0..<10, using: &generator) < 7 {
            return lowest(legal)
        }
        return legal.randomElement(using: &generator) ?? legal[0]
    }

    // MARK: - Leading

    private func lead(from legal: [Card], knowledge: TableKnowledge) -> Card {
        if knowledge.ownBid?.isNil == true {
            return safestNilLead(from: legal, knowledge: knowledge)
        }
        if knowledge.partnerBid?.isNil == true {
            // Take control so partner can shed. A top card is worth spending here.
            if let winner = legal.filter({ knowledge.isTopOfSuit($0) }).max(by: { $0.rank < $1.rank }) {
                return winner
            }
        }
        if traits.contains(.nilSetting), let attack = nilSettingLead(from: legal, knowledge: knowledge) {
            return attack
        }
        if traits.contains(.bagAvoidance), shouldAvoidTricks(knowledge) {
            return lowest(legal)
        }

        // Otherwise: cash a sure winner if the team still needs tricks,
        // else develop the longest suit from the bottom.
        if knowledge.tricksStillNeeded > 0,
           let sure = legal.filter({ knowledge.isTopOfSuit($0) }).max(by: { $0.rank < $1.rank }) {
            return sure
        }
        return lowFromLongestSuit(legal, knowledge: knowledge)
    }

    /// A nil bidder leads their lowest card, avoiding spades so as not to break
    /// them and hand themselves the lead back.
    private func safestNilLead(from legal: [Card], knowledge: TableKnowledge) -> Card {
        let nonSpades = legal.filter { $0.suit != .spades }
        return lowest(nonSpades.isEmpty ? legal : nonSpades)
    }

    /// Hard bots attack an opponent's nil by leading low into a suit that
    /// opponent must still follow — the nil bidder may be forced to win it.
    private func nilSettingLead(from legal: [Card], knowledge: TableKnowledge) -> Card? {
        let nilOpponents = knowledge.opponents.filter { knowledge.bids[$0]?.isNil == true }
        guard !nilOpponents.isEmpty else { return nil }
        let candidates = legal.filter { card in
            card.suit != .spades
                && nilOpponents.contains { !knowledge.isKnownVoid($0, in: card.suit) }
        }
        return candidates.min { $0.rank < $1.rank }
    }

    private func lowFromLongestSuit(_ legal: [Card], knowledge: TableKnowledge) -> Card {
        let nonSpades = legal.filter { $0.suit != .spades }
        var pool = nonSpades.isEmpty ? legal : nonSpades

        // Leading a suit an opponent has shown a void in is handing them a
        // ruff. Only hard bots have the void table to notice.
        if traits.contains(.voidInference) {
            let safe = pool.filter { card in
                !knowledge.opponents.contains { knowledge.isKnownVoid($0, in: card.suit) }
            }
            if !safe.isEmpty { pool = safe }
        }

        let lengths = knowledge.suitLengths
        let longest = pool.map(\.suit).max { lengths[$0.rawValue] < lengths[$1.rawValue] }
        let inSuit = pool.filter { $0.suit == longest }
        return lowest(inSuit.isEmpty ? pool : inSuit)
    }

    // MARK: - Following

    private func follow(from legal: [Card], trick: Trick, knowledge: TableKnowledge) -> Card {
        if knowledge.ownBid?.isNil == true {
            return highestLoser(from: legal, trick: trick, seat: knowledge.seat) ?? lowest(legal)
        }

        let partnerWinning = trick.currentWinner == knowledge.partner

        if knowledge.partnerBid?.isNil == true {
            // Partner is trying for nil: win the trick if there is any way to,
            // so the trick never lands on them.
            return cheapestWinner(from: legal, trick: trick, seat: knowledge.seat) ?? lowest(legal)
        }

        if traits.contains(.bagAvoidance), shouldAvoidTricks(knowledge) {
            return highestLoser(from: legal, trick: trick, seat: knowledge.seat) ?? lowest(legal)
        }

        // Never take a trick off your own partner. Spending an ace to overtake
        // a king wins one trick with two winners; the discipline is worth more
        // than the occasional trick it costs.
        if partnerWinning { return discard(from: legal, knowledge: knowledge) }

        return cheapestWinner(from: legal, trick: trick, seat: knowledge.seat)
            ?? discard(from: legal, knowledge: knowledge)
    }

    /// The cheapest card to throw away.
    ///
    /// Hard bots break ties toward their shortest side suit, because going
    /// void is what makes their small spades worth something later. The
    /// candidates are junk only — preferring the short suit outright means
    /// pitching a singleton king to create a void, which costs far more than
    /// the void is worth.
    private func discard(from legal: [Card], knowledge: TableKnowledge) -> Card {
        guard traits.contains(.shortSuitDiscard) else { return lowest(legal) }
        let junk = legal.filter { $0.suit != .spades && $0.rank <= .nine }
        guard !junk.isEmpty else { return lowest(legal) }
        let lengths = knowledge.suitLengths
        let shortest = junk.map(\.suit).min { lengths[$0.rawValue] < lengths[$1.rawValue] }
        let candidates = junk.filter { $0.suit == shortest }
        return lowest(candidates.isEmpty ? junk : candidates)
    }

    /// True when another trick is worth less than the bag it creates.
    ///
    /// An overtrick pays one point and costs a bag, and a bag is worth about
    /// minus ten once the penalty is amortised — so a made contract should
    /// stop taking tricks. The exception is that a trick taken off opponents
    /// who are still short of *their* contract sets them, which is worth ten
    /// times their bid and dwarfs the bag either way.
    private func shouldAvoidTricks(_ knowledge: TableKnowledge) -> Bool {
        guard knowledge.tricksStillNeeded <= 0 else { return false }
        guard knowledge.partnerBid?.isNil != true else { return false }
        return knowledge.tricksStillNeeded(for: knowledge.team.opponent) <= 0
    }

    // MARK: - Trick arithmetic
    //
    // These ask `Trick` who would be winning rather than re-deriving trump and
    // follow-suit rules. There is one implementation of "what beats what".

    private func wouldWin(_ card: Card, trick: Trick, seat: Seat) -> Bool {
        var probe = trick
        probe.append(Trick.Play(seat: seat, card: card))
        return probe.currentWinner == seat
    }

    private func cheapestWinner(from legal: [Card], trick: Trick, seat: Seat) -> Card? {
        legal.filter { wouldWin($0, trick: trick, seat: seat) }
            .min { rankCost($0) < rankCost($1) }
    }

    private func highestLoser(from legal: [Card], trick: Trick, seat: Seat) -> Card? {
        legal.filter { !wouldWin($0, trick: trick, seat: seat) }
            .max { $0.rank < $1.rank }
    }

    /// Spending a spade costs more than spending a side card of the same rank.
    private func rankCost(_ card: Card) -> Int {
        card.rank.rawValue + (card.suit == .spades ? 20 : 0)
    }

    private func lowest(_ cards: [Card]) -> Card {
        cards.min { rankCost($0) < rankCost($1) } ?? cards[0]
    }

    // MARK: - Social

    /// An occasional quick-chat line. Returns `nil` most of the time on
    /// purpose — a table of bots that comments on everything reads as spam.
    public func chatAction(
        for moment: ChatMoment,
        state: GameState,
        seat: Seat,
        using generator: inout some RandomNumberGenerator
    ) -> GameAction? {
        guard LegalMoves.canSendPhrase(state: state, from: seat) else { return nil }
        guard Double.random(in: 0..<1, using: &generator) < persona.chattiness else { return nil }

        let phrase: QuickPhrase
        switch moment {
        case .handStart:
            phrase = [.goodLuck, .hi, .hello].randomElement(using: &generator) ?? .goodLuck
        case .partnerMadeNil:
            phrase = [.niceHand, .wellPlayed].randomElement(using: &generator) ?? .niceHand
        case .handComplete:
            phrase = [.goodGame, .close, .niceHand].randomElement(using: &generator) ?? .goodGame
        }
        return .chat(from: seat, phrase: phrase)
    }
}
