import SpadesEngine
import SwiftUI

/// The reaction picker. Opened by tapping a seat's avatar.
struct ReactionPicker: View {
    let targetName: String
    var onSelect: (ReactionKind) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("reaction.to \(targetName)")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 14) {
                ForEach(ReactionKind.allCases, id: \.self) { kind in
                    Button {
                        onSelect(kind)
                    } label: {
                        Image(systemName: kind.symbolName)
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(labelKey(kind)))
                    .accessibilityIdentifier("reaction.\(kind.rawValue)")
                }
            }

            // The mute control ships before the reactions do, not after.
            Text("reaction.muteHint")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .accessibilityIdentifier("reactionPicker")
    }

    private func labelKey(_ kind: ReactionKind) -> LocalizedStringKey {
        LocalizedStringKey("reaction.\(kind.rawValue)")
    }
}

/// The fixed quick-chat list. There is no free-text field, on purpose: free
/// text means owing users moderation, reporting and blocking (§8).
struct QuickChatSheet: View {
    var onSelect: (QuickPhrase) -> Void

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(QuickPhrase.allCases, id: \.self) { phrase in
                    Button {
                        onSelect(phrase)
                    } label: {
                        Text(LocalizedStringKey(phrase.localizationKey))
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("phrase.\(phrase.rawValue)")
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("quickChatSheet")
    }
}

/// A reaction or phrase, floating briefly near the player who sent it.
struct SocialEventBubble: View {
    let event: SocialEvent
    let name: String

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("social.from \(name)"))
    }

    @ViewBuilder
    private var content: some View {
        switch event.kind {
        case .reaction(let kind):
            HStack(spacing: 6) {
                Image(systemName: kind.symbolName)
                Text(name).font(.caption)
            }
        case .phrase(let phrase):
            HStack(spacing: 6) {
                Text(name).font(.caption.weight(.semibold))
                Text(LocalizedStringKey(phrase.localizationKey)).font(.caption)
            }
        }
    }
}
