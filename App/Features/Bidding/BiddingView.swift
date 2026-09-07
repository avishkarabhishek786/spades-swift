import SpadesEngine
import SwiftUI

/// The bidding control. Offers exactly what `LegalMoves` says is legal — a
/// team minimum or an ineligible blind nil simply is not on screen.
struct BiddingBar: View {
    @Bindable var session: GameSession
    @State private var confirmingBlindNil = false

    var body: some View {
        let legal = session.legalBids
        let numeric = legal.compactMap { bid -> Int? in
            if case .tricks(let count) = bid { return count } else { return nil }
        }

        VStack(spacing: 8) {
            Text("bid.prompt")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(numeric, id: \.self) { count in
                        Button("\(count)") {
                            session.place(bid: .tricks(count))
                        }
                        .buttonStyle(BidChipStyle())
                        .accessibilityIdentifier("bid.\(count)")
                    }
                }
                .padding(.horizontal, 14)
            }

            HStack(spacing: 10) {
                if legal.contains(.nilBid) {
                    Button("bid.nil") { session.place(bid: .nilBid) }
                        .buttonStyle(BidChipStyle(tint: .indigo))
                        .accessibilityIdentifier("bid.nil")
                }
                if legal.contains(.blindNil) {
                    // Blind nil is declared before the hand is looked at. The
                    // engine cannot enforce that — it has no notion of who has
                    // seen their cards — so the confirmation is the enforcement.
                    Button("bid.blindNil") { confirmingBlindNil = true }
                        .buttonStyle(BidChipStyle(tint: .purple))
                        .accessibilityIdentifier("bid.blindNil")
                }
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.3))
        .accessibilityIdentifier("biddingBar")
        .alert("bid.blindNil.title", isPresented: $confirmingBlindNil) {
            Button("bid.blindNil.confirm", role: .destructive) { session.place(bid: .blindNil) }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("bid.blindNil.message")
        }
    }
}

private struct BidChipStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(minWidth: 42, minHeight: 42)
            .padding(.horizontal, 8)
            .background(tint.opacity(configuration.isPressed ? 0.6 : 0.9),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// Shown between hands: what each seat bid, what they took, and the damage.
struct HandSummaryOverlay: View {
    @Bindable var session: GameSession

    var body: some View {
        let summary = session.state.history.last

        VStack(spacing: 14) {
            Text("hand.complete")
                .font(.title2.weight(.bold))

            if let summary {
                HStack(alignment: .top, spacing: 24) {
                    teamColumn(summary, team: session.localSeat.team, titleKey: "score.us")
                    teamColumn(summary, team: session.localSeat.team.opponent, titleKey: "score.them")
                }
            }

            Button("hand.continue") { session.continueToNextHand() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("continueButton")
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("handSummary")
    }

    private func teamColumn(_ summary: HandSummary, team: Team, titleKey: LocalizedStringKey) -> some View {
        let result = summary.results[team]
        return VStack(alignment: .leading, spacing: 3) {
            Text(titleKey).font(.subheadline.weight(.semibold))
            Text("hand.contract \(result.contract) \(result.countedTricks)")
                .font(.caption)
            if result.nilPoints != 0 {
                Text("hand.nil \(result.nilPoints)").font(.caption)
            }
            if result.bagPenaltiesApplied > 0 {
                Text("hand.bagPenalty").font(.caption).foregroundStyle(.orange)
            }
            Text("\(result.points > 0 ? "+" : "")\(result.points)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(result.points >= 0 ? .green : .red)
            Text("hand.bagsNow \(result.bagsAfter)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// End of the match.
struct MatchResultOverlay: View {
    @Bindable var session: GameSession
    var onDone: () -> Void

    var body: some View {
        let won = session.state.winner == session.localSeat.team

        VStack(spacing: 14) {
            Image(systemName: won ? "crown.fill" : "hand.thumbsdown.fill")
                .font(.system(size: 40))
                .foregroundStyle(won ? .yellow : .secondary)
            Text(won ? "match.won" : "match.lost")
                .font(.title.weight(.bold))
            Text("match.finalScore \(session.state.scores[session.localSeat.team]) \(session.state.scores[session.localSeat.team.opponent])")
                .font(.subheadline.monospacedDigit())
            Button("match.done", action: onDone)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("matchDoneButton")
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("matchResult")
    }
}
