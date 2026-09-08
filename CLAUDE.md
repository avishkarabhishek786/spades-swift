# CLAUDE.md — Spades (iOS / Swift)

Project instructions for Claude Code. Read this before making changes.

**Spec version 0.2.** Amended after the engine build. Changes from 0.1 are logged
in §17; where the code and this file disagreed, this file was wrong and has been
corrected.

---

## 0. Current status

| Layer | State |
|---|---|
| `SpadesEngine` | Built, 119 tests green |
| `SpadesEconomy` | Built, tested |
| App layer (SwiftUI / GameKit / AVFoundation) | **Written, never compiled** |
| `Tools/fetch_audio.sh` | Written, syntax-checked, unrun |

The app layer has only been syntax-parsed (`swiftc -frontend -parse`), which
catches nothing beyond syntax. A first compile on a Mac will surface type errors.
Expect them to cluster in `GameSession`, `MatchService` and `AudioService` —
that is where actor isolation meets framework callbacks. Fix those before
trusting anything else in `App/`.

---

## 1. What this is

A native iOS Spades game. Four seats, two partnerships, 13-card hands, spades
always trump. Any seat can be a human or a bot, so the same code path serves
solo play, pass-and-play, and online multiplayer.

**Deliberate non-goals:** no real-money wagering, no crypto, no server-authoritative
rules engine in v1, no Android, no iPad-specific layout in v1 (it should not crash
on iPad, but phone layout is the target).

**Card art is drawn in code.** There are no card face images in this repo and none
should be added. See §11.

---

## 2. Repo layout

```
Spades/
├── CLAUDE.md
├── project.yml                  # XcodeGen manifest — edit this, NOT .pbxproj
├── Makefile                     # canonical entry point for all commands
├── Packages/
│   └── SpadesEngine/
│       ├── Package.swift        # TWO targets — see §4 module boundaries
│       ├── Sources/
│       │   ├── SpadesEngine/    # pure Swift, Foundation only
│       │   │   ├── Card.swift
│       │   │   ├── Deck.swift
│       │   │   ├── Seat.swift
│       │   │   ├── Bid.swift
│       │   │   ├── Trick.swift
│       │   │   ├── HandState.swift
│       │   │   ├── GameState.swift
│       │   │   ├── RulesConfig.swift
│       │   │   ├── Scoring.swift
│       │   │   ├── LegalMoves.swift
│       │   │   ├── Social.swift        # ReactionKind, QuickPhrase — wire format
│       │   │   └── Bots/
│       │   │       ├── BotPlayer.swift
│       │   │       ├── BotDifficulty.swift
│       │   │       └── HandEvaluator.swift
│       │   └── SpadesEconomy/   # separate target — must NOT import SpadesEngine
│       │       ├── StakeTier.swift
│       │       ├── PointsLedger.swift
│       │       ├── BonusRules.swift
│       │       └── MatchOutcome.swift
│       └── Tests/
│           ├── SpadesEngineTests/
│           └── SpadesEconomyTests/
├── App/
│   ├── SpadesApp.swift
│   ├── Features/
│   │   ├── Table/               # main game screen
│   │   ├── Bidding/
│   │   ├── Lobby/               # seat config, stake selection
│   │   ├── Career/              # profile, points, history
│   │   └── Social/              # reactions + quick chat UI
│   ├── Services/
│   │   ├── AudioService.swift
│   │   ├── HapticsService.swift
│   │   ├── CareerStore.swift    # wraps SpadesEconomy, owns persistence
│   │   ├── DailyBonusService.swift  # owns Calendar/Date — see §4
│   │   ├── AdService.swift
│   │   └── MatchService.swift   # GameKit wrapper
│   ├── Rendering/
│   │   ├── CardView.swift       # programmatic card face
│   │   ├── CardBackView.swift
│   │   ├── HandFanLayout.swift
│   │   └── Theme.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Audio/               # VENDORED CC0 WAVs, committed — see §10
└── Tools/
    └── fetch_audio.sh           # provenance + regeneration only, NOT in build path
```

---

## 3. Build, run, test

**Always go through the Makefile.** Do not invent one-off `xcodebuild`
invocations; if you need a new operation, add a target to the Makefile.

```bash
make bootstrap       # brew install xcodegen swiftlint xcbeautify
make project         # xcodegen generate  (run after ANY project.yml change)
make engine-test     # ~3s   reduced-scale sims — the iteration loop
make engine-test-full # ~30s  full §13 scale, release build — CI + pre-PR
make build           # xcodebuild build for simulator
make test            # engine-test-full + app unit tests + UI smoke test
make run             # build, boot sim, install, launch
make lint            # swiftlint --strict
make ci              # what CI runs: lint + purity-check + engine-test-full + test
make sim-nightly     # rotating-seed simulation sweep — see §13
make clean
```

