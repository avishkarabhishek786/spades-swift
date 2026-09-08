import Foundation
import SpadesEconomy
import SpadesEngine

/// How a table is set up before the first card is dealt.
///
/// The table always has exactly four seats. `humanCount` says how many of them
/// are people; the rest are filled with bots at match start (§6).
struct MatchConfig: Equatable, Sendable, Codable {
    /// Where two humans sit relative to each other.
    enum PartnerArrangement: String, Codable, Sendable, CaseIterable {
        /// Seats 0 and 2 — the two humans play together.
        case partners
        /// Seats 0 and 1 — the two humans play against each other.
        case opponents
    }

    var humanCount: Int
    var botDifficulty: BotDifficulty
    var stake: StakeTier
    var rules: RulesConfig
    var arrangement: PartnerArrangement
    var seed: UInt64
    /// The seat this device controls. Always rendered at the bottom of the screen.
    var localSeat: Seat
    var localPlayerID: PlayerID

    init(
        humanCount: Int = 1,
        botDifficulty: BotDifficulty = .medium,
        stake: StakeTier = .casual,
        rules: RulesConfig = .standard,
        arrangement: PartnerArrangement = .partners,
        seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
        localSeat: Seat = .zero,
        localPlayerID: PlayerID = PlayerID("local")
    ) {
        self.humanCount = min(max(humanCount, 1), Seat.allCases.count)
        self.botDifficulty = botDifficulty
        self.stake = stake
        self.rules = rules
        self.arrangement = arrangement
        self.seed = seed
        self.localSeat = localSeat
        self.localPlayerID = localPlayerID
    }

    /// True when every other seat is a bot. Solo play pays and costs forty
    /// percent, so bot-farming does not trivialise the ladder.
    var isSoloVsBots: Bool { humanCount == 1 }

    /// Which seats the humans occupy.
    ///
    /// One human sits at seat 0. Two humans sit at 0 and 2 as partners, or 0
    /// and 1 as opponents. Three or four fill 0, 1, 2 in order.
    var humanSeats: [Seat] {
        switch humanCount {
        case 1: [.zero]
        case 2: arrangement == .partners ? [.zero, .two] : [.zero, .one]
        case 3: [.zero, .one, .two]
        default: Seat.allCases
        }
    }

    /// The occupant of every seat at match start.
    func seats(humanIDs: [PlayerID] = []) -> SeatMap<SeatOccupant> {
        let humans = humanSeats
        return SeatMap { seat in
            guard let index = humans.firstIndex(of: seat) else {
                return .bot(botDifficulty, persona: BotPersona.forSeat(seat))
            }
            let id = index < humanIDs.count ? humanIDs[index] : PlayerID("player-\(seat.rawValue)")
            return .human(index == 0 ? localPlayerID : id)
        }
    }
}

/// Enough to rebuild an in-progress match exactly: a seed and an ordered list
/// of actions. Everything else is derived (§12).
struct MatchResumeRecord: Codable, Sendable, Equatable {
    var config: MatchConfig
    var seats: SeatMap<SeatOccupant>
    var actions: [GameAction]
}
