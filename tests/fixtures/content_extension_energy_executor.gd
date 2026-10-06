extends EffectExecutor

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor := context.actor as CombatantState
	var target := context.target as CombatantState
	var before := target.energy
	target.energy = mini(target.max_energy, target.energy + effect.amount)
	context.emit.call(&"energy_changed", actor.instance_id, target.instance_id, {
		"amount": target.energy - before,
		"energy": target.energy,
		"fixture_executor": String(effect.id),
	})
