import Foundation
import SpadesEngine
import Testing
@testable import Spades

@MainActor
@Suite("Multiplayer transport")
struct MatchTransportTests {

    /// Two sessions wired to each other through the loopback transport. No
    /// network, no Game Center account, and nothing in this test knows GameKit
    /// exists — which is the point of the `MatchTransport` seam.
    private func makePair(seed: UInt64 = 4_004) -> (GameSession, GameSession, LoopbackMatchTransport, LoopbackMatchTransport) {
        let hostTransport = LoopbackMatchTransport(localPlayerID: PlayerID("host"), isHost: true)
        let peerTransport = LoopbackMatchTransport(localPlayerID: PlayerID("peer"), isHost: false)
        hostTransport.peers = [peerTransport]
        peerTransport.peers = [hostTransport]

        func session(seat: Seat, transport: LoopbackMatchTransport) -> GameSession {
            let store = MemoryPersistence()
            let config = MatchConfig(humanCount: 2, seed: seed, arrangement: .partners, localSeat: seat)
            let session = GameSession(
                config: config,
                seats: config.seats(),
                audio: SilentAudioService(),
                haptics: SilentHapticsService(),
                career: CareerStore(store: store),
                settings: SettingsStore(store: store),
                persistence: store,
                transport: transport
            )
            session.automatesBots = false
            transport.delegate = session
            return session
        }

        let host = session(seat: .zero, transport: hostTransport)
        let peer = session(seat: .two, transport: peerTransport)
        return (host, peer, hostTransport, peerTransport)
    }

    @Test("An action applied on one client reaches the other")
    func actionsPropagate() {
        let (host, peer, hostTransport, _) = makePair()
        host.skipDeal()
        peer.skipDeal()

        let bidder = host.state.hand.firstBidder
        host.apply(.bid(seat: bidder, bid: .tricks(4)))

        #expect(host.state.hand.bids[bidder] == .tricks(4))
        #expect(peer.state.hand.bids[bidder] == .tricks(4))
        #expect(hostTransport.sent.count == 1)
    }

    @Test("Both clients agree on the state hash after every action")
    func hashesAgree() throws {
        let (host, peer, _, _) = makePair(seed: 777)
        host.skipDeal()
        peer.skipDeal()

        for offset in 0..<4 {
            let seat = host.state.hand.firstBidder.advanced(by: offset)
            host.apply(.bid(seat: seat, bid: .tricks(3)))
        }
        #expect(try host.state.stateHash() == peer.state.stateHash())
        #expect(host.state == peer.state)
    }

    @Test("A client that cannot apply an action asks for a resync instead of limping on")
    func divergenceTriggersResync() throws {
        let (host, peer, _, peerTransport) = makePair(seed: 31)
        host.skipDeal()
        peer.skipDeal()

        // Force the peer out of step, then send it something it cannot apply.
        peer.apply(.bid(seat: peer.state.hand.firstBidder, bid: .tricks(2)))
        peerTransport.sent.removeAll()

        let envelope = MatchEnvelope(
            sequence: 99,
            action: .bid(seat: host.state.hand.firstBidder, bid: .tricks(5)),
            stateHash: 0
        )
        peer.transport(peerTransport, didReceive: .action(envelope), from: PlayerID("host"))
        #expect(peerTransport.sent.contains(.resyncRequest))
    }

    @Test("The host answers a resync request with a full snapshot")
    func hostAnswersResync() {
        let (host, _, hostTransport, _) = makePair(seed: 42)
        host.skipDeal()
        host.apply(.bid(seat: host.state.hand.firstBidder, bid: .tricks(6)))
        hostTransport.sent.removeAll()

        host.transport(hostTransport, didReceive: .resyncRequest, from: PlayerID("peer"))

        let snapshot = hostTransport.sent.compactMap { payload -> MatchSnapshot? in
            if case .snapshot(let snapshot) = payload { return snapshot } else { return nil }
        }.first
        #expect(snapshot?.state == host.state)
    }

    @Test("A snapshot replaces local state wholesale")
    func snapshotApplies() {
        let (host, peer, _, peerTransport) = makePair(seed: 5)
        host.skipDeal()
        peer.skipDeal()
        for offset in 0..<4 {
            let seat = host.state.hand.firstBidder.advanced(by: offset)
            host.apply(.bid(seat: seat, bid: .tricks(3)))
        }

        var stale = peer.state
        stale.scores[.zeroTwo] = -999
        peer.transport(peerTransport, didReceive: .snapshot(MatchSnapshot(sequence: 1, state: host.state)), from: PlayerID("host"))
        #expect(peer.state == host.state)
        #expect(peer.state.scores[.zeroTwo] != stale.scores[.zeroTwo])
    }

    @Test("A dropped player is replaced by a bot at their seat")
    func disconnectSubstitutesBot() {
        let (host, _, hostTransport, _) = makePair(seed: 61)
        host.skipDeal()
        let droppedSeat = Seat.two
        let dropped = host.state.seats[droppedSeat].playerID

        host.transport(hostTransport, playerDidDisconnect: dropped ?? PlayerID("peer"))
        #expect(host.state.seats[droppedSeat].isBot)
        #expect(!host.systemMessages.isEmpty)
    }

    @Test("The wire format survives encoding")
    func payloadRoundTrip() throws {
        let payloads: [MatchPayload] = [
            .action(MatchEnvelope(sequence: 7, action: .play(seat: .one, card: Card(.ace, of: .spades)), stateHash: 12_345)),
            .resyncRequest,
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for payload in payloads {
            #expect(try decoder.decode(MatchPayload.self, from: encoder.encode(payload)) == payload)
        }
    }
}
