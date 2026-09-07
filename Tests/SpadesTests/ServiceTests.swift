import Foundation
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

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        return calendar
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
        let calendar = fixedCalendar()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let career = CareerStore(store: MemoryPersistence())
        let service = DailyBonusService(career: career, calendar: calendar, now: { clock })

        #expect(service.claimIfDue().granted)
        #expect(career.profile.points == 50)
        #expect(!service.claimIfDue().granted, "A second foreground the same day pays nothing")
        #expect(career.profile.points == 50)

        clock = clock.addingTimeInterval(60 * 60 * 26)
        let second = service.claimIfDue()
        #expect(second.granted)
        #expect(second.streakDay == 2)
    }

    @Test("A rolled-back clock breaks the streak instead of paying out")
    func clockRollback() {
        let calendar = fixedCalendar()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let career = CareerStore(store: MemoryPersistence())
        let service = DailyBonusService(career: career, calendar: calendar, now: { clock })

        service.claimIfDue()
        let banked = career.profile.points

        clock = clock.addingTimeInterval(-60 * 60 * 24 * 7)
        let cheated = service.claimIfDue()
        #expect(!cheated.granted)
        #expect(cheated.clockRolledBack)
        #expect(career.profile.points == banked)
        #expect(career.profile.dailyBonusStreak == 0)
    }

    @Test("Ads pay only through the reward callback, and only five times a day")
    func adCap() {
        let calendar = fixedCalendar()
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let career = CareerStore(store: MemoryPersistence())
        let provider = StubAdService(isReady: true)
        let ads = AdService(provider: provider, career: career, calendar: calendar, now: { clock })

        for _ in 0..<AdReward.dailyCap {
            #expect(ads.canOfferReward)
            ads.watchForReward()
        }
        #expect(career.profile.points == 500)
        #expect(!ads.canOfferReward)

        ads.watchForReward()
        #expect(career.profile.points == 500, "The cap holds")
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
