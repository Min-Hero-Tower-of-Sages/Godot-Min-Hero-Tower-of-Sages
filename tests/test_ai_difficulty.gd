extends Node

const SampleFactory = preload("res://content/sample/sample_content_factory.gd")
const Planner = preload("res://src/domain/battle/legacy_ai_planner.gd")

func _ready() -> void:
	var catalog := SampleFactory.build_catalog()
	assert(catalog.rebuild_index().is_empty())
	var strike := catalog.get_definition(&"foundation:move/strike/tier1") as MoveDefinition
	var setup := SampleFactory.battle_setup()
	setup.combatants[0].instance_id = "ai"
	setup.combatants[0].team = 1
	setup.combatants[0].slot_index = 0
	setup.combatants[0].level = 10
	setup.combatants[0].move_ids = [String(strike.id)]
	setup.combatants[1].instance_id = "target-a"
	setup.combatants[1].team = 0
	setup.combatants[1].slot_index = 0
	setup.combatants[1].move_ids = []
	var second_target: Dictionary = setup.combatants[1].duplicate(true)
	second_target.instance_id = "target-b"
	second_target.slot_index = 1
	setup.combatants.append(second_target)
	var state := BattleState.new()
	state.turn_order = [&"ai", &"target-a", &"target-b"]
	for entry in setup.combatants:
		var combatant := CombatantState.from_setup(entry)
		state.combatants[combatant.instance_id] = combatant
	var rng := BattleRng.new(1, [999999, 0])
	var planner := Planner.new()
	var choice: Dictionary = planner.choose(
		state.combatants[&"ai"], state, catalog, catalog.get_type_chart(),
		{"trainer_type": "hard", "floor_rate": 1.0}, rng
	)
	assert(choice.move_id == strike.id)
	assert(choice.target_ids == [&"target-a"], "first per-target hard-trainer bonus should make target-a the selected equal-value target")
	assert(int(rng.snapshot().script_index) == 2, "source draws one trainer bonus for each eligible move/target score")
	print("PASS: trainer difficulty draws once per eligible target and affects target ranking")
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(0)