Underlying commands, for reference:

```bash
# Engine only — no simulator, ~3s. Primary iteration loop.
cd Packages/SpadesEngine && swift test

# Full-scale, release. Statistical assertions only hold here.
cd Packages/SpadesEngine && swift test -c release

# Full app build
xcodebuild -project Spades.xcodeproj -scheme Spades \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath .build/DerivedData build | xcbeautify

# Run on simulator
xcrun simctl boot "iPhone 16" || true
open -a Simulator
xcrun simctl install booted \
  .build/DerivedData/Build/Products/Debug-iphonesimulator/Spades.app
xcrun simctl launch --console booted com.example.spades
```

### Toolchain and the Docker fallback

The Makefile uses a local `swift` when one exists and otherwise falls back to a
container, so the engine loop works on Linux machines with no Swift toolchain.

- **Pin the container to the same Swift version as the Mac toolchain.** A 6.0
  container silently diverging from a newer local toolchain is a miserable class
  of bug to chase.
- The Makefile **must print which path it took** on every engine-test invocation
  (`>>> toolchain: local swift 6.x` / `>>> toolchain: docker swift:6.0-jammy`).
  Silent divergence is the thing being defended against; an unlabelled pass tells
  you nothing.
- Only the engine and economy targets can run this way. `build`, `test`, `run`
  and `lint` require macOS — SwiftUI, UIKit, GameKit and AVFoundation do not
  exist on Linux. These targets should fail with a clear message on non-macOS
  rather than a confusing linker error.

### Iteration rules

1. **Engine or economy work → `make engine-test` only.** Both targets are free of
   Apple frameworks precisely so you can compile and test them in seconds. Never
   boot a simulator to verify a scoring or stake change.
2. Run `make engine-test-full` before opening a PR. The fast target scales the
   simulations down; statistical assertions do not hold at reduced scale.
3. Only run `make build` / `make run` once engine tests are green.
4. If `xcodebuild` fails with a signing error, add
   `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`. Simulator builds do not
   need a team.
5. If the simulator name is wrong, list what exists:
   `xcrun simctl list devices available`.
6. If `xcbeautify` is missing, pipe to `cat` rather than letting xcodebuild's raw
   output flood the context.

### Never do these

- Never hand-edit `Spades.xcodeproj/project.pbxproj`. Edit `project.yml`, run
  `make project`. The `.xcodeproj` is gitignored and regenerated.
- Never add a dependency without adding it to `project.yml` or `Package.swift`.
- Never commit anything under `.build/`, `DerivedData/`, or `*.xcuserdata`.

---

## 4. Architecture rules

### Purity

**`SpadesEngine` and `SpadesEconomy` are pure and deterministic.** They import
only `Foundation`. No `UIKit`, no `SwiftUI`, no `AVFoundation`, no `GameKit`, no
singletons.

Specifically banned anywhere under `Packages/SpadesEngine/Sources/`:

- `Date()` — current time enters as an injected value, never read.
- `Calendar` / `TimeZone` / `DateFormatter` — see the calendar boundary below.
- `Task.sleep` — pacing is a presentation concern.
- Direct RNG. Randomness enters through an injected `RandomNumberGenerator`.
- Dictionary or Set iteration where order affects output. This leaks
  non-determinism that only shows up across runs.

`make ci` runs a **purity check**: a grep over `Sources/` for `Date(`, `Calendar`,
`import UIKit|SwiftUI|GameKit|AVFoundation`, failing the build on a hit. Enforce
it mechanically; a rule this easy to violate by accident will not survive on
discipline alone.

### The calendar boundary

The daily bonus is inherently calendar-shaped, and that is exactly why the
calendar arithmetic does not live in the package.

`SpadesEconomy` takes the day-key and the monotonic reference as **inputs**:

```swift
public func evaluateDailyBonus(
    dayKey: String,              // "yyyy-MM-dd", already resolved by the caller
    lastClaimDayKey: String?,
    currentStreak: Int,
    monotonicNow: UInt64,        // e.g. clock uptime, never wall time
    lastClaimMonotonic: UInt64?
) -> DailyBonusResult
```

Deriving `dayKey` from `Calendar.current` is `DailyBonusService`'s job, in the
app layer. If `Calendar.current` leaks into the package, the clock-rollback test
is exercising the wrong layer and the engine stops being reproducible across
timezones — a test suite that passes in one CI region and fails in another.

### Module boundaries

