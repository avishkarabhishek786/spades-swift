# CLAUDE.md — Spades (iOS / Swift)

Project instructions for Claude Code. Read this before making changes.

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
│   └── SpadesEngine/            # pure Swift, zero Apple framework imports
│       ├── Package.swift
│       ├── Sources/SpadesEngine/
│       │   ├── Card.swift
│       │   ├── Deck.swift
│       │   ├── Seat.swift
│       │   ├── Bid.swift
│       │   ├── Trick.swift
│       │   ├── HandState.swift
│       │   ├── GameState.swift
│       │   ├── RulesConfig.swift
│       │   ├── Scoring.swift
│       │   ├── LegalMoves.swift
│       │   └── Bots/
│       │       ├── BotPlayer.swift
│       │       ├── BotDifficulty.swift
│       │       └── HandEvaluator.swift
│       └── Tests/SpadesEngineTests/
├── App/
│   ├── SpadesApp.swift
│   ├── Features/
│   │   ├── Table/               # main game screen
│   │   ├── Bidding/
│   │   ├── Lobby/               # seat config, stake selection
│   │   ├── Career/              # profile, points, history
│   │   └── Social/              # reactions + quick chat
│   ├── Services/
│   │   ├── AudioService.swift
│   │   ├── HapticsService.swift
│   │   ├── CareerStore.swift
│   │   ├── DailyBonusService.swift
│   │   ├── AdService.swift
│   │   └── MatchService.swift   # GameKit wrapper
│   ├── Rendering/
│   │   ├── CardView.swift       # programmatic card face
│   │   ├── CardBackView.swift
│   │   ├── HandFanLayout.swift
│   │   └── Theme.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Audio/               # Kenney CC0 WAVs — see §10
└── Tools/
    └── fetch_audio.sh           # downloads + trims Kenney packs
```

---

## 3. Build, run, test

**Always go through the Makefile.** Do not invent one-off `xcodebuild`
invocations; if you need a new operation, add a target to the Makefile.

```bash
make bootstrap     # brew install xcodegen swiftlint; ./Tools/fetch_audio.sh
make project       # xcodegen generate  (run after ANY project.yml change)
make engine-test   # swift test in Packages/SpadesEngine  — FAST, use constantly
make build         # xcodebuild build for simulator
make test          # engine tests + app unit tests + UI smoke test
make run           # build, boot sim, install, launch
make lint          # swiftlint --strict
make clean
```

Underlying commands, for reference:

```bash
# Engine only — no simulator, ~2s. This is your primary iteration loop.
cd Packages/SpadesEngine && swift test

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

### Iteration rules

1. **Engine work → `make engine-test` only.** SpadesEngine has no Apple framework
   dependencies precisely so you can compile and test it in seconds without a
   simulator. Never boot a simulator to verify a scoring change.
2. Only run `make build` / `make run` once engine tests are green.
3. If `xcodebuild` fails with a signing error, add
   `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`. Simulator builds do not
   need a team.
4. If the simulator name is wrong, list what exists:
   `xcrun simctl list devices available`.
5. `xcbeautify` is optional; if it is missing, pipe to `cat` rather than letting
   xcodebuild's raw output flood the context.

### Never do these

- Never hand-edit `Spades.xcodeproj/project.pbxproj`. Edit `project.yml`, run
  `make project`. The `.xcodeproj` is gitignored and regenerated.
- Never add a dependency without adding it to `project.yml` or `Package.swift`.
- Never commit anything under `.build/`, `DerivedData/`, or `*.xcuserdata`.

---

## 4. Architecture rules

**SpadesEngine is pure and deterministic.** It imports only `Foundation`. No
`UIKit`, no `SwiftUI`, no `AVFoundation`, no singletons, no `Date()`, no
`Task.sleep`, no direct RNG. Randomness enters through an injected
`RandomNumberGenerator`; time enters through an injected clock. This is what
makes the engine testable and replayable.

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
derived. This gives you free replay, free undo in practice mode, free bug
reports ("attach the action log"), and a trivially syncable multiplayer payload.

**The app layer owns all effects.** SwiftUI views observe an `@Observable
GameSession` that wraps the engine, drives bot turns, plays audio, fires
haptics, and talks to GameKit. Views never mutate `GameState` directly.

**Swift 6 language mode, strict concurrency on.** `GameState` and all engine
types are `Sendable`. `GameSession` is `@MainActor`. Bot computation runs off the
main actor and returns a `GameAction`.

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
| Contract made | `10 × bid`, plus `1` per overtrick (bag) |
| Contract missed | `−10 × bid` |
| Nil made | `+100` |
| Nil failed | `−100` |
| Blind nil made / failed | `+200` / `−200` |

