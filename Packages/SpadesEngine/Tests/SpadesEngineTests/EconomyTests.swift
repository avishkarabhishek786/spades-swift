import Foundation
import Testing
@testable import SpadesEngine

/// A fixed calendar so these tests do not change behaviour with the machine's
/// timezone. The daily bonus rule itself is explicitly about the *user's* local
/// calendar, which is why the calendar is a parameter everywhere.
private func calendar(timeZoneIdentifier: String = "Asia/Kolkata") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    return calendar
}

private func date(_ iso: String, in calendar: Calendar) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: iso) ?? .distantPast
}

@Suite("Stakes and points")
struct StakeTests {

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
            #expect(Economy.entry(for: tier, soloVsBots: true) == tier.entry * 2 / 5)
            #expect(Economy.payout(for: tier, soloVsBots: true) == tier.winPayout * 2 / 5)
            #expect(Economy.entry(for: tier, soloVsBots: false) == tier.entry)
        }
        #expect(Economy.payout(for: .gold, soloVsBots: true) == 640)
        #expect(Economy.entry(for: .gold, soloVsBots: true) == 300)
    }

    @Test("Points never go below zero")
    func pointsClampAtZero() {
        let broke = CareerProfile(points: 20, lifetimePointsEarned: 400)
        let after = Economy.settle(profile: broke, tier: .silver, outcome: .loss, soloVsBots: false)
        #expect(after.points == 0, "A loss larger than the balance clamps rather than going negative")
        #expect(after.gamesPlayed == 1)

        let stillZero = Economy.settle(profile: after, tier: .silver, outcome: .loss, soloVsBots: false)
        #expect(stillZero.points == 0)
    }

    @Test("A player at zero can always sit at a Casual table")
    func casualAlwaysReachable() {
        let broke = CareerProfile(points: 0, lifetimePointsEarned: 0)
        #expect(Economy.isSelectable(.casual, profile: broke, soloVsBots: false))
        #expect(Economy.selectableTiers(profile: broke, soloVsBots: false) == [.casual])

        // Even a veteran who has lost everything keeps the way back in.
        let veteran = CareerProfile(points: 0, lifetimePointsEarned: 50_000)
        #expect(Economy.isSelectable(.casual, profile: veteran, soloVsBots: false))
        #expect(!Economy.isSelectable(.elite, profile: veteran, soloVsBots: false))
    }

    @Test("A tier needs both its unlock threshold and the entry on hand")
    func tierGating() {
        // Enough points, never earned enough lifetime: still locked.
        let newRich = CareerProfile(points: 900, lifetimePointsEarned: 300)
        #expect(!Economy.isUnlocked(.silver, profile: newRich))
        #expect(!Economy.isSelectable(.silver, profile: newRich, soloVsBots: false))

        // Unlocked but currently short of the entry.
        let unlockedBroke = CareerProfile(points: 100, lifetimePointsEarned: 900)
        #expect(Economy.isUnlocked(.silver, profile: unlockedBroke))
        #expect(!Economy.isSelectable(.silver, profile: unlockedBroke, soloVsBots: false))

        // The solo discount can bring a tier back in reach.
        #expect(Economy.isSelectable(.silver, profile: unlockedBroke, soloVsBots: true))
    }

    @Test("Winning pays the tier payout and extends the streak")
    func winPayout() {
        var profile = CareerProfile(points: 500, lifetimePointsEarned: 500, currentStreak: 2, bestStreak: 2)
        profile = Economy.settle(profile: profile, tier: .bronze, outcome: .win, soloVsBots: false)
        #expect(profile.points == 600)
        #expect(profile.lifetimePointsEarned == 600)
        #expect(profile.gamesWon == 1)
        #expect(profile.currentStreak == 3)
        #expect(profile.bestStreak == 3)
    }

    @Test("A loss resets the streak; quitting only dents it and forfeits the stake")
    func lossAndQuit() {
        let base = CareerProfile(points: 1_000, lifetimePointsEarned: 1_000, currentStreak: 4, bestStreak: 6)

        let lost = Economy.settle(profile: base, tier: .silver, outcome: .loss, soloVsBots: false)
        #expect(lost.points == 800)
        #expect(lost.currentStreak == 0)
        #expect(lost.bestStreak == 6)

        let quit = Economy.settle(profile: base, tier: .silver, outcome: .quit, soloVsBots: false)
        #expect(quit.points == 800, "Quitting forfeits the stake")
        #expect(quit.currentStreak == 3, "A quit is a dent, not a reset")
    }

    @Test("Losing does not inflate lifetime earnings")
    func lifetimeOnlyCountsGains() {
        var profile = CareerProfile(points: 300, lifetimePointsEarned: 300)
        profile = Economy.settle(profile: profile, tier: .bronze, outcome: .loss, soloVsBots: false)
        #expect(profile.lifetimePointsEarned == 300)
        #expect(profile.points == 250)
    }
}

