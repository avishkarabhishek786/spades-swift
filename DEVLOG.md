# Development log

A record of what was built, what broke, and what was measured. The numbers here
are expensive to reproduce — several took multi-thousand-match simulation runs —
so they are written down rather than left in a terminal.

Kept in reverse-chronological order: newest session first.

Conventions:

- **Win rate** always means the stronger side's share, with the two partnerships
  swapped on alternate matches so a seat advantage cannot masquerade as bot
  strength.
- **Table bid** is the sum of both teams' numeric contracts in one hand. Thirteen
  tricks exist, so a healthy table lands slightly under 13 — everyone shades a
  little optimistic.
- All simulations are seeded and reproducible. A failing seed is always printed.

---

## 2026-09-08 — Spec 0.2

Commit `1df101a`. Applied the thirteen amendments in CLAUDE.md §17.

### Shipped

- `SpadesEconomy` split out as a second library target. Neither it nor
  `SpadesEngine` depends on the other; the app composes them by mapping an engine
  result into a `MatchOutcome`.
- Calendar boundary: `evaluateDailyBonus` takes day-keys and a monotonic reading
  as inputs. `App/Services/CalendarClock.swift` is the only place that reads
  `Calendar.current`.
- `Tools/purity_check.sh`, wired into `make ci`.
- Makefile: toolchain reporting and pinning, macOS guards, `ci`, `ci-portable`,
  `purity-check`, `sim-nightly` with a rotating `SPADES_SEED_BASE`.
- Bidding calibration assertions, loud skips at reduced scale, regression tests
  for `Card.id` and both halves of `minBidPerTeam`.
- 21 audio clips rendered from Kenney's CC0 packs and committed (971 KB).

Test count 119 → 128.

### Bug: a purity rule that could never fire

The first version of `purity_check.sh` had one `scan` helper taking an optional
directory in position 3 and `grep -v` filters after it. The RNG rule passed its
filter (`using:`) in that position, so it scanned a *directory named `using:`*,
found nothing, and reported clean forever.

Found by probing each rule with a deliberate violation rather than trusting that
a passing check meant anything:

| probe | rule fired |
|---|---|
| `let x = Date()` | yes |
| `let x = Calendar.current` | yes |
| `import UIKit` | yes |
| `let x = Task.sleep` | yes |
| `let x = [1].randomElement()` | **no** |
| `let x = Foo.shared` | yes |

Fixed by making the directory an explicit positional argument. All seven rules
now fire. A check that cannot fail is decoration; the probe is worth re-running
whenever a rule is added.

### Measurement: evaluator error

300 matches, hard bots, comparing what each seat bid against what it took.

```
seat: n=15996  bias=+0.042  meanAbsErr=0.897
team: n=8394   bias=+0.079  meanAbsErr=1.019
sureTricks vs actual tricks: bias=-0.022  meanAbsErr=0.901
```

The evaluator is essentially unbiased. Its mean *absolute* error of about one
trick is the natural spread of a Spades hand, and it is what forces set frequency
to roughly a third: a team's contract is off by a trick either way about as often
as not.

### Measurement: calibration envelope

800 matches per difficulty. Targets from CLAUDE.md §13.

| | table bid | set freq | hands/match | bags/team/match |
|---|---|---|---|---|
| **target** | 12.5 – 14.0 | 0.15 – 0.35 | 8 – 14 | 4 – 12 |
| hard | 12.81 | 0.324 | 13.94 | 7.58 |
| medium | 12.88 | 0.331 | 14.95 | 8.16 |
| easy | 10.80 | 0.216 | 27.91 | 36.22 |

Re-measured in the full-scale suite on different seeds: hard `12.80 / 0.322 /
14.11 / 7.63`, medium `12.87 / 0.330 / 14.38 / 7.82`. Hard straddles the
hands-per-match bound; medium sits just outside it.

### Measurement: the underbidding trade-off

