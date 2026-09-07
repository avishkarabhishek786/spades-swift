import SwiftUI

/// Where each card in a fanned hand sits.
///
/// Pure geometry, no view code, so the numbers can be reasoned about and tested
/// without a simulator.
struct HandFanLayout {
    /// Total sweep of the fan, in degrees, for a full thirteen-card hand.
    var maximumSpread: Double = 34
    /// How far the middle of the fan rises above its ends, as a fraction of card width.
    var arcHeight: Double = 0.28
    /// Fraction of a card's width that stays visible when cards overlap.
    var minimumVisibleFraction: Double = 0.34

    struct Placement: Equatable {
        var rotation: Angle
        var offset: CGSize
        /// Later cards draw on top so the fan reads left to right.
        var zIndex: Double
    }

    /// The width one card should be drawn at so `count` of them fit `available`.
    func cardWidth(count: Int, available: CGFloat, maximum: CGFloat) -> CGFloat {
        guard count > 1 else { return min(maximum, available) }
        // n cards at width w overlapping by (1 - f) occupy w * (1 + (n-1) * f).
        let span = 1 + Double(count - 1) * minimumVisibleFraction
        return min(maximum, max(24, available / span))
    }

    /// Placement for one card, relative to the centre of the fan.
    func placement(index: Int, count: Int, cardWidth: CGFloat) -> Placement {
        guard count > 1 else {
            return Placement(rotation: .zero, offset: .zero, zIndex: 0)
        }

        // -0.5 at the far left, +0.5 at the far right.
        let position = Double(index) / Double(count - 1) - 0.5
        let spread = min(maximumSpread, maximumSpread * Double(count) / 13.0)

        let step = cardWidth * CGFloat(minimumVisibleFraction)
        let horizontal = CGFloat(position) * step * CGFloat(count - 1)

        // A shallow parabola: ends drop, middle rises.
        let rise = arcHeight * (position * position * 4 - 1) * 0.5
        let vertical = CGFloat(rise) * cardWidth

        return Placement(
            rotation: .degrees(position * spread),
            offset: CGSize(width: horizontal, height: vertical),
            zIndex: Double(index)
        )
    }
}