@Suite("Daily bonus")
struct DailyBonusTests {

    @Test("The streak ladder escalates then holds at five hundred")
    func ladder() {
        #expect((1...7).map(DailyBonus.amount(forStreakDay:)) == [50, 75, 100, 150, 200, 300, 500])
        #expect(DailyBonus.amount(forStreakDay: 8) == 500)
        #expect(DailyBonus.amount(forStreakDay: 400) == 500)
        #expect(DailyBonus.amount(forStreakDay: 0) == 0)
    }

    @Test("The first claim of a calendar day is granted; the second is not")
    func onceADay() {
        let cal = calendar()
        var profile = CareerProfile.new
        let morning = date("2026-09-07 09:00", in: cal)

        let first = DailyBonus.claim(profile: profile, now: morning, calendar: cal)
        #expect(first.evaluation.granted)
        #expect(first.evaluation.points == 50)
        profile = first.profile
        #expect(profile.points == 50)

        let evening = date("2026-09-07 21:30", in: cal)
        let second = DailyBonus.claim(profile: profile, now: evening, calendar: cal)
        #expect(!second.evaluation.granted)
        #expect(second.profile.points == 50)
    }

    @Test("A local calendar day, not a rolling twenty-four hours")
    func localCalendarDay() {
        // The case from §15: play at 23:00 IST, again at 08:00. Nine hours
        // apart, two different local days, two bonuses.
        let cal = calendar(timeZoneIdentifier: "Asia/Kolkata")
        var profile = CareerProfile.new

        let lateNight = date("2026-09-07 23:00", in: cal)
        profile = DailyBonus.claim(profile: profile, now: lateNight, calendar: cal).profile
        #expect(profile.points == 50)
        #expect(profile.dailyBonusStreak == 1)

        let nextMorning = date("2026-09-08 08:00", in: cal)
        let second = DailyBonus.claim(profile: profile, now: nextMorning, calendar: cal)
        #expect(second.evaluation.granted, "Nine hours later but a new local day")
        #expect(second.evaluation.streakDay == 2)
        #expect(second.profile.points == 125)
    }

    @Test("A consecutive run walks up the ladder")
    func consecutiveDays() {
        let cal = calendar()
        var profile = CareerProfile.new
        var total = 0
        for day in 1...9 {
            let now = date(String(format: "2026-09-%02d 10:00", day), in: cal)
            let claim = DailyBonus.claim(profile: profile, now: now, calendar: cal)
            #expect(claim.evaluation.granted)
            #expect(claim.evaluation.streakDay == day)
            total += claim.evaluation.points
            profile = claim.profile
        }
        #expect(profile.dailyBonusStreak == 9)
        #expect(total == 50 + 75 + 100 + 150 + 200 + 300 + 500 + 500 + 500)
        #expect(profile.points == total)
    }

    @Test("A missed day resets the streak to day one")
    func missedDayResets() {
        let cal = calendar()
        var profile = CareerProfile.new
        for day in [1, 2, 3] {
            profile = DailyBonus.claim(profile: profile, now: date(String(format: "2026-09-%02d 10:00", day), in: cal), calendar: cal).profile
        }
        #expect(profile.dailyBonusStreak == 3)

        // Skips the 4th.
        let resumed = DailyBonus.claim(profile: profile, now: date("2026-09-05 10:00", in: cal), calendar: cal)
        #expect(resumed.evaluation.granted)
        #expect(resumed.evaluation.streakDay == 1)
        #expect(resumed.evaluation.points == 50)
    }

    @Test("A backwards clock breaks the streak and grants nothing")
    func clockRollback() {
        let cal = calendar()
        var profile = CareerProfile.new
        profile = DailyBonus.claim(profile: profile, now: date("2026-09-07 10:00", in: cal), calendar: cal).profile
        let banked = profile.points
        #expect(profile.dailyBonusStreak == 1)

        // The device clock is wound back a week to farm bonuses.
        let cheated = DailyBonus.claim(profile: profile, now: date("2026-08-31 10:00", in: cal), calendar: cal)
        #expect(!cheated.evaluation.granted)
        #expect(cheated.evaluation.clockRolledBack)
        #expect(cheated.profile.points == banked, "No points for a rolled-back clock")
        #expect(cheated.profile.dailyBonusStreak == 0, "The streak breaks rather than paying out")
        #expect(cheated.profile.lastDailyBonusClaim == profile.lastDailyBonusClaim, "The claim timestamp never moves backwards")
    }

