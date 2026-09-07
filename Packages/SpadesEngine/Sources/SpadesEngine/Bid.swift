import Foundation

/// A single seat's bid.
///
/// House rules describe the range as "0 to 13, or nil". Zero and nil are the
/// same declaration, so there is exactly one representation for it: ``nilBid``.
/// ``init(tricks:)`` maps a literal 0 onto it rather than admitting a second one.
public enum Bid: Equatable, Hashable, Codable, Sendable, CustomStringConvertible {
    /// A numeric contract of 1 through 13 tricks.
    case tricks(Int)
    /// A declaration of zero tricks, scored separately from the team contract.
    case nilBid
    /// Nil declared before looking at the hand. Double stakes.
    case blindNil

    /// Builds a bid from a trick count, mapping 0 to ``nilBid``.
    /// Returns `nil` for counts outside 0...13.
    public init?(tricks count: Int) {
        switch count {
        case 0: self = .nilBid
        case 1...13: self = .tricks(count)
        default: return nil
        }
    }

    /// What this bid contributes to the team contract. Nil bids contribute nothing —
    /// they are scored per seat, not folded into the partnership's number.
    public var contractValue: Int {
        switch self {
        case .tricks(let count): count
        case .nilBid, .blindNil: 0
        }
    }

    /// True for ``nilBid`` and ``blindNil``.
    public var isNil: Bool {
        switch self {
        case .nilBid, .blindNil: true
        case .tricks: false
        }
    }

    public var isBlindNil: Bool { self == .blindNil }

    /// Points awarded for making this nil, or zero for a numeric bid.
    public var nilReward: Int {
        switch self {
        case .nilBid: 100
        case .blindNil: 200
        case .tricks: 0
        }
    }

    public var description: String {
        switch self {
        case .tricks(let count): "\(count)"
        case .nilBid: "nil"
        case .blindNil: "blind nil"
        }
    }
}