Before accepting the hands-per-match gap, the obvious fix was tested — shade
every hard bid down by one trick. 300 matches:

| | table bid | set freq | hands/match | bags/team/match |
|---|---|---|---|---|
| shade 0 | 12.80 ✓ | 0.323 ✓ | 13.99 ✓ | 7.68 ✓ |
| shade −1 | 10.14 ✗ | 0.075 ✗ | 11.36 ✓ | 17.04 ✗ |

Shading fixes hands-per-match and breaks three other metrics. This is precisely
the failure §13's four-metric table exists to catch — win rate alone would have
looked fine. Closing the gap honestly needs a lower-error evaluator, not a tuning
constant, so the assertion was set at `< 16` with the reasoning recorded in
`CalibrationTests`.

### Measurement: difficulty ladder, settled

The 400-match ladder test reported hard-vs-medium at **0.500**, contradicting the
54.7% recorded in the spec. Re-run at 8,000 matches per pair on an independent
seed spread:

| matchup | win rate | n | SE | z |
|---|---|---|---|---|
| hard vs medium | 0.5506 | 8000 | 0.0056 | 9.10 |
| medium vs easy | 0.9994 | 8000 | 0.0003 | — |
| hard vs easy | 0.9996 | 8000 | 0.0002 | — |

The 0.500 was sampling noise: at n=400 the standard error is 0.025, so 0.500 and
0.551 are two standard errors apart. The 55% edge is real at nine standard
errors.

This also answers the open question in §13. Hard-vs-easy at 99.96% means the
tiers *are* differentiated where a new player meets them; the narrow
hard-vs-medium gap reflects how much random deals compress skill edges in
trick-taking games, not a broken ladder.

The permanent test keeps a slack floor (0.45) because at its 400-match sample an
honest build lands anywhere from about 0.48 to 0.62. It still catches the
regression that mattered — an earlier build sat at 0.43.

### Audio

Kenney's download URLs carry a rotating content hash, which is why the previous
script's hard-coded URLs 404'd. The asset pages themselves are stable, so
`fetch_audio.sh` now scrapes the current link from `kenney.nl/assets/<slug>`.

All three packs downloaded (207 source files), 21 clips rendered to 16-bit
44.1 kHz mono WAV, leading silence trimmed, peak-normalised to −3 dBFS. Total
971 KB against a 1.5 MB budget. Committed, per §10 — CC0 permits redistribution
and a hermetic build beats a network dependency.

### Spec disagreements raised

Per §18, flagged rather than silently resolved:

1. **§4's `evaluateDailyBonus` signature is insufficient.** Deciding whether two
   day-keys are consecutive is calendar arithmetic — month lengths, leap years —
   which is the one thing that module may not do. Added a `previousDayKey`
   parameter.
2. **§9's `CareerProfile` lacks the fields §4's API needs.** It lists only
   `lastDailyBonusClaim: Date?`. Added `lastDailyBonusDayKey` and
   `lastDailyBonusMonotonic`; kept the `Date` for display.
3. **§13's hands-per-match range excludes the current bots.** See above.
4. **The calibration table does not say which difficulty it applies to.** Easy is
   outside three of four ranges by design. The envelope is asserted for medium and
   hard; easy is asserted to be weak *in the intended direction* instead.
5. **§3 drops `swift-format` from bootstrap while §14 still requires it.**
   Resolved without a change: it ships with the Swift 6 toolchain.

### Also decided

- The daily-bonus anti-cheat now catches a **forward** date jump, not only a
  backward one: a day advance with almost no monotonic movement means the date
  was wound forward rather than lived through. A monotonic reading *lower* than
  the stored one is treated as a reboot and explicitly not as cheating.
- The 60-second monotonic gate is a speed bump, not a wall. Without a server
  clock there is no way to make it one, and v1 has no backend by design.

---

## 2026-09-07 — Initial build, spec 0.1

