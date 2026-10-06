class_name HealEffectExecutor
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
	var calculated: float
	if effect.scaling == EffectDefinition.Scaling.HEALING:
		var cache_key := "%s:heal" % effect.id
		if effect.roll_scope == EffectDefinition.RollScope.SHARED_MOVE and shared.has(cache_key):
			calculated = float(shared[cache_key])
		else:
			calculated = LegacyMath.calculate_scaled_amount(effect.amount, effect.random_bonus, LegacyModifiers.effective_healing(actor, content, combatants), actor.level, rng.next_unit())
			if effect.roll_scope == EffectDefinition.RollScope.SHARED_MOVE: shared[cache_key] = calculated
	else:
		var rolled := effect.amount + (rng.next_int(effect.random_bonus + 1) if effect.random_bonus > 0 else 0)
		calculated = maxi(0, rolled + actor.healing)
	if move != null and move.type_id in actor.type_ids:
		calculated *= LegacyMath.STAB_MODIFIER
	var effectiveness := 1.0
	if effect.uses_type_effectiveness and move != null and chart != null:
		effectiveness = chart.combined_multiplier(move.type_id, target.type_ids, true)
		calculated *= effectiveness
	var critical := effect.can_critical and LegacyModifiers.critical_chance(actor, content, combatants) > rng.next_percent_value()
	if critical: calculated *= 2.0
	var amount := mini(target.max_health - target.health, maxi(0, int(calculated)))
	target.health += amount
	context.emit.call(&"healed", actor.instance_id, target.instance_id, {"amount": amount, "health": target.health, "effectiveness": effectiveness, "critical": critical and calculated > 0.0, "feedback_has_healing": calculated > 0.0})
