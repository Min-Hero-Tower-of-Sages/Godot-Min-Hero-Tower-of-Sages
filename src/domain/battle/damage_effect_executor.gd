class_name DamageEffectExecutor
extends EffectExecutor

const LegacyMath = preload("res://src/domain/battle/legacy_combat_math.gd")
const LegacyModifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor: CombatantState = context.actor
	var target: CombatantState = context.target
	var rng: BattleRng = context.rng
	var move: MoveDefinition = context.get("move") as MoveDefinition
	var chart: TypeChartDefinition = context.get("type_chart") as TypeChartDefinition
	var content: ContentCatalog = context.get("content") as ContentCatalog
	var combatants: Dictionary = context.get("combatants", {})
	var shared: Dictionary = context.get("shared_amounts", {})
	var amount: float
	if effect.scaling == EffectDefinition.Scaling.ATTACK:
		var cache_key := "%s:damage" % effect.id
		if effect.roll_scope == EffectDefinition.RollScope.SHARED_MOVE and shared.has(cache_key):
			amount = float(shared[cache_key])
		else:
			amount = LegacyMath.calculate_scaled_amount(effect.amount, effect.random_bonus, LegacyModifiers.effective_attack(actor, content, combatants), actor.level, rng.next_unit())
			if effect.roll_scope == EffectDefinition.RollScope.SHARED_MOVE: shared[cache_key] = amount
	else:
		var raw := effect.amount + (rng.next_int(effect.random_bonus + 1) if effect.random_bonus > 0 else 0)
		amount = maxi(0, raw + actor.attack)
	if move != null and move.type_id in actor.type_ids:
		amount *= LegacyMath.STAB_MODIFIER
	var effectiveness := 1.0
	if effect.uses_type_effectiveness and move != null and chart != null:
		effectiveness = chart.combined_multiplier(move.type_id, target.type_ids)
		amount *= effectiveness
	var critical := effect.can_critical and LegacyModifiers.critical_chance(actor, content, combatants) > rng.next_percent_value()
	if critical: amount *= 2.0
	var remaining := amount
	var redirectors := _redirectors(target.team, content, combatants, shared, move)
	var divisor_key := "%s:redirect_divisor" % move.id
	var redirect_divisor := float(shared.get(divisor_key, _redirect_total(redirectors, content))) / 100.0
	shared[divisor_key] = redirect_divisor
	var target_reflect := LegacyModifiers.reflect_rate(target, content, combatants)
	for redirector in redirectors:
		var redirect_fraction := LegacyModifiers.redirect_percent(redirector, content) / 100.0
		var redirected := amount * (redirect_fraction / redirect_divisor) if redirect_divisor > 1.0 else amount * redirect_fraction
		remaining -= redirected
		var redirected_reflect_result := _deal_damage(actor, redirected * target_reflect)
		if int(redirected_reflect_result.amount) > 0:
			context.emit.call(&"reflected_damage", target.instance_id, actor.instance_id, redirected_reflect_result)
		var redirected_result := _deal_damage(redirector, redirected * LegacyModifiers.armor_rate(redirector, content, combatants))
		context.emit.call(&"redirected_damage", actor.instance_id, redirector.instance_id, redirected_result.merged({"source_target_id": String(target.instance_id)}))
	var reflected_result := _deal_damage(actor, remaining * target_reflect)
	if int(reflected_result.amount) > 0:
		context.emit.call(&"reflected_damage", target.instance_id, actor.instance_id, reflected_result)
	var result := _deal_damage(target, remaining * LegacyModifiers.armor_rate(target, content, combatants))
	context.emit.call(&"damage", actor.instance_id, target.instance_id, result.merged({"effectiveness": effectiveness, "critical": critical, "raw_amount": int(amount)}))
	_emit_defeat_if_needed(actor, target, context)
	for redirector in redirectors: _emit_defeat_if_needed(actor, redirector, context)
	_emit_defeat_if_needed(target, actor, context)

func _redirectors(team: int, content: ContentCatalog, combatants: Dictionary, shared: Dictionary, move: MoveDefinition) -> Array[CombatantState]:
	var key := "%s:redirectors" % move.id
	if shared.has(key):
		var cached: Array[CombatantState] = []
		for id in shared[key]:
			var combatant := combatants.get(id) as CombatantState
			if combatant != null: cached.append(combatant)
		return cached
	var result: Array[CombatantState] = []
	for combatant in combatants.values():
		if combatant.team == team and not combatant.defeated and LegacyModifiers.redirect_percent(combatant, content) > 0.0:
			result.append(combatant)
	result.sort_custom(func(left: CombatantState, right: CombatantState): return left.slot_index < right.slot_index if left.slot_index != right.slot_index else String(left.instance_id) < String(right.instance_id))
	shared[key] = result.map(func(combatant: CombatantState): return combatant.instance_id)
	return result

func _redirect_total(redirectors: Array[CombatantState], content: ContentCatalog) -> float:
	var result := 0.0
	for redirector in redirectors: result += LegacyModifiers.redirect_percent(redirector, content)
	return result

func _deal_damage(recipient: CombatantState, amount: float) -> Dictionary:
	var requested := maxi(0, int(amount))
	if recipient.battle_mod_shield_active:
		return {"amount": 0, "absorbed": 0, "blocked": requested, "health": recipient.health, "shield": recipient.shield}
	var absorbed := mini(recipient.shield, requested)
	recipient.shield -= absorbed
	var dealt := mini(recipient.health, requested - absorbed)
	recipient.health -= dealt
	return {"amount": dealt, "absorbed": absorbed, "blocked": 0, "health": recipient.health, "shield": recipient.shield}

func _emit_defeat_if_needed(source: CombatantState, recipient: CombatantState, context: Dictionary) -> void:
	if recipient.health <= 0 and not recipient.defeated:
		recipient.defeated = true
		context.emit.call(&"defeated", source.instance_id, recipient.instance_id, {})
