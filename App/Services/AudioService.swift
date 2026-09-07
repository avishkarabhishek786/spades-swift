import AVFoundation
import Foundation
import Observation

/// Every sound the game makes. One enum, so no filename string is ever written
/// anywhere else (§10).
enum SoundEffect: String, CaseIterable, Sendable {
    case shuffle, dealCard, playCard, trickWon, invalidMove
    case bidConfirm, bidNil, handComplete, gameWon, gameLost
    case buttonTap, reactionSent, chatSent, pointsAwarded, dailyBonus

    /// Clips that ship several takes. A single card sound repeated fifty-two
    /// times during a deal is the fastest way to make a game feel cheap.
    var variantCount: Int {
        switch self {
        case .dealCard, .playCard: 4
        default: 1
        }
    }

    /// Filenames in `Resources/Audio`, produced by `Tools/fetch_audio.sh`.
    var resourceNames: [String] {
        guard variantCount > 1 else { return [rawValue] }
        return (1...variantCount).map { "\(rawValue)\($0)" }
    }
}

protocol AudioPlaying: AnyObject, Sendable {
    @MainActor func play(_ effect: SoundEffect)
    @MainActor func prepare()
}

/// Plays short effects from a pre-warmed pool of players.
@MainActor
@Observable
final class AudioService: AudioPlaying {
    /// Four players per clip, round-robin. One `AVAudioPlayer` cannot overlap
    /// itself, and a staggered deal absolutely will overlap.
    private static let poolSize = 4

    private var pools: [String: [AVAudioPlayer]] = [:]
    private var cursors: [String: Int] = [:]
    private let settings: SettingsStore
    private let bundle: Bundle

    init(settings: SettingsStore, bundle: Bundle = .main) {
        self.settings = settings
        self.bundle = bundle
    }

    /// Configures the session and loads every clip. Called once at launch;
    /// nothing is constructed at play time.
    func prepare() {
        configureSession()
        for effect in SoundEffect.allCases {
            for name in effect.resourceNames {
                guard let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
                        ?? bundle.url(forResource: name, withExtension: "wav") else { continue }
                let players = (0..<Self.poolSize).compactMap { _ -> AVAudioPlayer? in
                    guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
                    player.prepareToPlay()
                    return player
                }
                guard !players.isEmpty else { continue }
                pools[name] = players
                cursors[name] = 0
            }
        }
    }

    private func configureSession() {
        // .ambient with .mixWithOthers respects the ringer switch and leaves
        // the player's music alone. .playback is the wrong category here and
        // a card game that stops someone's podcast earns one-star reviews.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func play(_ effect: SoundEffect) {
        guard settings.values.soundEnabled else { return }
        // Something else is already making the noise that matters — a call,
        // a navigation prompt. Stay out of the way.
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else { return }

        let name = effect.resourceNames.randomElement() ?? effect.rawValue
        guard let pool = pools[name], !pool.isEmpty else { return }

        let index = (cursors[name] ?? 0) % pool.count
        cursors[name] = index + 1

        let player = pool[index]
        player.volume = Float(settings.values.sfxVolume)
        player.currentTime = 0
        player.play()
    }
}

/// Silent stand-in for tests, previews and any build without audio resources.
@MainActor
final class SilentAudioService: AudioPlaying {
    private(set) var played: [SoundEffect] = []
    func play(_ effect: SoundEffect) { played.append(effect) }
    func prepare() {}
}
