import Testing
@testable import SpadesEngine

@Suite("Scoring")
struct ScoringTests {

    private func hand(bids: [Seat: Bid], tricks: [Seat: Int]) -> HandState {
        var hand = HandState(dealer: .zero, hands: SeatMap(repeating: []))
        hand.bids = SeatMap { bids[$0] }
        hand.tricksWon = SeatMap { tricks[$0] ?? 0 }
        hand.phase = .complete
        return hand
    }

    private func score(
        bids: [Seat: Bid],
        tricks: [Seat: Int],
        rules: RulesConfig = .standard,
        bags: TeamMap<Int> = TeamMap(repeating: 0)
    ) -> TeamMap<Scoring.TeamResult> {
        Scoring.score(hand: hand(bids: bids, tricks: tricks), rules: rules, bags: bags)
    }

    @Test("A made contract scores ten times the bid")
    func madeContract() {
        let results = score(
            bids: [.zero: .tricks(4), .two: .tricks(3), .one: .tricks(3), .three: .tricks(3)],
            tricks: [.zero: 4, .two: 3, .one: 3, .three: 3]
        )
        let team = results[.zeroTwo]
        #expect(team.contract == 7)
        #expect(team.madeContract)
        #expect(team.contractPoints == 70)
        #expect(team.bagsGained == 0)
        #expect(team.points == 70)
    }

    @Test("Overtricks pay a point each and become bags")
    func overtricks() {
        let results = score(
            bids: [.zero: .tricks(4), .two: .tricks(3), .one: .tricks(2), .three: .tricks(1)],
            tricks: [.zero: 5, .two: 4, .one: 2, .three: 2]
        )
        let team = results[.zeroTwo]
        #expect(team.countedTricks == 9)
        #expect(team.bagsGained == 2)
        #expect(team.points == 72)
        #expect(team.bagsAfter == 2)
    }

    @Test("A set contract loses ten times the bid and earns no bags")
    func setContract() {
        let results = score(
            bids: [.zero: .tricks(4), .two: .tricks(3), .one: .tricks(3), .three: .tricks(3)],
            tricks: [.zero: 3, .two: 2, .one: 4, .three: 4]
        )
        let team = results[.zeroTwo]
        #expect(!team.madeContract)
        #expect(team.points == -70)
        #expect(team.bagsGained == 0)
        #expect(team.bagsAfter == 0)
    }

    @Test("Bags accumulate across hands")
    func bagAccumulation() {
        let results = score(
            bids: [.zero: .tricks(2), .two: .tricks(2), .one: .tricks(4), .three: .tricks(4)],
            tricks: [.zero: 3, .two: 3, .one: 4, .three: 3],
            bags: TeamMap { $0 == .zeroTwo ? 3 : 0 }
        )
        #expect(results[.zeroTwo].bagsGained == 2)
        #expect(results[.zeroTwo].bagsAfter == 5)
    }

    @Test("The bag penalty fires at the threshold and carries the remainder")
    func bagPenaltyCarriesRemainder() {
        // Eight bags going in, four earned this hand: twelve. One penalty, carry two.
        let results = score(
            bids: [.zero: .tricks(2), .two: .tricks(1), .one: .tricks(4), .three: .tricks(2)],
            tricks: [.zero: 4, .two: 3, .one: 3, .three: 3],
            bags: TeamMap { $0 == .zeroTwo ? 8 : 0 }
        )
        let team = results[.zeroTwo]
        #expect(team.contract == 3)
        #expect(team.countedTricks == 7)
        #expect(team.bagsGained == 4)
        #expect(team.bagPenaltiesApplied == 1)
        #expect(team.bagsAfter == 2, "At twelve bags you take one penalty and start on two, not zero")
        #expect(team.points == 30 + 4 - 100)
    }

    @Test("The penalty can fire more than once in a single hand")
    func repeatedBagPenalty() {
        var rules = RulesConfig.standard
        rules.bagPenaltyThreshold = 5
        rules.bagPenalty = 50
        let results = score(
            bids: [.zero: .tricks(1), .two: .tricks(1), .one: .tricks(5), .three: .tricks(5)],
            tricks: [.zero: 6, .two: 5, .one: 1, .three: 1],
            rules: rules,
            bags: TeamMap { $0 == .zeroTwo ? 3 : 0 }
        )
        let team = results[.zeroTwo]
        #expect(team.bagsGained == 9)
        #expect(team.bagPenaltiesApplied == 2)
        #expect(team.bagsAfter == 2)
        #expect(team.points == 20 + 9 - 100)
    }

    @Test("A made nil pays one hundred")
    func nilMade() {
        let results = score(
            bids: [.zero: .nilBid, .two: .tricks(5), .one: .tricks(4), .three: .tricks(4)],
            tricks: [.zero: 0, .two: 5, .one: 4, .three: 4]
        )
        let team = results[.zeroTwo]
        #expect(team.nilPoints == 100)
        #expect(team.contract == 5)
        #expect(team.points == 150)
    }

