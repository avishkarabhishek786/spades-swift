import Foundation
import Observation
import SpadesEconomy
import SpadesEngine

/// The one object that turns a pure `GameState` into a game.
///
/// It owns every effect the engine deliberately does not have: the clock that
/// paces bot turns, the sounds, the haptics, the save file, and the network.
/// Views observe it and ask it to do things; nothing outside this type ever
/// mutates a `GameState` (§4).
@MainActor
@Observable
final class GameSession {

    /// What the table is showing. Distinct from `HandState.Phase` because the
    /// deal and the trick pause are presentation, not rules.
    enum Stage: Equatable {
        case dealing
        case bidding
        case playing
        case handComplete
        case matchComplete
    }

    // MARK: - Observable state

    private(set) var state: GameState
    private(set) var stage: Stage = .dealing
    private(set) var actionLog: [GameAction] = []
    /// How many cards of the current deal have landed. Drives the stagger.
    private(set) var dealtCards = 0
    /// A completed trick, held on the table so players can see what happened.
    private(set) var showcasedTrick: Trick?
    /// Social events currently animating, newest last.
    private(set) var activeSocialEvents: [SocialEvent] = []
    /// Local-only announcements: substitutions, reconnects. Never sent anywhere.
    private(set) var systemMessages: [String] = []
    /// Set when the player tries something illegal. Cleared on the next action.
    private(set) var rejection: String?

    let config: MatchConfig
    var localSeat: Seat { config.localSeat }

    // MARK: - Collaborators

    private let audio: any AudioPlaying
    private let haptics: any HapticsProviding
    private let career: CareerStore
    private let settings: SettingsStore
    private let persistence: any Persisting
    private let transport: (any MatchTransport)?

    /// Set to false by tests that drive every seat themselves. Bot turns are
    /// timer-driven, and a timer firing mid-assertion is not a useful test.
    var automatesBots = true

    private var botTask: Task<Void, Never>?
    private var socialTasks: [Int: Task<Void, Never>] = [:]
    private var sequence = 0
    private var settled = false
    /// The last hand whose result has been recorded, so a hand that also ends
    /// the match still gets its nil counters and its haptic.
    private var lastConcludedHand = -1
    private var disconnectedSeats: Set<Seat> = []

    // MARK: - Init

    init(
        config: MatchConfig,
        seats: SeatMap<SeatOccupant>? = nil,
        audio: any AudioPlaying,
        haptics: any HapticsProviding,
        career: CareerStore,
        settings: SettingsStore,
        persistence: any Persisting,
        transport: (any MatchTransport)? = nil
    ) {
        self.config = config
        self.audio = audio
        self.haptics = haptics
        self.career = career
        self.settings = settings
        self.persistence = persistence
        self.transport = transport
        state = GameState(seed: config.seed, rules: config.rules, seats: seats ?? config.seats())
    }

    /// Rebuilds a session from a saved seed and action list.
    convenience init?(
        resuming record: MatchResumeRecord,
        audio: any AudioPlaying,
        haptics: any HapticsProviding,
        career: CareerStore,
        settings: SettingsStore,
        persistence: any Persisting
    ) {
        self.init(
            config: record.config,
            seats: record.seats,
            audio: audio,
            haptics: haptics,
            career: career,
            settings: settings,
            persistence: persistence
        )
        var rebuilt = state
        for action in record.actions {
            guard let next = try? reduce(rebuilt, action) else { return nil }
            rebuilt = next
        }
        state = rebuilt
        actionLog = record.actions
        dealtCards = 52
        syncStage()
    }

    // MARK: - Derived views for the UI

    /// The four screen positions, clockwise from the local player.
    enum TablePosition: Int, CaseIterable {
        case bottom = 0, left, top, right
    }

    /// Which seat is drawn where. Seat 0 is not the bottom of the screen —
    /// the *local* seat is, on every client. Rotate the render, not the model.
    func seat(at position: TablePosition) -> Seat {
        localSeat.advanced(by: position.rawValue)
    }

    func position(of seat: Seat) -> TablePosition {
        let offset = (seat.rawValue - localSeat.rawValue + Seat.allCases.count) % Seat.allCases.count
        return TablePosition(rawValue: offset) ?? .bottom
    }

    var localHand: [Card] { state.hand.hands[localSeat] }

    var isLocalTurn: Bool { state.seatToAct == localSeat && !isBusy }

    /// True while the table is animating and input should be ignored.
    var isBusy: Bool { stage == .dealing || showcasedTrick != nil }

    /// Cards the local player may play. The view greys out everything else
    /// rather than deciding legality for itself (§15).
    var legalPlays: [Card] {
        isBusy ? [] : LegalMoves.legalPlays(state: state, seat: localSeat)
    }

