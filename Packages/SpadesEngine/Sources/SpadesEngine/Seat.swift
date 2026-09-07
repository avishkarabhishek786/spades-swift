import Foundation

/// One of the four table positions. Seats are numbered clockwise.
///
/// Seat numbering is a *model* concept and never a screen position. Every
/// client renders relative to its own local seat so that the local player is
/// always at the bottom — rotate the render, not the model.
public enum Seat: Int, CaseIterable, Codable, Sendable, Comparable, Hashable, Identifiable {
    case zero = 0
    case one
    case two
    case three

    public var id: Int { rawValue }

    public static func < (lhs: Seat, rhs: Seat) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The next seat clockwise. Clockwise is defined as increasing seat index.
    public var next: Seat {
        // Safe: rawValue is 0...3 so (rawValue + 1) % 4 is always in range.
        Seat(rawValue: (rawValue + 1) % Seat.allCases.count) ?? .zero
    }

    /// The seat directly across the table — this seat's partner.
    public var partner: Seat {
        Seat(rawValue: (rawValue + 2) % Seat.allCases.count) ?? .zero
    }

    /// The partnership this seat belongs to. Seats 0 and 2 are one team, 1 and 3 the other.
    public var team: Team { rawValue.isMultiple(of: 2) ? .zeroTwo : .oneThree }

    /// The seat `count` positions clockwise from this one.
    public func advanced(by count: Int) -> Seat {
        let n = Seat.allCases.count
        let wrapped = ((rawValue + count) % n + n) % n
        return Seat(rawValue: wrapped) ?? .zero
    }

    /// The four seats in clockwise bidding/play order starting at this one.
    public var clockwiseOrder: [Seat] { (0..<Seat.allCases.count).map { advanced(by: $0) } }
}

/// A partnership. `zeroTwo` is seats 0 and 2; `oneThree` is seats 1 and 3.
public enum Team: Int, CaseIterable, Codable, Sendable, Hashable, Identifiable {
    case zeroTwo = 0
    case oneThree

    public var id: Int { rawValue }

    public var seats: (Seat, Seat) {
        switch self {
        case .zeroTwo: (.zero, .two)
        case .oneThree: (.one, .three)
        }
    }

    public var opponent: Team { self == .zeroTwo ? .oneThree : .zeroTwo }

    public func contains(_ seat: Seat) -> Bool { seat.team == self }
}

/// A stable identifier for a human player. Opaque to the engine.
public struct PlayerID: Hashable, Codable, Sendable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

/// Who is sitting in a seat. The reducer never inspects this — `reduce` treats
/// human and bot actions identically. Only the app layer's session routes turns.
public enum SeatOccupant: Equatable, Codable, Sendable {
    case human(PlayerID)
    case bot(BotDifficulty, persona: BotPersona)
    case empty

    public var isBot: Bool { if case .bot = self { true } else { false } }
    public var isHuman: Bool { if case .human = self { true } else { false } }

    public var playerID: PlayerID? { if case .human(let id) = self { id } else { nil } }
}

/// A fixed four-element mapping keyed by ``Seat``.
///
/// This exists instead of `[Seat: Value]` deliberately. Dictionaries have no
/// guaranteed iteration order, which leaks non-determinism into replay and into
/// `Codable` output; a seat-indexed array cannot.
public struct SeatMap<Value>: Sendable, Codable, Equatable
where Value: Sendable & Codable & Equatable {
    private var storage: [Value]

    public init(repeating value: Value) {
        storage = Array(repeating: value, count: Seat.allCases.count)
    }

    public init(_ builder: (Seat) throws -> Value) rethrows {
        storage = try Seat.allCases.map(builder)
    }

    public subscript(seat: Seat) -> Value {
        get { storage[seat.rawValue] }
        set { storage[seat.rawValue] = newValue }
    }

    /// Values in seat order, 0 through 3.
    public var values: [Value] { storage }

    public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> SeatMap<T> {
        try SeatMap<T> { try transform(self[$0]) }
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Value] = []
        while !container.isAtEnd {
            decoded.append(try container.decode(Value.self))
        }
        guard decoded.count == Seat.allCases.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "SeatMap requires exactly \(Seat.allCases.count) values, got \(decoded.count)")
            )
        }
        storage = decoded
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in storage { try container.encode(value) }
    }
}

/// A fixed two-element mapping keyed by ``Team``. Same rationale as ``SeatMap``.
public struct TeamMap<Value>: Sendable, Codable, Equatable
where Value: Sendable & Codable & Equatable {
    private var storage: [Value]

    public init(repeating value: Value) {
        storage = Array(repeating: value, count: Team.allCases.count)
    }

    public init(_ builder: (Team) throws -> Value) rethrows {
        storage = try Team.allCases.map(builder)
    }

    public subscript(team: Team) -> Value {
        get { storage[team.rawValue] }
        set { storage[team.rawValue] = newValue }
    }

    public var values: [Value] { storage }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Value] = []
        while !container.isAtEnd {
            decoded.append(try container.decode(Value.self))
        }
        guard decoded.count == Team.allCases.count else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "TeamMap requires exactly \(Team.allCases.count) values, got \(decoded.count)")
            )
        }
        storage = decoded
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for value in storage { try container.encode(value) }
    }
}
