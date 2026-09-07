import Testing
@testable import SpadesEngine

@Suite("Bidding")
struct BiddingTests {

    private func bidding(rules: RulesConfig = .standard, scores: TeamMap<Int> = TeamMap(repeating: 0)) -> GameState {
        var state = GameState(seed: 42, rules: rules, seats: allBots())
        state.scores = scores
        return state
    }

    @Test("Zero is nil; there is one representation for the same declaration")
    func zeroIsNil() {
        #expect(Bid(tricks: 0) == .nilBid)
        #expect(Bid(tricks: 7) == .tricks(7))
        #expect(Bid(tricks: 13) == .tricks(13))
        #expect(Bid(tricks: 14) == nil)
        #expect(Bid(tricks: -1) == nil)
    }

    @Test("Nil bids contribute nothing to the team contract")
    func nilContributesNothing() {
        #expect(Bid.nilBid.contractValue == 0)
        #expect(Bid.blindNil.contractValue == 0)
        #expect(Bid.tricks(6).contractValue == 6)
        #expect(Bid.blindNil.nilReward == 200)
        #expect(Bid.nilBid.nilReward == 100)
    }

    @Test("Bidding runs clockwise from the dealer's left")
    func biddingOrder() {
        for dealer in Seat.allCases {
            var state = bidding()
            state.hand.dealer = dealer
            #expect(state.hand.seatToAct == dealer.next)
            for offset in 0..<4 {
                let seat = dealer.next.advanced(by: offset)
                #expect(state.hand.seatToAct == seat)
                state = try! reduce(state, .bid(seat: seat, bid: .tricks(3)))
            }
            #expect(state.hand.biddingIsComplete)
            #expect(state.hand.phase == .playing)
        }
    }

    @Test("Play opens to the dealer's left")
    func openingLead() {
        var state = bidding()
        state.hand.dealer = .two
        for seat in Seat.three.clockwiseOrder {
            state = try! reduce(state, .bid(seat: seat, bid: .tricks(3)))
        }
        #expect(state.hand.currentTrick?.leader == .three)
    }

    @Test("A bid out of turn is rejected")
    func outOfTurnBid() {
        let state = bidding()
        #expect(throws: GameError.notYourTurn(expected: .one, got: .three)) {
            _ = try reduce(state, .bid(seat: .three, bid: .tricks(4)))
        }
    }

    @Test("Legal bids are one through thirteen plus nil")
    func legalBidRange() {
        var rules = RulesConfig.standard
        rules.allowBlindNil = false
        let state = bidding(rules: rules)
        let legal = LegalMoves.legalBids(state: state, seat: .one)
        #expect(legal.count == 14)
        #expect(legal.contains(.nilBid))
        #expect(!legal.contains(.blindNil))
        #expect(legal.contains(.tricks(1)))
        #expect(legal.contains(.tricks(13)))
    }

    @Test("Blind nil needs the configured deficit")
    func blindNilDeficit() {
        var rules = RulesConfig.standard
        rules.blindNilRequiresDeficit = 100

        // Seat 1 is on team oneThree, level on points: not eligible.
        let level = bidding(rules: rules, scores: TeamMap(repeating: 200))
        #expect(!LegalMoves.isBlindNilAvailable(state: level, seat: .one))

        // Now a hundred behind: eligible.
        let behind = bidding(rules: rules, scores: TeamMap { $0 == .zeroTwo ? 300 : 200 })
        #expect(LegalMoves.isBlindNilAvailable(state: behind, seat: .one))
        #expect(!LegalMoves.isBlindNilAvailable(state: behind, seat: .zero))
        #expect(LegalMoves.legalBids(state: behind, seat: .one).contains(.blindNil))
    }

    @Test("A nil deficit requirement means blind nil is always on offer")
    func blindNilUnrestricted() {
        var rules = RulesConfig.standard
        rules.blindNilRequiresDeficit = nil
        let state = bidding(rules: rules)
        #expect(LegalMoves.isBlindNilAvailable(state: state, seat: .one))
    }

    @Test("allowBlindNil off removes it entirely")
    func blindNilDisabled() {
        var rules = RulesConfig.standard
        rules.allowBlindNil = false
        rules.blindNilRequiresDeficit = nil
        let state = bidding(rules: rules, scores: TeamMap { $0 == .zeroTwo ? 900 : 0 })
        #expect(!LegalMoves.isBlindNilAvailable(state: state, seat: .one))
    }

    @Test("An illegal blind nil is rejected by the reducer")
    func reducerRejectsIneligibleBlindNil() {
        var rules = RulesConfig.standard
        rules.blindNilRequiresDeficit = 100
        let state = bidding(rules: rules)
        #expect(throws: GameError.illegalBid(.blindNil, seat: .one)) {
            _ = try reduce(state, .bid(seat: .one, bid: .blindNil))
        }
    }

    @Test("minBidPerTeam binds the second partner to bid, not the first")
    func teamMinimum() {
        var rules = RulesConfig.standard
        rules.minBidPerTeam = 4
        var state = bidding(rules: rules)

        // Seat 1 bids first for its team and is unconstrained.
        #expect(LegalMoves.legalBids(state: state, seat: .one).contains(.tricks(1)))
        state = try! reduce(state, .bid(seat: .one, bid: .tricks(1)))
        state = try! reduce(state, .bid(seat: .two, bid: .tricks(5)))

        // Seat 3 completes team oneThree and must lift the total to four.
        let legal = LegalMoves.legalBids(state: state, seat: .three)
        #expect(!legal.contains(.tricks(1)))
        #expect(!legal.contains(.tricks(2)))
        #expect(legal.contains(.tricks(3)))
        #expect(throws: GameError.illegalBid(.tricks(2), seat: .three)) {
            _ = try reduce(state, .bid(seat: .three, bid: .tricks(2)))
        }
    }

    @Test("Nil is exempt from a team minimum")
    func teamMinimumExemptsNil() {
        var rules = RulesConfig.standard
        rules.minBidPerTeam = 4
        var state = bidding(rules: rules)
        state = try! reduce(state, .bid(seat: .one, bid: .tricks(1)))
        state = try! reduce(state, .bid(seat: .two, bid: .tricks(5)))
        // The minimum exists to stop sandbagging. Nil is the opposite of a safe bid.
        #expect(LegalMoves.legalBids(state: state, seat: .three).contains(.nilBid))
        #expect(throws: Never.self) {
            _ = try reduce(state, .bid(seat: .three, bid: .nilBid))
        }
    }

    @Test("No bids are legal once bidding is over")
    func noBidsAfterBidding() {
        var state = bidding()
        for seat in Seat.one.clockwiseOrder {
            state = try! reduce(state, .bid(seat: seat, bid: .tricks(3)))
        }
        #expect(LegalMoves.legalBids(state: state, seat: .one).isEmpty)
        #expect(throws: GameError.wrongPhase(.playing)) {
            _ = try reduce(state, .bid(seat: .one, bid: .tricks(2)))
        }
    }
}
