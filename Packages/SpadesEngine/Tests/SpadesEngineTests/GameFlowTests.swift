import Foundation
import Testing
@testable import SpadesEngine

@Suite("Game flow")
struct GameFlowTests {

    @Test("A deal gives thirteen cards to each seat and uses all fifty-two")
    func dealIsComplete() {
        for seed in [UInt64(0), 1, 99, 123_456_789] {
            let state = GameState(seed: seed, seats: allBots())
            var seen: Set<Card> = []
            for seat in Seat.allCases {
                let hand = state.hand.hands[seat]
                #expect(hand.count == 13)
                seen.formUnion(hand)
            }
            #expect(seen.count == 52)
        }
    }

    @Test("Hands come back sorted by suit then rank")
    func handsAreSorted() {
        let state = GameState(seed: 7, seats: allBots())
        for seat in Seat.allCases {
            #expect(state.hand.hands[seat] == state.hand.hands[seat].sorted())
        }
    }

    @Test("The dealer rotates clockwise every hand")
    func dealerRotates() {
        var state = GameState(seed: 5, seats: allBots())
        #expect(state.hand.dealer == .zero)
        for expected in [Seat.one, .two, .three, .zero] {
            state.hand.phase = .complete
            state = state.advancingToNextHand()
            #expect(state.hand.dealer == expected)
        }
        #expect(state.handNumber == 4)
    }

    @Test("Each hand plays exactly thirteen tricks and accounts for all fifty-two cards")
    func handAccounting() throws {
        try runMatch(seed: 2_024, difficulties: SeatMap(repeating: .medium), onHandComplete: { state in
            #expect(state.hand.completedTricks.count == HandState.tricksPerHand)
            let played = state.hand.completedTricks.flatMap(\.cards)
            #expect(played.count == 52)
            #expect(Set(played).count == 52, "Every card is played exactly once")
            for seat in Seat.allCases {
                #expect(state.hand.hands[seat].isEmpty)
            }
            let tricksWon = Seat.allCases.reduce(0) { $0 + state.hand.tricksWon[$1] }
            #expect(tricksWon == HandState.tricksPerHand)
        })
    }

    @Test("Scores are the running sum of the hand results")
    func scoresSumFromHistory() throws {
        let run = try runMatch(seed: 909, difficulties: SeatMap(repeating: .hard))
        for team in Team.allCases {
            let expected = run.finalState.history.reduce(0) { $0 + $1.results[team].points }
            #expect(run.finalState.scores[team] == expected)
        }
    }

    @Test("A match ends when a team reaches the target, and rejects further actions")
    func matchEnds() throws {
        let run = try runMatch(seed: 31, difficulties: SeatMap(repeating: .medium))
        let state = run.finalState
        let winner = try #require(state.winner)
        #expect(state.scores[winner] >= state.rules.targetScore)
        #expect(state.seatToAct == nil)
        #expect(throws: GameError.matchAlreadyFinished) {
            _ = try reduce(state, .bid(seat: .zero, bid: .tricks(3)))
        }
    }

    @Test("Bidding after a scored hand deals the next one implicitly")
    func implicitHandAdvance() throws {
        var state = GameState(seed: 88, seats: allBots())
        state.hand.phase = .complete
        #expect(state.isAwaitingNextHand)

        // The action log alone must be enough to reproduce a match, so the
        // reducer deals rather than demanding an out-of-band step.
        let next = state.advancingToNextHand()
        let viaBid = try reduce(state, .bid(seat: next.hand.firstBidder, bid: .tricks(3)))
        #expect(viaBid.handNumber == next.handNumber)
        #expect(viaBid.hand.dealtHands == next.hand.dealtHands)
        #expect(viaBid.hand.bids[next.hand.firstBidder] == .tricks(3))
    }

    @Test("advancingToNextHand does nothing mid-hand or after the match")
    func advanceIsGuarded() {
        let mid = GameState(seed: 4, seats: allBots())
        #expect(mid.advancingToNextHand() == mid)

        var finished = mid
        finished.hand.phase = .complete
        finished.winner = .zeroTwo
        #expect(finished.advancingToNextHand() == finished)
    }

    @Test("Every hand of a match deals a different set of holdings")
    func handsVaryAcrossHands() {
        var state = GameState(seed: 1_234, seats: allBots())
        var seen: Set<[Card]> = []
        for _ in 0..<8 {
            seen.insert(state.hand.hands[.zero])
            state.hand.phase = .complete
            state = state.advancingToNextHand()
        }
        #expect(seen.count == 8)
    }
}

