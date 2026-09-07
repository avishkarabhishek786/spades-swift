import Foundation
import Observation
import SpadesEngine

/// The player's career: points, record, streaks.
///
/// All the arithmetic lives in `SpadesEngine.Economy`, which has no clock and
/// no filesystem and is therefore covered by `make engine-test`. This type only
/// owns persistence and observation.
@MainActor
@Observable
final class CareerStore {
    private(set) var profile: CareerProfile
    private let store: any Persisting

    init(store: any Persisting) {
        self.store = store
        profile = (try? store.loadVersioned(CareerProfile.self, from: .careerProfile)) ?? .new
    }

    // MARK: - Queries

    func selectableTiers(soloVsBots: Bool) -> [StakeTier] {
        Economy.selectableTiers(profile: profile, soloVsBots: soloVsBots)
    }

    func isUnlocked(_ tier: StakeTier) -> Bool {
        Economy.isUnlocked(tier, profile: profile)
    }

    func entry(for tier: StakeTier, soloVsBots: Bool) -> Int {
        Economy.entry(for: tier, soloVsBots: soloVsBots)
    }

    func payout(for tier: StakeTier, soloVsBots: Bool) -> Int {
        Economy.payout(for: tier, soloVsBots: soloVsBots)
    }

    var winRate: Double {
        guard profile.gamesPlayed > 0 else { return 0 }
        return Double(profile.gamesWon) / Double(profile.gamesPlayed)
    }

    // MARK: - Mutation

    /// Settles a finished match. Called once, when the game concludes — never
    /// per hand, and never on a disconnect that reconnects inside the window.
    func settle(tier: StakeTier, outcome: Economy.MatchOutcome, soloVsBots: Bool) {
        profile = Economy.settle(profile: profile, tier: tier, outcome: outcome, soloVsBots: soloVsBots)
        persist()
    }

    func recordNils(made: Int, failed: Int) {
        guard made > 0 || failed > 0 else { return }
        profile = Economy.recordNils(profile: profile, made: made, failed: failed)
        persist()
    }

    /// Applies a bonus that has already been earned elsewhere — a daily claim
    /// or a completed rewarded view.
    func apply(_ updated: CareerProfile) {
        profile = updated
        persist()
    }

    private func persist() {
        try? store.saveVersioned(profile, to: .careerProfile)
    }
}
