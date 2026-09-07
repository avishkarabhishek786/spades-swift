import SwiftUI
import SpadesEngine

/// Colours, metrics and motion. Everything here is computed, not loaded — the
/// app ships no card art, no gradients as images and no animation assets (§11).
enum Theme {

    // MARK: - Metrics

    /// Standard playing-card proportions, 2.5 by 3.5 inches.
    static let cardAspectRatio: CGFloat = 2.5 / 3.5
    static let cardCornerRadius: CGFloat = 0.075
    static let cardBorderWidth: CGFloat = 1

    // MARK: - Colours

    static let felt = Color("Felt", bundle: .main)
    static let feltFallback = Color(red: 0.08, green: 0.32, blue: 0.24)
    static let cardFace = Color(white: 0.98)
    static let cardInk = Color(white: 0.12)
    static let cardEdge = Color(white: 0.72)

    // MARK: - Motion

    /// The house spring. Every card movement uses this unless it has a reason not to.
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.75)
    /// Substituted for every spring when Reduce Motion is on.
    static let reducedMotion = Animation.easeInOut(duration: 0.2)

    static let dealStagger: Double = 0.04
    /// A full deal must land inside this budget and stay tap-to-skip.
    static let maxDealDuration: Double = 1.5
    /// How long a completed trick sits on the table before it is collected.
    static let trickShowcaseDuration: Double = 0.85
    /// How long a reaction lingers near its target.
    static let reactionLinger: Double = 1.5
}

/// Which colours the suits are drawn in.
///
/// The four-colour deck is an accessibility feature, not a novelty: red and
/// black are the two colours a red-green colourblind player can least reliably
/// separate from each other at card-pip size.
enum DeckPalette: String, CaseIterable, Codable, Sendable {
    case classic
    case fourColour

    var displayNameKey: LocalizedStringKey {
        switch self {
        case .classic: "deck.classic"
        case .fourColour: "deck.fourColour"
        }
    }

    func color(for suit: Suit) -> Color {
        switch (self, suit) {
        case (.classic, .spades), (.classic, .clubs):
            Color(white: 0.12)
        case (.classic, .hearts), (.classic, .diamonds):
            Color(red: 0.78, green: 0.12, blue: 0.16)
        case (.fourColour, .spades):
            Color(white: 0.12)
        case (.fourColour, .hearts):
            Color(red: 0.78, green: 0.12, blue: 0.16)
        case (.fourColour, .diamonds):
            Color(red: 0.10, green: 0.35, blue: 0.80)
        case (.fourColour, .clubs):
            Color(red: 0.05, green: 0.45, blue: 0.25)
        }
    }
}

// MARK: - Environment

private struct DeckPaletteKey: EnvironmentKey {
    static let defaultValue: DeckPalette = .classic
}

private struct ReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var deckPalette: DeckPalette {
        get { self[DeckPaletteKey.self] }
        set { self[DeckPaletteKey.self] = newValue }
    }

    /// Set by the settings screen's preview and by UI tests. The real signal is
    /// `accessibilityReduceMotion`; this only forces it on.
    var forcesReducedMotion: Bool {
        get { self[ReduceMotionOverrideKey.self] }
        set { self[ReduceMotionOverrideKey.self] = newValue }
    }
}

extension View {
    /// Applies the house spring, or a cross-fade when the player has asked for
    /// less motion. Cards flying around the screen make some players ill, so
    /// this is a requirement rather than a nicety (§11).
    func tableAnimation<V: Equatable>(_ value: V) -> some View {
        modifier(TableAnimation(value: value))
    }
}

private struct TableAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.forcesReducedMotion) private var forced
    let value: V

    func body(content: Content) -> some View {
        let reduced = systemReduceMotion || forced
        return content.animation(reduced ? Theme.reducedMotion : Theme.spring, value: value)
    }
}
