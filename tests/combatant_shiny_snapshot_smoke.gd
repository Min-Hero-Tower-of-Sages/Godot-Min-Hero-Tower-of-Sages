extends SceneTree

## Shiny appearance identity survives battle setup, combatant snapshots and
## retirement/replacement state serialization without changing legacy defaults.
##   godot --headless --path . --script res://tests/combatant_shiny_snapshot_smoke.gd

func _initialize() -> void:
	var setup := {
		"instance_id": "shiny-party-1",
		"definition_id": "base:minion/anteater_1",
		"is_shiny": true,
		"shiny_line_id": "base:minion/anteater_1",
		"team": 0,
		"max_health": 12,
		"health": 9,
	}
	var combatant := CombatantState.from_setup(setup)
	assert(combatant.is_shiny and combatant.shiny_line_id == &"base:minion/anteater_1")

	var serialized := combatant.to_dict()
	var restored := CombatantState.from_snapshot(serialized)
	assert(restored.is_shiny and restored.shiny_line_id == combatant.shiny_line_id)
	assert(restored.health == 9 and restored.instance_id == combatant.instance_id)

	var battle_state := BattleState.new()
	battle_state.combatants[combatant.instance_id] = combatant
	var snapshot := battle_state.snapshot()
	var resumed := BattleState.new()
	resumed.restore(snapshot)
	var resumed_combatant := resumed.combatants[combatant.instance_id] as CombatantState
	assert(resumed_combatant.is_shiny and resumed_combatant.shiny_line_id == combatant.shiny_line_id)

	var replacement_data := resumed_combatant.to_dict()
	replacement_data["instance_id"] = "shiny-replacement-2"
	var replacement := CombatantState.from_snapshot(replacement_data)
	assert(replacement.is_shiny and replacement.shiny_line_id == combatant.shiny_line_id)

	var legacy := CombatantState.from_setup({"instance_id": "legacy", "definition_id": "base:minion/anteater_1"})
	assert(not legacy.is_shiny and legacy.shiny_line_id.is_empty())
	print("PASS: shiny identity survives setup, snapshot restore and replacement; legacy setup defaults to non-shiny")
	quit(0)
