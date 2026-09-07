import Foundation
import Testing
@testable import SpadesEngine

// Helpers shared by the suites below. Tests build states directly rather than
// dealing, so a rule can be pinned to one exact holding.

func allBots(_ difficulty: BotDifficulty = .medium) -> SeatMap<SeatOccupant> {
    SeatMap { .bot(difficulty, persona: BotPersona.forSeat($0)) }
}

/// A state with hand-picked holdings, already past bidding unless `bids` is nil.
func makeState(
    hands: SeatMap<[Card]>,
    dealer: Seat = .zero,
    rules: RulesConfig = .standard,
    bids: SeatMap<Bid?>? = nil,
    scores: TeamMap<Int> = TeamMap(repeating: 0),
    bags: TeamMap<Int> = TeamMap(repeating: 0)
) -> GameState {
    var state = GameState(seed: 0, rules: rules, seats: allBots())
    state.hand = HandState(dealer: dealer, hands: hands)
    state.scores = scores
    state.bags = bags
    if let bids {
        state.hand.bids = bids
        state.hand.phase = .playing
        state.hand.currentTrick = Trick(leader: dealer.next)
    }
    return state
}

/// Parses "AS KH 3C" style shorthand into cards. Keeps trick fixtures readable.
func cards(_ shorthand: String) -> [Card] {
    shorthand.split(separator: " ").compactMap { token -> Card? in
        guard let suitChar = token.last else { return nil }
        let rankText = String(token.dropLast())
        let suit: Suit? = switch suitChar {
        case "S": .spades
        case "H": .hearts
        case "D": .diamonds
        case "C": .clubs
        default: nil
        }
        let rank: Rank? = switch rankText {
        case "A": .ace
        case "K": .king
        case "Q": .queen
        case "J": .jack
        case "10", "T": .ten
        default: Rank(rawValue: Int(rankText) ?? 0)
        }
        guard let suit, let rank else { return nil }
        return Card(rank, of: suit)
    }
}

func card(_ shorthand: String) -> Card {
    guard let card = cards(shorthand).first else {
        Issue.record("Bad card shorthand: \(shorthand)")
        return Card(.two, of: .clubs)
    }
    return card
}

/// Builds a trick from an ordered list of (seat, card) pairs.
func makeTrick(leader: Seat, _ played: [Card]) -> Trick {
    var trick = Trick(leader: leader)
    for (index, card) in played.enumerated() {
        trick.append(Trick.Play(seat: leader.advanced(by: index), card: card))
    }
    return trick
}

// MARK: - Full-match driver

/// Result of driving one match to completion with bots in every seat.
struct MatchRun {
    var finalState: GameState
    var actions: [GameAction]
    var handsPlayed: Int
}

enum MatchRunError: Error, CustomStringConvertible {
    case stalled(afterActions: Int)
    case illegalAction(GameAction, Error)

    var description: String {
        switch self {
        case .stalled(let count): "Match made no progress after \(count) actions"
        case .illegalAction(let action, let error): "Rejected \(action): \(error)"
        }
    }
}

/// Plays a whole match with bots in all four seats.
///
/// `inspect` runs before every action is applied, which is where the property
/// tests assert that no bot ever proposes something illegal.
@discardableResult
func runMatch(
    seed: UInt64,
    difficulties: SeatMap<BotDifficulty>,
    rules: RulesConfig = .standard,
    maxHands: Int = 200,
    inspect: ((GameState, GameAction) -> Void)? = nil,
    onHandComplete: ((GameState) -> Void)? = nil
) throws -> MatchRun {
    let seats = SeatMap<SeatOccupant> { .bot(difficulties[$0], persona: BotPersona.forSeat($0)) }
    var state = GameState(seed: seed, rules: rules, seats: seats)
    var generator = SeededGenerator(seed: seed ^ 0xA5A5_A5A5_A5A5_A5A5)
    var actions: [GameAction] = []

    while !state.isFinished {
        if state.isAwaitingNextHand {
            guard state.handNumber + 1 < maxHands else { break }
            state = state.advancingToNextHand()
            continue
        }
        guard let seat = state.seatToAct else { throw MatchRunError.stalled(afterActions: actions.count) }
        let bot = BotPlayer(difficulty: difficulties[seat], persona: BotPersona.forSeat(seat))
        guard let action = bot.act(in: state, seat: seat, using: &generator) else {
            throw MatchRunError.stalled(afterActions: actions.count)
        }
        inspect?(state, action)
        let phaseBefore = state.hand.phase
        do {
            state = try reduce(state, action)
        } catch {
            throw MatchRunError.illegalAction(action, error)
        }
        actions.append(action)
        if state.hand.phase == .complete, phaseBefore != .complete {
            onHandComplete?(state)
        }
    }

    return MatchRun(finalState: state, actions: actions, handsPlayed: state.history.count)
}

/// Replays an action list from scratch. Used by the determinism suite.
func replay(seed: UInt64, rules: RulesConfig, seats: SeatMap<SeatOccupant>, actions: [GameAction]) throws -> GameState {
    var state = GameState(seed: seed, rules: rules, seats: seats)
    for action in actions {
        state = try reduce(state, action)
    }
    return state
}