Bags accumulate across hands. At 10 bags: `−100` points and subtract 10 from the
bag counter (carry the remainder, do not reset to zero).

**Configurable via `RulesConfig`,** because house rules genuinely vary and this
is where naive implementations get review complaints:

```swift
public struct RulesConfig: Codable, Sendable, Equatable {
    public var targetScore: Int = 500                 // or 250
    public var bagPenaltyThreshold: Int = 10
    public var bagPenalty: Int = 100
    public var nilTricksCountForPartner: Bool = false // tricks taken by a failed nil bidder
    public var allowBlindNil: Bool = true
    public var blindNilRequiresDeficit: Int? = 100    // nil = always allowed
    public var mustLeadTwoOfClubs: Bool = false
    public var minBidPerTeam: Int? = nil              // e.g. 4 in some house rules
    public static let standard = RulesConfig()
}
```

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
- **m = 2** — two humans; they may be partners (seats 0 & 2) or opponents.
  Local pass-and-play or online.
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

Bots must only ever choose from `LegalMoves.legalPlays(state:seat:)`. Add a test
asserting that across 10,000 simulated games no bot ever emits an illegal action.

---

## 7. Multiplayer

**v1: GameKit** (`GKMatch` real-time). It gives you matchmaking, identity,
friends, and no server bill. `MatchService.swift` is the only file that imports
GameKit; everything above it talks to a `MatchTransport` protocol so the engine
and UI can be tested with an in-memory fake.

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
partners, including bots):

`thumbsUp`, `thumbsDown`, `laughing`, `crying`, `angry`

```swift
public enum ReactionKind: String, Codable, CaseIterable, Sendable {
    case thumbsUp, thumbsDown, laughing, crying, angry
}
```

UI: tap a seat's avatar to open a small radial or row picker; the reaction
animates from sender's seat to target's seat and lingers ~1.5s near the target.
SF Symbols cover all five (`hand.thumbsup.fill`, `hand.thumbsdown.fill`,
`face.smiling.inverse`, etc.) — or use emoji glyphs; do not ship image assets.

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
after a made nil). Keep it rare — roughly one per bot per hand — or it reads as spam.

---

## 9. Career, points and stakes

