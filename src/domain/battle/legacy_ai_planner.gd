class_name LegacyAiPlanner
extends RefCounted

## Source-compatible threat scorer recovered from AIMoveSystem.as.  The original
## AI is deliberately heuristic (and contains a few arithmetic oddities), so
## this class keeps selection separate from resolution and never previews with
## the battle RNG.

const LegacyMath = preload("res://src/domain/battle/legacy_combat_math.gd")
const LegacyModifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")
const DESPERATION_ID := &"base:move/desperation/tier1"

var _team_threats: Dictionary = {}
var _team_ratios: Dictionary = {}
var _team_redirect: Dictionary = {}

func reset() -> void:
	_team_threats.clear()
	_team_ratios.clear()
	_team_redirect.clear()

func snapshot() -> Dictionary:
	return {
		"team_threats": _team_threats.duplicate(true),
		"team_ratios": _team_ratios.duplicate(true),
		"team_redirect": _team_redirect.duplicate(true),
	}

func restore(data: Dictionary) -> void:
	_team_threats = data.get("team_threats", {}).duplicate(true)
	_team_ratios = data.get("team_ratios", {}).duplicate(true)
	_team_redirect = data.get("team_redirect", {}).duplicate(true)

func choose(actor: CombatantState, state: BattleState, content: ContentCatalog, type_chart: TypeChartDefinition, difficulty: Dictionary = {}, rng: BattleRng = null) -> Dictionary:
	var allies := state.living_team_members(actor.team)
	var enemies := state.living_team_members(1 - actor.team)
	_sort_by_turn_order(allies, state)
	_sort_by_slot(enemies)
	_initialize_team(actor.team, allies)
	_initialize_team(1 - actor.team, enemies)
	# AIMoveSystem recalculates the prospective targets first, then its own team.
	_calculate_team_threat(1 - actor.team, enemies, allies, state, content, type_chart)
	_calculate_team_threat(actor.team, allies, enemies, state, content, type_chart)

	var best: Dictionary = {}
	var best_threat := 0.0
	for move in _available_moves(actor, content):
		if move.is_passive or move.is_global_passive: continue
		var heals_allies := _is_ally_move(move)
		var targets := allies if heals_allies else enemies
		if targets.is_empty(): continue
		var ranked: Array[Dictionary] = []
		for target in targets:
			var value := _healing_threat(move, actor, target, state, content, type_chart, true, difficulty, rng) if heals_allies else _damage_threat(move, actor, target, state, content, type_chart, true, difficulty, rng)
			ranked.append({"target": target, "threat": value})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary):
			if not is_equal_approx(float(a.threat), float(b.threat)): return float(a.threat) > float(b.threat)
			return String((a.target as CombatantState).instance_id) < String((b.target as CombatantState).instance_id))
		var total := _ranked_total(ranked, move.target_count, move.target_mode == MoveDefinition.TargetMode.RANDOM)
		if total > best_threat:
			best_threat = total
			best = {"move": move, "ranked": ranked}
	if best.is_empty(): return {}
	var chosen_move := best.move as MoveDefinition
	var ids: Array[StringName] = []
	if chosen_move.target_mode == MoveDefinition.TargetMode.CHOSEN:
		for index in mini(chosen_move.target_count, (best.ranked as Array).size()):
			ids.append(((best.ranked as Array)[index].target as CombatantState).instance_id)
	return {"move_id": chosen_move.id, "target_ids": ids, "threat": best_threat}

func _available_moves(actor: CombatantState, content: ContentCatalog) -> Array[MoveDefinition]:
	var result: Array[MoveDefinition] = []
	for id in actor.move_ids:
		var move := content.get_definition(id) as MoveDefinition
		if move != null and move.available and actor.energy >= move.energy_cost and int(actor.cooldowns.get(move.id, 0)) <= 0:
			result.append(move)
	var desperation := content.get_definition(DESPERATION_ID) as MoveDefinition
	if desperation != null and desperation.available and actor.energy >= desperation.energy_cost and int(actor.cooldowns.get(desperation.id, 0)) <= 0 and not result.has(desperation):
		result.append(desperation)
	return result

