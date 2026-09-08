import SpadesEconomy
import SpadesEngine
import SwiftUI

/// Seat configuration and stake selection.
struct LobbyView: View {
    @Environment(CareerStore.self) private var career
    @Environment(SettingsStore.self) private var settings
    @Environment(AudioServiceBox.self) private var audioBox
    @Environment(HapticsBox.self) private var hapticsBox
    @Environment(PersistenceBox.self) private var persistenceBox

    @State private var humanCount = 1
    @State private var difficulty: BotDifficulty = .medium
    @State private var arrangement: MatchConfig.PartnerArrangement = .partners
    @State private var stake: StakeTier = .casual
    @State private var session: GameSession?

    /// Drives the push. A `Bool` rather than `item:` because `GameSession` is a
    /// reference type with no meaningful identity beyond "the current match".
    private var isPlaying: Binding<Bool> {
        Binding(get: { session != nil }, set: { presented in if !presented { session = nil } })
    }

    private var soloVsBots: Bool { humanCount == 1 }

    var body: some View {
        Form {
            Section("lobby.table") {
                Picker("lobby.humans", selection: $humanCount) {
                    ForEach(1...4, id: \.self) { count in
                        Text(LocalizedStringKey("lobby.humans.\(count)")).tag(count)
                    }
                }
                .accessibilityIdentifier("humanCountPicker")

                if humanCount == 2 {
                    Picker("lobby.arrangement", selection: $arrangement) {
                        Text("lobby.arrangement.partners").tag(MatchConfig.PartnerArrangement.partners)
                        Text("lobby.arrangement.opponents").tag(MatchConfig.PartnerArrangement.opponents)
                    }
                    .pickerStyle(.segmented)
                }

                if humanCount < 4 {
                    Picker("lobby.difficulty", selection: $difficulty) {
                        ForEach(BotDifficulty.allCases, id: \.self) { level in
                            Text(LocalizedStringKey("difficulty.\(level.rawValue)")).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("difficultyPicker")
                }
            }

            Section {
                ForEach(StakeTier.allCases, id: \.self) { tier in
                    stakeRow(tier)
                }
            } header: {
                Text("lobby.stake")
            } footer: {
                if soloVsBots {
                    Text("lobby.soloDiscount")
                }
            }

            Section {
                NavigationLink("lobby.houseRules") {
                    HouseRulesView()
                }
            }

            Section {
                Button("lobby.start") { startMatch() }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("startMatchButton")
            }
        }
        .navigationTitle("lobby.title")
        .navigationDestination(isPresented: isPlaying) {
            if let session { TableView(session: session) }
        }
    }

    private func stakeRow(_ tier: StakeTier) -> some View {
        let selectable = career.isSelectable(tier, soloVsBots: soloVsBots)
        let unlocked = career.isUnlocked(tier)

        return Button {
            stake = tier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(tier.displayNameKey))
                        .font(.body.weight(stake == tier ? .semibold : .regular))
                    if unlocked {
                        Text("lobby.entryPayout \(career.entry(for: tier, soloVsBots: soloVsBots)) \(career.payout(for: tier, soloVsBots: soloVsBots))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("lobby.locked \(tier.unlockThreshold)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if stake == tier { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .disabled(!selectable)
        .accessibilityIdentifier("stake.\(tier.rawValue)")
    }

    private func startMatch() {
        let config = MatchConfig(
            humanCount: humanCount,
            botDifficulty: difficulty,
            stake: stake,
            rules: settings.values.houseRules,
            arrangement: arrangement
        )
        session = GameSession(
            config: config,
            audio: audioBox.service,
            haptics: hapticsBox.service,
            career: career,
            settings: settings,
            persistence: persistenceBox.store
        )
    }
}

/// House rules. These genuinely vary between tables, which is why they are
/// configurable rather than hard-coded (§5).
struct HouseRulesView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let rules = settings.values.houseRules

        Form {
            Section("rules.scoring") {
                Picker("rules.target", selection: binding(\.targetScore)) {
                    Text("250").tag(250)
                    Text("500").tag(500)
                }
                .pickerStyle(.segmented)

                Stepper("rules.bagThreshold \(rules.bagPenaltyThreshold)",
                        value: binding(\.bagPenaltyThreshold), in: 5...20)
                Stepper("rules.bagPenalty \(rules.bagPenalty)",
                        value: binding(\.bagPenalty), in: 50...200, step: 25)
            }

            Section("rules.nil") {
                Toggle("rules.blindNil", isOn: binding(\.allowBlindNil))
                Toggle("rules.nilTricksCountForPartner", isOn: binding(\.nilTricksCountForPartner))
            }

            Section("rules.play") {
                Toggle("rules.twoOfClubs", isOn: binding(\.mustLeadTwoOfClubs))
            }
        }
        .navigationTitle("rules.title")
    }

    private func binding<Value>(_ path: WritableKeyPath<RulesConfig, Value>) -> Binding<Value> {
        Binding(
            get: { settings.values.houseRules[keyPath: path] },
            set: { newValue in settings.update { $0.houseRules[keyPath: path] = newValue } }
        )
    }
}
