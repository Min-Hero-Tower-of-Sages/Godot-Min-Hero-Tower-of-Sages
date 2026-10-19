extends SceneTree

var catalog: ContentCatalog = preload("res://content/imported/recovered-20260911/catalog.tres")

func _initialize() -> void:
	assert(catalog.ensure_index().is_empty())
	for family in ["invigorate", "watergize"]:
		for tier in range(1, 6):
			var move_id := StringName("base:move/%s/tier%d" % [family, tier])
			var move := catalog.get_definition(move_id) as MoveDefinition
			var engine := BattleEngine.new()
			var setup := {"tie_first_team": 0, "combatants": [
				{"instance_id": "caster", "definition_id": "base:minion/fire_pig_1", "team": 0, "speed": 100, "max_health": 200, "max_energy": 200, "energy": 120, "move_ids": [move_id]},
				{"instance_id": "ally", "definition_id": "base:minion/fire_pig_1", "team": 0, "speed": 2, "max_health": 200, "max_energy": 80, "energy": 1, "move_ids": ["base:move/claw/tier1"]},
				{"instance_id": "enemy", "definition_id": "base:minion/fire_pig_1", "team": 1, "speed": 1, "max_health": 200, "max_energy": 80, "move_ids": ["base:move/claw/tier1"]}]}
			assert(engine.start(setup, catalog, RuleSetDefinition.new(), BattleRng.new(1)).accepted)
			var caster: CombatantState = engine._state.combatants[&"caster"]
			var ally: CombatantState = engine._state.combatants[&"ally"]
			# Invoke the resolution phases with resolved allies: Watergize still uses
			# random targeting in actual commands, rather than becoming single-target.
			var targets: Array[CombatantState] = [ally]
			var rolls := LegacyMoveRolls.new()
			engine._execute_before_accuracy(caster, move)
			assert(caster.energy == 120, "No unconditional caster restoration")
			engine._execute_target_phase(EffectDefinition.Phase.ALLY_TARGET, caster, move, targets, rolls)
			assert(ally.energy == mini(80, 1 + int(80.0 * move.effects[0].amount / 100.0)), "Restore percentage uses recipient's maximum and clamps")
			assert(caster.energy == 120, "Other ally restoration leaves caster unchanged")
			assert(engine._current_events.any(func(event: BattleEvent) -> bool: return event.kind == &"energy_changed" and event.target_id == &"ally"), "Energy event identifies ally")
			caster.energy = 0
			engine._execute_target_phase(EffectDefinition.Phase.ALLY_TARGET, caster, move, [caster], rolls)
			assert(caster.energy == mini(200, int(200.0 * move.effects[0].amount / 100.0)), "Caster can still be an ally recipient")
	print("PASS: all 10 ally-energy move tiers, recipient scaling, clamping, self-target and event routing")
	quit()
