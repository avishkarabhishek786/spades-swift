import Foundation
import SpadesEconomy
import SpadesEngine
import Testing
@testable import Spades

@MainActor
@Suite("Settings")
struct SettingsStoreTests {

    @Test("Changes persist and reload")
    func persistence() {
        let store = MemoryPersistence()
        let settings = SettingsStore(store: store)
        settings.update { $0.hapticsEnabled = false; $0.deckPalette = .fourColour }

        let reloaded = SettingsStore(store: store)
        #expect(reloaded.values.hapticsEnabled == false)
        #expect(reloaded.values.deckPalette == .fourColour)
    }

    @Test("Muting is per player and stays local")
    func muting() {
        let settings = SettingsStore(store: MemoryPersistence())
        #expect(!settings.isMuted("noisy"))
        settings.toggleMute("noisy")
        #expect(settings.isMuted("noisy"))
        #expect(!settings.showsSocial(from: "noisy"))
        #expect(settings.showsSocial(from: "quiet"))
        settings.toggleMute("noisy")
        #expect(settings.showsSocial(from: "noisy"))
    }

    @Test("The global switch hides everything, muted or not")
    func hideAllReactions() {
        let settings = SettingsStore(store: MemoryPersistence())
        settings.update { $0.hideAllReactions = true }
        #expect(!settings.showsSocial(from: "anyone"))
        #expect(!settings.showsSocial(from: nil))
    }

    @Test("House rules survive the round trip")
    func houseRules() {
        let store = MemoryPersistence()
        let settings = SettingsStore(store: store)
        settings.update {
            $0.houseRules.targetScore = 250
            $0.houseRules.mustLeadTwoOfClubs = true
            $0.houseRules.minBidPerTeam = 4
        }
        let reloaded = SettingsStore(store: store)
        #expect(reloaded.values.houseRules.targetScore == 250)
        #expect(reloaded.values.houseRules.mustLeadTwoOfClubs)
        #expect(reloaded.values.houseRules.minBidPerTeam == 4)
    }
}

@MainActor
@Suite("Career, bonuses and ads")
struct CareerServiceTests {

    /// A clock the test drives directly. `CalendarClock` is the only place in
    /// the app that reads the real calendar, so pinning it here is what makes
    /// these deterministic in any CI region.
    private final class TestClock: @unchecked Sendable {
        var wall: Date
        var monotonic: UInt64
        init(wall: Date, monotonic: UInt64) {
            self.wall = wall
            self.monotonic = monotonic
        }
    }

    private func makeClock(
        timeZone: String = "Asia/Kolkata",
        start: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> (CalendarClock, TestClock) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .gmt
        let state = TestClock(wall: start, monotonic: 1_000_000)
        let clock = CalendarClock(
            calendar: calendar,
            wallClock: { state.wall },
            monotonic: { state.monotonic }
        )
        return (clock, state)
    }

    @Test("A settled match persists")
    func settlePersists() {
        let store = MemoryPersistence()
        let career = CareerStore(store: store)
        career.apply(CareerProfile(points: 500, lifetimePointsEarned: 500))
        career.settle(tier: .bronze, outcome: .win, soloVsBots: false)
        #expect(career.profile.points == 600)
        #expect(CareerStore(store: store).profile.points == 600)
    }

    @Test("A solo win pays forty percent")
    func soloPayout() {
        let career = CareerStore(store: MemoryPersistence())
        career.settle(tier: .casual, outcome: .win, soloVsBots: true)
        #expect(career.profile.points == 10)
    }

    @Test("The daily bonus is granted once per local day")
    func dailyBonusOncePerDay() {
        let (clock, state) = makeClock()
        let career = CareerStore(store: MemoryPersistence())
        let service = DailyBonusService(career: career, clock: clock)

        #expect(service.claimIfDue().granted)
        #expect(career.profile.points == 50)
        #expect(!service.claimIfDue().granted, "A second foreground the same day pays nothing")
        #expect(career.profile.points == 50)

        state.wall = state.wall.addingTimeInterval(60 * 60 * 26)
        state.monotonic += 60 * 60 * 26
        let second = service.claimIfDue()
        #expect(second.granted)
        #expect(second.streakDay == 2)
    }

    /// The case from §15, and the reason the day-key is derived here rather than
    /// in the economy module: a player in IST at 23:00 and again at 08:00 is
    /// nine hours later but two calendar days.
    @Test("A local calendar day, not a rolling twenty-four hours")
    func localCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let lateNight = formatter.date(from: "2026-09-07 23:00") ?? .distantPast
        let nextMorning = formatter.date(from: "2026-09-08 08:00") ?? .distantPast

