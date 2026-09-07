import Observation
import SpadesEngine
import SwiftUI

/// Player preferences. Injected through the environment, never reached through
/// a singleton (§14).
@MainActor
@Observable
final class SettingsStore {

    /// The persisted shape. Kept separate from the observable class so it can
    /// be versioned and round-tripped without dragging observation into the file.
    struct Values: Codable, Sendable, Equatable {
        var sfxVolume: Double = 0.8
        var musicVolume: Double = 0.5
        var soundEnabled = true
        var musicEnabled = true
        var hapticsEnabled = true
        var deckPalette: DeckPalette = .classic
        /// The global "hide all reactions" switch required by §8.
        var hideAllReactions = false
        /// Seats this player has muted, by opponent identifier. Local only —
        /// a mute is this player's business and never goes over the wire.
        var mutedPlayers: Set<String> = []
        var houseRules: RulesConfig = .standard

        init() {}

        /// Tolerates missing keys, for the same reason `CareerProfile` does:
        /// the synthesised decoder ignores defaults and throws on an absent
        /// key, so adding a preference would otherwise reset everyone's
        /// existing ones.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Values()
            sfxVolume = try container.decodeIfPresent(Double.self, forKey: .sfxVolume) ?? defaults.sfxVolume
            musicVolume = try container.decodeIfPresent(Double.self, forKey: .musicVolume) ?? defaults.musicVolume
            soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? defaults.soundEnabled
            musicEnabled = try container.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? defaults.musicEnabled
            hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? defaults.hapticsEnabled
            deckPalette = try container.decodeIfPresent(DeckPalette.self, forKey: .deckPalette) ?? defaults.deckPalette
            hideAllReactions = try container.decodeIfPresent(Bool.self, forKey: .hideAllReactions) ?? defaults.hideAllReactions
            mutedPlayers = try container.decodeIfPresent(Set<String>.self, forKey: .mutedPlayers) ?? defaults.mutedPlayers
            houseRules = try container.decodeIfPresent(RulesConfig.self, forKey: .houseRules) ?? defaults.houseRules
        }
    }

    private(set) var values: Values
    private let store: any Persisting

    init(store: any Persisting) {
        self.store = store
        values = (try? store.loadVersioned(Values.self, from: .settings)) ?? Values()
    }

    // MARK: - Mutation

    func update(_ change: (inout Values) -> Void) {
        var copy = values
        change(&copy)
        guard copy != values else { return }
        values = copy
        persist()
    }

    func isMuted(_ playerID: String) -> Bool { values.mutedPlayers.contains(playerID) }

    func toggleMute(_ playerID: String) {
        update { values in
            if values.mutedPlayers.contains(playerID) {
                values.mutedPlayers.remove(playerID)
            } else {
                values.mutedPlayers.insert(playerID)
            }
        }
    }

    /// Whether a social event from this seat should be shown at all.
    func showsSocial(from playerID: String?) -> Bool {
        guard !values.hideAllReactions else { return false }
        guard let playerID else { return true }
        return !isMuted(playerID)
    }

    private func persist() {
        // A failed settings write is not worth interrupting a game for; the
        // next change will try again.
        try? store.saveVersioned(values, to: .settings)
    }
}
