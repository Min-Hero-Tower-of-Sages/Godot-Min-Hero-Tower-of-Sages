# Required port exceptions

## Selective cleansing and dispelling (approved 2026-10-10)

The user approved separating beneficial and harmful conditions after a player
reported Cleansing Heal stripping allied buffs. Flash's `ClearBuffsAndDebuffs`
cleared every periodic effect, all stat stages, stun and freeze regardless of
which team received the move. Extended intentionally changes this behavior:

- Clearing effects aimed at enemies remove buffs only; clearing effects aimed at
  allies remove debuffs only. This applies to every tier of Blow By, Cleanse
  Darkness, Cleansing Heal, Cutting Wind, and Purge.
- Positive stat stages, healing-over-time, positive armor and reflect are buffs.
  Negative stages, damage-over-time, negative armor, stun and freeze are debuffs.
  Mixed periodic payloads retain their opposite-polarity components and elapsed
  duration. Unknown extension statuses are preserved by selective removal.
- Targets, energy costs, accuracy and original clearing chances are unchanged.
  Blow By does not gain a caster/ally cleanse. Shield, charge, exhaustion,
  cooldowns and permanent passives are not cleared.
- `EffectDefinition.removal_policy` defaults to `BOTH` for authored extensions
  that deliberately require the original full wipe. Legacy clear events without
  a policy retain their presentation behavior.

This is an authorized gameplay improvement, not a claim about original Flash
parity. `tests/selective_cleanse_smoke.gd` covers content policies, selective
execution, mixed periodic ticks/modifiers, presentation state, tooltip wording,
JSON snapshots, and real battle commands. Both stages of the content importer
preserve the policies when resources are regenerated.

Presentation-copy deviation requested during battle review: when every learned
move is cooling down but the minion still has enough energy, the ActionScript
`MoveSelectorForPlayer.BringIn` displays Desperation together with the fixed
"OUT OF ENERGY, USE DESPERATION" image. The Godot selector keeps Desperation,
the dimmed learned icons, and their cooldown overlays, but uses "MOVES COOLING
DOWN, USE DESPERATION" for that case. The user flagged the original wording as
contradicting the visible 90/91 energy value; this changes only the explanatory
text, not move legality, cooldowns, cost, or damage. The 2026-09-23 headless
battle UI check covers both high-energy cooldown and true low-energy fallback.

Platform-only decisions already fixed by the plan are not gameplay corrections:
Flash startup/global wiring is replaced by Godot scene/application construction;
save files use a new JSON schema; animation callbacks cannot apply authoritative
effects; and rendering is decoupled from the original 30 FPS simulation cadence.

When a functioning exception is required, record: trigger, original observed
behavior, replacement, reason the port could not preserve it, fixture/reference
evidence, and approval status. Never put suspected bugs in this file by default.
