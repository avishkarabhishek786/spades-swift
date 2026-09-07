import SpadesEngine
import SwiftUI

/// The back of a card. Drawn, like the front — a repeating diagonal lattice
/// rather than a bitmap pattern.
struct CardBackView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let radius = size.width * Theme.cardCornerRadius
            let inset = size.width * 0.08

            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.22, blue: 0.44),
                                     Color(red: 0.10, green: 0.14, blue: 0.32)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Lattice(spacing: size.width * 0.16)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    .padding(inset)
                    .clipShape(RoundedRectangle(cornerRadius: radius * 0.7, style: .continuous))

                RoundedRectangle(cornerRadius: radius * 0.7, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    .padding(inset)

                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.cardEdge, lineWidth: Theme.cardBorderWidth)
            }
        }
        .aspectRatio(Theme.cardAspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Diagonal cross-hatch, drawn in both directions.
private struct Lattice: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 0 else { return path }
        let span = rect.width + rect.height
        var offset = -rect.height
        while offset < span {
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
            offset += spacing
        }
        return path
    }
}

/// A card that can turn over. Swaps face for back exactly at the halfway point
/// so the back is never seen mirrored.
struct FlippableCardView: View {
    let card: Card
    var faceUp: Bool
    var isPlayable: Bool = true

    var body: some View {
        ZStack {
            if faceUp {
                CardView(card: card, isPlayable: isPlayable)
            } else {
                CardBackView()
            }
        }
        .rotation3DEffect(.degrees(faceUp ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        .tableAnimation(faceUp)
    }
}

#Preview {
    HStack {
        CardBackView().frame(width: 80)
        FlippableCardView(card: Card(.king, of: .hearts), faceUp: true).frame(width: 80)
    }
    .padding()
    .background(Theme.feltFallback)
}
