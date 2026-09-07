import SwiftUI
import SpadesEngine

/// A card face, drawn entirely in code.
///
/// There are no card images in this repo and none should be added (§11). Doing
/// it this way buys infinite resolution, free dark mode, a free four-colour
/// deck for colourblind players, and a bundle that costs nothing. If this view
/// looks wrong, the fix is a better `CardView`, not a PNG.
struct CardView: View {
    let card: Card
    var isPlayable: Bool = true
    var isDimmed: Bool = false

    @Environment(\.deckPalette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let unit = min(size.width, size.height / 1.4)
            let radius = size.width * Theme.cardCornerRadius

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardFace)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.cardEdge, lineWidth: Theme.cardBorderWidth)
                    )

                corner(unit: unit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(unit * 0.07)

                corner(unit: unit)
                    .rotationEffect(.degrees(180))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(unit * 0.07)

                centre(size: size, unit: unit)
            }
            .opacity(isDimmed ? 0.45 : 1)
            .saturation(isPlayable ? 1 : 0.25)
        }
        .aspectRatio(Theme.cardAspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(card.accessibilityName))
        .accessibilityIdentifier("card.\(card.suit.rawValue).\(card.rank.rawValue)")
        .accessibilityAddTraits(isPlayable ? .isButton : [])
    }

    private var ink: Color { palette.color(for: card.suit) }

    private func corner(unit: CGFloat) -> some View {
        VStack(spacing: -unit * 0.04) {
            Text(card.rank.label)
                .font(.system(size: unit * 0.30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
            Text(card.suit.glyph)
                .font(.system(size: unit * 0.24))
        }
        .foregroundStyle(ink)
        .lineLimit(1)
    }

    @ViewBuilder
    private func centre(size: CGSize, unit: CGFloat) -> some View {
        if card.rank.isFace {
            // Face cards are stylised monograms. Illustrations would mean assets.
            Text(card.rank.label)
                .font(.system(size: unit * 0.72, weight: .heavy, design: .serif))
                .foregroundStyle(ink)
                .overlay(alignment: .bottomTrailing) {
                    Text(card.suit.glyph)
                        .font(.system(size: unit * 0.30))
                        .foregroundStyle(ink)
                        .offset(x: unit * 0.20, y: unit * 0.10)
                }
        } else {
            PipLayout(rank: card.rank, suit: card.suit, colour: ink)
                .frame(width: size.width * 0.56, height: size.height * 0.70)
        }
    }
}

/// Pips arranged the way a real deck arranges them, from a positions table.
private struct PipLayout: View {
    let rank: Rank
    let suit: Suit
    let colour: Color

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let pip = min(size.width / 2.6, size.height / 5.2)
            ForEach(Array(Self.positions(for: rank).enumerated()), id: \.offset) { _, spot in
                Text(suit.glyph)
                    .font(.system(size: pip * 1.5))
                    .foregroundStyle(colour)
                    // The bottom half of a real card is printed upside down.
                    .rotationEffect(.degrees(spot.y > 0.5 ? 180 : 0))
                    .position(x: spot.x * size.width, y: spot.y * size.height)
            }
        }
    }

    /// Unit-square pip positions. Ten is the awkward one: its two extra pips sit
    /// between the columns rather than on them.
    private static func positions(for rank: Rank) -> [CGPoint] {
        let left: CGFloat = 0.22
        let right: CGFloat = 0.78
        let mid: CGFloat = 0.5
        let top: CGFloat = 0.08
        let bottom: CGFloat = 0.92

        func column(_ x: CGFloat, _ ys: [CGFloat]) -> [CGPoint] { ys.map { CGPoint(x: x, y: $0) } }

        switch rank {
        case .two: return column(mid, [top, bottom])
        case .three: return column(mid, [top, mid, bottom])
        case .four: return column(left, [top, bottom]) + column(right, [top, bottom])
        case .five: return column(left, [top, bottom]) + column(right, [top, bottom]) + [CGPoint(x: mid, y: mid)]
        case .six: return column(left, [top, mid, bottom]) + column(right, [top, mid, bottom])
        case .seven:
            return column(left, [top, mid, bottom]) + column(right, [top, mid, bottom])
                + [CGPoint(x: mid, y: 0.29)]
        case .eight:
            return column(left, [top, mid, bottom]) + column(right, [top, mid, bottom])
                + [CGPoint(x: mid, y: 0.29), CGPoint(x: mid, y: 0.71)]
        case .nine:
            return column(left, [top, 0.36, 0.64, bottom]) + column(right, [top, 0.36, 0.64, bottom])
                + [CGPoint(x: mid, y: mid)]
        case .ten:
            return column(left, [top, 0.36, 0.64, bottom]) + column(right, [top, 0.36, 0.64, bottom])
                + [CGPoint(x: mid, y: 0.22), CGPoint(x: mid, y: 0.78)]
        default:
            return []
        }
    }
}

#Preview("Faces") {
    let cards = [Card(.ace, of: .spades), Card(.ten, of: .hearts),
                 Card(.queen, of: .diamonds), Card(.seven, of: .clubs)]
    return HStack {
        ForEach(cards) { CardView(card: $0).frame(width: 76) }
    }
    .padding()
    .background(Theme.feltFallback)
    .environment(\.deckPalette, .fourColour)
}
