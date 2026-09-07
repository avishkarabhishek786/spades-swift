import Foundation
import UIKit

/// Haptic feedback. For a card game these land harder than the audio does.
@MainActor
protocol HapticsProviding: AnyObject {
    func prepare()
    func cardPlayed()
    func trickCollected()
    func bidConfirmed()
    func contractMade()
    func penalty()
}

@MainActor
final class HapticsService: HapticsProviding {
    private let settings: SettingsStore

    // Generators are kept alive and pre-warmed. An unprepared generator has
    // roughly a hundred milliseconds of latency, which on a card tap reads as
    // a dropped input rather than as feedback.
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    /// Simulators and the iPod touch have no Taptic Engine; asking them to
    /// buzz does nothing but cost time.
    private let deviceSupportsHaptics: Bool

    init(settings: SettingsStore) {
        self.settings = settings
        deviceSupportsHaptics = UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isEnabled: Bool { settings.values.hapticsEnabled && deviceSupportsHaptics }

    func prepare() {
        guard isEnabled else { return }
        light.prepare()
        rigid.prepare()
        selection.prepare()
        notification.prepare()
    }

    func cardPlayed() {
        guard isEnabled else { return }
        light.impactOccurred()
        light.prepare()
    }

    func trickCollected() {
        guard isEnabled else { return }
        rigid.impactOccurred()
        rigid.prepare()
    }

    func bidConfirmed() {
        guard isEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    func contractMade() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    func penalty() {
        guard isEnabled else { return }
        notification.notificationOccurred(.warning)
        notification.prepare()
    }
}

/// No-op implementation for tests and previews.
@MainActor
final class SilentHapticsService: HapticsProviding {
    func prepare() {}
    func cardPlayed() {}
    func trickCollected() {}
    func bidConfirmed() {}
    func contractMade() {}
    func penalty() {}
}
