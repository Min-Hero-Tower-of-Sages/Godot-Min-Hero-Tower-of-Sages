# Required port exceptions

No gameplay exception is accepted yet.

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