`Package.swift` declares two library targets. **`SpadesEconomy` does not depend
on `SpadesEngine`, and `SpadesEngine` does not depend on `SpadesEconomy`.** The
app composes them: it maps an engine result into a `MatchOutcome` value and hands
that to the economy.

The target boundary is deliberate. Spades rules should not be able to reach for
stake tiers, and stake arithmetic should not be able to reach for `Trick`. A file
split inside one module relies on discipline; a target split is enforced by the
compiler for free.

### State model

```swift
public struct GameState: Equatable, Codable, Sendable { ... }
public enum GameAction: Equatable, Codable, Sendable {
    case bid(seat: Seat, bid: Bid)
    case play(seat: Seat, card: Card)
    case reaction(from: Seat, to: Seat, kind: ReactionKind)
    case chat(from: Seat, phrase: QuickPhrase)
}
public func reduce(_ state: GameState, _ action: GameAction) throws -> GameState
```

A game is a seed plus an ordered list of `GameAction`s. Everything else is
derived. This gives you free replay, free undo in practice mode, free bug reports
("attach the action log"), and a trivially syncable multiplayer payload.

`ReactionKind` and `QuickPhrase` live in `SpadesEngine` alongside `GameAction`
because they are wire format — the action enum references them, so they cannot
live in the app layer. (Spec 0.1 had this wrong; see §17.)

**The app layer owns all effects.** SwiftUI views observe an `@Observable
GameSession` that wraps the engine, drives bot turns, plays audio, fires haptics,
and talks to GameKit. Views never mutate `GameState` directly.

**Swift 6 language mode, strict concurrency on.** All engine and economy types
are `Sendable`. `GameSession` is `@MainActor`. Bot computation runs off the main
actor and returns a `GameAction`.

---

## 5. Rules engine spec

Implement exactly this. All of it must be covered by tests.

**Deal.** 52 cards, 13 each, clockwise from dealer's left. Dealer rotates each hand.

**Bidding.** Clockwise from dealer's left. Each seat bids 0–13 or nil. Team
contract is the sum of the two partners' numeric bids.

**Play.** Leader plays first; others must follow suit if able, otherwise may play
anything. Highest card of the led suit wins unless a spade is played, in which
case highest spade wins. Trick winner leads next.

**Spades broken.** A spade may not be *led* until a spade has been played on a
trick where its player could not follow suit. Exception: a seat holding only
spades may lead one. `LegalMoves.swift` is the single source of truth for this —
the UI must call it rather than reimplementing the check.

**Scoring** (`Scoring.swift`, per hand, per team):

| Outcome | Points |
|---|---|
| Contract made | `10 × bid`, **plus `1` per overtrick (bag)** |
| Contract missed | `−10 × bid` |
| Nil made | `+100` |
| Nil failed | `−100` |
| Blind nil made / failed | `+200` / `−200` |

The overtrick point is easy to drop — the bag is both a score and a counter, and
implementing only the counter passes a surprising number of naive tests. It is a
fixed regression case (§17).

Bags accumulate across hands. At 10 bags: `−100` points and subtract 10 from the
bag counter (**carry the remainder** — at 12 bags you keep 2, you do not reset).

**Configurable via `RulesConfig`,** because house rules genuinely vary and this
is where naive implementations get review complaints:

```swift
public struct RulesConfig: Codable, Sendable, Equatable {
    public var targetScore: Int = 500                 // or 250
    public var bagPenaltyThreshold: Int = 10
    public var bagPenalty: Int = 100
    public var nilTricksCountForPartner: Bool = false
    public var allowBlindNil: Bool = true
    public var blindNilRequiresDeficit: Int? = 100    // nil = always allowed
    public var mustLeadTwoOfClubs: Bool = false

    /// Minimum combined numeric bid per team. Anti-sandbagging measure.
    ///
    /// A nil bid is EXEMPT: nil is the opposite of a safe low bid, so forcing a
    /// nil bidder up to a minimum defeats the purpose of the rule.
    ///
    /// When one partner bids nil, the other partner MUST still reach the full
    /// minimum alone. This matches the most common house interpretation and
    /// keeps the rule's teeth: otherwise "partner bids nil" becomes the
    /// standard route around the minimum.
    public var minBidPerTeam: Int? = nil

    public static let standard = RulesConfig()
}
```

Both halves of the `minBidPerTeam` interpretation need explicit tests. They are
decisions, not accidents, and without tests someone will "fix" them later.

**Game end.** First team to reach `targetScore` wins. If both cross in the same
hand, higher score wins. On an exact tie, play another hand.

---

## 6. Seats, humans and bots

```swift
public enum SeatOccupant: Equatable, Codable, Sendable {
    case human(PlayerID)
    case bot(BotDifficulty, persona: BotPersona)
    case empty
}
```