Commit `5494099`. Built from an empty repo.

### Environment

Linux with no Swift toolchain and no Xcode. The engine's Foundation-only rule is
what made this workable: it compiles and tests in a `swift:6.0-jammy` container.
The app layer was written but could not be compiled — SwiftUI, UIKit, GameKit and
AVFoundation do not exist on Linux. It was syntax-parsed with
`swiftc -frontend -parse`, which catches nothing beyond syntax.

### Bug: `Card.id` returned 0–53

`suit.rawValue * 13 + rank.rawValue`, with `Rank.two = 2`, produces ids 2–53 —
not a valid index into a 52-element table. Surfaced as
`Fatal error: Index out of range` the first time `TableKnowledge` used it to
index a seen-card table.

Fixed to `suit.rawValue * 13 + (rank.rawValue - 2)`. The regression test asserts
the ids are exactly `0..<52` *and* uses them as array subscripts, which is how
the bug actually manifested.

### Bug: the overtrick point was dropped

§5 scores a made contract as `10 × bid` **plus one per overtrick**. The first
implementation counted the bag but not the point. This passes a surprising number
of naive tests because bags are visible in the bag counter either way.

### Bug: three separate bid-inflation loops

All three had the same shape — matches that never end — and none is visible in a
per-hand unit test. They were found by asserting that every simulated match
reaches the target score.

**1. Easy bots picked a uniformly random bid.** The intent was "beginners
misjudge sometimes"; the implementation replaced the evaluation with a uniform
draw from 1–13. A traced stall:

```
STALL seed=54260162780 hands=200 scores=[-5980, -3560]
  h193 bids=["10","4","1","2"]  tricks=[2,4,1,6]
  h194 bids=["1","1","1","12"]  tricks=[4,1,5,3]
```

A table bidding 17 and 15 tricks out of 13 sets somebody every hand, scores walk
away from the target, and the match never ends. Fixed to a ±1 jitter around the
evaluation. A uniformly random bid is not a weak player, it is a broken one.

**2. Hard bots shaded up when behind.** Behind → overbid → set → further behind →
bid higher still. Self-reinforcing, and only visible in a match that runs to
completion.

**3. Bag-avoidance shading was applied by both partners.** Each partner
independently added a trick, so the team bid two it did not hold.

Combined effect, traced on a stalled hard-vs-hard match:

```
STALL seed=21550064651 hands=200 scores=[-10785, -5992]
  meanTableBid=14.905  setA=128/200  setB=106/200
```

