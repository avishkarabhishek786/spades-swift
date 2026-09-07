import Foundation
import SpadesEngine
import Testing
@testable import Spades

@MainActor
@Suite("Game session")
struct GameSessionTests {

    private func makeSession(
        config: MatchConfig = MatchConfig(seed: 99, botDifficulty: .medium, stake: .casual),
        persistence: MemoryPersistence = MemoryPersistence()
    ) -> (GameSession, SilentAudioService, CareerStore) {
        let audio = SilentAudioService()
        let settings = SettingsStore(store: persistence)
        let career = CareerStore(store: persistence)
        let session = GameSession(
            config: config,
            audio: audio,
            haptics: SilentHapticsService(),
            career: career,
            settings: settings,
            persistence: persistence
        )
        session.automatesBots = false
        return (session, audio, career)
    }

    @Test("The local seat is always drawn at the bottom, whatever its number")
    func renderRotation() {
        for seat in Seat.allCases {
            let (session, _, _) = makeSession(config: MatchConfig(seed: 1, localSeat: seat))
            #expect(session.seat(at: .bottom) == seat)
            #expect(session.position(of: seat) == .bottom)
            // Clockwise on screen from the bottom: left, then top, then right.
            #expect(session.seat(at: .left) == seat.next)
            #expect(session.seat(at: .top) == seat.partner)
            #expect(session.position(of: seat.partner) == .top)
        }
    }

    @Test("No input is accepted while the deal is still running")
    func inputBlockedDuringDeal() {
        let (session, _, _) = makeSession()
        #expect(session.stage == .dealing)
        #expect(session.isBusy)
        #expect(session.legalPlays.isEmpty)
        #expect(session.legalBids.isEmpty)
    }

    @Test("Skipping the deal moves straight to bidding")
    func skipDeal() {
        let (session, _, _) = makeSession()
        session.skipDeal()
        #expect(session.stage == .bidding)
        #expect(session.dealtCards == 52)
    }

    @Test("The legal set comes from the engine, not from the view")
    func legalPlaysMatchTheEngine() {
        let (session, _, _) = makeSession(config: MatchConfig(seed: 7, localSeat: .zero))
        session.skipDeal()
        // Drive bidding to the local seat's turn and past it.
        while session.state.hand.phase == .bidding {
            guard let seat = session.state.seatToAct else { break }
            let legal = LegalMoves.legalBids(state: session.state, seat: seat)
            guard let bid = legal.first else { break }
            session.apply(.bid(seat: seat, bid: bid))
        }
        #expect(session.state.hand.phase == .playing)

        while session.state.seatToAct != session.localSeat {
            guard let seat = session.state.seatToAct,
                  let card = LegalMoves.legalPlays(state: session.state, seat: seat).first else { break }
            session.apply(.play(seat: seat, card: card))
        }
        #expect(session.legalPlays == LegalMoves.legalPlays(state: session.state, seat: session.localSeat))
        #expect(!session.legalPlays.isEmpty)
    }

    @Test("An illegal play is refused and reported rather than applied")
    func illegalPlayRefused() {
        let (session, audio, _) = makeSession()
        session.skipDeal()
        let before = session.state
        // Playing during bidding is never legal.
        session.play(card: session.localHand[0])
        #expect(session.state == before)
        #expect(session.rejection != nil)
        #expect(audio.played.contains(.invalidMove))
    }

    @Test("Bots take over every seat that is not the local player")
    func botsFillRemainingSeats() {
        let (session, _, _) = makeSession(config: MatchConfig(humanCount: 1, seed: 3))
        #expect(session.state.seats[.zero].isHuman)
        for seat in [Seat.one, .two, .three] {
            #expect(session.state.seats[seat].isBot)
        }
    }

    @Test("Two humans sit as partners or as opponents on request")
    func seatArrangements() {
        let partners = MatchConfig(humanCount: 2, arrangement: .partners)
        #expect(partners.humanSeats == [.zero, .two])
        let opponents = MatchConfig(humanCount: 2, arrangement: .opponents)
        #expect(opponents.humanSeats == [.zero, .one])
        #expect(MatchConfig(humanCount: 3).humanSeats == [.zero, .one, .two])
        #expect(MatchConfig(humanCount: 4).humanSeats == Seat.allCases)
    }

    @Test("A disconnected seat gets a bot and a system line, and comes back on reconnect")
    func substitution() {
        let (session, _, _) = makeSession(config: MatchConfig(humanCount: 2, seed: 12))
        let seat = Seat.two
        #expect(session.state.seats[seat].isHuman)

        session.substituteBot(at: seat)
        #expect(session.state.seats[seat].isBot)
        #expect(session.systemMessages.count == 1)

        session.restoreSeat(seat, to: PlayerID("returning"))
        #expect(session.state.seats[seat].playerID == PlayerID("returning"))
        #expect(session.systemMessages.count == 2)
    }

    @Test("A match resumes from its saved seed and action list")
    func resume() throws {
        let persistence = MemoryPersistence()
        let (session, _, _) = makeSession(config: MatchConfig(seed: 555), persistence: persistence)
        session.skipDeal()
        while session.state.hand.phase == .bidding {
            guard let seat = session.state.seatToAct,
                  let bid = LegalMoves.legalBids(state: session.state, seat: seat).first else { break }
            session.apply(.bid(seat: seat, bid: bid))
        }

        let record = try #require(try persistence.loadVersioned(MatchResumeRecord.self, from: .matchInProgress))
        let resumed = try #require(
            GameSession(
                resuming: record,
                audio: SilentAudioService(),
                haptics: SilentHapticsService(),
                career: CareerStore(store: persistence),
                settings: SettingsStore(store: persistence),
                persistence: persistence
            )
        )
        #expect(resumed.state == session.state)
        #expect(resumed.stage == .playing)
    }

    @Test("Muting a player hides their reactions without changing the game state")
    func muteHidesLocallyOnly() {
        let persistence = MemoryPersistence()
        let settings = SettingsStore(store: persistence)
        let session = GameSession(
            config: MatchConfig(humanCount: 2, seed: 8),
            audio: SilentAudioService(),
            haptics: SilentHapticsService(),
            career: CareerStore(store: persistence),
            settings: settings,
            persistence: persistence
        )
        session.automatesBots = false
        session.skipDeal()

        let sender = Seat.two
        let id = session.state.seats[sender].playerID?.rawValue ?? ""
        #expect(!id.isEmpty)
        settings.toggleMute(id)

        let before = session.state
        session.apply(.reaction(from: sender, to: .zero, kind: .angry))
        // The reducer still counted it — peers must stay in sync — but this
        // client does not draw it.
        #expect(session.state.socialSequence == before.socialSequence + 1)
        #expect(session.activeSocialEvents.isEmpty)
    }

    @Test("Quitting a ranked match forfeits the stake once")
    func forfeit() {
        let persistence = MemoryPersistence()
        let career = CareerStore(store: persistence)
        career.apply(CareerProfile(points: 1_000, lifetimePointsEarned: 1_000, currentStreak: 3))
        let session = GameSession(
            config: MatchConfig(humanCount: 1, stake: .silver, seed: 2),
            audio: SilentAudioService(),
            haptics: SilentHapticsService(),
            career: career,
            settings: SettingsStore(store: persistence),
            persistence: persistence
        )
        session.automatesBots = false

        session.forfeit()
        // Solo entry is forty percent of two hundred.
        #expect(career.profile.points == 920)
        #expect(career.profile.currentStreak == 2)

        session.forfeit()
        #expect(career.profile.points == 920, "Settlement happens once, at the end of the match")
    }
}
