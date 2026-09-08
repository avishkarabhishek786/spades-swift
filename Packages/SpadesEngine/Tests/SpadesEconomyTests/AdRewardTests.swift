import Foundation
import Testing
@testable import SpadesEconomy

@Suite("Rewarded ads")
struct AdRewardTests {

    @Test("Each completed view pays a hundred points")
    func grantPays() {
        let profile = AdReward.grant(profile: .new, dayKey: "2026-09-08")
        #expect(profile.points == 100)
        #expect(profile.adBonusesClaimedToday == 1)
        #expect(profile.adBonusDayKey == "2026-09-08")
    }

    @Test("The cap holds at five a day")
    func dailyCap() {
        let today = "2026-09-08"
        var profile = CareerProfile.new

        for expected in 1...AdReward.dailyCap {
            #expect(AdReward.canWatch(profile: profile, dayKey: today))
            profile = AdReward.grant(profile: profile, dayKey: today)
            #expect(profile.adBonusesClaimedToday == expected)
        }

        #expect(profile.points == 500)
        #expect(!AdReward.canWatch(profile: profile, dayKey: today))
        #expect(AdReward.remainingToday(profile: profile, dayKey: today) == 0)

        let sixth = AdReward.grant(profile: profile, dayKey: today)
        #expect(sixth.points == 500, "The sixth view of the day pays nothing")
        #expect(sixth.adBonusesClaimedToday == AdReward.dailyCap)
    }

    @Test("The cap rolls over on the local calendar day")
    func capRollsOver() {
        var profile = CareerProfile.new
        for _ in 0..<AdReward.dailyCap {
            profile = AdReward.grant(profile: profile, dayKey: "2026-09-08")
        }
        #expect(!AdReward.canWatch(profile: profile, dayKey: "2026-09-08"))

        #expect(AdReward.canWatch(profile: profile, dayKey: "2026-09-09"))
        #expect(AdReward.remainingToday(profile: profile, dayKey: "2026-09-09") == AdReward.dailyCap)

        profile = AdReward.grant(profile: profile, dayKey: "2026-09-09")
        #expect(profile.adBonusesClaimedToday == 1)
        #expect(profile.points == 600)
    }

    @Test("Ad points count toward lifetime earnings and unlock progress")
    func adPointsCountTowardUnlocks() {
        var profile = CareerProfile.new
        var day = 8
        while profile.lifetimePointsEarned < 100 {
            profile = AdReward.grant(profile: profile, dayKey: String(format: "2026-09-%02d", day))
            day += 1
        }
        #expect(PointsLedger.isUnlocked(.bronze, profile: profile))
    }
}

@Suite("Career profile persistence shape")
struct CareerProfileTests {

    @Test("A profile survives a JSON round trip")
    func roundTrip() throws {
        let profile = CareerProfile(
            points: 1_234,
            lifetimePointsEarned: 9_876,
            gamesPlayed: 40,
            gamesWon: 22,
            nilsMade: 7,
            nilsFailed: 3,
            currentStreak: 4,
            bestStreak: 9,
            lastDailyBonusClaim: Date(timeIntervalSince1970: 1_800_000_000),
            lastDailyBonusDayKey: "2026-09-08",
            lastDailyBonusMonotonic: 123_456,
            dailyBonusStreak: 5,
            adBonusesClaimedToday: 2,
            adBonusDayKey: "2026-09-08"
        )
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(CareerProfile.self, from: data) == profile)
    }

    @Test("A profile written by an older build still loads")
    func tolerantDecoding() throws {
        // Only the fields that existed before the day-key markers were added.
        let partial = Data(#"{"points":300,"lifetimePointsEarned":800,"gamesPlayed":5}"#.utf8)
        let profile = try JSONDecoder().decode(CareerProfile.self, from: partial)
        #expect(profile.points == 300)
        #expect(profile.lifetimePointsEarned == 800)
        #expect(profile.gamesPlayed == 5)
        #expect(profile.dailyBonusStreak == 0)
        #expect(profile.lastDailyBonusDayKey == nil)
        #expect(profile.adBonusDayKey.isEmpty)
    }

    @Test("A stored negative balance is clamped on the way in")
    func decodingClampsNegativePoints() throws {
        let corrupt = Data(#"{"points":-50}"#.utf8)
        #expect(try JSONDecoder().decode(CareerProfile.self, from: corrupt).points == 0)
    }

    @Test("A profile cannot be constructed with negative points")
    func negativePointsRejected() {
        #expect(CareerProfile(points: -500).points == 0)
    }

    @Test("Nil counters accumulate")
    func nilCounters() {
        let profile = PointsLedger.recordNils(profile: .new, made: 2, failed: 1)
        #expect(profile.nilsMade == 2)
        #expect(profile.nilsFailed == 1)
    }
}