The table always has exactly 4 seats. A match config declares `n` total seats
(always 4 here) and `m` human players; the remaining `4 − m` are filled with bots
at match start. Supported configurations:

- **m = 1** — solo vs three bots. Default. Must work fully offline.
- **m = 2** — two humans; partners (seats 0 & 2) or opponents. Local pass-and-play
  or online.
- **m = 3** — three humans, one bot.
- **m = 4** — full online table.

Rules that matter:

- Bots must be indistinguishable in the state machine. `reduce` does not know or
  care whether a seat is human. Only `GameSession` routes turns.
- If a human disconnects mid-hand, substitute a bot at that seat and post a
  system chat line. On reconnect within 90s, hand the seat back.
- Bot turns need artificial delay (`0.6–1.4s`, randomised) or the game feels
  broken. Delay lives in `GameSession`, never in the engine.
- Seats 0 & 2 are one team, 1 & 3 the other. Seat 0 is always the local player in
  solo/host view; rotate the render, not the model.

### Bot AI (`Bots/`)

Three difficulties, all sharing `HandEvaluator`:

- **Easy** — bids from a crude high-card count; plays a random legal card with a
  weak preference for following suit low.
- **Medium** — bids by counting sure tricks (aces, protected kings, spade length
  above 3); tracks played cards; leads long suits; ducks when partner is winning
  the trick; covers partner's nil.
- **Hard** — Medium plus void tracking per opponent, inference from bids, bag
  avoidance when the team is near the threshold, and active nil-setting when an
  opponent bids nil.

Bots must only ever choose from `LegalMoves.legalPlays(state:seat:)`.

### Team-level shading is applied ONCE

This is the pattern behind the worst bug found so far, and it will recur.

Any team-level bid adjustment — bag avoidance, nil coverage, endgame "we need N
to win", catch-up aggression — **compounds if both partners apply it
independently**. Two partners each shading up when behind produced tables bidding
14.9 tricks out of 13, so contracts were always set, teams fell further behind,
and shading escalated. Matches never reached 500.

The rule: **team-level shading is applied by the partner who bids second, with
the first partner's bid visible.** The first bidder bids their hand. Never apply
a team adjustment in two places.

The catch-up loop specifically was self-reinforcing — behind → overbid → set →
further behind. Any adjustment keyed on score deficit needs an explicit damping
term and a test that runs matches to completion, since the failure mode is
"matches never end", which a per-hand unit test cannot see.

---

## 7. Multiplayer

**v1: GameKit** (`GKMatch` real-time). Matchmaking, identity, friends, no server
bill. `MatchService.swift` is the only file that imports GameKit; everything
above it talks to a `MatchTransport` protocol so the engine and UI can be tested
with an in-memory fake.

Wire format is the `GameAction` enum encoded as JSON, plus a monotonically
increasing sequence number. Host is authoritative for shuffle and turn order.
Clients apply actions through the same `reduce` the host uses; a state hash
mismatch triggers a full state resync rather than a desync limp-along.

Do not build a custom backend in v1. If GameKit proves limiting, the
`MatchTransport` seam is where a WebSocket implementation slots in.

---

## 8. Social features

### Reactions

Five reactions, sendable from any player to any specific player (including
partners, including bots). Defined in `SpadesEngine/Social.swift`:

```swift
public enum ReactionKind: String, Codable, CaseIterable, Sendable {
    case thumbsUp, thumbsDown, laughing, crying, angry
}
```

UI: tap a seat's avatar to open a small radial or row picker; the reaction
animates from sender's seat to target's seat and lingers ~1.5s near the target.
SF Symbols cover all five — or use emoji glyphs; do not ship image assets.

### Quick chat

Fixed phrase list only. **No free-text chat in v1** — free text means you owe
users moderation, reporting, and blocking infrastructure, and App Review will ask
for it.

```swift
public enum QuickPhrase: String, Codable, CaseIterable, Sendable {
    case hi, hello, goodLuck, niceHand, wellPlayed, sorry
    case yourTurn, goodGame, thanks, oops, close, rematch
}
```

Localise the display strings; the enum case is what goes over the wire.

### Abuse controls (required, not optional)

- Rate limit: max 5 reactions + 5 phrases per player per hand. Silently drop excess.
- Per-player mute toggle, persisted locally, long-press on a seat.
- Global "hide all reactions" switch in Settings.
- `thumbsDown` and `angry` are the ones that get abused. Ship the mute before you
  ship the reactions.

Bots should occasionally send phrases too (`goodLuck` at hand start, `niceHand`
after a made nil). Roughly one per bot per hand — more reads as spam.

