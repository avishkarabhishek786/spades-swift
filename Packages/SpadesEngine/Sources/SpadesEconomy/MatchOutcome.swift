import Foundation

/// How a match ended, from the local player's point of view.
///
/// This is the seam between the two modules. `SpadesEconomy` never sees a
/// `GameState`, a `Team` or a `Trick`; the app maps whatever the engine
/// produced into one of these values and hands it over.
public enum MatchOutcome: String, Codable, Sendable, CaseIterable {
    case win
    case loss
    /// Left a ranked match in progress. Forfeits the stake and dents the streak.
    ///
    /// A disconnection with a successful reconnect inside the grace window is
    /// not a quit and must never be mapped to this case.
    case quit
}

/// How long a disconnected seat is held open before the seat is forfeited.
///
/// Lives here rather than in the transport because it is an economic rule —
/// what separates a dropped connection from an abandoned match.
public enum ReconnectPolicy {
    public static let graceWindowSeconds: Int = 90
}
