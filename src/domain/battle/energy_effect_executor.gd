class_name EnergyEffectExecutor
extends EffectExecutor

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor: CombatantState = context.actor
	var target: CombatantState = context.target
	var before := target.energy
	var delta := effect.amount
	if effect.scaling == EffectDefinition.Scaling.ENERGY_STAT_PERCENT:
		delta = int(float(target.max_energy) * float(effect.amount) / 100.0)
	target.energy = clampi(target.energy + delta, 0, target.max_energy)
	context.emit.call(&"energy_changed", actor.instance_id, target.instance_id, {"amount": target.energy - before, "energy": target.energy})