    var legalBids: [Bid] {
        isBusy ? [] : LegalMoves.legalBids(state: state, seat: localSeat)
    }

    func occupantName(for seat: Seat) -> String {
        switch state.seats[seat] {
        case .bot(_, let persona): persona.displayName
        case .human(let id): seat == localSeat ? String(localized: "seat.you") : id.rawValue
        case .empty: String(localized: "seat.empty")
        }
    }

    /// VoiceOver description of a seat: who it is, what they bid, what they have taken.
    func accessibilityLabel(for seat: Seat) -> String {
        let name = occupantName(for: seat)
        let taken = state.hand.tricksWon[seat]
        guard let bid = state.hand.bids[seat] else {
            return String(localized: "seat.a11y.noBid \(name) \(taken)")
        }
        return String(localized: "seat.a11y \(name) \(bid.description) \(taken)")
    }

    // MARK: - Lifecycle

    /// Starts the deal. Idempotent.
    func start() {
        guard stage == .dealing, dealtCards == 0 else { return }
        audio.play(.shuffle)
        Task { await runDeal() }
    }

    private func runDeal() async {
        let total = 52
        // The whole deal must land inside the budget, however many cards it is.
        let interval = min(Theme.dealStagger, Theme.maxDealDuration / Double(total))
        for index in 0..<total {
            guard stage == .dealing else { return }
            dealtCards = index + 1
            if index.isMultiple(of: 4) { audio.play(.dealCard) }
            try? await Task.sleep(for: .seconds(interval))
        }
        finishDeal()
    }

    /// Tap-to-skip. Uninterruptible animation becomes irritating by game ten.
    func skipDeal() {
        guard stage == .dealing else { return }
        dealtCards = 52
        finishDeal()
    }

    private func finishDeal() {
        guard stage == .dealing else { return }
        dealtCards = 52
        stage = .bidding
        offerBotChat(.handStart)
        scheduleBotTurn()
    }

    // MARK: - Player input

    func place(bid: Bid) {
        perform(.bid(seat: localSeat, bid: bid))
    }

    func play(card: Card) {
        guard legalPlays.contains(card) else {
            audio.play(.invalidMove)
            rejection = String(localized: "table.illegalPlay")
            return
        }
        perform(.play(seat: localSeat, card: card))
    }

    func react(to seat: Seat, with kind: ReactionKind) {
        guard seat != localSeat else { return }
        perform(.reaction(from: localSeat, to: seat, kind: kind))
    }

    func sendPhrase(_ phrase: QuickPhrase) {
        perform(.chat(from: localSeat, phrase: phrase))
    }

    /// Moves on from the score screen. The next hand is dealt deterministically,
    /// so a replay of the action log reaches the same place either way.
    func continueToNextHand() {
        guard stage == .handComplete, state.isAwaitingNextHand else { return }
        state = state.advancingToNextHand()
        dealtCards = 0
        stage = .dealing
        start()
    }

    // MARK: - The one place state changes

    /// Applies an action and fires every effect that goes with it.
    ///
    /// The table view never calls this directly — it goes through
    /// ``play(card:)`` and friends, which check ``LegalMoves`` first. It is
    /// internal so tests can drive a hand without waiting on bot timers.
    func apply(_ action: GameAction) { perform(action) }

    private func perform(_ action: GameAction) {
        rejection = nil
        let before = state
        let newState: GameState
        do {
            newState = try reduce(state, action)
        } catch {
            // The UI asks LegalMoves first, so reaching here means a bug or a
            // hostile peer. Neither should take the game down.
            audio.play(.invalidMove)
            rejection = String(localized: "table.rejected")
            return
        }

        state = newState
        actionLog.append(action)
        sequence += 1

        emitEffects(for: action, before: before, after: newState)
        broadcast(action)
        if isCheckpoint(before: before, after: newState) { saveResumePoint() }
        advanceAfter(action, before: before)
    }

    private func emitEffects(for action: GameAction, before: GameState, after: GameState) {
        switch action {
        case .bid(_, let bid):
            audio.play(bid.isNil ? .bidNil : .bidConfirm)
            haptics.bidConfirmed()
        case .play:
            audio.play(.playCard)
            haptics.cardPlayed()
        case .reaction:
            audio.play(.reactionSent)
        case .chat:
            audio.play(.chatSent)
        }

        // Any social event the reducer actually accepted — dropped ones never
        // reach the feed, so this is also the rate limit taking effect.
        for event in after.socialFeed where event.sequence > before.socialSequence {
            show(event)
        }
    }