@Suite("Social actions")
struct SocialTests {

    private var table: GameState { GameState(seed: 3, seats: allBots()) }

    @Test("Reactions and phrases are capped at five per seat per hand")
    func rateLimit() throws {
        var state = table
        for _ in 0..<GameState.socialBudgetPerHand {
            state = try reduce(state, .reaction(from: .zero, to: .one, kind: .thumbsUp))
        }
        #expect(state.hand.reactionsUsed[.zero] == 5)
        #expect(state.socialFeed.count == 5)

        // Excess is dropped silently. Throwing here would desync multiplayer clients.
        let after = try reduce(state, .reaction(from: .zero, to: .one, kind: .angry))
        #expect(after.socialFeed.count == 5)
        #expect(after.hand.reactionsUsed[.zero] == 5)
        #expect(!LegalMoves.canSendReaction(state: after, from: .zero))
    }

    @Test("Reaction and phrase budgets are independent")
    func budgetsAreSeparate() throws {
        var state = table
        for _ in 0..<GameState.socialBudgetPerHand {
            state = try reduce(state, .reaction(from: .two, to: .three, kind: .laughing))
        }
        #expect(LegalMoves.canSendPhrase(state: state, from: .two))
        state = try reduce(state, .chat(from: .two, phrase: .goodLuck))
        #expect(state.hand.phrasesUsed[.two] == 1)
        #expect(state.socialFeed.count == 6)
    }

    @Test("Budgets reset when the next hand is dealt")
    func budgetResets() throws {
        var state = table
        state = try reduce(state, .chat(from: .one, phrase: .hi))
        #expect(state.hand.phrasesUsed[.one] == 1)
        state.hand.phase = .complete
        state = state.advancingToNextHand()
        #expect(state.hand.phrasesUsed[.one] == 0)
    }

    @Test("A seat cannot react to itself")
    func noSelfReaction() {
        #expect(throws: GameError.cannotReactToSelf(.zero)) {
            _ = try reduce(table, .reaction(from: .zero, to: .zero, kind: .thumbsUp))
        }
    }

    @Test("Social events carry a monotonic sequence and the feed is capped")
    func feedIsBounded() throws {
        var state = table
        var expectedSequence = 0
        for seat in Seat.allCases {
            for _ in 0..<GameState.socialBudgetPerHand {
                state = try reduce(state, .chat(from: seat, phrase: .thanks))
                expectedSequence += 1
            }
        }
        #expect(state.socialSequence == expectedSequence)
        #expect(state.socialFeed.count <= GameState.socialFeedLimit)
        let sequences = state.socialFeed.map(\.sequence)
        #expect(sequences == sequences.sorted())
    }

    @Test("Social actions never change whose turn it is")
    func socialDoesNotAdvanceTurn() throws {
        let before = table
        let after = try reduce(before, .reaction(from: .three, to: .zero, kind: .crying))
        #expect(after.seatToAct == before.seatToAct)
        #expect(after.hand.hands == before.hand.hands)
    }

    @Test("Every reaction has a symbol and every phrase a localisation key")
    func presentationMetadata() {
        for kind in ReactionKind.allCases {
            #expect(!kind.symbolName.isEmpty)
        }
        for phrase in QuickPhrase.allCases {
            #expect(phrase.localizationKey == "quickphrase.\(phrase.rawValue)")
            #expect(!phrase.englishFallback.isEmpty)
        }
        #expect(ReactionKind.allCases.count == 5)
        #expect(QuickPhrase.allCases.count == 12)
    }
}
