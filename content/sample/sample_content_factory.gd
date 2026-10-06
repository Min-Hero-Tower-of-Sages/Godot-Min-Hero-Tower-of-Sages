class_name SampleContentFactory
extends RefCounted

static func build_catalog() -> ContentCatalog:
	var none_type := TypeDefinition.new()
	none_type.id = &"base:type/none"
	none_type.display_name = "None"
	none_type.source_location = "StaticData.as"
	var type_chart := TypeChartDefinition.new()
	type_chart.id = &"base:type_chart/classic"
	type_chart.display_name = "Classic type chart"
	type_chart.source_location = "StaticData.as"

	var strike_effect := EffectDefinition.new()
	strike_effect.id = &"foundation:effect/strike_damage"
	strike_effect.display_name = "Strike damage"
	strike_effect.kind = EffectDefinition.Kind.DAMAGE
	strike_effect.amount = 7
	strike_effect.random_bonus = 3
	strike_effect.executor = preload("res://src/domain/battle/damage_effect_executor.gd")

	var mend_effect := EffectDefinition.new()
	mend_effect.id = &"foundation:effect/mend_heal"
	mend_effect.display_name = "Mend healing"
	mend_effect.kind = EffectDefinition.Kind.HEAL
	mend_effect.target_scope = EffectDefinition.TargetScope.ACTOR
	mend_effect.phase = EffectDefinition.Phase.ACTOR_AFTER_TARGETS
	mend_effect.amount = 5
	mend_effect.executor = preload("res://src/domain/battle/heal_effect_executor.gd")

	var strike := MoveDefinition.new()
	strike.id = &"foundation:move/strike/tier1"
	strike.display_name = "Strike"
	strike.family_id = &"foundation:move_family/strike"
	strike.type_id = none_type.id
	strike.energy_cost = 1
	strike.effects = [strike_effect]
	strike.presentation_id = &"foundation:presentation/move/strike"

	var mend := MoveDefinition.new()
	mend.id = &"foundation:move/mend/tier1"
	mend.display_name = "Mend"
	mend.family_id = &"foundation:move_family/mend"
	mend.type_id = none_type.id
	mend.energy_cost = 1
	mend.target_side = MoveDefinition.TargetSide.SELF
	mend.effects = [mend_effect]

	var apprentice := MinionDefinition.new()
	apprentice.id = &"foundation:minion/apprentice"
	apprentice.display_name = "Apprentice"
	apprentice.type_ids = [none_type.id]
	apprentice.base_health = 32
	apprentice.base_energy = 10
	apprentice.base_attack = 2
	apprentice.base_healing = 1
	apprentice.base_speed = 8
	apprentice.initial_move_ids = [strike.id, mend.id]
	apprentice.presentation_id = &"foundation:presentation/minion/apprentice"

	var rival := MinionDefinition.new()
	rival.id = &"foundation:minion/rival"
	rival.display_name = "Rival"
	rival.type_ids = [none_type.id]
	rival.base_health = 27
	rival.base_energy = 10
	rival.base_attack = 1
	rival.base_speed = 7
	rival.initial_move_ids = [strike.id]
	rival.presentation_id = &"foundation:presentation/minion/rival"

	var pack := ContentPackDefinition.new()
	pack.id = &"foundation:pack/smoke_test"
	pack.display_name = "Foundation smoke-test content"
	pack.enabled_by_default = true
	pack.definitions = [none_type, type_chart, strike_effect, mend_effect, strike, mend, apprentice, rival]

	var catalog := ContentCatalog.new()
	catalog.packs = [pack]
	return catalog

static func build_rules() -> RuleSetDefinition:
	var rules := RuleSetDefinition.new()
	rules.id = &"foundation:rules/classic"
	rules.display_name = "Classic foundation rules"
	rules.party_size = 5
	return rules

static func battle_setup() -> Dictionary:
	return {
		"battle_id": "foundation-demo",
		# Keep smoke fixtures independent from the battle-activation tie draw.
		"tie_first_team": 0,
		"combatants": [
			{"instance_id": "player-1", "definition_id": "foundation:minion/apprentice", "team": 0, "move_ids": ["foundation:move/strike/tier1", "foundation:move/mend/tier1"], "max_health": 32, "max_energy": 10, "attack": 2, "healing": 1, "speed": 8},
			{"instance_id": "enemy-1", "definition_id": "foundation:minion/rival", "team": 1, "move_ids": ["foundation:move/strike/tier1"], "max_health": 27, "max_energy": 10, "attack": 1, "healing": 0, "speed": 7}
		]
	}
