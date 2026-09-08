# App tests

These cover the app layer only: persistence, the service wrappers, the calendar
boundary, `GameSession`, the multiplayer transport, and that every `SoundEffect`
resolves to a bundled file.

The rules, the scoring, the bots and the economy arithmetic are tested in
`Packages/SpadesEngine/Tests`, because they are pure and run in seconds without
a simulator. If a test here needs a simulator to check a rule, the rule is in
the wrong place.

The one exception that belongs here on purpose is the timezone case: deriving a
local day-key is the app layer's job, so "23:00 and 08:00 IST are two different
days" is tested against a real `Calendar` in `ServiceTests`, not in
`SpadesEconomyTests`.