func _calculate_team_threat(team: int, members: Array[CombatantState], opponents: Array[CombatantState], state: BattleState, content: ContentCatalog, chart: TypeChartDefinition) -> void:
	var threats: Dictionary = {}
	var highest := 0.0
	var redirect := 0.0
	for member in members:
		redirect += LegacyModifiers.redirect_percent(member, content)
		var best := 0.0
		for move in _available_moves(member, content):
			if move.is_passive or move.is_global_passive: continue
			var heals_allies := _is_ally_move(move)
			var targets := members if heals_allies else opponents
			var ranked: Array[Dictionary] = []
			for target in targets:
				var score := _healing_threat(move, member, target, state, content, chart, false) if heals_allies else _damage_threat(move, member, target, state, content, chart, false)
				ranked.append({"threat": score})
			ranked.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.threat) > float(b.threat))
			best = maxf(best, _ranked_total(ranked, move.target_count, move.target_mode == MoveDefinition.TargetMode.RANDOM))
		threats[String(member.instance_id)] = best
		highest = maxf(highest, best)
	var ratios: Dictionary = {}
	for member in members:
		var value := float(threats.get(String(member.instance_id), 0.0))
		ratios[String(member.instance_id)] = value / highest if value > 0.0 and highest > 0.0 else 0.0
	_team_threats[team] = threats
	_team_ratios[team] = ratios
	_team_redirect[team] = minf(redirect / 100.0, 1.0)

func _damage_threat(move: MoveDefinition, actor: CombatantState, target: CombatantState, state: BattleState, content: ContentCatalog, chart: TypeChartDefinition, apply_ratio: bool, difficulty: Dictionary = {}, rng: BattleRng = null) -> float:
	if target.battle_mod_shield_active: return 0.0
	if move.id == DESPERATION_ID: return 1.0
	if actor.energy < move.energy_cost or int(actor.cooldowns.get(move.id, 0)) > 0: return 0.0
	var target_value := 0.0
	var self_value := 0.0
	for effect in move.effects:
		if effect == null: continue
		match effect.kind:
			EffectDefinition.Kind.DAMAGE:
				target_value += _scaled_expected(effect, actor, false, content, state)
			EffectDefinition.Kind.PERIODIC_DAMAGE:
				# Original AI calculates a scaled temporary, then accidentally adds raw average power.
				if not _periodic_active(target, move.id): target_value += effect.amount + effect.random_bonus / 2.0
			EffectDefinition.Kind.STUN:
				if not target.stunned: target_value += effect.chance_percent / 100.0 * (_threat(target) / 2.0)
			EffectDefinition.Kind.FREEZE:
				if not target.frozen: target_value += effect.chance_percent / 100.0 * (_threat(target) / 1.1)
			EffectDefinition.Kind.SELF_DAMAGE:
				self_value -= _typed_self_amount(effect, move, actor, content, chart, state)
			EffectDefinition.Kind.HEAL:
				if effect.target_scope == EffectDefinition.TargetScope.ACTOR:
					self_value += minf(_scaled_expected(effect, actor, true, content, state), actor.max_health - actor.health)
			EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE:
				if effect.target_scope == EffectDefinition.TargetScope.ACTOR: self_value -= actor.max_health * effect.amount / 100.0
			EffectDefinition.Kind.STAT_STAGE:
				target_value += _stat_effect_value(effect, actor, target, state)
			EffectDefinition.Kind.ARMOR:
				if not _periodic_active(target, move.id): target_value -= target.max_health * effect.amount / 100.0
	if move.type_id in actor.type_ids: target_value *= LegacyMath.STAB_MODIFIER
	if chart != null: target_value *= chart.combined_multiplier(move.type_id, target.type_ids)
	var redirected_remaining := 1.0 - float(_team_redirect.get(target.team, 0.0))
	if redirected_remaining * target_value > target.health:
		target_value = _threat(target) * 1.5
		if not _has_moved(target, state): target_value *= 1.3
	if actor.energy > 0: target_value += target_value / 10.0 * (1.0 - float(move.energy_cost) / actor.energy)
	# Preserve the source's duplicated exhaust reduction against the self component.
	self_value -= move.exhaust_turns * (self_value * 0.5)
	self_value -= move.exhaust_turns * (self_value * 0.66)
	if apply_ratio and redirected_remaining != 0.0:
		target_value *= redirected_remaining * _ratio(target)
	var result := (self_value + target_value) * move.accuracy_percent / 100.0
	result *= LegacyModifiers.armor_rate(target, content, state.combatants)
	# AIMoveSystem adds the trainer modifier to each actual candidate target score
	# after damage/accuracy/armor adjustments (AIMoveSystem.as:525-533).
	if apply_ratio: result += _difficulty_bonus(actor, difficulty, rng)
	return result

