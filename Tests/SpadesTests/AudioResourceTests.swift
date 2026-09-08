import Foundation
import Testing
@testable import Spades

@Suite("Audio resources")
struct AudioResourceTests {

    /// Every `SoundEffect` must resolve to a bundled file.
    ///
    /// `AudioService` skips a clip it cannot load, which is the right runtime
    /// behaviour and exactly why this needs a test: without one, a missing
    /// sound fails silently in a player's hands instead of failing in CI.
    @Test("Every sound effect resolves to a file in the bundle")
    func everyEffectIsBundled() {
        let bundle = Bundle(for: BundleToken.self)
        var missing: [String] = []

        for effect in SoundEffect.allCases {
            for name in effect.resourceNames {
                let url = bundle.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
                    ?? bundle.url(forResource: name, withExtension: "wav")
                if url == nil { missing.append("\(name).wav") }
            }
        }

        #expect(missing.isEmpty, "Missing audio: \(missing.joined(separator: ", "))")
    }

    /// Deal and play ship several takes; a single card sound repeated
    /// fifty-two times during a deal is the fastest way to make a game feel cheap.
    @Test("Card sounds ship multiple variants")
    func cardSoundsHaveVariants() {
        #expect(SoundEffect.dealCard.variantCount >= 3)
        #expect(SoundEffect.playCard.variantCount >= 3)
        #expect(SoundEffect.dealCard.resourceNames.count == SoundEffect.dealCard.variantCount)
        #expect(SoundEffect.shuffle.resourceNames == ["shuffle"])
    }

    @Test("Filenames are derived from the enum, never written out by hand")
    func namesComeFromTheEnum() {
        // One enum, so no filename string is ever written anywhere else (§10).
        for effect in SoundEffect.allCases {
            #expect(effect.resourceNames.allSatisfy { $0.hasPrefix(effect.rawValue) })
        }
    }
}

private final class BundleToken {}
