class_name LegacyCombatModifiers
extends RefCounted

const INCREASE_STAGES := [1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.25, 3.5]
const DECREASE_STAGES := [0.8, 0.51, 0.41, 0.33, 0.26, 0.21, 0.17, 0.15, 0.13, 0.1]

static func stat_stage_rate(stage: int) -> float:
	if stage == 0: return 1.0
	if stage > 0: return float(INCREASE_STAGES[mini(stage, 10) - 1])
	return float(DECREASE_STAGES[mini(-stage, 10) - 1])

static func effective_attack(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> float:
	return _effective_non_health_stat(combatant.max_attack_stat, combatant, &"base:stat/attack", content, combatants)

static func effective_healing(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> float:
	return _effective_non_health_stat(combatant.max_healing_stat, combatant, &"base:stat/healing", content, combatants)

static func effective_speed(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> float:
	return _effective_non_health_stat(combatant.speed, combatant, &"base:stat/speed", content, combatants)

static func effective_max_health(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> int:
	var stage := stat_stage_rate(int(combatant.stat_stages.get(&"base:stat/health", 0)))
	return maxi(1, int(float(combatant.source_raw_stats.get("health", combatant.base_max_health)) * stage * _passive_stat_rate(combatant, &"base:stat/health", content, combatants)))

static func effective_max_energy(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> int:
	var stage := stat_stage_rate(int(combatant.stat_stages.get(&"base:stat/energy", 0)))
	return maxi(0, int(float(combatant.source_raw_stats.get("energy", combatant.base_max_energy)) * stage * stage * _passive_stat_rate(combatant, &"base:stat/energy", content, combatants)))

static func critical_chance(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> float:
	var result := combatant.critical_chance
	result += _owned_passive_total(combatant, content, EffectDefinition.Kind.CRITICAL_CHANCE, false)
	result += _global_passive_total(combatant.team, content, combatants, EffectDefinition.Kind.CRITICAL_CHANCE)
	return result

static func armor_rate(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> float:
	var armor_percent := _payload_total(combatant, content, EffectDefinition.Kind.ARMOR)
	armor_percent += _owned_passive_total(combatant, content, EffectDefinition.Kind.ARMOR, false)
	armor_percent += _global_passive_total(combatant.team, content, combatants, EffectDefinition.Kind.ARMOR)
	return clampf(1.0 - armor_percent / 100.0, 0.05, 2.0)

static func reflect_rate(combatant: CombatantState, content: ContentCatalog, combatants: Dictionary) -> float:
	var reflect_percent := _payload_total(combatant, content, EffectDefinition.Kind.REFLECT)
	reflect_percent += _owned_passive_total(combatant, content, EffectDefinition.Kind.REFLECT, false)
	reflect_percent += _global_passive_total(combatant.team, content, combatants, EffectDefinition.Kind.REFLECT)
	return minf(reflect_percent / 100.0, 1.0)

static func redirect_percent(combatant: CombatantState, content: ContentCatalog) -> float:
	if combatant.battle_mod_shield_active: return 0.0
	return _owned_passive_total(combatant, content, EffectDefinition.Kind.REDIRECT_DAMAGE, true)

static func _payload_total(combatant: CombatantState, content: ContentCatalog, kind: EffectDefinition.Kind) -> float:
	var result := 0.0
	for status in combatant.statuses:
		if StringName(status.get("kind", "")) != &"periodic": continue
		var move := content.get_definition(StringName(status.get("move_id", ""))) as MoveDefinition
		if move == null: continue
		for effect in move.effects:
			if effect != null and effect.kind == kind: result += effect.amount
	return result

static func _owned_passive_total(combatant: CombatantState, content: ContentCatalog, kind: EffectDefinition.Kind, include_global: bool) -> float:
	var result := 0.0
	for move_id in combatant.move_ids:
		var move := content.get_definition(move_id) as MoveDefinition
		if move == null or not move.is_passive and not (include_global and move.is_global_passive): continue
		for effect in move.effects:
			if effect != null and effect.kind == kind: result += effect.amount
	return result

static func _global_passive_total(team: int, content: ContentCatalog, combatants: Dictionary, kind: EffectDefinition.Kind) -> float:
	var unique_moves: Dictionary = {}
	for member in combatants.values():
		if member.team != team or member.defeated: continue
		for move_id in member.move_ids:
			var move := content.get_definition(move_id) as MoveDefinition
			if move != null and move.is_global_passive: unique_moves[move_id] = move
	var result := 0.0
	for move in unique_moves.values() + _battle_bonus_global_moves(team, content, combatants):
		for effect in move.effects:
			if effect != null and effect.kind == kind: result += effect.amount
	return result

static func _effective_non_health_stat(base_value: float, combatant: CombatantState, stat_id: StringName, content: ContentCatalog, combatants: Dictionary) -> float:
	var stage := stat_stage_rate(int(combatant.stat_stages.get(stat_id, 0)))
	var key := "speed" if stat_id == &"base:stat/speed" else "max_attack_stat" if stat_id == &"base:stat/attack" else "max_healing_stat"
	var value := float(combatant.source_raw_stats.get(key, base_value)) * stage * stage * _passive_stat_rate(combatant, stat_id, content, combatants)
	return float(int(value)) if combatant.source_raw_stats.has(key) else value

static func _passive_stat_rate(combatant: CombatantState, stat_id: StringName, content: ContentCatalog, combatants: Dictionary) -> float:
	var percent := _first_stat_percent_from_owned(combatant, stat_id, content, false)
	var unique_global: Dictionary = {}
	for member in combatants.values():
		if member.team != combatant.team or member.defeated: continue
		for move_id in member.move_ids:
			var move := content.get_definition(move_id) as MoveDefinition
			if move != null and move.is_global_passive: unique_global[move_id] = move
	for move in unique_global.values() + _battle_bonus_global_moves(combatant.team, content, combatants): percent += _first_stat_percent(move, stat_id)
	return 1.0 + percent / 100.0

static func _battle_bonus_global_moves(team: int, content: ContentCatalog, combatants: Dictionary) -> Array:
	# DynamicData appends the trainer's stone buff after deduplicating learned
	# global moves. It stacks with an identical learned move, not per teammate.
	var unique: Dictionary = {}
	for member in combatants.values():
		if member.team != team: continue
		for move_id in member.battle_bonus_global_move_ids:
			var move := content.get_definition(move_id) as MoveDefinition
			if move != null and move.is_global_passive: unique[move_id] = move
	return unique.values()

static func _first_stat_percent_from_owned(combatant: CombatantState, stat_id: StringName, content: ContentCatalog, include_global: bool) -> float:
	var result := 0.0
	for move_id in combatant.move_ids:
		var move := content.get_definition(move_id) as MoveDefinition
		if move == null or not move.is_passive and not (include_global and move.is_global_passive): continue
		result += _first_stat_percent(move, stat_id)
	return result

static func _first_stat_percent(move: MoveDefinition, stat_id: StringName) -> float:
	for effect in move.effects:
		if effect != null and effect.kind == EffectDefinition.Kind.STAT_PERCENT:
			return float(effect.amount) if effect.stat_type_id == stat_id else 0.0
	return 0.0