    @Test("Day keys are zero-padded and timezone-aware")
    func dayKeyFormat() {
        let ist = calendar(timeZoneIdentifier: "Asia/Kolkata")
        let instant = date("2026-01-05 01:30", in: ist)
        #expect(DailyBonus.dayKey(for: instant, calendar: ist) == "2026-01-05")

        // The same instant is still the previous day in UTC.
        let utc = calendar(timeZoneIdentifier: "UTC")
        #expect(DailyBonus.dayKey(for: instant, calendar: utc) == "2026-01-04")
    }
}

@Suite("Rewarded ads")
struct AdRewardTests {

    @Test("Each completed view pays a hundred points")
    func grantPays() {
        let cal = calendar()
        let now = date("2026-09-07 12:00", in: cal)
        let profile = AdReward.grant(profile: .new, now: now, calendar: cal)
        #expect(profile.points == 100)
        #expect(profile.adBonusesClaimedToday == 1)
        #expect(profile.adBonusDayKey == "2026-09-07")
    }

    @Test("The cap holds at five a day")
    func dailyCap() {
        let cal = calendar()
        let now = date("2026-09-07 12:00", in: cal)
        var profile = CareerProfile.new

        for expected in 1...AdReward.dailyCap {
            #expect(AdReward.canWatch(profile: profile, now: now, calendar: cal))
            profile = AdReward.grant(profile: profile, now: now, calendar: cal)
            #expect(profile.adBonusesClaimedToday == expected)
        }

        #expect(profile.points == 500)
        #expect(!AdReward.canWatch(profile: profile, now: now, calendar: cal))
        #expect(AdReward.remainingToday(profile: profile, now: now, calendar: cal) == 0)

        let sixth = AdReward.grant(profile: profile, now: now, calendar: cal)
        #expect(sixth.points == 500, "The sixth view of the day pays nothing")
        #expect(sixth.adBonusesClaimedToday == AdReward.dailyCap)
    }

    @Test("The cap rolls over on the local calendar day")
    func capRollsOver() {
        let cal = calendar()
        var profile = CareerProfile.new
        let today = date("2026-09-07 23:50", in: cal)
        for _ in 0..<AdReward.dailyCap {
            profile = AdReward.grant(profile: profile, now: today, calendar: cal)
        }
        #expect(!AdReward.canWatch(profile: profile, now: today, calendar: cal))

        let tomorrow = date("2026-09-08 00:10", in: cal)
        #expect(AdReward.canWatch(profile: profile, now: tomorrow, calendar: cal))
        #expect(AdReward.remainingToday(profile: profile, now: tomorrow, calendar: cal) == AdReward.dailyCap)

        profile = AdReward.grant(profile: profile, now: tomorrow, calendar: cal)
        #expect(profile.adBonusesClaimedToday == 1)
        #expect(profile.points == 600)
    }

    @Test("Ad points count toward lifetime earnings and unlock progress")
    func adPointsCountTowardUnlocks() {
        let cal = calendar()
        var profile = CareerProfile.new
        var day = 7
        while profile.lifetimePointsEarned < 100 {
            let now = date(String(format: "2026-09-%02d 12:00", day), in: cal)
            profile = AdReward.grant(profile: profile, now: now, calendar: cal)
            day += 1
        }
        #expect(Economy.isUnlocked(.bronze, profile: profile))
    }
}

@Suite("Career profile persistence shape")
struct CareerProfileTests {

    @Test("A profile survives a JSON round trip")
    func roundTrip() throws {
        let cal = calendar()
        let profile = CareerProfile(
            points: 1_234,
            lifetimePointsEarned: 9_876,
            gamesPlayed: 40,
            gamesWon: 22,
            nilsMade: 7,
            nilsFailed: 3,
            currentStreak: 4,
            bestStreak: 9,
            lastDailyBonusClaim: date("2026-09-07 10:00", in: cal),
            adBonusesClaimedToday: 2,
            adBonusDayKey: "2026-09-07",
            dailyBonusStreak: 5
        )
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(CareerProfile.self, from: data) == profile)
    }

    @Test("A profile written by an older build still loads")
    func tolerantDecoding() throws {
        // Only the fields that existed before the daily-bonus streak was added.
        let partial = Data(#"{"points":300,"lifetimePointsEarned":800,"gamesPlayed":5}"#.utf8)
        let profile = try JSONDecoder().decode(CareerProfile.self, from: partial)
        #expect(profile.points == 300)
        #expect(profile.lifetimePointsEarned == 800)
        #expect(profile.gamesPlayed == 5)
        #expect(profile.dailyBonusStreak == 0)
        #expect(profile.adBonusDayKey.isEmpty)
        #expect(profile.lastDailyBonusClaim == nil)
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
        let profile = Economy.recordNils(profile: .new, made: 2, failed: 1)
        #expect(profile.nilsMade == 2)
        #expect(profile.nilsFailed == 1)
    }
}
