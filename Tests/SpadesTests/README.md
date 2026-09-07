# App tests

These cover the app layer only: persistence, the service wrappers, `GameSession`
and the multiplayer transport.

The rules, the scoring, the bots and the economy arithmetic are all tested in
`Packages/SpadesEngine/Tests`, because they are pure and run in seconds without
a simulator. If a test here needs a simulator to check a rule, the rule is in
the wrong place.
