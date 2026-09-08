import SpadesEconomy
import SpadesEngine
import SwiftUI

/// Profile, points and record.
struct CareerView: View {
    @Environment(CareerStore.self) private var career
    @Environment(DailyBonusService.self) private var dailyBonus
    @Environment(AdService.self) private var ads

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("career.points")
                    Spacer()
                    Text("\(career.profile.points)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .accessibilityIdentifier("careerPoints")
                }
                LabeledContent("career.lifetime", value: "\(career.profile.lifetimePointsEarned)")
            }

            Section("career.record") {
                LabeledContent("career.played", value: "\(career.profile.gamesPlayed)")
                LabeledContent("career.won", value: "\(career.profile.gamesWon)")
                LabeledContent("career.winRate", value: career.winRate.formatted(.percent.precision(.fractionLength(0))))
                LabeledContent("career.streak", value: "\(career.profile.currentStreak)")
                LabeledContent("career.bestStreak", value: "\(career.profile.bestStreak)")
            }

            Section("career.nils") {
                LabeledContent("career.nilsMade", value: "\(career.profile.nilsMade)")
                LabeledContent("career.nilsFailed", value: "\(career.profile.nilsFailed)")
            }

            Section("career.bonuses") {
                LabeledContent("career.dailyStreak", value: "\(career.profile.dailyBonusStreak)")
                LabeledContent("career.nextBonus", value: "\(dailyBonus.nextAmount)")

                // Hidden entirely when no ad is loaded — with no network the
                // provider never becomes ready and the player sees nothing,
                // rather than an error for something they never asked for.
                if ads.canOfferReward {
                    Button("career.watchForPoints \(ads.rewardAmount)") {
                        ads.watchForReward()
                    }
                    .accessibilityIdentifier("watchAdButton")
                    Text("career.adsRemaining \(ads.remainingToday)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("career.pointsDisclaimer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("career.title")
    }
}

/// Sound, motion, colour and the abuse controls.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Section("settings.sound") {
                Toggle("settings.sfx", isOn: bind(\.soundEnabled))
                if settings.values.soundEnabled {
                    Slider(value: bind(\.sfxVolume), in: 0...1) { Text("settings.sfxVolume") }
                }
                Toggle("settings.music", isOn: bind(\.musicEnabled))
                if settings.values.musicEnabled {
                    Slider(value: bind(\.musicVolume), in: 0...1) { Text("settings.musicVolume") }
                }
                Toggle("settings.haptics", isOn: bind(\.hapticsEnabled))
            }

            Section {
                Picker("settings.deck", selection: bind(\.deckPalette)) {
                    ForEach(DeckPalette.allCases, id: \.self) { palette in
                        Text(palette.displayNameKey).tag(palette)
                    }
                }
                .accessibilityIdentifier("deckPalettePicker")
            } header: {
                Text("settings.appearance")
            } footer: {
                Text("settings.deck.footer")
            }

            Section {
                Toggle("settings.hideReactions", isOn: bind(\.hideAllReactions))
                    .accessibilityIdentifier("hideReactionsToggle")
                if !settings.values.mutedPlayers.isEmpty {
                    Button("settings.unmuteAll", role: .destructive) {
                        settings.update { $0.mutedPlayers.removeAll() }
                    }
                }
            } header: {
                Text("settings.social")
            } footer: {
                Text("settings.social.footer")
            }

            Section("settings.about") {
                // CC0 requires no attribution. Crediting anyway costs nothing
                // and is the decent thing to do.
                Text("about.audioCredit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("settings.title")
    }

    private func bind<Value>(_ path: WritableKeyPath<SettingsStore.Values, Value>) -> Binding<Value> {
        Binding(
            get: { settings.values[keyPath: path] },
            set: { newValue in settings.update { $0[keyPath: path] = newValue } }
        )
    }
}
