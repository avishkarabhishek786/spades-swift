import Foundation
import SpadesEconomy
// TODO: drop @preconcurrency once GameKit's Sendable annotations land.
// It is a stopgap for incomplete upstream annotations, not a general way to
// silence concurrency diagnostics — it must not spread to another file.
@preconcurrency import GameKit
import Observation
import SpadesEngine

/// The wire format: one `GameAction` plus a monotonically increasing sequence
/// number, and periodically a state hash so divergence is caught rather than
/// tolerated.
struct MatchEnvelope: Codable, Sendable, Equatable {
    var sequence: Int
    var action: GameAction
    /// The sender's state hash *after* applying `action`.
    var stateHash: UInt64
}

/// A full state snapshot, sent when a hash mismatch says the peers have diverged.
struct MatchSnapshot: Codable, Sendable, Equatable {
    var sequence: Int
    var state: GameState
}

/// What crosses the network.
enum MatchPayload: Codable, Sendable, Equatable {
    case action(MatchEnvelope)
    case snapshot(MatchSnapshot)
    /// Sent by a client that has detected divergence and needs the host's state.
    case resyncRequest
}

@MainActor
protocol MatchTransportDelegate: AnyObject {
    func transport(_ transport: any MatchTransport, didReceive payload: MatchPayload, from player: PlayerID)
    func transport(_ transport: any MatchTransport, playerDidDisconnect player: PlayerID)
    func transport(_ transport: any MatchTransport, playerDidReconnect player: PlayerID)
}

/// Everything above this line is testable with an in-memory fake; only
/// `GameKitMatchService` imports anything from GameKit.
@MainActor
protocol MatchTransport: AnyObject {
    var localPlayerID: PlayerID { get }
    var isHost: Bool { get }
    var delegate: (any MatchTransportDelegate)? { get set }

    func send(_ payload: MatchPayload) throws
    func disconnect()
}

/// How long a disconnected seat is held open before the seat is forfeited.
///
/// The number itself lives in `SpadesEconomy.ReconnectPolicy`, because what
/// separates a dropped connection from an abandoned match is an economic rule,
/// not a transport detail.
enum MatchReconnect {
    static var graceWindow: Duration { .seconds(ReconnectPolicy.graceWindowSeconds) }
}

// MARK: - GameKit

/// The only file in the app that imports GameKit.
///
/// v1 uses `GKMatch` real-time: it brings matchmaking, identity and friends
/// with no server bill. If it proves limiting, a WebSocket implementation slots
/// in behind `MatchTransport` without the engine or the UI noticing (§7).
@MainActor
final class GameKitMatchService: NSObject, MatchTransport {
    private(set) var match: GKMatch?
    private(set) var isAuthenticated = false

    weak var delegate: (any MatchTransportDelegate)?

    var localPlayerID: PlayerID { PlayerID(GKLocalPlayer.local.gamePlayerID) }

    /// The host is chosen deterministically so every peer agrees without a
    /// negotiation round trip: lowest player id wins. The host is authoritative
    /// for the shuffle and for turn order.
    var isHost: Bool {
        guard let match else { return true }
        let ids = match.players.map(\.gamePlayerID) + [GKLocalPlayer.local.gamePlayerID]
        return ids.min() == GKLocalPlayer.local.gamePlayerID
    }

    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] _, _ in
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    func attach(to match: GKMatch) {
        self.match = match
        match.delegate = self
    }

    func send(_ payload: MatchPayload) throws {
        guard let match else { return }
        let data = try JSONEncoder().encode(payload)
        try match.sendData(toAllPlayers: data, with: .reliable)
    }

    func disconnect() {
        match?.disconnect()
        match = nil
    }
}

extension GameKitMatchService: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        let id = PlayerID(player.gamePlayerID)
        guard let payload = try? JSONDecoder().decode(MatchPayload.self, from: data) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            delegate?.transport(self, didReceive: payload, from: id)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let id = PlayerID(player.gamePlayerID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .disconnected:
                delegate?.transport(self, playerDidDisconnect: id)
            case .connected:
                delegate?.transport(self, playerDidReconnect: id)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Test double

/// An in-memory transport. Two of these wired to each other exercise the whole
/// multiplayer path — sequencing, hash mismatch, resync — with no network and
/// no Game Center account.
@MainActor
final class LoopbackMatchTransport: MatchTransport {
    let localPlayerID: PlayerID
    let isHost: Bool
    weak var delegate: (any MatchTransportDelegate)?

    private(set) var sent: [MatchPayload] = []
    /// The peers this transport delivers to.
    var peers: [LoopbackMatchTransport] = []
    /// Set to drop traffic and simulate a disconnect.
    var isConnected = true

    init(localPlayerID: PlayerID, isHost: Bool) {
        self.localPlayerID = localPlayerID
        self.isHost = isHost
    }

    func send(_ payload: MatchPayload) throws {
        guard isConnected else { return }
        sent.append(payload)
        for peer in peers where peer.isConnected {
            peer.delegate?.transport(peer, didReceive: payload, from: localPlayerID)
        }
    }

    func disconnect() {
        isConnected = false
        for peer in peers {
            peer.delegate?.transport(peer, playerDidDisconnect: localPlayerID)
        }
    }
}
