# Spades

A native iOS Spades game. Four seats, two partnerships, 13-card hands, spades
always trump. Any seat can be a human or a bot, so solo play, pass-and-play and
online multiplayer all run through one code path.

See [CLAUDE.md](CLAUDE.md) for the full specification this implements.

## Layout

```
Packages/SpadesEngine/   pure Swift rules engine — imports only Foundation
App/                     SwiftUI app: views, services, rendering
Tests/                   app unit tests and the UI smoke test
Tools/fetch_audio.sh     downloads and renders the Kenney CC0 audio
project.yml              XcodeGen manifest — edit this, never the .pbxproj
```

## Getting started

```bash
make bootstrap      # xcodegen, swiftlint, swift-format, and the audio packs
make project        # regenerate Spades.xcodeproj
make engine-test    # ~3s — the primary iteration loop
make run            # build, boot the simulator, install, launch
make help           # everything else
```

## The engine

`SpadesEngine` imports only `Foundation`: no UIKit, no SwiftUI, no clock, no
system RNG. A match is a seed plus an ordered list of `GameAction`, and
everything else is derived. That buys free replay, free undo, "attach the action
log" bug reports, and a multiplayer payload that is just the action enum as JSON.

Because it has no Apple framework dependencies, it builds and tests anywhere
Swift runs — no Xcode and no simulator. `make engine-test` uses the local
toolchain if there is one and falls back to the official `swift:6.0-jammy`
container otherwise, so the engine loop works on a Linux box too.

### Test scale

`make engine-test` runs the simulations at reduced scale so the loop stays
around three seconds. `make engine-test-full` runs them at the full scale §13
asks for — 10,000 property-test matches, 1,000 per difficulty, every house-rule
combination — in release, in about thirty seconds. `make test` runs the full
scale before touching the app targets, so that is what CI and pre-PR checks get.

The reduced scale is a fast-feedback convenience, not a lower bar: everything
except the statistical bot-strength comparison asserts identically at both
scales, and that one comparison says so explicitly rather than passing on eight
samples.

## Cards are drawn, not loaded

There are no card images in this repo and none should be added. `CardView`
renders a rounded rect, rank labels and Unicode pips; face cards are stylised
monograms. This is what gives the game infinite resolution, free dark mode, a
free four-colour deck for colourblind players, and a near-zero bundle.

## Points

Points are entertainment currency, earned by play and spent on play. They are
never purchasable with real money, never cashable out, and never transferable.
Staking mechanics put the App Store age rating at 17+; set that in the
questionnaire from the start.

## Audio

All sound is from Kenney's CC0 packs, rendered by `Tools/fetch_audio.sh` to
16-bit 44.1 kHz mono WAV, trimmed hard at the front and peak-normalised. Credit
appears on the about screen — CC0 does not require it, but it costs nothing.
