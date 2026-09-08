import Foundation
import Observation
import SpadesEconomy

/// The player's career: points, record, streaks.
///
/// All the arithmetic lives in `SpadesEconomy`, which has no clock and no
/// filesystem and is therefore covered by `make engine-test`. This type owns
/// persistence and observation and nothing else.
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
        PointsLedger.selectableTiers(profile: profile, soloVsBots: soloVsBots)
    }

    func isUnlocked(_ tier: StakeTier) -> Bool {
        PointsLedger.isUnlocked(tier, profile: profile)
    }

    func isSelectable(_ tier: StakeTier, soloVsBots: Bool) -> Bool {
        PointsLedger.isSelectable(tier, profile: profile, soloVsBots: soloVsBots)
    }

    func entry(for tier: StakeTier, soloVsBots: Bool) -> Int {
        tier.entry(soloVsBots: soloVsBots)
    }

    func payout(for tier: StakeTier, soloVsBots: Bool) -> Int {
        tier.winPayout(soloVsBots: soloVsBots)
    }

    var winRate: Double {
        guard profile.gamesPlayed > 0 else { return 0 }
        return Double(profile.gamesWon) / Double(profile.gamesPlayed)
    }

    // MARK: - Mutation

    /// Settles a finished match. Called once, when the game concludes — never
    /// per hand, and never on a disconnect that reconnects inside the window.
    func settle(tier: StakeTier, outcome: MatchOutcome, soloVsBots: Bool) {
        profile = PointsLedger.settle(profile: profile, tier: tier, outcome: outcome, soloVsBots: soloVsBots)
        persist()
    }

    func recordNils(made: Int, failed: Int) {
        guard made > 0 || failed > 0 else { return }
        profile = PointsLedger.recordNils(profile: profile, made: made, failed: failed)
        persist()
    }

    /// Applies a profile that a bonus rule has already produced — a daily claim
    /// or a completed rewarded view.
    func apply(_ updated: CareerProfile) {
        profile = updated
        persist()
    }

    private func persist() {
        try? store.saveVersioned(profile, to: .careerProfile)
    }
}