        let state = TestClock(wall: lateNight, monotonic: 1_000_000)
        let clock = CalendarClock(
            calendar: calendar,
            wallClock: { state.wall },
            monotonic: { state.monotonic }
        )
        let career = CareerStore(store: MemoryPersistence())
        let service = DailyBonusService(career: career, clock: clock)

        #expect(service.claimIfDue().granted)
        #expect(career.profile.points == 50)
        #expect(career.profile.lastDailyBonusDayKey == "2026-09-07")

        state.wall = nextMorning
        state.monotonic += 9 * 60 * 60
        let second = service.claimIfDue()
        #expect(second.granted, "Nine hours later but a new local day")
        #expect(second.streakDay == 2)
        #expect(career.profile.points == 125)
    }

    @Test("Day keys are timezone-aware and zero-padded")
    func dayKeyDerivation() {
        var ist = Calendar(identifier: .gregorian)
        ist.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt

        let formatter = DateFormatter()
        formatter.calendar = ist
        formatter.timeZone = ist.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let instant = formatter.date(from: "2026-01-05 01:30") ?? .distantPast

        #expect(CalendarClock.dayKey(for: instant, calendar: ist) == "2026-01-05")
        #expect(CalendarClock.dayKey(for: instant, calendar: utc) == "2026-01-04")
    }

    @Test("The previous day-key crosses month and year boundaries")
    func previousDayKey() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        // This arithmetic is exactly what the economy module must not do.
        for (today, yesterday) in [("2026-03-01", "2026-02-28"), ("2024-03-01", "2024-02-29"),
                                   ("2026-01-01", "2025-12-31")] {
            let date = formatter.date(from: today) ?? .distantPast
            let clock = CalendarClock(calendar: calendar, wallClock: { date }, monotonic: { 0 })
            #expect(clock.dayKey == today)
            #expect(clock.previousDayKey == yesterday)
        }
    }

    @Test("A rolled-back clock breaks the streak instead of paying out")
    func clockRollback() {
        let (clock, state) = makeClock()
        let career = CareerStore(store: MemoryPersistence())
        let service = DailyBonusService(career: career, clock: clock)

        service.claimIfDue()
        let banked = career.profile.points
        let marker = career.profile.lastDailyBonusDayKey

        state.wall = state.wall.addingTimeInterval(-60 * 60 * 24 * 7)
        state.monotonic += 30
        let cheated = service.claimIfDue()
        #expect(!cheated.granted)
        #expect(cheated.clockRolledBack)
        #expect(career.profile.points == banked)
        #expect(career.profile.dailyBonusStreak == 0)
        #expect(career.profile.lastDailyBonusDayKey == marker, "The claim marker never moves backwards")
    }

    @Test("Ads pay only through the reward callback, and only five times a day")
    func adCap() {
        let (clock, _) = makeClock()
        let career = CareerStore(store: MemoryPersistence())
        let provider = StubAdService(isReady: true)
        let ads = AdService(provider: provider, career: career, clock: clock)

        for _ in 0..<AdReward.dailyCap {
            #expect(ads.canOfferReward)
            ads.watchForReward()
        }
        #expect(career.profile.points == 500)
        #expect(!ads.canOfferReward)

        ads.watchForReward()
        #expect(career.profile.points == 500, "The cap holds")
    }

    @Test("The ad cap rolls over the next local day")
    func adCapRollsOver() {
        let (clock, state) = makeClock()
        let career = CareerStore(store: MemoryPersistence())
        let ads = AdService(provider: StubAdService(isReady: true), career: career, clock: clock)

        for _ in 0..<AdReward.dailyCap { ads.watchForReward() }
        #expect(!ads.canOfferReward)

        state.wall = state.wall.addingTimeInterval(60 * 60 * 24)
        #expect(ads.remainingToday == AdReward.dailyCap)
        #expect(ads.canOfferReward)
    }

    @Test("With nothing loaded the reward button is simply not offered")
    func noAdNoButton() {
        let career = CareerStore(store: MemoryPersistence())
        let ads = AdService(provider: StubAdService(isReady: false), career: career)
        // No network means no ready ad, which means no button — and no error
        // dialog for something the player never asked for.
        #expect(!ads.canOfferReward)
        ads.watchForReward()
        #expect(career.profile.points == 0)
    }
}