    private func advanceAfter(_ action: GameAction, before: GameState) {
        guard action.isTurnAdvancing else { return }

        // A trick just completed: hold it on the table before collecting.
        if state.hand.completedTricks.count > before.hand.completedTricks.count,
           let trick = state.hand.completedTricks.last {
            showcasedTrick = trick
            audio.play(.trickWon)
            haptics.trickCollected()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Theme.trickShowcaseDuration))
                self?.showcasedTrick = nil
                self?.syncStage()
                self?.scheduleBotTurn()
            }
            return
        }

        syncStage()
        scheduleBotTurn()
    }

    private func syncStage() {
        if state.hand.phase == .complete, state.handNumber != lastConcludedHand {
            lastConcludedHand = state.handNumber
            concludeHand()
        }

        if state.isFinished {
            stage = .matchComplete
            concludeMatch()
        } else if state.hand.phase == .complete {
            stage = .handComplete
        } else if state.hand.phase == .bidding {
            stage = .bidding
        } else {
            stage = .playing
        }
    }

    // MARK: - Scoring moments

    private func concludeHand() {
        guard let summary = state.history.last else { return }
        audio.play(.handComplete)

        let localTeam = localSeat.team
        let result = summary.results[localTeam]
        if result.madeContract {
            haptics.contractMade()
        }
        if result.bagPenaltiesApplied > 0 || !result.madeContract {
            haptics.penalty()
        }

        // Nil counters are career statistics, not score. Points are settled
        // once, when the match ends.
        var made = 0
        var failed = 0
        for seat in [localTeam.seats.0, localTeam.seats.1] {
            guard let bid = summary.bids[seat], bid.isNil else { continue }
            if summary.tricksWon[seat] == 0 { made += 1 } else { failed += 1 }
        }
        career.recordNils(made: made, failed: failed)
        offerBotChat(.handComplete)
    }

    private func concludeMatch() {
        guard !settled, let winner = state.winner else { return }
        settled = true
        let won = winner == localSeat.team
        audio.play(won ? .gameWon : .gameLost)
        // The engine produced a winning `Team`; the economy is handed a
        // `MatchOutcome` and never sees the game state (§4).
        career.settle(
            tier: config.stake,
            outcome: won ? MatchOutcome.win : .loss,
            soloVsBots: config.isSoloVsBots
        )
        if won { audio.play(.pointsAwarded) }
        botTask?.cancel()
        try? persistence.remove(.matchInProgress)
    }

    /// Called when the player abandons a ranked match in progress. Forfeits the
    /// stake and dents the streak; a reconnect inside the grace window never
    /// reaches here.
    func forfeit() {
        guard !settled, !state.isFinished else { return }
        settled = true
        botTask?.cancel()
        career.settle(tier: config.stake, outcome: MatchOutcome.quit, soloVsBots: config.isSoloVsBots)
        try? persistence.remove(.matchInProgress)
    }

    // MARK: - Bots

    private func scheduleBotTurn() {
        botTask?.cancel()
        guard automatesBots else { return }
        guard !state.isFinished, showcasedTrick == nil else { return }
        guard let seat = state.seatToAct, seat != localSeat else { return }
        guard case .bot(let difficulty, let persona) = state.seats[seat] else { return }

        let snapshot = state
        let salt = UInt64(actionLog.count)
        botTask = Task { [weak self] in
            // Without this a bot's turn is instant and the game feels broken.
            // The delay belongs here and never in the engine (§6).
            let delay = Double.random(in: 0.6...1.4)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            let action = await Self.decide(
                state: snapshot, seat: seat, difficulty: difficulty, persona: persona, salt: salt
            )
            guard !Task.isCancelled, let action else { return }
            self?.perform(action)
        }
    }

    /// Runs off the main actor. A hard bot doing void inference on the main
    /// thread drops frames (§15); `nonisolated` is what keeps it off.
    private nonisolated static func decide(
        state: GameState,
        seat: Seat,
        difficulty: BotDifficulty,
        persona: BotPersona,
        salt: UInt64
    ) async -> GameAction? {
        var generator = SeededGenerator(seed: state.seed &+ salt &* 0x2545_F491_4F6C_DD1D)
        let bot = BotPlayer(difficulty: difficulty, persona: persona)
        return bot.act(in: state, seat: seat, using: &generator)
    }

    /// Gives each bot one chance to say something. The engine's per-hand budget
    /// caps it even if the dice are kind, and the personas are barely chatty on
    /// purpose — roughly one line per bot per hand, or it reads as spam.
    private func offerBotChat(_ moment: BotPlayer.ChatMoment) {
        // In a networked match the host owns the bots. A client generating its
        // own bot chatter would put an action into its log that no peer has.
        guard transport?.isHost ?? true else { return }

        for seat in Seat.allCases {
            guard case .bot(let difficulty, let persona) = state.seats[seat] else { continue }
            var generator = SeededGenerator(
                seed: state.seed &+ UInt64(state.handNumber) &* 31 &+ UInt64(seat.rawValue)
            )
            let bot = BotPlayer(difficulty: difficulty, persona: persona)
            guard let action = bot.chatAction(for: moment, state: state, seat: seat, using: &generator)
            else { continue }
            // Goes through the same path as everything else, so it is
            // broadcast, saved and rate-limited exactly like a player's line.
            perform(action)
        }
    }

    // MARK: - Social presentation

    private func show(_ event: SocialEvent) {
        // Muting and the global hide switch are local presentation decisions.
        // They never change the game state, so peers stay in sync.
        guard settings.showsSocial(from: state.seats[event.from].playerID?.rawValue) else { return }
        activeSocialEvents.append(event)
        socialTasks[event.sequence]?.cancel()
        socialTasks[event.sequence] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.reactionLinger))
            guard !Task.isCancelled else { return }
            self?.activeSocialEvents.removeAll { $0.sequence == event.sequence }
            self?.socialTasks[event.sequence] = nil
        }
    }

    // MARK: - Persistence and network

    /// Writes the resume point. Called at checkpoints rather than after every
    /// card: an atomic write per action is fifty-two file rewrites a hand, and
    /// the action log only grows.
    func saveNow() { saveResumePoint() }

    /// Trick and phase boundaries. Resuming from one loses at most the cards
    /// already face up on the table, and backgrounding calls ``saveNow()``
    /// anyway, so nothing is lost in the case that actually matters.
    private func isCheckpoint(before: GameState, after: GameState) -> Bool {
        after.hand.phase != before.hand.phase
            || after.handNumber != before.handNumber
            || after.hand.completedTricks.count != before.hand.completedTricks.count
    }

    private func saveResumePoint() {
        guard !state.isFinished else { return }
        let record = MatchResumeRecord(config: config, seats: state.seats, actions: actionLog)
        try? persistence.saveVersioned(record, to: .matchInProgress)
    }

    private func broadcast(_ action: GameAction) {
        guard let transport else { return }
        let hash = (try? state.stateHash()) ?? 0
        let envelope = MatchEnvelope(sequence: sequence, action: action, stateHash: hash)
        try? transport.send(.action(envelope))
    }

    /// Substitutes a bot for a seat whose player has dropped, and says so.
    func substituteBot(at seat: Seat) {
        guard case .human = state.seats[seat] else { return }
        disconnectedSeats.insert(seat)
        let persona = BotPersona.forSeat(seat)
        state.seats[seat] = .bot(config.botDifficulty, persona: persona)
        systemMessages.append(String(localized: "table.substituted \(persona.displayName)"))
        scheduleBotTurn()
    }

    /// Hands a seat back to a player who reconnected inside the grace window.
    func restoreSeat(_ seat: Seat, to player: PlayerID) {
        guard disconnectedSeats.contains(seat) else { return }
        disconnectedSeats.remove(seat)
        state.seats[seat] = .human(player)
        systemMessages.append(String(localized: "table.reconnected \(occupantName(for: seat))"))
        botTask?.cancel()
        scheduleBotTurn()
    }
}

