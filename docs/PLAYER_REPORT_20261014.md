# Player report fixes — October 14, 2026

Implemented from the six supplied recordings and two screenshots:

- Hard Mode's regular boss door is always passable and consumes no keys. Its
  hatchery door requires three floor keys and three hatchery keys before consuming
  both rings. Loading an older hard save restores floor keys previously consumed
  at the first door when the hatchery remains closed; this recovery runs once.
- Hard/Expert trainer introductions with empty recovered text use the original
  fallback, “In Hard Mode, we must fight!”. The hard-tower importer retains it.
- Victory stars use the final active player slots, including surviving stone
  replacements, before the original owned party is restored. Retired originals
  cannot count as additional dead slots. Persistent health and XP settlement
  continue to use the individual owned participants.
- Room loading binds every source heal zone, including multiple zones sharing
  interaction ID 1. This restores wide-room healing and death/forfeit checkpoints
  on the reported Floors 2-2, 2-3 and 2-4 and other affected rooms.
- Missing numeric portal routes are paired from the source room markers and
  corresponding entry markers. Floor 2-2's teleporter links are restored. The
  Floor 7/8 generator now includes both recovered teleporter spellings.
- Target selection markers draw above focused minions; resurrection gravestones
  draw above the arena and minions while remaining below move/menu overlays.
- Timer move and passive icons use the source top-left placement, with their
  sprite centers adjusted for texture size and the authored 0.8 scale. Rotation
  and size animation retain a center pivot.
- Minions with more than 12 active moves use a four-column layout, with 16 moves
  per page and navigation for additional moves. The selector stays within the
  viewport. Cooldowns, unavailable moves, tooltips and Desperation remain usable
  on the expanded layout. Selectors up to 12 moves retain the recovered layout.
- Delayed entry animation callbacks hold weak references so closing a battle
  before an entry timer fires does not report a freed capture.

The focused fixture `tests/player_report_20261014_smoke.gd` checks room contacts,
checkpoint healing, hard door costs and routing, old-save key recovery, trainer
dialogue, replacement scoring, 25-move pagination and battle overlay placement.
It uses memory sessions and an isolated application-data profile, without user
saves. A rendered capture is kept under ignored `build/player-report-20261014/`.

An executable export must be rebuilt to distribute these changes.