`CareerStore.swift`. Local persistence in v1 (see §12), with the schema designed
so it can move to CloudKit or GameKit later without migration pain.

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
    var adBonusDayKey: String        // "yyyy-MM-dd" in user's local calendar
}
```

### Stake tiers

Stake is chosen in the lobby before a match. A tier is only selectable if
`points >= entry`. Winners split the pot; losers lose their stake.

| Tier | Entry | Win payout | Unlocks at |
|---|---|---|---|
| Casual | 0 | +25 | 0 |
| Bronze | 50 | +100 | 100 |
| Silver | 200 | +425 | 500 |
| Gold | 750 | +1,600 | 2,000 |
| Elite | 2,500 | +5,500 | 10,000 |

Rules:

- Points **cannot go below zero**. If a loss would take a player negative, clamp
  to 0. A player at 0 always retains access to the Casual tier — never let the
  economy trap someone in an unplayable state.
- Solo games against bots pay **40% of the listed payout** and cost 40% of the
  entry. Otherwise bot-farming trivialises the ladder.
- Bots do not have careers. Their stake is notional.
- A player who quits a ranked match mid-game forfeits their stake and takes a
  small streak penalty. Disconnection under 90s with a successful reconnect does
  not count as quitting.
- Apply the loss when the game concludes, not per hand.

### Daily bonus

`DailyBonusService.swift`. Awarded on first app foreground per calendar day
(user's local timezone, `Calendar.current`, day-key string — **not** a raw
24-hour interval since last claim).

Escalating streak: 50 / 75 / 100 / 150 / 200 / 300 / 500 on days 1–7, then holds
at 500. Streak resets if a day is missed.

**Anti-cheat:** compare against a stored day-key AND a monotonic reference. If
`Date()` moves backwards relative to the last recorded claim, treat the streak as
broken rather than granting a bonus. Do not trust the device clock for grants.

### Rewarded ads

`AdService.swift`. Google AdMob rewarded video is the pragmatic choice; keep it
behind an `AdProviding` protocol with a `StubAdService` so the app builds and
tests without the SDK.

- +100 points per completed rewarded view.
- Cap: **5 per day**, tracked via `adBonusDayKey`.
- Only ever user-initiated ("Watch for +100"). No interstitials between hands.
- Grant the reward on the SDK's reward callback only, never on ad dismissal.
- Must degrade gracefully with no network: hide the button, do not show an error.
- App Tracking Transparency prompt is required if the ad SDK uses IDFA. Request it
  contextually, not on first launch.

### Compliance note (read before shipping)

Points are for entertainment only. They must **never** be purchasable with real
money, cashable out, or transferable between players — the moment any of those is
true this stops being a casual game and becomes real-money gaming with licensing
obligations. Keep it one-way: earned by play, spent on play.

Apple classifies staking mechanics as simulated gambling, which pushes the age
rating to 17+. Set that in the App Store Connect questionnaire from the start.

---

## 10. Audio — Kenney (CC0)

All sound comes from Kenney's CC0 packs. CC0 means public domain dedication: no
attribution required, no license contamination, safe for a commercial app.
Credit "kenney.nl" on the about screen anyway — it costs nothing and it is the
decent thing to do.

Packs to pull (`Tools/fetch_audio.sh` automates this):

| Pack | Contents | Used for |
|---|---|---|
| **Casino Audio** | 54 sounds — 23 card handling, 19 chip, 12 dice | deal, play, shuffle, trick, chips/stake |
| **Interface Sounds** | 100 clicks, snaps, confirmations | buttons, bid confirm, toggles |
| **UI Audio** | 50 buttons, switches, generic clicks | menus, settings |

Download from `kenney.nl/assets` (filter Audio). Prefer the card-handling subset
of Casino Audio for everything table-related — it is exactly the right material
for this game.

### Required sound map

Define one enum, never scatter filename strings through the codebase:

```swift
enum SoundEffect: String, CaseIterable {
    case shuffle, dealCard, playCard, trickWon, invalidMove
    case bidConfirm, bidNil, handComplete, gameWon, gameLost
    case buttonTap, reactionSent, chatSent, pointsAwarded, dailyBonus
}
```

### Processing

Convert Kenney's OGG/WAV to 16-bit 44.1kHz mono WAV, trim leading silence
aggressively (a 40ms lead-in on a card sound reads as lag), and normalise to
about −3 dBFS. `ffmpeg` one-liner lives in `fetch_audio.sh`. Total audio budget
under 1.5 MB.

For `dealCard` and `playCard`, ship **3–4 variants** and pick randomly each time.
A single card sound repeated 52 times during a deal is the fastest way to make a
game feel cheap.

### AudioService requirements

- Session category `.ambient` with `.mixWithOthers`. This respects the ringer
  switch and does not stop the user's music. Non-negotiable — a card game that
  kills someone's podcast earns one-star reviews.
- Preload every clip into `AVAudioPlayer` instances at launch. Construct nothing
  at play time.
- Maintain a **pool of ≥4 players per clip**, round-robin. A single player cannot
  overlap itself and staggered deals will drop sounds.
- Independent SFX / music volume, both persisted, both defaulting to on.
- Duck or skip SFX when `AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint`
  is true.

### Haptics

`HapticsService.swift`. For a card game these land harder than audio.

- Card played: `UIImpactFeedbackGenerator(style: .light)`
- Trick collected: `.rigid`
- Bid confirmed: `UISelectionFeedbackGenerator`
- Contract made: `UINotificationFeedbackGenerator` `.success`
- Bag penalty / set: `.warning`
- Prepare generators ahead of the interaction; unprepared generators have ~100ms latency.
- Respect a Settings toggle and skip entirely on devices without haptics.

---

## 11. Rendering and animation

**Cards are drawn, not loaded.** `CardView.swift` renders a rounded rect, rank
label, and Unicode pip glyphs (♠ ♥ ♦ ♣). No PNG, no SVG, no asset catalog entry
for any card. This gives infinite resolution, free dark mode, free colourblind
four-colour deck, and a near-zero bundle. If you find yourself wanting a card
image, the answer is a better `CardView`.

Face cards use stylised monograms, not illustrations.

**Animation is code, not assets.** No Lottie, no sprite sheets in v1.

- `matchedGeometryEffect` with a stable `card.id` drives hand → table transitions.
  This is the single most important animation primitive here; get it right first.
- Deal: staggered `.delay(Double(index) * 0.04)` springs from a deck origin.
- Hand fan: `.rotationEffect` of a few degrees per card plus an arc offset,
  computed from index in `HandFanLayout.swift`.
- Card flip: `.rotation3DEffect(axis: (0, 1, 0))`, swap face for back at 90°.
- Trick collection: all four cards animate to the winning seat with a slight
  scale-down.
- House spring: `.spring(response: 0.35, dampingFraction: 0.75)`.
- Full deal must complete in **under 1.5s** and be tap-to-skip. Uninterruptible
  animation becomes irritating by game ten.

**Accessibility (required, not a nice-to-have):**

- Check `UIAccessibility.isReduceMotionEnabled` and substitute cross-fades for
  every spring. Some players get motion sickness from cards flying around.
- Every card needs a VoiceOver label ("Queen of Spades"). Every seat needs one
  reporting occupant, bid, and tricks taken.
- Support Dynamic Type in all non-card UI.
- Offer a four-colour deck option (spades black, hearts red, diamonds blue,
  clubs green) for colourblind players.

---

## 12. Persistence

- `CareerProfile`, `RulesConfig`, and settings: JSON in Application Support via a
  `Persisting` protocol. Not UserDefaults — this is real user progress and it
  deserves atomic writes and a versioned schema.
- Include `schemaVersion` from day one and write the migration switch even when
  there is only one version.
- In-progress match state: encode `seed + [GameAction]` so a backgrounded game
  resumes exactly.
- Never store secrets or ad SDK keys in the repo. Use xcconfig + a gitignored
  `Secrets.xcconfig`, with a checked-in `Secrets.example.xcconfig`.

---

## 13. Testing

`make engine-test` must stay green at all times. Required coverage:

- **Rules:** follow-suit enforcement, spades-broken including the only-spades
  exception, trick winner determination across all suit/trump combinations.
- **Scoring:** made contract, set contract, overtricks, bag accumulation, bag
  penalty at threshold with correct remainder carry, nil made, nil failed, blind
  nil, and both settings of `nilTricksCountForPartner`.
- **Property test:** 10,000 seeded games with random bots — assert no illegal
  action, every hand yields exactly 13 tricks, all 52 cards accounted for, and
  scores sum correctly.
- **Determinism:** same seed + same action list ⇒ identical final state. Run it
  twice in the same test to catch accidental dictionary-ordering leaks.
- **Economy:** points never go negative; Casual tier always reachable at 0;
  daily bonus cannot be claimed twice in one local day; clock-rollback does not
  grant a bonus; ad cap holds at 5.
- **Bots:** each difficulty completes 1,000 games without crashing or stalling.

UI tests: one smoke test that launches, starts a solo Casual game, plays a full
hand via accessibility identifiers, and asserts the score screen appears.

Write the test before the fix for any reported bug. Attach the failing seed.

---

## 14. Code style

- Swift 6 language mode, strict concurrency, warnings as errors in CI.
- SwiftLint config at repo root; `make lint` must pass.
- `swift-format` for formatting. 4-space indent, 100-column soft limit.
- Value types by default. Reference types need a stated reason.
- No force unwraps outside tests. No `try!`. No `fatalError` in shipping paths
  except genuinely unreachable `default` cases, and prefer exhaustive switches.
- No singletons in the engine. Services in the app layer are injected via the
  SwiftUI environment, not accessed through `.shared`.
- Public engine API gets doc comments. Private helpers do not need them.
- Comments explain *why*. The code already says what.

---

## 15. Things that commonly go wrong here

- **Reimplementing legality in the UI.** The view must ask
  `LegalMoves.legalPlays` and grey out everything else. Two implementations means
  two behaviours.
- **Bag remainder reset.** At 12 bags the penalty fires and you carry 2, not 0.
- **Timezone in the daily bonus.** Use the user's calendar day, not elapsed hours.
  A user in IST who plays at 11pm and again at 8am should get both days.
- **Blocking the main actor with bot search.** Hard bots doing void inference on
  the main thread will drop frames. Compute off-actor, deliver the action back on.
- **Audio session `.playback`.** It is the wrong category and it will get reported.
- **Rendering seats absolutely.** Always render relative to the local player's
  seat so seat 0 is at the bottom of every client's screen.
- **Granting ad rewards on dismissal.** Only the SDK's reward callback counts.

---

## 16. Working agreement

- Prefer small, reviewable changes. One feature per branch.
- Run `make engine-test` before every commit, `make test` before every PR.
- If a change touches `RulesConfig` or `Scoring`, add or update tests in the same
  commit — no exceptions.
- If you need a new third-party dependency, ask first. The current answer for
  anything that is not the ad SDK is almost certainly no.
- If a requirement in this file conflicts with what you are asked to do, say so
  rather than silently picking one.