import Testing
@testable import SpadesEconomy

@Suite("Stakes and points")
struct StakeTierTests {

    @Test("Every tier matches the published table")
    func tierTable() {
        #expect(StakeTier.casual.entry == 0 && StakeTier.casual.winPayout == 25 && StakeTier.casual.unlockThreshold == 0)
        #expect(StakeTier.bronze.entry == 50 && StakeTier.bronze.winPayout == 100 && StakeTier.bronze.unlockThreshold == 100)
        #expect(StakeTier.silver.entry == 200 && StakeTier.silver.winPayout == 425 && StakeTier.silver.unlockThreshold == 500)
        #expect(StakeTier.gold.entry == 750 && StakeTier.gold.winPayout == 1_600 && StakeTier.gold.unlockThreshold == 2_000)
        #expect(StakeTier.elite.entry == 2_500 && StakeTier.elite.winPayout == 5_500 && StakeTier.elite.unlockThreshold == 10_000)
    }

    @Test("Solo matches against bots pay and cost forty percent")
    func soloDiscount() {
        for tier in StakeTier.allCases {
            #expect(tier.entry(soloVsBots: true) == tier.entry * 2 / 5)
            #expect(tier.winPayout(soloVsBots: true) == tier.winPayout * 2 / 5)
            #expect(tier.entry(soloVsBots: false) == tier.entry)
        }
        #expect(StakeTier.gold.winPayout(soloVsBots: true) == 640)
        #expect(StakeTier.gold.entry(soloVsBots: true) == 300)
    }

    @Test("Points never go below zero")
    func pointsClampAtZero() {
        let broke = CareerProfile(points: 20, lifetimePointsEarned: 400)
        let after = PointsLedger.settle(profile: broke, tier: .silver, outcome: .loss, soloVsBots: false)
        #expect(after.points == 0, "A loss larger than the balance clamps rather than going negative")
        #expect(after.gamesPlayed == 1)

        let stillZero = PointsLedger.settle(profile: after, tier: .silver, outcome: .loss, soloVsBots: false)
        #expect(stillZero.points == 0)
    }

    @Test("A player at zero can always sit at a Casual table")
    func casualAlwaysReachable() {
        let broke = CareerProfile(points: 0, lifetimePointsEarned: 0)
        #expect(PointsLedger.isSelectable(.casual, profile: broke, soloVsBots: false))
        #expect(PointsLedger.selectableTiers(profile: broke, soloVsBots: false) == [.casual])

        // Even a veteran who has lost everything keeps the way back in.
        let veteran = CareerProfile(points: 0, lifetimePointsEarned: 50_000)
        #expect(PointsLedger.isSelectable(.casual, profile: veteran, soloVsBots: false))
        #expect(!PointsLedger.isSelectable(.elite, profile: veteran, soloVsBots: false))
    }

    @Test("A tier needs both its unlock threshold and the entry on hand")
    func tierGating() {
        let newRich = CareerProfile(points: 900, lifetimePointsEarned: 300)
        #expect(!PointsLedger.isUnlocked(.silver, profile: newRich))
        #expect(!PointsLedger.isSelectable(.silver, profile: newRich, soloVsBots: false))

        let unlockedBroke = CareerProfile(points: 100, lifetimePointsEarned: 900)
        #expect(PointsLedger.isUnlocked(.silver, profile: unlockedBroke))
        #expect(!PointsLedger.isSelectable(.silver, profile: unlockedBroke, soloVsBots: false))

        // The solo discount can bring a tier back in reach.
        #expect(PointsLedger.isSelectable(.silver, profile: unlockedBroke, soloVsBots: true))
    }

    @Test("Winning pays the tier payout and extends the streak")
    func winPayout() {
        var profile = CareerProfile(points: 500, lifetimePointsEarned: 500, currentStreak: 2, bestStreak: 2)
        profile = PointsLedger.settle(profile: profile, tier: .bronze, outcome: .win, soloVsBots: false)
        #expect(profile.points == 600)
        #expect(profile.lifetimePointsEarned == 600)
        #expect(profile.gamesWon == 1)
        #expect(profile.currentStreak == 3)
        #expect(profile.bestStreak == 3)
    }

    @Test("A loss resets the streak; quitting only dents it and forfeits the stake")
    func lossAndQuit() {
        let base = CareerProfile(points: 1_000, lifetimePointsEarned: 1_000, currentStreak: 4, bestStreak: 6)

        let lost = PointsLedger.settle(profile: base, tier: .silver, outcome: .loss, soloVsBots: false)
        #expect(lost.points == 800)
        #expect(lost.currentStreak == 0)
        #expect(lost.bestStreak == 6)

        let quit = PointsLedger.settle(profile: base, tier: .silver, outcome: .quit, soloVsBots: false)
        #expect(quit.points == 800, "Quitting forfeits the stake")
        #expect(quit.currentStreak == 3, "A quit is a dent, not a reset")
    }

    @Test("Losing does not inflate lifetime earnings")
    func lifetimeOnlyCountsGains() {
        var profile = CareerProfile(points: 300, lifetimePointsEarned: 300)
        profile = PointsLedger.settle(profile: profile, tier: .bronze, outcome: .loss, soloVsBots: false)
        #expect(profile.lifetimePointsEarned == 300)
        #expect(profile.points == 250)
    }

    @Test("The reconnect grace window is ninety seconds")
    func gracePeriod() {
        // A disconnect inside this window is not a quit and costs no stake.
        #expect(ReconnectPolicy.graceWindowSeconds == 90)
    }
}
