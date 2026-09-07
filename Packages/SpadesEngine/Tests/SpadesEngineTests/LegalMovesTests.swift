import Testing
@testable import SpadesEngine

@Suite("Legal plays")
struct LegalMovesTests {

    /// A playing state with the given holdings and a chosen leader.
    private func playing(
        _ holdings: [Seat: String],
        leader: Seat = .zero,
        spadesBroken: Bool = false,
        rules: RulesConfig = .standard
    ) -> GameState {
        let hands = SeatMap<[Card]> { cards(holdings[$0] ?? "") }
        var state = makeState(hands: hands, rules: rules, bids: SeatMap(repeating: .tricks(3)))
        state.hand.currentTrick = Trick(leader: leader)
        state.hand.spadesBroken = spadesBroken
        return state
    }

    @Test("A seat holding the led suit must follow it")
    func mustFollowSuit() {
        var state = playing([.zero: "5H 2C", .one: "AH 3H 9C 4S"])
        state = try! reduce(state, .play(seat: .zero, card: card("5H")))
        let legal = LegalMoves.legalPlays(state: state, seat: .one)
        #expect(Set(legal) == Set(cards("AH 3H")))
    }

    @Test("A seat void in the led suit may play anything")
    func voidPlaysAnything() {
        var state = playing([.zero: "5H 2C", .one: "9C 4S 2D"])
        state = try! reduce(state, .play(seat: .zero, card: card("5H")))
        let legal = LegalMoves.legalPlays(state: state, seat: .one)
        #expect(Set(legal) == Set(cards("9C 4S 2D")))
    }

    @Test("Spades may not be led before they are broken")
    func cannotLeadSpadesBeforeBroken() {
        let state = playing([.zero: "AS 5H 2C"])
        let legal = LegalMoves.legalPlays(state: state, seat: .zero)
        #expect(Set(legal) == Set(cards("5H 2C")))
        #expect(!LegalMoves.isLegal(play: card("AS"), state: state, seat: .zero))
    }

    @Test("A seat holding only spades may lead one")
    func onlySpadesException() {
        let state = playing([.zero: "AS 4S 2S"])
        let legal = LegalMoves.legalPlays(state: state, seat: .zero)
        #expect(Set(legal) == Set(cards("AS 4S 2S")))
    }

    @Test("Spades may be led once broken")
    func leadSpadesAfterBroken() {
        let state = playing([.zero: "AS 5H 2C"], spadesBroken: true)
        #expect(Set(LegalMoves.legalPlays(state: state, seat: .zero)) == Set(cards("AS 5H 2C")))
    }

    @Test("Discarding a spade when unable to follow breaks spades")
    func sluffingASpadeBreaksSpades() {
        var state = playing([.zero: "5H 2C", .one: "4S 9C"])
        state = try! reduce(state, .play(seat: .zero, card: card("5H")))
        #expect(!state.hand.spadesBroken)
        state = try! reduce(state, .play(seat: .one, card: card("4S")))
        #expect(state.hand.spadesBroken)
    }

    @Test("Discarding a non-spade does not break spades")
    func sluffingASideCardDoesNotBreakSpades() {
        var state = playing([.zero: "5H 2C", .one: "4S 9C"])
        state = try! reduce(state, .play(seat: .zero, card: card("5H")))
        state = try! reduce(state, .play(seat: .one, card: card("9C")))
        #expect(!state.hand.spadesBroken)
    }

    @Test("Leading a spade under the only-spades exception breaks spades")
    func onlySpadesLeadBreaksSpades() {
        var state = playing([.zero: "AS 4S", .one: "2S 9C"])
        state = try! reduce(state, .play(seat: .zero, card: card("AS")))
        #expect(state.hand.spadesBroken)
    }

    @Test("Legal plays are empty when it is not this seat's turn")
    func noPlaysOutOfTurn() {
        let state = playing([.zero: "5H 2C", .one: "AH 3H"])
        #expect(LegalMoves.legalPlays(state: state, seat: .one).isEmpty)
        #expect(LegalMoves.legalPlays(state: state, seat: .two).isEmpty)
    }

    @Test("The reducer rejects an illegal play")
    func reducerRejectsIllegalPlay() {
        var state = playing([.zero: "5H 2C", .one: "AH 3H 9C"])
        state = try! reduce(state, .play(seat: .zero, card: card("5H")))
        #expect(throws: GameError.illegalPlay(card("9C"), seat: .one)) {
            _ = try reduce(state, .play(seat: .one, card: card("9C")))
        }
    }

    @Test("The reducer rejects a card the seat does not hold")
    func reducerRejectsUnheldCard() {
        let state = playing([.zero: "5H 2C"])
        #expect(throws: GameError.cardNotHeld(card("KD"), seat: .zero)) {
            _ = try reduce(state, .play(seat: .zero, card: card("KD")))
        }
    }

    @Test("The reducer rejects a play from the wrong seat")
    func reducerRejectsWrongSeat() {
        let state = playing([.zero: "5H 2C", .one: "AH 3H"])
        #expect(throws: GameError.notYourTurn(expected: .zero, got: .one)) {
            _ = try reduce(state, .play(seat: .one, card: card("AH")))
        }
    }

    @Test("mustLeadTwoOfClubs forces the opening lead and the holder leads it")
    func twoOfClubsOpening() {
        var rules = RulesConfig.standard
        rules.mustLeadTwoOfClubs = true

        let hands = SeatMap<[Card]> { seat in
            seat == .two ? cards("2C AH") : cards("5H 9C")
        }
        var state = makeState(hands: hands, dealer: .zero, rules: rules)
        for seat in state.hand.firstBidder.clockwiseOrder {
            state = try! reduce(state, .bid(seat: seat, bid: .tricks(3)))
        }
        // Seat 2 holds the two of clubs, so seat 2 leads regardless of the dealer.
        #expect(state.hand.currentTrick?.leader == .two)
        #expect(LegalMoves.legalPlays(state: state, seat: .two) == [card("2C")])
    }

    @Test("mustLeadTwoOfClubs only constrains the first trick")
    func twoOfClubsOnlyFirstTrick() {
        var rules = RulesConfig.standard
        rules.mustLeadTwoOfClubs = true
        var state = playing([.zero: "2C 5H", .one: "3C 6H", .two: "4C 7H", .three: "9C 8H"], rules: rules)
        state.hand.completedTricks = [makeTrick(leader: .zero, cards("2D 3D 4D 5D"))]
        #expect(Set(LegalMoves.legalPlays(state: state, seat: .zero)) == Set(cards("2C 5H")))
    }
}
