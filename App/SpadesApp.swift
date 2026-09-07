import SpadesEngine
import SwiftUI

@main
@MainActor
struct SpadesApp: App {
    @State private var container = ServiceContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container.settings)
                .environment(container.career)
                .environment(container.dailyBonus)
                .environment(container.ads)
                .environment(container.audioBox)
                .environment(container.hapticsBox)
                .environment(container.persistenceBox)
                .task { container.prepare() }
        }
        .onChange(of: scenePhase) { _, phase in
            // The daily bonus is awarded on the first foreground of each local
            // calendar day, not after a rolling twenty-four hours (§9).
            if phase == .active { container.dailyBonus.claimIfDue() }
        }
    }
}

/// Builds and holds the services. Everything reaches them through the SwiftUI
/// environment; nothing is a singleton (§14).
@MainActor
@Observable
final class ServiceContainer {
    let persistence: any Persisting
    let settings: SettingsStore
    let career: CareerStore
    let dailyBonus: DailyBonusService
    let ads: AdService
    let audioBox: AudioServiceBox
    let hapticsBox: HapticsBox
    let persistenceBox: PersistenceBox

    private let audio: any AudioPlaying
    private let haptics: any HapticsProviding

    /// Set by `-uitesting`: silent effects and a throwaway profile, so a UI
    /// run neither makes noise nor inherits whatever the last one left behind.
    nonisolated static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitesting")
    }

    init(persistence: (any Persisting)? = nil, useSilentEffects: Bool = Self.isUITesting) {
        // A profile that cannot be written is still better than a crash on
        // launch, so fall back to memory rather than trapping.
        let store = persistence
            ?? (Self.isUITesting ? MemoryPersistence() : ((try? FilePersistence()) ?? MemoryPersistence()))
        self.persistence = store

        let settings = SettingsStore(store: store)
        let career = CareerStore(store: store)
        self.settings = settings
        self.career = career
        dailyBonus = DailyBonusService(career: career)
        ads = AdService(provider: StubAdService(), career: career)

        audio = useSilentEffects ? SilentAudioService() : AudioService(settings: settings)
        haptics = useSilentEffects ? SilentHapticsService() : HapticsService(settings: settings)
        audioBox = AudioServiceBox(audio)
        hapticsBox = HapticsBox(haptics)
        persistenceBox = PersistenceBox(store)
    }

    /// Preloads every clip and pre-warms the haptic generators. Nothing is
    /// constructed at play time.
    func prepare() {
        audio.prepare()
        haptics.prepare()
        ads.preload()
    }
}

struct RootView: View {
    @Environment(CareerStore.self) private var career
    @Environment(DailyBonusService.self) private var dailyBonus

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        LobbyView()
                    } label: {
                        Label("root.play", systemImage: "suit.spade.fill")
                    }
                    .accessibilityIdentifier("playButton")
                }

                Section {
                    NavigationLink {
                        CareerView()
                    } label: {
                        Label("root.career", systemImage: "person.crop.circle")
                    }
                    .accessibilityIdentifier("careerButton")

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("root.settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }

                Section {
                    LabeledContent("career.points", value: "\(career.profile.points)")
                }
            }
            .navigationTitle("root.title")
        }
        .overlay(alignment: .top) {
            if let award = dailyBonus.pendingAward, award.granted {
                DailyBonusBanner(award: award) { dailyBonus.acknowledgeAward() }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .tableAnimation(dailyBonus.pendingAward?.streakDay ?? 0)
    }
}

struct DailyBonusBanner: View {
    let award: DailyBonus.Evaluation
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gift.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text("bonus.title \(award.points)").font(.subheadline.weight(.semibold))
                Text("bonus.streak \(award.streakDay)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("common.ok", action: onDismiss)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("dailyBonusBanner")
    }
}