---

## 9. Career, points and stakes

Arithmetic lives in **`SpadesEconomy`** (pure, tested under `make engine-test`).
`CareerStore.swift` and `DailyBonusService.swift` in `App/Services` wrap it and
own persistence, `Calendar`, and the ad SDK. See §4 for the calendar boundary.

```swift
struct CareerProfile: Codable {
    var points: Int                  // career currency — never below 0
    var lifetimePointsEarned: Int
    var gamesPlayed: Int
    var gamesWon: Int
    var nilsMade: Int
    var nilsFailed: Int
    var currentStreak: Int
    var bestStreak: Int
    var lastDailyBonusClaim: Date?
    var adBonusesClaimedToday: Int
    var adBonusDayKey: String        // "yyyy-MM-dd", resolved in the app layer
}
```

### Stake tiers

Chosen in the lobby before a match. A tier is selectable only if
`points >= entry`. Winners split the pot; losers lose their stake.

| Tier | Entry | Win payout | Unlocks at |
|---|---|---|---|
| Casual | 0 | +25 | 0 |
| Bronze | 50 | +100 | 100 |
| Silver | 200 | +425 | 500 |
| Gold | 750 | +1,600 | 2,000 |
| Elite | 2,500 | +5,500 | 10,000 |

Rules:

- Points **cannot go below zero**. Clamp on loss. A player at 0 always retains
  access to Casual — never let the economy strand someone in an unplayable state.
- Solo games against bots pay **40% of the listed payout** and cost 40% of the
  entry. Otherwise bot-farming trivialises the ladder.
- Bots do not have careers. Their stake is notional.
- Quitting a ranked match mid-game forfeits the stake and takes a small streak
  penalty. Disconnection under 90s with a successful reconnect is not a quit.
- Apply the loss when the game concludes, not per hand.

### Daily bonus

Awarded on first app foreground per **calendar day** in the user's local timezone
— a day-key string, not a raw 24-hour interval since last claim. A user in IST
who plays at 11pm and again at 8am gets both days.

Escalating streak: 50 / 75 / 100 / 150 / 200 / 300 / 500 on days 1–7, then holds
at 500. Streak resets if a day is missed.

**Anti-cheat:** compare against the stored day-key AND the monotonic reference.
If wall time moves backwards relative to the last recorded claim, treat the
streak as broken rather than granting. Do not trust the device clock for grants.
Both values are inputs to `evaluateDailyBonus` (§4), so this is testable without
a device.

### Rewarded ads

`AdService.swift`. AdMob rewarded video is the pragmatic choice; keep it behind an
`AdProviding` protocol with a `StubAdService` so the app builds and tests without
the SDK.

- +100 points per completed rewarded view.
- Cap: **5 per day**, tracked via `adBonusDayKey`.
- Only ever user-initiated ("Watch for +100"). No interstitials between hands.
- Grant on the SDK's **reward callback only**, never on ad dismissal.
- Degrade gracefully with no network: hide the button, do not show an error.
- ATT prompt is required if the ad SDK uses IDFA. Request it contextually, not on
  first launch.

### Compliance note (read before shipping)

Points are for entertainment only. They must **never** be purchasable with real
money, cashable out, or transferable between players — the moment any of those is
true this stops being a casual game and becomes real-money gaming with licensing
obligations. Keep it one-way: earned by play, spent on play.

Apple classifies staking mechanics as simulated gambling, which pushes the age
rating to 17+. Set that in App Store Connect from the start.

---

## 10. Audio — Kenney (CC0)

All sound comes from Kenney's CC0 packs. CC0 is a public domain dedication: no
attribution required, no license contamination, redistribution explicitly
permitted. Credit "kenney.nl" on the about screen anyway — it costs nothing and
it is the decent thing to do.

### The processed audio is VENDORED

`App/Resources/Audio/` contains the **trimmed, normalised WAVs, committed to the
repo**. The whole set is under 1.5 MB and CC0 permits redistribution, so there is
no reason to make a fresh clone depend on a network fetch.

`Tools/fetch_audio.sh` exists as documented provenance and a regeneration path.
It is **not on the critical path of a build**. Kenney's download URLs carry a
rotating content hash, so the script has a `--list` mode and falls back to zips
dropped in `.build/audio-src/`; its filename map will likely need adjusting on
first run. That fragility is precisely why the output is committed rather than
fetched.

Source packs:

| Pack | Contents | Used for |
|---|---|---|
| **Casino Audio** | 54 sounds — 23 card handling, 19 chip, 12 dice | deal, play, shuffle, trick, chips/stake |
| **Interface Sounds** | 100 clicks, snaps, confirmations | buttons, bid confirm, toggles |
| **UI Audio** | 50 buttons, switches, generic clicks | menus, settings |