// MARK: - Applying remote actions

extension GameSession: MatchTransportDelegate {
    func transport(_ transport: any MatchTransport, didReceive payload: MatchPayload, from player: PlayerID) {
        switch payload {
        case .action(let envelope):
            guard let next = try? reduce(state, envelope.action) else {
                // Cannot apply it: the peers have diverged. Ask for the truth
                // rather than limping along out of sync (§7).
                try? transport.send(.resyncRequest)
                return
            }
            state = next
            actionLog.append(envelope.action)
            if let local = try? state.stateHash(), local != envelope.stateHash {
                try? transport.send(.resyncRequest)
            }
            syncStage()
            scheduleBotTurn()

        case .snapshot(let snapshot):
            state = snapshot.state
            syncStage()
            scheduleBotTurn()

        case .resyncRequest:
            guard transport.isHost else { return }
            try? transport.send(.snapshot(MatchSnapshot(sequence: sequence, state: state)))
        }
    }

    func transport(_ transport: any MatchTransport, playerDidDisconnect player: PlayerID) {
        guard let seat = Seat.allCases.first(where: { state.seats[$0].playerID == player }) else { return }
        substituteBot(at: seat)
    }

    func transport(_ transport: any MatchTransport, playerDidReconnect player: PlayerID) {
        guard let seat = disconnectedSeats.first else { return }
        restoreSeat(seat, to: player)
    }
}
