# Architecture

## Dependency direction

`content → domain → application → presentation` is the gameplay dependency
direction. Infrastructure implements storage and loading at the application edge.
Domain objects never depend on Nodes, animation callbacks, files, or input.

- `src/content`: Inspector-authored immutable definitions and catalog validation.
- `src/domain`: mutable logical state, commands, events, RNG, and resolution.
- `src/application`: session/controller orchestration and exactly-once result use.
- `src/presentation`: scenes and event playback; never authoritative gameplay.
- `src/infrastructure`: save storage and eventual content loaders.

No global singleton or combat signal bus is used. `BattleController` owns one
engine and emits event batches to views. A future server can submit the same
`BattleCommand` values without importing presentation code.

## Content identity

Every definition derives from `ContentDefinition`, uses a namespaced stable ID,
and keeps legacy IDs/classes only as migration metadata. `ContentCatalog` indexes
all definitions—including disabled packs—then rejects duplicate IDs and missing
references. Pack availability must govern acquisition, not identity resolution.

Loaded Resources are definitions only. `OwnedMinionState` and `CombatantState`
are separate `RefCounted` runtime values so two instances of one species never
share health, energy, statuses, or cooldowns.

## Battle contract

- `start(setup, content, rules, rng)` validates and reaches a decision.
- `get_decision()` returns the actor, revision, legal moves, and legal targets.
- `submit(command)` validates atomically, resolves, emits numeric facts, advances,
  and increments the revision only after an accepted command.
- `snapshot()/restore()` round-trip state, RNG, and event sequence.
- `get_result()` is empty until completion.

Rejected commands do not consume RNG or alter state/revision. Effect Resources
hold executor Scripts; adding a new executor does not edit the scheduler.

The current engine is a representative foundation, not the complete legacy rules
library. Type/STAB math, status lifecycle, passives, full AI, reflection,
redirection, revival, charge/exhaustion, and campaign rules remain gated on
reference extraction and order capture.
