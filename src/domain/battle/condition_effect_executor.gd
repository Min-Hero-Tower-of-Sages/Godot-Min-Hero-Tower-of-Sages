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
			target.statuses.clear()
			target.stat_stages.clear()
			target.stunned = false
			target.frozen = false
			target.turns_frozen = 0
			context.emit.call(&"buffs_debuffs_cleared", actor.instance_id, target.instance_id, {})
		_:
			push_error("ConditionEffectExecutor cannot execute kind %s" % effect.kind)
