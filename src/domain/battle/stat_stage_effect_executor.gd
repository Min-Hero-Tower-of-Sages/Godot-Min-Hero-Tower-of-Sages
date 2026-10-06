class_name StatStageEffectExecutor
extends EffectExecutor

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor: CombatantState = context.actor
	var target: CombatantState = context.target
	var before := int(target.stat_stages.get(effect.stat_type_id, 0))
	var after := before + effect.amount
	target.stat_stages[effect.stat_type_id] = after
	context.emit.call(&"stat_stage_changed", actor.instance_id, target.instance_id, {
		"stat_type_id": String(effect.stat_type_id), "amount": effect.amount, "stage": after,
	})
