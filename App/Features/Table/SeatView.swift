import SpadesEngine
import SwiftUI

/// One player's nameplate: who they are, what they bid, what they have taken.
struct SeatView: View {
    let seat: Seat
    let name: String
    let bid: Bid?
    let tricksWon: Int
    let isActive: Bool
    let isLocal: Bool
    let accessibilityText: String
    var onTap: () -> Void
    var onLongPress: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.black.opacity(0.35))
                Text(initials)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .overlay(Circle().strokeBorder(.white.opacity(isActive ? 0.9 : 0.25), lineWidth: 2))

            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(scoreLine)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(6)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(perform: onLongPress)
        .tableAnimation(isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityIdentifier("seat.\(seat.rawValue)")
        .accessibilityHint(Text("seat.hint"))
    }

    private var initials: String {
        String(name.prefix(isLocal ? 2 : 1)).uppercased()
    }

    private var scoreLine: String {
        guard let bid else { return "—" }
        return "\(tricksWon)/\(bid.description)"
    }
}

/// The running match score.
struct ScoreBar: View {
    let state: GameState
    let localTeam: Team

    var body: some View {
        HStack(spacing: 16) {
            teamColumn(localTeam, titleKey: "score.us")
            Divider().frame(height: 26).overlay(.white.opacity(0.3))
            teamColumn(localTeam.opponent, titleKey: "score.them")
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("score.target \(state.rules.targetScore)")
                Text("score.hand \(state.handNumber + 1)")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.28))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scoreBar")
    }

    private func teamColumn(_ team: Team, titleKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(titleKey)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 6) {
                Text("\(state.scores[team])")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                Text("score.bags \(state.bags[team])")
                    .font(.caption2.monospacedDigit())
                    // Bags are a slow-burning trap; make them visible before
                    // the hundred-point penalty is a surprise.
                    .foregroundStyle(bagColour(state.bags[team]))
            }
        }
    }

    private func bagColour(_ bags: Int) -> Color {
        let remaining = state.rules.bagPenaltyThreshold - bags
        if remaining <= 2 { return .orange }
        if remaining <= 4 { return .yellow }
        return .white.opacity(0.7)
    }
}
