# Extension guide

## Minion and move

Create `MinionDefinition` and `MoveDefinition` Resources with namespaced IDs.
Compose a move from ordered `EffectDefinition` Resources, add all definitions to
a `ContentPackDefinition`, and add that pack to the catalog. No scheduler switch
or numeric ID arithmetic is required.

## New effect

Create a focused script extending `EffectExecutor`, implement `execute(effect,
context)`, and assign it to the effect Resource's `executor`. The executor changes
only domain state passed in context and emits resolved facts through `context.emit`.
Add deterministic boundary tests.

## Rule, room, and menu

Rules are ordered Resources in `RuleSetDefinition` (the lifecycle hook interface
is pending complete order capture). A room is a Node2D scene plus
`RoomDefinition` and a campaign connection. A menu is a Control scene plus
`MenuDefinition`; the future screen router discovers it from the catalog.

Test-only extension fixtures will live in a catalog excluded by the Windows export
preset. The current sample pack demonstrates registration and composed effects;
room/menu/rule exercises remain future milestone evidence.
