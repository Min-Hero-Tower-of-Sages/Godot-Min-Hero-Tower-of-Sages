class_name ConditionEffectExecutor
extends EffectExecutor

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor: CombatantState = context.actor
	var target: CombatantState = context.target
	match effect.kind:
		EffectDefinition.Kind.STUN:
			target.stunned = true
			context.emit.call(&"stunned", actor.instance_id, target.instance_id, {})
		EffectDefinition.Kind.FREEZE:
			target.frozen = true
			target.turns_frozen = 0
			context.emit.call(&"frozen", actor.instance_id, target.instance_id, {"turns_frozen": 0})
		EffectDefinition.Kind.CLEAR_BUFFS_DEBUFFS:
			_clear_conditions(target, effect.removal_policy, context.content)
			# Presentation must use the state at this impact, not clear everything
			# again or read the engine's already-advanced end-of-turn state.
			context.emit.call(&"buffs_debuffs_cleared", actor.instance_id, target.instance_id, {
				"removal_policy": effect.removal_policy,
				"statuses": target.statuses.duplicate(true), "stat_stages": target.stat_stages.duplicate(true),
				"stunned": target.stunned, "frozen": target.frozen, "turns_frozen": target.turns_frozen})
		_:
			push_error("ConditionEffectExecutor cannot execute kind %s" % effect.kind)

static func is_effect_active(status: Dictionary, effect: EffectDefinition) -> bool:
	return effect.id not in status.get("suppressed_effect_ids", [])

static func _persistent_polarity(effect: EffectDefinition) -> int:
	match effect.kind:
		EffectDefinition.Kind.PERIODIC_DAMAGE: return -1
		EffectDefinition.Kind.PERIODIC_HEAL: return 1
		EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.REFLECT:
			return signi(effect.amount)
	return 0

static func _matches_policy(polarity: int, policy: EffectDefinition.RemovalPolicy) -> bool:
	return policy == EffectDefinition.RemovalPolicy.BOTH or (polarity > 0 and policy == EffectDefinition.RemovalPolicy.BUFFS_ONLY) or (polarity < 0 and policy == EffectDefinition.RemovalPolicy.DEBUFFS_ONLY)

static func _clear_conditions(target: CombatantState, policy: EffectDefinition.RemovalPolicy, content: ContentCatalog) -> void:
	if policy == EffectDefinition.RemovalPolicy.BOTH:
		target.statuses.clear()
	else:
		for index in range(target.statuses.size() - 1, -1, -1):
			var status: Dictionary = target.statuses[index].duplicate(true)
			if StringName(status.get("kind", "")) != &"periodic": continue
			var move := content.get_definition(StringName(status.get("move_id", ""))) as MoveDefinition
			if move == null: continue # Unknown extension statuses must not be guessed away.
			var suppressed: Array = status.get("suppressed_effect_ids", []).duplicate()
			var remaining := 0
			for component in move.effects:
				if component == null or component.kind not in [EffectDefinition.Kind.PERIODIC_DAMAGE, EffectDefinition.Kind.PERIODIC_HEAL, EffectDefinition.Kind.ARMOR, EffectDefinition.Kind.REFLECT]: continue
				if component.id in suppressed: continue
				if _matches_policy(_persistent_polarity(component), policy):
					suppressed.append(component.id)
				else:
					remaining += 1
			if remaining == 0 and not suppressed.is_empty():
				target.statuses.remove_at(index)
			else:
				status["suppressed_effect_ids"] = suppressed
				target.statuses[index] = status
	for stat_id in target.stat_stages.keys():
		if _matches_policy(signi(int(target.stat_stages[stat_id])), policy):
			target.stat_stages.erase(stat_id)
	if policy != EffectDefinition.RemovalPolicy.BUFFS_ONLY:
		target.stunned = false
		target.frozen = false
		target.turns_frozen = 0
