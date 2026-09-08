import Foundation
import Observation
import SpadesEconomy

/// Rewarded video, behind a protocol so the app builds, runs and tests with no
/// ad SDK present at all.
@MainActor
protocol AdProviding: AnyObject {
    /// Whether an ad is loaded and ready right now.
    var isReady: Bool { get }
    /// Loads the next rewarded ad. Safe to call repeatedly.
    func preload()
    /// Presents the ad. The closure fires **only** on the SDK's reward
    /// callback, never on dismissal.
    func presentRewarded(onReward: @escaping @MainActor () -> Void)
}

/// Coordinates the reward button: availability, the daily cap, and granting.
@MainActor
@Observable
final class AdService {
    private(set) var isPresenting = false
    private(set) var lastGrant: Int?

    private let provider: any AdProviding
    private let career: CareerStore
    private let clock: CalendarClock

    init(provider: any AdProviding, career: CareerStore, clock: CalendarClock = CalendarClock()) {
        self.provider = provider
        self.career = career
        self.clock = clock
    }

    var remainingToday: Int {
        AdReward.remainingToday(profile: career.profile, dayKey: clock.dayKey)
    }

    var rewardAmount: Int { AdReward.pointsPerView }

    /// Whether to show the button at all.
    ///
    /// With no network the provider never becomes ready, so the button simply
    /// does not appear. Showing an error for something the player did not ask
    /// for is worse than showing nothing.
    var canOfferReward: Bool {
        provider.isReady && remainingToday > 0 && !isPresenting
    }

    func preload() {
        guard remainingToday > 0 else { return }
        provider.preload()
    }

    /// Only ever called from a button the player tapped. There are no
    /// interstitials between hands.
    func watchForReward() {
        guard canOfferReward else { return }
        isPresenting = true
        provider.presentRewarded { [weak self] in
            guard let self else { return }
            // Reached only from the SDK's reward callback. Granting on
            // dismissal would pay out for an ad that was skipped.
            let updated = AdReward.grant(profile: career.profile, dayKey: clock.dayKey)
            let delta = updated.points - career.profile.points
            career.apply(updated)
            lastGrant = delta > 0 ? delta : nil
            isPresenting = false
            preload()
        }
    }

    func acknowledgeGrant() { lastGrant = nil }
}

/// The default provider. Never ready, so the reward button stays hidden and the
/// app builds without the AdMob SDK linked.
///
/// Swapping in the real provider means implementing `AdProviding` against
/// `GADRewardedAd`. Two things must survive that swap: the reward fires on the
/// SDK's reward callback only, and App Tracking Transparency is requested
/// contextually rather than on launch.
@MainActor
final class StubAdService: AdProviding {
    /// Set in tests to exercise the reward path.
    var isReady: Bool

    init(isReady: Bool = false) {
        self.isReady = isReady
    }

    func preload() {}

    func presentRewarded(onReward: @escaping @MainActor () -> Void) {
        guard isReady else { return }
        onReward()
    }
}