Fixed by bounding shading to at most one trick, applying it only from the second
partner to bid (who can see the first's bid), and moving bag avoidance out of
bidding entirely — it is a *play* decision. This generalised into the rule now in
§6: team-level shading is applied once, by the partner who bids second.

### Measurement: is the evaluator calibrated?

Before blaming `sureTricks`, it was measured over 4,000 deals:

```
sureTricks: mean=3.285 per seat  -> 13.14 per table
hard bots at level scores:          13.02 per table
```

Nearly exactly the thirteen tricks that exist. The evaluator was fine; the
shading on top of it was the problem. This saved rewriting the wrong component.

### Measurement: hard was not actually better than medium

After the stall fixes, the ladder was:

```
medium vs easy: 0.9975
hard vs easy:   0.9975
hard vs medium: 0.485
```

Hard was marginally *worse*. A `BotTraits` option set was introduced so each
hard-only behaviour could be switched on alone and measured, rather than guessed
at.

Single-trait, 300 matches, against a medium-equivalent baseline:

| traits | win rate |
|---|---|
| all hard traits | 0.433 |
| + voidInference | 0.470 |
| + bagAvoidance | 0.490 |
| + nilSetting | 0.490 |
| + shortSuitDiscard | 0.497 |
| + tableAwareBidding | 0.463 |

Every trait was neutral-to-negative individually, and worse combined. Leave-one-
out, 400 matches:

| configuration | win rate |
|---|---|
| all hard traits | 0.4325 |
| − voidInference | 0.4375 |
| − bagAvoidance | 0.4300 |
| − nilSetting | 0.4525 |
| − shortSuitDiscard | 0.4325 |
| − **tableAwareBidding** | **0.4750** |

Bid shading was the biggest single drag.

### Rejected: second hand low

A well-known bridge technique — as second player, hold a winner that is not
certain rather than spend it. Measured at **0.3925**, clearly harmful, and
removed.

The reason is instructive: in Spades you bid an exact number, so the value
function is "hit your contract", not "maximise tricks". Ducking a trick you could
have taken gets you *set*, which costs ten times the bid. Techniques imported
from trick-maximising games do not transfer.

### Other play fixes found by measurement

- **Overtaking one's own partner.** Spending an ace to overtake partner's king
  wins one trick with two winners. Removed; both medium and hard now duck to a
  winning partner.
- **Short-suit discard threw singleton honours.** "Discard from the shortest
  suit to create a void" pitched a singleton king. Restricted to junk (rank ≤ 9),
  where the void is worth more than the card.
- **Bag avoidance made contract-aware.** Ducking once the contract is made is
  right, *unless* the trick would set the opponents — that is worth ten times
  their bid and dwarfs the bag.

### The fix that worked

Replacing score-deficit shading with **oversubscription awareness**: a hard bot
that bids after others estimates the table total, and shades down when the table
has already claimed more tricks than exist, up when it has underbid.

```
tableAwareBidding alone vs baseline: 0.5325
all hard traits vs baseline:         0.5400
```

Final ladder over 1,200 matches: medium beats easy 0.998, hard beats easy 1.000,
hard beats medium 0.547. Convergence, 400 matches per difficulty:

| | worst hands | mean hands | stalls | mean table bid |
|---|---|---|---|---|
| easy | 122 | 26.1 | 0 | 10.78 |
| medium | 51 | 14.9 | 0 | 12.88 |
| hard | 40 | 13.9 | 0 | 12.82 |

### Performance

`TableKnowledge.unseenCards` built a 52-element `Set` and filtered it *per
candidate card*, so a hard bot leading did that work thirteen times per turn.
Precomputing three things once in `init` — the unseen list, the top outstanding
rank per suit, and a void bitmask per seat — removed the dominant cost of a
simulated match. This is the same computation §15 warns will drop frames if it
runs on the main actor.

### Decision: two test scales

§3 asked for a ~2s engine loop; §13 asked for 10,000-match property tests. These
are in direct conflict. Split into `make engine-test` (reduced scale, ~3s) and
`make engine-test-full` (full scale, release, ~30s). Carried into spec 0.2 as
amendment 4, with the loud-skip requirement added so the fast target cannot
quietly become the only one anyone runs.

### Decision: `minBidPerTeam` semantics

Unspecified in 0.1. Implemented as: nil is exempt (the minimum exists to stop
sandbagging, and nil is the opposite of a safe bid), and a nil bidder's partner
must still reach the full minimum alone (otherwise "partner bids nil" becomes the
standard route around the rule). Both halves are now spec'd in §5 and tested.

---

## Standing debt

- **The app layer has never been compiled.** Syntax-parsed only. Expect type
  errors clustered in `GameSession`, `MatchService` and `AudioService`, where
  actor isolation meets framework callbacks.
- **`@preconcurrency import GameKit`** is a stopgap for incomplete upstream
  Sendable annotations. It carries a TODO and must not spread.
- **Hard beats medium by only 55%.** Real (z=9.1) but narrow. Whether it is
  *perceptible* to a player is unanswered; hard-vs-easy at 99.96% at least
  confirms the bottom of the ladder is differentiated.
- **Medium runs ~14.4 hands per match** against a §13 target of 8–14. Cause
  measured (≈1 trick evaluator error); not closable by tuning.