Download from `kenney.nl/assets` (filter Audio). The card-handling subset of
Casino Audio is exactly the right material for everything table-related.

### Required sound map

One enum. Never scatter filename strings through the codebase.

```swift
enum SoundEffect: String, CaseIterable {
    case shuffle, dealCard, playCard, trickWon, invalidMove
    case bidConfirm, bidNil, handComplete, gameWon, gameLost
    case buttonTap, reactionSent, chatSent, pointsAwarded, dailyBonus
}
```

Add a test asserting every `SoundEffect` case resolves to a bundled file. A
missing sound should fail CI, not fail silently in a player's hands.

### Processing (what `fetch_audio.sh` does, already applied to the vendored set)

16-bit 44.1kHz mono WAV. Trim leading silence aggressively — a 40ms lead-in on a
card sound reads as lag. Normalise to about −3 dBFS. Total budget under 1.5 MB.

Ship **3–4 variants** of `dealCard` and `playCard` and pick randomly. A single
card sound repeated 52 times during a deal is the fastest way to make a game feel
cheap.

### AudioService requirements

- Session category `.ambient` with `.mixWithOthers`. Respects the ringer switch,
  does not stop the user's music. Non-negotiable — a card game that kills
  someone's podcast earns one-star reviews.
- Preload every clip into `AVAudioPlayer` instances at launch. Construct nothing
  at play time.
- Maintain a **pool of ≥4 players per clip**, round-robin. A single player cannot
  overlap itself and staggered deals will drop sounds.
- Independent SFX / music volume, both persisted, both defaulting to on.
- Skip SFX when `secondaryAudioShouldBeSilencedHint` is true.

### Haptics

`HapticsService.swift`. For a card game these land harder than audio.

- Card played: `UIImpactFeedbackGenerator(style: .light)`
- Trick collected: `.rigid`
- Bid confirmed: `UISelectionFeedbackGenerator`
- Contract made: `UINotificationFeedbackGenerator` `.success`
- Bag penalty / set: `.warning`
- Prepare generators ahead of the interaction; unprepared ones have ~100ms latency.
- Respect a Settings toggle; skip entirely on devices without haptics.

---

## 11. Rendering and animation

**Cards are drawn, not loaded.** `CardView.swift` renders a rounded rect, rank
label, and Unicode pip glyphs (♠ ♥ ♦ ♣). No PNG, no SVG, no asset catalog entry
for any card. Infinite resolution, free dark mode, free colourblind four-colour
deck, near-zero bundle. If you find yourself wanting a card image, the answer is a
better `CardView`. Face cards use stylised monograms, not illustrations.

**Animation is code, not assets.** No Lottie, no sprite sheets in v1.

- `matchedGeometryEffect` with a stable `card.id` drives hand → table transitions.
  The single most important primitive here; get it right first.
- Deal: staggered `.delay(Double(index) * 0.04)` springs from a deck origin.
- Hand fan: `.rotationEffect` of a few degrees per card plus an arc offset,
  computed from index in `HandFanLayout.swift`.
- Card flip: `.rotation3DEffect(axis: (0, 1, 0))`, swap face for back at 90°.
- Trick collection: all four cards animate to the winning seat, slight scale-down.
- House spring: `.spring(response: 0.35, dampingFraction: 0.75)`.
- Full deal completes in **under 1.5s** and is tap-to-skip. Uninterruptible
  animation becomes irritating by game ten.

**Accessibility (required, not a nice-to-have):**

- Check `UIAccessibility.isReduceMotionEnabled` and substitute cross-fades for
  every spring. Some players get motion sickness from cards flying around.
- Every card needs a VoiceOver label ("Queen of Spades"). Every seat needs one
  reporting occupant, bid, and tricks taken.
- Dynamic Type in all non-card UI.
- Four-colour deck option (spades black, hearts red, diamonds blue, clubs green).

---

## 12. Persistence

- `CareerProfile`, `RulesConfig`, settings: JSON in Application Support via a
  `Persisting` protocol. Not UserDefaults — this is real user progress and
  deserves atomic writes and a versioned schema.
- `Persisting` must be `Sendable`. `FileManager` is not; do not hold one as
  stored state on a `Sendable` conformer. Create it at the point of use or
  isolate it.
- Include `schemaVersion` from day one and write the migration switch even when
  there is only one version.
- In-progress match state: encode `seed + [GameAction]` so a backgrounded game
  resumes exactly.
- Never store secrets or ad SDK keys in the repo. xcconfig + a gitignored
  `Secrets.xcconfig`, with a checked-in `Secrets.example.xcconfig`.

