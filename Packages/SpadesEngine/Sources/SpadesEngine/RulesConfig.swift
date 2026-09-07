import Foundation

/// House rules. Spades varies enough between tables that hard-coding any of
/// these produces "that's not how Spades works" reviews from half the players.
public struct RulesConfig: Codable, Sendable, Equatable {
    /// Score a team must reach to win the match.
    public var targetScore: Int = 500
    /// Bags at which the penalty fires.
    public var bagPenaltyThreshold: Int = 10
    /// Points deducted when the bag threshold is crossed.
    public var bagPenalty: Int = 100
    /// Whether tricks taken by a *failed* nil bidder count toward the partner's contract.
    public var nilTricksCountForPartner: Bool = false
    /// Whether blind nil may be declared at all.
    public var allowBlindNil: Bool = true
    /// How far behind a team must be to declare blind nil. `nil` means always allowed.
    public var blindNilRequiresDeficit: Int? = 100
    /// Whether the holder of the two of clubs must lead it on the first trick of a hand.
    public var mustLeadTwoOfClubs: Bool = false
    /// Minimum combined numeric bid per team, if the table enforces one.
    public var minBidPerTeam: Int?

    public static let standard = RulesConfig()

    public init(
        targetScore: Int = 500,
        bagPenaltyThreshold: Int = 10,
        bagPenalty: Int = 100,
        nilTricksCountForPartner: Bool = false,
        allowBlindNil: Bool = true,
        blindNilRequiresDeficit: Int? = 100,
        mustLeadTwoOfClubs: Bool = false,
        minBidPerTeam: Int? = nil
    ) {
        self.targetScore = targetScore
        self.bagPenaltyThreshold = bagPenaltyThreshold
        self.bagPenalty = bagPenalty
        self.nilTricksCountForPartner = nilTricksCountForPartner
        self.allowBlindNil = allowBlindNil
        self.blindNilRequiresDeficit = blindNilRequiresDeficit
        self.mustLeadTwoOfClubs = mustLeadTwoOfClubs
        self.minBidPerTeam = minBidPerTeam
    }

    /// Decoding tolerates missing keys so a profile written by an older build
    /// still loads. Every field has a defined default; see §12 on schema versioning.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = RulesConfig.standard
        targetScore = try container.decodeIfPresent(Int.self, forKey: .targetScore) ?? standard.targetScore
        bagPenaltyThreshold = try container.decodeIfPresent(Int.self, forKey: .bagPenaltyThreshold) ?? standard.bagPenaltyThreshold
        bagPenalty = try container.decodeIfPresent(Int.self, forKey: .bagPenalty) ?? standard.bagPenalty
        nilTricksCountForPartner = try container.decodeIfPresent(Bool.self, forKey: .nilTricksCountForPartner) ?? standard.nilTricksCountForPartner
        allowBlindNil = try container.decodeIfPresent(Bool.self, forKey: .allowBlindNil) ?? standard.allowBlindNil
        blindNilRequiresDeficit = try container.decodeIfPresent(Int.self, forKey: .blindNilRequiresDeficit)
        mustLeadTwoOfClubs = try container.decodeIfPresent(Bool.self, forKey: .mustLeadTwoOfClubs) ?? standard.mustLeadTwoOfClubs
        minBidPerTeam = try container.decodeIfPresent(Int.self, forKey: .minBidPerTeam)
    }
}