func _healing_threat(move: MoveDefinition, actor: CombatantState, target: CombatantState, state: BattleState, content: ContentCatalog, chart: TypeChartDefinition, apply_ratio: bool, difficulty: Dictionary = {}, rng: BattleRng = null) -> float:
	if actor.energy < move.energy_cost or int(actor.cooldowns.get(move.id, 0)) > 0: return 0.0
	var target_value := 0.0
	var self_value := 0.0
	var heal_multiplier := chart.combined_multiplier(move.type_id, target.type_ids, true) if chart != null else 1.0
	for effect in move.effects:
		if effect == null: continue
		match effect.kind:
			EffectDefinition.Kind.HEAL:
				var amount := _scaled_expected(effect, actor, true, content, state) * heal_multiplier
				if move.type_id in actor.type_ids: amount *= LegacyMath.STAB_MODIFIER
				target_value += minf(amount, target.max_health - target.health)
			EffectDefinition.Kind.SHIELD:
				var shield := _scaled_expected(effect, actor, true, content, state) * heal_multiplier
				if move.type_id in actor.type_ids: shield *= LegacyMath.STAB_MODIFIER
				if shield > target.shield: target_value += shield - target.shield
			EffectDefinition.Kind.PERIODIC_HEAL:
				if not _periodic_active(target, move.id):
					var hot := (effect.amount + effect.random_bonus / 2.0) * heal_multiplier
					if move.type_id in actor.type_ids: hot *= LegacyMath.STAB_MODIFIER
					if target.health + hot > target.max_health: hot = (target.max_health - target.health) * 2.0
					target_value += hot
			EffectDefinition.Kind.SELF_DAMAGE:
				self_value -= _typed_self_amount(effect, move, actor, content, chart, state)
			EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE:
				if effect.target_scope == EffectDefinition.TargetScope.ACTOR: self_value -= actor.max_health * effect.amount / 100.0
			EffectDefinition.Kind.STAT_STAGE:
				target_value += _stat_effect_value(effect, actor, target, state)
			EffectDefinition.Kind.ARMOR:
				if not _periodic_active(target, move.id): target_value += target.max_health * effect.amount / 100.0
	if actor.energy > 0: target_value += target_value / 10.0 * (1.0 - float(move.energy_cost) / actor.energy)
	self_value -= move.exhaust_turns * (self_value * 0.5)
	self_value -= move.exhaust_turns * (self_value * 0.66)
	if apply_ratio: target_value *= _ratio(target)
	var result := (self_value + target_value) * move.accuracy_percent / 100.0
	var armor := LegacyModifiers.armor_rate(target, content, state.combatants)
	if armor < 1.0: result *= 1.0 / armor
	result *= 1.0 + LegacyModifiers.redirect_percent(target, content) / 100.0
	# The source also draws once per target after all healing modifiers
	# (AIMoveSystem.as:727-742), not once per move after target aggregation.
	if apply_ratio: result += _difficulty_bonus(actor, difficulty, rng)
	return result

func _stat_effect_value(effect: EffectDefinition, actor: CombatantState, target: CombatantState, state: BattleState) -> float:
	var recipient := actor if effect.target_scope == EffectDefinition.TargetScope.ACTOR else target
	var direction := -1.0 if effect.amount < 0 else 1.0
	var magnitude := _buff_value(effect.stat_type_id, absi(effect.amount), recipient, _threat(recipient), state)
	return direction * magnitude * effect.chance_percent / 100.0

func _buff_value(stat_id: StringName, stages: int, target: CombatantState, threat: float, state: BattleState) -> float:
	var rate := LegacyModifiers.stat_stage_rate(stages)
	match stat_id:
		&"base:stat/attack":
			var weight := minf(1.0, float(target.attack) / maxf(target.healing, 1.0))
			return weight * threat * (1.0 - rate)
		&"base:stat/healing":
			var weight := minf(1.0, float(target.healing) / maxf(target.attack, 1.0))
			return weight * threat * rate
		&"base:stat/speed":
			var position := state.turn_order.find(target.instance_id) + 1
			var weight := float(state.turn_order.size() - position) / 10.0
			weight *= 0.3 if not _has_moved(target, state) else 0.1
			return weight * threat * rate
		&"base:stat/energy": return float(target.energy) / maxf(target.max_energy, 1.0) * threat * (1.0 - rate)
		&"base:stat/health": return float(target.max_health) / 150.0 * threat * rate
	return 0.0

