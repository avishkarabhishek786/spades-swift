import SpadesEngine
import SwiftUI

/// The main game screen.
struct TableView: View {
    @Bindable var session: GameSession
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @Namespace private var cardNamespace
    @State private var reactionTarget: Seat?
    @State private var showingQuickChat = false
    @State private var showingQuitConfirmation = false

    var body: some View {
        ZStack {
            Theme.felt.ignoresSafeArea()

            VStack(spacing: 0) {
                ScoreBar(state: session.state, localTeam: session.localSeat.team)
                tableArea
                bottomArea
            }

            socialOverlay

            if session.stage == .handComplete {
                HandSummaryOverlay(session: session)
                    .transition(.opacity)
            }
            if session.stage == .matchComplete {
                MatchResultOverlay(session: session) { dismiss() }
                    .transition(.opacity)
            }
        }
        .environment(\.deckPalette, settings.values.deckPalette)
        .tableAnimation(session.stage)
        .toolbar(.hidden, for: .navigationBar)
        .task { session.start() }
        .onChange(of: scenePhase) { _, phase in
            // A backgrounded match must come back exactly where it was, so the
            // resume point is written here as well as at trick boundaries.
            if phase != .active { session.saveNow() }
        }
        .onTapGesture { session.skipDeal() }
        .overlay(alignment: .topTrailing) { quitButton }
        .confirmationDialog("table.quit.title", isPresented: $showingQuitConfirmation) {
            Button("table.quit.confirm", role: .destructive) {
                session.forfeit()
                dismiss()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("table.quit.message")
        }
        .sheet(isPresented: $showingQuickChat) {
            QuickChatSheet { phrase in
                session.sendPhrase(phrase)
                showingQuickChat = false
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $reactionTarget) { target in
            ReactionPicker(targetName: session.occupantName(for: target)) { kind in
                session.react(to: target, with: kind)
                reactionTarget = nil
            }
            .presentationDetents([.height(200)])
        }
    }

    // MARK: - Table

    private var tableArea: some View {
        GeometryReader { geometry in
            ZStack {
                seatBadge(.top, in: geometry)
                seatBadge(.left, in: geometry)
                seatBadge(.right, in: geometry)
                trickArea(in: geometry)
            }
        }
    }

    private func seatBadge(_ position: GameSession.TablePosition, in geometry: GeometryProxy) -> some View {
        let seat = session.seat(at: position)
        let size = geometry.size
        let point: CGPoint = switch position {
        case .top: CGPoint(x: size.width / 2, y: 34)
        case .left: CGPoint(x: 44, y: size.height / 2)
        case .right: CGPoint(x: size.width - 44, y: size.height / 2)
        case .bottom: CGPoint(x: size.width / 2, y: size.height - 34)
        }

        return SeatView(
            seat: seat,
            name: session.occupantName(for: seat),
            bid: session.state.hand.bids[seat],
            tricksWon: session.state.hand.tricksWon[seat],
            isActive: session.state.seatToAct == seat,
            isLocal: seat == session.localSeat,
            accessibilityText: session.accessibilityLabel(for: seat),
            onTap: { reactionTarget = seat },
            onLongPress: { muteSeat(seat) }
        )
        .position(point)
    }

    /// Cards currently on the table, each drawn toward the seat that played it.
    private func trickArea(in geometry: GeometryProxy) -> some View {
        let trick = session.showcasedTrick ?? session.state.hand.currentTrick
        let centre = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let width = min(geometry.size.width * 0.18, 76)

        let plays = trick?.plays ?? []

        return ZStack {
            ForEach(Array(plays.enumerated()), id: \.element.card.id) { order, play in
                CardView(card: play.card)
                    .frame(width: width)
                    // The stable card id is what lets a card fly from the hand
                    // to the table instead of cross-fading. Get this right first.
                    .matchedGeometryEffect(id: play.card.id, in: cardNamespace, isSource: true)
                    .position(offset(for: play.seat, around: centre, spread: width * 0.62))
                    .scaleEffect(session.showcasedTrick == nil ? 1 : 0.92)
                    .zIndex(Double(order))
            }
        }
        .tableAnimation(plays.count)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trickArea")
    }

    private func offset(for seat: Seat, around centre: CGPoint, spread: CGFloat) -> CGPoint {
        switch session.position(of: seat) {
        case .bottom: CGPoint(x: centre.x, y: centre.y + spread)
        case .left: CGPoint(x: centre.x - spread, y: centre.y)
        case .top: CGPoint(x: centre.x, y: centre.y - spread)
        case .right: CGPoint(x: centre.x + spread, y: centre.y)
        }
    }

    // MARK: - Bottom

    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 8) {
            if let rejection = session.rejection {
                Text(rejection)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(.red.opacity(0.7), in: Capsule())
                    .accessibilityIdentifier("rejectionBanner")
            }

            if session.stage == .bidding, session.state.seatToAct == session.localSeat {
                BiddingBar(session: session)
            }

            HandFanView(session: session, namespace: cardNamespace)
                .frame(height: 132)

            HStack {
                Button {
                    showingQuickChat = true
                } label: {
                    Label("table.chat", systemImage: "bubble.left.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("quickChatButton")

                Spacer()

                if session.stage == .playing {
                    Text("table.spades \(session.state.hand.spadesBroken ? String(localized: "table.spades.broken") : String(localized: "table.spades.unbroken"))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .tint(.white)
    }

    private var quitButton: some View {
        Button {
            showingQuitConfirmation = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 44)
        .padding(.trailing, 12)
        .accessibilityLabel(Text("table.quit.title"))
        .accessibilityIdentifier("quitButton")
    }

    private var socialOverlay: some View {
        VStack(spacing: 6) {
            ForEach(session.activeSocialEvents) { event in
                SocialEventBubble(event: event, name: session.occupantName(for: event.from))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 90)
        .frame(maxHeight: .infinity, alignment: .top)
        .tableAnimation(session.activeSocialEvents.map(\.sequence))
        .allowsHitTesting(false)
    }

    private func muteSeat(_ seat: Seat) {
        guard let id = session.state.seats[seat].playerID?.rawValue else { return }
        settings.toggleMute(id)
    }
}


/// The local player's hand, fanned.
struct HandFanView: View {
    @Bindable var session: GameSession
    let namespace: Namespace.ID

    private let layout = HandFanLayout()

    var body: some View {
        GeometryReader { geometry in
            let hand = session.localHand
            let visible = min(hand.count, max(0, session.dealtCards / 4))
            let width = layout.cardWidth(
                count: hand.count,
                available: geometry.size.width - 24,
                maximum: 84
            )
            let legal = Set(session.legalPlays)

            ZStack {
                ForEach(Array(hand.enumerated()), id: \.element.id) { index, card in
                    let placement = layout.placement(index: index, count: hand.count, cardWidth: width)
                    CardView(
                        card: card,
                        isPlayable: legal.contains(card),
                        isDimmed: session.stage == .playing && !legal.contains(card)
                    )
                    .frame(width: width)
                    .matchedGeometryEffect(id: card.id, in: namespace, isSource: false)
                    .rotationEffect(placement.rotation)
                    .offset(placement.offset)
                    .offset(y: legal.contains(card) ? -8 : 0)
                    .zIndex(placement.zIndex)
                    .opacity(index < visible ? 1 : 0)
                    .onTapGesture { session.play(card: card) }
                    .allowsHitTesting(legal.contains(card))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .tableAnimation(session.localHand.count * 100 + session.dealtCards)
        .accessibilityIdentifier("handFan")
    }
}