---

## 13. Testing

### Two scales, one suite

`make engine-test` scales simulations down for a ~3s loop. `make engine-test-full`
runs them at §13 scale in release, ~30s. Both run the same tests.

- **`engine-test-full` runs in CI on every PR.** Without this the fast target
  quietly becomes the only one anyone runs, and the statistical assertions decay
  into decoration.
- Tests whose assertions are only valid at full scale — the bot-strength
  comparison in particular — must **skip loudly** at reduced scale, naming
  themselves in the output. Never let a statistical test "pass" on eight samples.

### Required coverage

- **Rules:** follow-suit enforcement, spades-broken including the only-spades
  exception, trick winner across all suit/trump combinations.
- **Scoring:** made contract, set contract, **the overtrick point** (regression),
  bag accumulation, bag penalty at threshold with correct remainder carry, nil
  made, nil failed, blind nil, both settings of `nilTricksCountForPartner`.
- **`minBidPerTeam`:** nil is exempt; the non-nil partner must still reach the
  full minimum alone. Both are decisions (§5) and both need a test.
- **`Card.id` is 0–51** (regression). Assert the full round-trip and that every id
  is a valid index into a 52-element table.
- **Property test:** 10,000 seeded matches with random bots — no illegal action,
  every hand yields exactly 13 tricks, all 52 cards accounted for, scores sum.
- **Determinism:** same seed + same action list ⇒ identical final state, replayed
  twice. Catches accidental dictionary-ordering leaks.
- **Economy:** points never negative; Casual reachable at 0; daily bonus not
  claimable twice in one local day; clock rollback does not grant; ad cap at 5.
- **Bots:** 1,000 matches per difficulty, no crash, no stall, **every match
  reaches `targetScore`**. Match termination is the assertion that catches
  runaway bid inflation.

### Bidding calibration metrics

Win rate alone cannot distinguish a fixed bidding model from one that overshot
into systematic underbidding — underbidding looks healthy in win rates while
making bag penalties universal. `make sim-nightly` and the full suite must report
and assert on:

| Metric | Healthy range | Failure it catches |
|---|---|---|
| Mean total table bid per hand | **12.5 – 14.0** | Inflation (was 14.9) or overcorrected underbidding |
| Set frequency per team per hand | **0.15 – 0.35** | Contracts always made (too timid) or always set |
| Mean hands per match to 500 | **8 – 14** | Miscalibrated scoring or bidding, even when matches terminate |
| Mean bags per team per match | **4 – 12** | Systematic underbidding hiding behind a fine win rate |

Real tables land near 13 because everyone shades slightly optimistic. A table
averaging 11.5 is broken in the other direction from where it started.

### Difficulty ladder

Current: hard beats medium **54.7%** over 1,200 matches — about 3.3 standard
errors above even, so real, not noise. Trick-taking games with random deals
compress skill edges, so a modest edge here may be honest.

The open question is whether it is *perceptible*, and the diagnostic is
**hard vs easy**. If that also lands near 55%, the tiers are not differentiated
and Easy is not easy enough for a new player's first ten games — which is where
retention is won or lost. Track hard-vs-easy and medium-vs-easy as named
assertions, not just hard-vs-medium.

### Nightly sweep

`make sim-nightly` runs the simulations with a **rotating seed set**, not the
fixed seeds used in CI.

Fixed seeds are a regression net — valuable, and they must stay — but they
re-test the same 10,000 paths forever and stop finding anything new. Rotating
seeds are what actually searches. On failure the job must **print the offending
seed** so it can be pinned as a permanent regression case in the fixed set.

### App-layer tests

One UI smoke test: launch, start a solo Casual game, play a full hand via
accessibility identifiers, assert the score screen appears. These require macOS.

Write the test before the fix for any reported bug. Attach the failing seed.

---

## 14. Code style

- Swift 6 language mode, strict concurrency, warnings as errors in CI.
- SwiftLint config at repo root; `make lint` must pass.
- `swift-format` for formatting. 4-space indent, 100-column soft limit.
- Value types by default. Reference types need a stated reason.
- No force unwraps outside tests. No `try!`. No `fatalError` in shipping paths
  except genuinely unreachable `default` cases; prefer exhaustive switches.
- No singletons in the engine. App-layer services are injected via the SwiftUI
  environment, not accessed through `.shared`.
- Public engine API gets doc comments. Where a doc comment records a *decision*
  (as `minBidPerTeam` does), that is load-bearing — do not strip it.
- Comments explain *why*. The code already says what.

---

## 15. Things that commonly go wrong here

**Already hit and fixed — keep the regression tests:**