func _scaled_expected(effect: EffectDefinition, actor: CombatantState, healing: bool, content: ContentCatalog, state: BattleState) -> float:
	var stat := LegacyModifiers.effective_healing(actor, content, state.combatants) if healing else LegacyModifiers.effective_attack(actor, content, state.combatants)
	return LegacyMath.calculate_scaled_amount(effect.amount + effect.random_bonus / 2.0, 0.0, stat, actor.level, 0.0)

func _typed_self_amount(effect: EffectDefinition, move: MoveDefinition, actor: CombatantState, content: ContentCatalog, chart: TypeChartDefinition, state: BattleState) -> float:
	var amount := _scaled_expected(effect, actor, false, content, state)
	if move.type_id in actor.type_ids: amount *= LegacyMath.STAB_MODIFIER
	if chart != null: amount *= chart.combined_multiplier(move.type_id, actor.type_ids)
	if amount > actor.health: return _threat(actor) * 1.3
	return amount

func _periodic_active(target: CombatantState, move_id: StringName) -> bool:
	for status in target.statuses:
		if StringName(status.get("kind", "")) == &"periodic" and StringName(status.get("move_id", "")) == move_id: return true
	return false

func _ranked_total(ranked: Array[Dictionary], target_count: int, random_targets: bool) -> float:
	if ranked.is_empty(): return 0.0
	if random_targets:
		var random_total := 0.0
		for item in ranked: random_total += float(item.threat)
		return random_total / ranked.size() * mini(ranked.size(), target_count)
	var total := 0.0
	for index in mini(ranked.size(), target_count): total += float(ranked[index].threat)
	return total

func _is_ally_move(move: MoveDefinition) -> bool:
	# Imported moves carry the legacy ally count. Foundation/custom content may
	# express the same fact solely through its target side.
	return move.ally_target_count > 0 or move.target_side in [MoveDefinition.TargetSide.ALLY, MoveDefinition.TargetSide.SELF]

func _initialize_team(team: int, members: Array[CombatantState]) -> void:
	if _team_threats.has(team): return
	var values: Dictionary = {}
	var ratios: Dictionary = {}
	for member in members:
		values[String(member.instance_id)] = float(member.level)
		ratios[String(member.instance_id)] = 1.0
	_team_threats[team] = values
	_team_ratios[team] = ratios

func _threat(target: CombatantState) -> float:
	return float((_team_threats.get(target.team, {}) as Dictionary).get(String(target.instance_id), target.level))

func _ratio(target: CombatantState) -> float:
	return float((_team_ratios.get(target.team, {}) as Dictionary).get(String(target.instance_id), 1.0))

func _has_moved(target: CombatantState, state: BattleState) -> bool:
	return target.instance_id in state.acted_ids

func _difficulty_bonus(actor: CombatantState, difficulty: Dictionary, rng: BattleRng = null) -> float:
	var trainer := StringName(difficulty.get("trainer_type", "none"))
	if trainer in [&"none", &"expert"]: return 0.0
	var floor_rate := float(difficulty.get("floor_rate", 0.0))
	var maximum := actor.level * floor_rate
	if trainer == &"hard": maximum /= 2.0
	# StaticData.GetDifficultyModifierForMinion returns Math.random() * maximum.
	# Use the battle RNG so a snapshot/replay reproduces the same candidate scores;
	# deterministic fixtures may inject a fixed unit instead.
	var unit := float(difficulty.random_unit) if difficulty.has("random_unit") else (rng.next_unit() if rng != null else 0.0)
	return maximum * clampf(unit, 0.0, 0.999999)

func _sort_by_turn_order(members: Array[CombatantState], state: BattleState) -> void:
	members.sort_custom(func(a: CombatantState, b: CombatantState): return state.turn_order.find(a.instance_id) < state.turn_order.find(b.instance_id))

func _sort_by_slot(members: Array[CombatantState]) -> void:
	members.sort_custom(func(a: CombatantState, b: CombatantState):
		return a.slot_index < b.slot_index if a.slot_index != b.slot_index else String(a.instance_id) < String(b.instance_id))