    @Test("A failed nil costs one hundred")
    func nilFailed() {
        let results = score(
            bids: [.zero: .nilBid, .two: .tricks(5), .one: .tricks(4), .three: .tricks(3)],
            tricks: [.zero: 1, .two: 5, .one: 4, .three: 3]
        )
        let team = results[.zeroTwo]
        #expect(team.nilPoints == -100)
        #expect(team.points == 50 - 100)
    }

    @Test("Blind nil doubles the stake in both directions")
    func blindNil() {
        let made = score(
            bids: [.zero: .blindNil, .two: .tricks(6), .one: .tricks(4), .three: .tricks(3)],
            tricks: [.zero: 0, .two: 6, .one: 4, .three: 3]
        )
        #expect(made[.zeroTwo].nilPoints == 200)
        #expect(made[.zeroTwo].points == 260)

        let failed = score(
            bids: [.zero: .blindNil, .two: .tricks(6), .one: .tricks(4), .three: .tricks(3)],
            tricks: [.zero: 2, .two: 6, .one: 3, .three: 2]
        )
        #expect(failed[.zeroTwo].nilPoints == -200)
        #expect(failed[.zeroTwo].points == 60 - 200)
    }

    @Test("nilTricksCountForPartner off: a failed nil's tricks do not help the contract")
    func failedNilTricksExcluded() {
        var rules = RulesConfig.standard
        rules.nilTricksCountForPartner = false
        let results = score(
            bids: [.zero: .nilBid, .two: .tricks(5), .one: .tricks(3), .three: .tricks(3)],
            tricks: [.zero: 3, .two: 4, .one: 3, .three: 3],
            rules: rules
        )
        let team = results[.zeroTwo]
        #expect(team.tricksTaken == 7)
        #expect(team.countedTricks == 4)
        #expect(!team.madeContract)
        #expect(team.points == -50 - 100)
    }

    @Test("nilTricksCountForPartner on: the same hand makes the contract")
    func failedNilTricksIncluded() {
        var rules = RulesConfig.standard
        rules.nilTricksCountForPartner = true
        let results = score(
            bids: [.zero: .nilBid, .two: .tricks(5), .one: .tricks(3), .three: .tricks(3)],
            tricks: [.zero: 3, .two: 4, .one: 3, .three: 3],
            rules: rules
        )
        let team = results[.zeroTwo]
        #expect(team.countedTricks == 7)
        #expect(team.madeContract)
        #expect(team.bagsGained == 2)
        #expect(team.points == 50 + 2 - 100)
    }

    @Test("A made nil never contributes tricks, whatever the setting")
    func madeNilUnaffectedBySetting() {
        for flag in [true, false] {
            var rules = RulesConfig.standard
            rules.nilTricksCountForPartner = flag
            let results = score(
                bids: [.zero: .nilBid, .two: .tricks(5), .one: .tricks(4), .three: .tricks(4)],
                tricks: [.zero: 0, .two: 5, .one: 4, .three: 4],
                rules: rules
            )
            #expect(results[.zeroTwo].countedTricks == 5)
            #expect(results[.zeroTwo].points == 150)
        }
    }

    @Test("Both partners bidding nil scores each seat independently")
    func doubleNil() {
        let results = score(
            bids: [.zero: .nilBid, .two: .nilBid, .one: .tricks(7), .three: .tricks(6)],
            tricks: [.zero: 0, .two: 2, .one: 7, .three: 4]
        )
        let team = results[.zeroTwo]
        #expect(team.contract == 0)
        #expect(team.nilPoints == 0, "One nil made and one failed cancel out")
        #expect(team.points == 0)
    }

    @Test("The team that reaches the target first wins")
    func matchWinner() {
        let rules = RulesConfig.standard
        #expect(Scoring.matchWinner(scores: TeamMap { $0 == .zeroTwo ? 510 : 300 }, rules: rules) == .zeroTwo)
        #expect(Scoring.matchWinner(scores: TeamMap { $0 == .zeroTwo ? 300 : 501 }, rules: rules) == .oneThree)
        #expect(Scoring.matchWinner(scores: TeamMap(repeating: 400), rules: rules) == nil)
    }

    @Test("When both teams cross, the higher score wins; an exact tie plays on")
    func simultaneousCrossing() {
        let rules = RulesConfig.standard
        #expect(Scoring.matchWinner(scores: TeamMap { $0 == .zeroTwo ? 540 : 505 }, rules: rules) == .zeroTwo)
        #expect(Scoring.matchWinner(scores: TeamMap { $0 == .zeroTwo ? 505 : 540 }, rules: rules) == .oneThree)
        #expect(Scoring.matchWinner(scores: TeamMap(repeating: 520), rules: rules) == nil, "An exact tie means another hand")
    }

    @Test("A 250-point target is honoured")
    func alternativeTarget() {
        var rules = RulesConfig.standard
        rules.targetScore = 250
        #expect(Scoring.matchWinner(scores: TeamMap { $0 == .zeroTwo ? 260 : 100 }, rules: rules) == .zeroTwo)
    }
}
