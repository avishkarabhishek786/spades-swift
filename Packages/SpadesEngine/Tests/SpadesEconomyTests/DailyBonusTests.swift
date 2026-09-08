import Foundation
import Testing
@testable import SpadesEconomy

/// These are pure string and integer tests. Every calendar decision has already
/// been made by the caller, so there is no timezone in here to make the suite
/// pass in one CI region and fail in another — that case is covered where it
/// belongs, in the app layer's `DailyBonusService` tests.
@Suite("Daily bonus")
struct DailyBonusTests {

    private let day: UInt64 = 86_400

    @Test("The streak ladder escalates then holds at five hundred")
    func ladder() {
        #expect((1...7).map(DailyBonus.amount(forStreakDay:)) == [50, 75, 100, 150, 200, 300, 500])
        #expect(DailyBonus.amount(forStreakDay: 8) == 500)
        #expect(DailyBonus.amount(forStreakDay: 400) == 500)
        #expect(DailyBonus.amount(forStreakDay: 0) == 0)
    }

    @Test("The first claim ever is day one")
    func firstClaim() {
        let result = evaluateDailyBonus(
            dayKey: "2026-09-08",
            previousDayKey: "2026-09-07",
            lastClaimDayKey: nil,
            currentStreak: 0,
            monotonicNow: 1_000,
            lastClaimMonotonic: nil
        )
        #expect(result.granted)
        #expect(result.points == 50)
        #expect(result.streakDay == 1)
    }

    @Test("A second claim on the same day pays nothing")
    func onceADay() {
        let result = evaluateDailyBonus(
            dayKey: "2026-09-08",
            previousDayKey: "2026-09-07",
            lastClaimDayKey: "2026-09-08",
            currentStreak: 3,
            monotonicNow: 50_000,
            lastClaimMonotonic: 1_000
        )
        #expect(!result.granted)
        #expect(result.points == 0)
        #expect(result.streakDay == 3, "The standing streak is untouched")
    }

    @Test("A consecutive day advances the streak")
    func consecutiveDay() {
        let result = evaluateDailyBonus(
            dayKey: "2026-09-08",
            previousDayKey: "2026-09-07",
            lastClaimDayKey: "2026-09-07",
            currentStreak: 2,
            monotonicNow: 100_000,
            lastClaimMonotonic: 10_000
        )
        #expect(result.granted)
        #expect(result.streakDay == 3)
        #expect(result.points == 100)
    }

    @Test("A missed day resets to day one")
    func missedDay() {
        let result = evaluateDailyBonus(
            dayKey: "2026-09-10",
            previousDayKey: "2026-09-09",
            lastClaimDayKey: "2026-09-07",
            currentStreak: 5,
            monotonicNow: 400_000,
            lastClaimMonotonic: 10_000
        )
        #expect(result.granted)
        #expect(result.streakDay == 1)
        #expect(result.points == 50)
    }

    @Test("A full run walks the ladder and then holds")
    func ladderWalk() {
        var profile = CareerProfile.new
        var monotonic: UInt64 = 0
        var total = 0

        for index in 0..<9 {
            let dayKey = String(format: "2026-09-%02d", index + 1)
            let previousDayKey = String(format: "2026-09-%02d", index)
            monotonic += day

            let result = evaluateDailyBonus(
                dayKey: dayKey,
                previousDayKey: previousDayKey,
                lastClaimDayKey: profile.lastDailyBonusDayKey,
                currentStreak: profile.dailyBonusStreak,
                monotonicNow: monotonic,
                lastClaimMonotonic: profile.lastDailyBonusMonotonic
            )
            #expect(result.granted)
            #expect(result.streakDay == index + 1)
            total += result.points
            profile = applyDailyBonus(result, to: profile, dayKey: dayKey, monotonicNow: monotonic, claimedAt: nil)
        }

        #expect(profile.dailyBonusStreak == 9)
        #expect(total == 50 + 75 + 100 + 150 + 200 + 300 + 500 + 500 + 500)
        #expect(profile.points == total)
    }

    @Test("A backwards day-key breaks the streak and grants nothing")
    func clockRollback() {
        var profile = CareerProfile(points: 200, lifetimePointsEarned: 200, dailyBonusStreak: 4)
        profile.lastDailyBonusDayKey = "2026-09-08"
        profile.lastDailyBonusMonotonic = 500_000

        let result = evaluateDailyBonus(
            dayKey: "2026-09-01",
            previousDayKey: "2026-08-31",
            lastClaimDayKey: profile.lastDailyBonusDayKey,
            currentStreak: profile.dailyBonusStreak,
            monotonicNow: 500_010,
            lastClaimMonotonic: profile.lastDailyBonusMonotonic
        )
        #expect(!result.granted)
        #expect(result.clockRolledBack)
        #expect(result.streakDay == 0)

        let after = applyDailyBonus(result, to: profile, dayKey: "2026-09-01", monotonicNow: 500_010, claimedAt: nil)
        #expect(after.points == 200, "No points for a rolled-back clock")
        #expect(after.dailyBonusStreak == 0, "The streak breaks rather than paying out")
        #expect(after.lastDailyBonusDayKey == "2026-09-08", "The claim marker never moves backwards")
        #expect(after.lastDailyBonusMonotonic == 500_000)
    }

    @Test("Winding the date forward without living through it grants nothing")
    func forwardJumpDetected() {
        // The date advances by a day but the monotonic clock has moved ten
        // seconds — the player changed the device date rather than waiting.
        let result = evaluateDailyBonus(
            dayKey: "2026-09-09",
            previousDayKey: "2026-09-08",
            lastClaimDayKey: "2026-09-08",
            currentStreak: 1,
            monotonicNow: 10_010,
            lastClaimMonotonic: 10_000
        )
        #expect(!result.granted)
        #expect(result.clockRolledBack)
        #expect(result.streakDay == 0)
    }

    @Test("A reboot is not treated as tampering")
    func rebootIsNotCheating() {
        // The monotonic reference resets on reboot, so a lower reading than the
        // stored one is ordinary. Punishing it would break the streak of anyone
        // who restarts their phone.
        let result = evaluateDailyBonus(
            dayKey: "2026-09-09",
            previousDayKey: "2026-09-08",
            lastClaimDayKey: "2026-09-08",
            currentStreak: 4,
            monotonicNow: 30,
            lastClaimMonotonic: 900_000
        )
        #expect(result.granted)
        #expect(!result.clockRolledBack)
        #expect(result.streakDay == 5)
    }

    @Test("A real day apart clears the monotonic gate comfortably")
    func genuineDayPasses() {
        let result = evaluateDailyBonus(
            dayKey: "2026-09-09",
            previousDayKey: "2026-09-08",
            lastClaimDayKey: "2026-09-08",
            currentStreak: 1,
            monotonicNow: 10_000 + day,
            lastClaimMonotonic: 10_000
        )
        #expect(result.granted)
        #expect(result.streakDay == 2)
    }
}
