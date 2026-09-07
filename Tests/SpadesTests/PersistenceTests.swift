import Foundation
import SpadesEngine
import Testing
@testable import Spades

@Suite("Persistence")
struct PersistenceTests {

    @Test("A value round trips through storage")
    func roundTrip() throws {
        let store = MemoryPersistence()
        let profile = CareerProfile(points: 420, lifetimePointsEarned: 900, gamesPlayed: 3)
        try store.saveVersioned(profile, to: .careerProfile)
        #expect(try store.loadVersioned(CareerProfile.self, from: .careerProfile) == profile)
    }

    @Test("An absent key loads as nil rather than failing")
    func missingKey() throws {
        let store = MemoryPersistence()
        #expect(try store.loadVersioned(CareerProfile.self, from: .careerProfile) == nil)
    }

    @Test("Everything on disk carries a schema version from day one")
    func documentsAreVersioned() throws {
        let store = MemoryPersistence()
        try store.saveVersioned(SettingsStore.Values(), to: .settings)
        let document = try store.load(VersionedDocument<SettingsStore.Values>.self, from: .settings)
        #expect(document?.schemaVersion == 1)
    }

    @Test("A file from a newer build is refused, not silently truncated")
    func refusesNewerSchema() throws {
        let store = MemoryPersistence()
        // Round-tripping a future version through this build would drop every
        // field it does not know about — that is deleting the player's progress.
        var document = VersionedDocument(CareerProfile(points: 10))
        document.schemaVersion = 99
        try store.save(document, to: .careerProfile)

        #expect(throws: PersistenceError.unsupportedSchemaVersion(found: 99, supported: 1)) {
            _ = try store.loadVersioned(CareerProfile.self, from: .careerProfile)
        }
    }

    @Test("A match is stored as a seed plus its action list, and replays exactly")
    func matchResumeRoundTrip() throws {
        let store = MemoryPersistence()
        let config = MatchConfig(seed: 4_242)
        var state = GameState(seed: config.seed, rules: config.rules, seats: config.seats())
        var actions: [GameAction] = []
        for offset in 0..<4 {
            let seat = state.hand.firstBidder.advanced(by: offset)
            let action = GameAction.bid(seat: seat, bid: .tricks(3))
            state = try reduce(state, action)
            actions.append(action)
        }

        let record = MatchResumeRecord(config: config, seats: config.seats(), actions: actions)
        try store.saveVersioned(record, to: .matchInProgress)
        let restored = try #require(try store.loadVersioned(MatchResumeRecord.self, from: .matchInProgress))

        var replayed = GameState(seed: restored.config.seed, rules: restored.config.rules, seats: restored.seats)
        for action in restored.actions { replayed = try reduce(replayed, action) }
        #expect(replayed == state)
    }

    @Test("Files land in Application Support and survive a reload")
    func filePersistence() throws {
        let name = "SpadesTests-\(UUID().uuidString)"
        let store = try FilePersistence(directoryName: name)
        defer {
            let base = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
            )
            if let url = base?.appendingPathComponent(name) { try? FileManager.default.removeItem(at: url) }
        }

        try store.saveVersioned(CareerProfile(points: 77), to: .careerProfile)
        let reopened = try FilePersistence(directoryName: name)
        #expect(try reopened.loadVersioned(CareerProfile.self, from: .careerProfile)?.points == 77)

        try reopened.remove(.careerProfile)
        #expect(try reopened.loadVersioned(CareerProfile.self, from: .careerProfile) == nil)
    }
}
