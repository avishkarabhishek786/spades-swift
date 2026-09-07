import Foundation
import Testing
@testable import SpadesEngine

@Suite("Determinism and encoding")
struct DeterminismTests {

    @Test("The same seed and action list produce an identical final state, twice over")
    func replayIsStable() throws {
        let seed: UInt64 = 20_260_907
        let seats = allBots(.hard)
        let run = try runMatch(seed: seed, difficulties: SeatMap(repeating: .hard))

        // Run the replay twice in the same test: a single replay would not
        // catch a hash-ordering leak that happens to be stable within a process.
        let first = try replay(seed: seed, rules: .standard, seats: seats, actions: run.actions)
        let second = try replay(seed: seed, rules: .standard, seats: seats, actions: run.actions)

        #expect(first == run.finalState)
        #expect(second == run.finalState)
        #expect(first == second)
        #expect(try first.stateHash() == second.stateHash())
    }

    @Test("The same seed deals the same cards")
    func dealIsSeedDetermined() {
        for seed in [UInt64(0), 7, 4_294_967_296] {
            let a = GameState(seed: seed, seats: allBots())
            let b = GameState(seed: seed, seats: allBots())
            #expect(a.hand.hands == b.hand.hands)
        }
    }

    @Test("Different seeds deal different cards")
    func differentSeedsDiffer() {
        let holdings = Set((0..<32).map { GameState(seed: UInt64($0), seats: allBots()).hand.hands[.zero] })
        #expect(holdings.count == 32)
    }

    @Test("A seeded generator repeats exactly")
    func generatorRepeats() {
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)
        var c = SeededGenerator(seed: 100)
        let fromA = (0..<64).map { _ in a.next() }
        let fromB = (0..<64).map { _ in b.next() }
        let fromC = (0..<64).map { _ in c.next() }
        #expect(fromA == fromB)
        #expect(fromA != fromC)
    }

    @Test("Game state survives a JSON round trip unchanged")
    func stateRoundTrip() throws {
        let run = try runMatch(seed: 555, difficulties: SeatMap(repeating: .medium))
        var state = run.finalState
        state = try reduceIgnoringFinish(state, .chat(from: .one, phrase: .rematch))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(decoded == state)
        #expect(try decoded.stateHash() == state.stateHash())
    }

    @Test("Actions survive a JSON round trip — this is the multiplayer wire format")
    func actionRoundTrip() throws {
        let actions: [GameAction] = [
            .bid(seat: .two, bid: .tricks(4)),
            .bid(seat: .three, bid: .nilBid),
            .bid(seat: .zero, bid: .blindNil),
            .play(seat: .one, card: Card(.queen, of: .spades)),
            .reaction(from: .zero, to: .two, kind: .thumbsDown),
            .chat(from: .three, phrase: .wellPlayed),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for action in actions {
            let decoded = try decoder.decode(GameAction.self, from: encoder.encode(action))
            #expect(decoded == action)
        }
    }

    @Test("The state hash changes when the state does")
    func hashDetectsDivergence() throws {
        let base = GameState(seed: 17, seats: allBots())
        let after = try reduce(base, .bid(seat: base.hand.firstBidder, bid: .tricks(5)))
        #expect(try base.stateHash() != after.stateHash())

        var diverged = after
        diverged.scores[.zeroTwo] += 10
        #expect(try after.stateHash() != diverged.stateHash())
    }

    @Test("A SeatMap rejects the wrong number of values")
    func seatMapValidatesArity() {
        let short = Data("[1,2,3]".utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(SeatMap<Int>.self, from: short)
        }
        let exact = Data("[1,2,3,4]".utf8)
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode(SeatMap<Int>.self, from: exact)
        }
    }

    @Test("RulesConfig decodes from a partial payload written by an older build")
    func rulesConfigTolerantDecoding() throws {
        let partial = Data(#"{"targetScore":250,"mustLeadTwoOfClubs":true}"#.utf8)
        let rules = try JSONDecoder().decode(RulesConfig.self, from: partial)
        #expect(rules.targetScore == 250)
        #expect(rules.mustLeadTwoOfClubs)
        #expect(rules.bagPenaltyThreshold == RulesConfig.standard.bagPenaltyThreshold)
        #expect(rules.blindNilRequiresDeficit == nil, "An absent optional stays absent")
    }

    /// The final state of a finished match rejects everything, including chat.
    /// This helper keeps the round-trip test honest without relaxing that rule.
    private func reduceIgnoringFinish(_ state: GameState, _ action: GameAction) throws -> GameState {
        var unfinished = state
        unfinished.winner = nil
        var result = try reduce(unfinished, action)
        result.winner = state.winner
        return result
    }
}
