import Foundation

/// Hand scoring. See §5 of CLAUDE.md for the table this implements.
public enum Scoring {

    /// What one partnership earned from one hand.
    public struct TeamResult: Equatable, Codable, Sendable {
        public let team: Team
        /// Combined numeric bid of both partners.
        public let contract: Int
        /// Every trick the two partners took, including a failed nil bidder's.
        public let tricksTaken: Int
        /// Tricks that counted toward the contract, after applying
        /// `RulesConfig.nilTricksCountForPartner`.
        public let countedTricks: Int
        public let madeContract: Bool
        /// `10 × contract`, positive if made and negative if set.
        public let contractPoints: Int
        /// One point per overtrick. Bags are worth a point each *and* count
        /// toward the penalty — that is what makes them a slow-burning trap.
        public let overtrickPoints: Int
        /// Nil and blind nil bonuses and penalties, summed over both seats.
        public let nilPoints: Int
        /// Overtricks earned this hand.
        public let bagsGained: Int
        /// How many times the bag threshold was crossed while scoring this hand.
        public let bagPenaltiesApplied: Int
        /// Bag count after the hand, with any penalty remainder carried.
        public let bagsAfter: Int
        /// Net score change, including bag penalties.
        public let points: Int

        /// Points deducted by bag penalties this hand. Zero or negative.
        public var bagPenaltyPoints: Int { points - (contractPoints + overtrickPoints + nilPoints) }

        /// Points from the contract, overtricks and nils, before bag penalties.
        public var pointsBeforeBagPenalty: Int { contractPoints + overtrickPoints + nilPoints }
    }

    /// Scores a completed hand for both partnerships.
    ///
    /// - Parameters:
    ///   - hand: A hand whose 13 tricks have all been played.
    ///   - rules: The table's house rules.
    ///   - bags: Each team's bag count going into this hand.
    public static func score(
        hand: HandState,
        rules: RulesConfig,
        bags: TeamMap<Int>
    ) -> TeamMap<TeamResult> {
        TeamMap { team in
            result(for: team, hand: hand, rules: rules, bagsBefore: bags[team])
        }
    }

    private static func result(
        for team: Team,
        hand: HandState,
        rules: RulesConfig,
        bagsBefore: Int
    ) -> TeamResult {
        let (first, second) = team.seats
        let seats = [first, second]

        let contract = hand.contract(for: team)
        let tricksTaken = seats.reduce(0) { $0 + hand.tricksWon[$1] }

        // A nil bidder's tricks never help their own contract — they have none.
        // Whether a *failed* nil bidder's tricks help the partner is a house rule.
        var countedTricks = 0
        var nilPoints = 0
        for seat in seats {
            let tricks = hand.tricksWon[seat]
            guard let bid = hand.bids[seat] else { continue }
            if bid.isNil {
                if tricks == 0 {
                    nilPoints += bid.nilReward
                } else {
                    nilPoints -= bid.nilReward
                    if rules.nilTricksCountForPartner { countedTricks += tricks }
                }
            } else {
                countedTricks += tricks
            }
        }

        let madeContract = countedTricks >= contract
        let contractPoints = madeContract ? 10 * contract : -10 * contract
        let bagsGained = madeContract ? countedTricks - contract : 0

        var bagTotal = bagsBefore + bagsGained
        var penalties = 0
        if rules.bagPenaltyThreshold > 0 {
            // Carry the remainder rather than resetting: at 12 bags you take one
            // penalty and start the next hand on 2.
            while bagTotal >= rules.bagPenaltyThreshold {
                bagTotal -= rules.bagPenaltyThreshold
                penalties += 1
            }
        }

        let points = contractPoints + bagsGained + nilPoints - penalties * rules.bagPenalty

        return TeamResult(
            team: team,
            contract: contract,
            tricksTaken: tricksTaken,
            countedTricks: countedTricks,
            madeContract: madeContract,
            contractPoints: contractPoints,
            overtrickPoints: bagsGained,
            nilPoints: nilPoints,
            bagsGained: bagsGained,
            bagPenaltiesApplied: penalties,
            bagsAfter: bagTotal,
            points: points
        )
    }

    /// Decides the match after a hand, per §5: first to `targetScore` wins; if
    /// both cross, the higher score wins; an exact tie means another hand.
    public static func matchWinner(scores: TeamMap<Int>, rules: RulesConfig) -> Team? {
        let a = scores[.zeroTwo]
        let b = scores[.oneThree]
        let aReached = a >= rules.targetScore
        let bReached = b >= rules.targetScore
        switch (aReached, bReached) {
        case (true, false): return .zeroTwo
        case (false, true): return .oneThree
        case (true, true): return a == b ? nil : (a > b ? .zeroTwo : .oneThree)
        case (false, false): return nil
        }
    }
}

/// A scored hand, kept for the score screen and for replay.
public struct HandSummary: Equatable, Codable, Sendable {
    public let handNumber: Int
    public let dealer: Seat
    public let bids: SeatMap<Bid?>
    public let tricksWon: SeatMap<Int>
    public let results: TeamMap<Scoring.TeamResult>
    /// Cumulative match score after this hand.
    public let scoresAfter: TeamMap<Int>
    public let bagsAfter: TeamMap<Int>

    public init(
        handNumber: Int,
        dealer: Seat,
        bids: SeatMap<Bid?>,
        tricksWon: SeatMap<Int>,
        results: TeamMap<Scoring.TeamResult>,
        scoresAfter: TeamMap<Int>,
        bagsAfter: TeamMap<Int>
    ) {
        self.handNumber = handNumber
        self.dealer = dealer
        self.bids = bids
        self.tricksWon = tricksWon
        self.results = results
        self.scoresAfter = scoresAfter
        self.bagsAfter = bagsAfter
    }
}