- **`Card.id` out of range.** It returned 0–53, not 0–51, and crashed on first use
  as a table index.
- **Dropped overtrick point.** §5 is `10 × bid` *plus 1 per bag*; counting only
  the bag passes naive tests.
- **Double-applied team shading.** See §6. The general pattern: any team-level
  adjustment applied independently by both partners compounds. Nil coverage and
  endgame "we need N" bidding have the same shape.
- **Self-reinforcing catch-up bidding.** Behind → overbid → set → further behind.
  Needs damping and a match-completion test; per-hand tests cannot see it.

**Still live:**

- **Reimplementing legality in the UI.** The view asks `LegalMoves.legalPlays` and
  greys out the rest. Two implementations means two behaviours.
- **Bag remainder reset.** At 12 bags the penalty fires and you carry 2, not 0.
- **Timezone in the daily bonus.** User's calendar day, not elapsed hours.
- **`Calendar` or `Date()` creeping into `Sources/`.** The purity check in
  `make ci` exists because this is easy to do by accident.
- **Blocking the main actor with bot search.** Hard bots doing void inference on
  the main thread will drop frames. Compute off-actor, deliver on.
- **Audio session `.playback`.** Wrong category; it will get reported.
- **Rendering seats absolutely.** Always render relative to the local player's
  seat so seat 0 is at the bottom on every client.
- **Granting ad rewards on dismissal.** Only the SDK's reward callback counts.

---

## 16. Known debt

- **App layer has never been compiled.** See §0.
- **`@preconcurrency import GameKit`** in `MatchService.swift` is a stopgap for
  incomplete Sendable annotations upstream. It carries a `// TODO` — revisit when
  GameKit's annotations improve. Do not let it spread to other files or become
  the default way of silencing concurrency diagnostics.
- **`fetch_audio.sh` unrun.** Its filename map is a best guess. Low risk now that
  the processed audio is vendored (§10), but it will need a pass before anyone
  regenerates.
- **Bot difficulty spread unvalidated below hard-vs-medium.** See §13.

---

## 17. Amendments (0.1 → 0.2)

Recorded so the spec stops drifting from the code.

| # | Change | Reason |
|---|---|---|
| 1 | `Social.swift` added to `SpadesEngine` | 0.1 self-contradicted: `GameAction` referenced `ReactionKind`/`QuickPhrase` while the tree placed them nowhere in the engine. Wire format belongs with the action enum. |
| 2 | `SpadesEconomy` added as a **second target** | Keeps economy tests in `swift test` instead of behind a simulator. Made a target rather than a file so the module boundary is compiler-enforced. |
| 3 | Calendar boundary specified (§4) | Economy in the package would otherwise breach 0.1's no-`Date()` rule. Day-key and monotonic reference are now inputs. |
| 4 | `engine-test` / `engine-test-full` split | 0.1's §3 (~2s) and §13 (10,000 matches) were in direct conflict. |
| 5 | `engine-test-full` wired into CI; loud skips at reduced scale | Otherwise the fast target becomes the only one run. |
| 6 | `make sim-nightly` with rotating seeds | Fixed seeds are a regression net, not a search. |
| 7 | `minBidPerTeam` semantics fixed in doc + tests | Unspecified in 0.1. Nil exempt; non-nil partner still meets the full minimum. |
| 8 | Bidding calibration metrics table (§13) | Win rate cannot distinguish a fix from an overcorrection into underbidding. |
| 9 | Audio vendored; `fetch_audio.sh` off the build path | CC0 permits redistribution, the set is <1.5 MB, and Kenney's URLs rotate a content hash. Hermetic builds beat a network dependency. |
| 10 | Docker fallback documented, version-pinned, path printed | Silent toolchain divergence is hard to diagnose later. |
| 11 | Purity check added to `make ci` | The `Sources/` import and `Date`/`Calendar` rules are too easy to break on discipline alone. |
| 12 | Team-shading-applied-once rule (§6) | Generalises the bug that made matches non-terminating. |
| 13 | §0 status, §16 known debt, this table | The app layer being uncompiled is the single most important fact about this repo right now. |

---

## 18. Working agreement

- Prefer small, reviewable changes. One feature per branch.
- Run `make engine-test` before every commit, `make engine-test-full` before every PR.
- If a change touches `RulesConfig`, `Scoring`, or `SpadesEconomy`, add or update
  tests in the same commit — no exceptions.
- If you need a new third-party dependency, ask first. The current answer for
  anything that is not the ad SDK is almost certainly no.
- **If this file and the code disagree, say so rather than silently picking one.**
  Three of the amendments above came from exactly that, and each was a spec bug.