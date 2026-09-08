# Spades

A native iOS Spades game. Four seats, two partnerships, 13-card hands, spades
always trump. Any seat can be a human or a bot, so solo play, pass-and-play and
online multiplayer all run through one code path.

See [CLAUDE.md](CLAUDE.md) for the specification this implements.

## Status

| Layer | State |
|---|---|
| `SpadesEngine` | Built, tested |
| `SpadesEconomy` | Built, tested |
| App layer (SwiftUI / GameKit / AVFoundation) | **Written, never compiled** |
| `App/Resources/Audio` | Vendored, 21 clips, 971 KB |

128 tests green across the two pure targets. The app layer has only been
syntax-parsed — a first compile on a Mac will surface type errors, most likely
in `GameSession`, `MatchService` and `AudioService`, where actor isolation meets
framework callbacks.

## Layout

```
Packages/SpadesEngine/
  Sources/SpadesEngine/    rules, bots, wire format — Foundation only
  Sources/SpadesEconomy/   stakes, points, bonuses — Foundation only
App/                       SwiftUI app: views, services, rendering
Tests/                     app unit tests and the UI smoke test
Tools/                     purity check, audio regeneration
project.yml                XcodeGen manifest — edit this, never the .pbxproj
```

`SpadesEngine` and `SpadesEconomy` are separate targets with **no dependency in
either direction**. The app composes them: it maps an engine result into a
`MatchOutcome` and hands that to the economy. Spades rules cannot reach for
stake tiers, and stake arithmetic cannot reach for `Trick` — the compiler
enforces it, so no one has to remember.

## Getting started

```bash
make bootstrap       # xcodegen, swiftlint, xcbeautify
make project         # regenerate Spades.xcodeproj
make engine-test     # ~3s — the primary iteration loop
make engine-test-full # ~35s — full §13 scale, release
make run             # build, boot the simulator, install, launch
make ci              # lint + purity-check + engine-test-full + test
make help            # everything else
```

Both pure targets import only Foundation, so they build and test anywhere Swift
runs — no Xcode, no simulator. `make engine-test` uses a local toolchain when
one exists and otherwise falls back to a pinned container, and **prints which
path it took** on every invocation. Targets that genuinely need macOS (`build`,
`test`, `run`, `lint`) fail with a message saying so rather than a linker error.

## Purity is enforced, not agreed

`make purity-check` greps the pure targets for anything that would make them
non-deterministic: `Date()`, `Calendar`, framework imports, `Task.sleep`, the
system RNG, singletons, and a cross-import between the two modules. Every rule
has been checked to actually fire — a rule that cannot fail is decoration.

The calendar boundary is the subtle one. The daily bonus is inherently
calendar-shaped, which is exactly why `SpadesEconomy` takes a day-key string and
a monotonic reading as *inputs*; `CalendarClock` in the app layer is the only
place that reads `Calendar.current`. That keeps the clock-rollback rule testable
without a device and stops the suite passing in one CI region and failing in
another.

## Test scale

`make engine-test` scales the simulations down for a ~3s loop. `make
engine-test-full` runs them at §13 scale in release and is what `make ci` uses.

Tests whose assertions need a real sample — the bidding calibration and the
difficulty ladder — **skip loudly at reduced scale**, naming themselves:

```
>>> SKIPPED at reduced scale: hard vs medium win rate
>>>   2 matches, needs 200. Run `make engine-test-full`.
```

`make sim-nightly` runs the same suite with a rotating seed base rather than the
fixed CI seeds. Fixed seeds are a regression net; rotating seeds are what
actually searches. A failure prints the offending seed so it can be pinned.

## Bot calibration

Measured over 800 matches per difficulty:

| | table bid | set freq | hands/match | bags/team/match |
|---|---|---|---|---|
| target (§13) | 12.5–14.0 | 0.15–0.35 | 8–14 | 4–12 |
| hard | 12.80 | 0.322 | 14.11 | 7.63 |
| medium | 12.87 | 0.330 | 14.38 | 7.82 |
| easy | 10.82 | 0.216 | 27.84 | 35.97 |

Hard sits inside every range. Medium is marginally over on hands-per-match, and
easy is outside three of them by design — a table that underbids is what "easy"
means. See the note in `CalibrationTests` for why the hands-per-match gap is not
closable by tuning: the evaluator is unbiased but has a ~1 trick mean absolute
error, and shading bids down to cut sets breaks three of the four metrics
instead of one.

Difficulty ladder over 8,000 matches per pair: hard beats medium 55.1%
(z = 9.1), medium beats easy 99.9%, hard beats easy 100.0%.

## Cards are drawn, not loaded

There are no card images in this repo and none should be added. `CardView`
renders a rounded rect, rank labels and Unicode pips; face cards are stylised
monograms. Infinite resolution, free dark mode, a free four-colour deck for
colourblind players, and a near-zero bundle.

## Audio

`App/Resources/Audio` holds 21 clips rendered from Kenney's CC0 packs — 16-bit
44.1 kHz mono WAV, leading silence trimmed hard, peak-normalised to −3 dBFS,
971 KB of a 1.5 MB budget. They are **committed**: CC0 explicitly permits
redistribution and a hermetic build beats a network dependency.

`Tools/fetch_audio.sh` regenerates them and is not on the build path. Kenney's
URLs carry a rotating content hash, so it scrapes the current link from each
asset page; `--list` shows what the packs contain and `--verify` checks the
vendored set against the sound map.

Credit appears on the about screen. CC0 does not require it; it costs nothing.

## Points

Points are entertainment currency, earned by play and spent on play. They are
never purchasable with real money, never cashable out, and never transferable.
Staking mechanics put the App Store age rating at 17+; set that in the
questionnaire from the start.
