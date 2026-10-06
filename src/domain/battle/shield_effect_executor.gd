class_name ShieldEffectExecutor
extends EffectExecutor

const LegacyMath = preload("res://src/domain/battle/legacy_combat_math.gd")
const LegacyModifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor: CombatantState = context.actor
	var target: CombatantState = context.target
	var amount := effect.amount
	if effect.scaling == EffectDefinition.Scaling.HEALING:
		amount = LegacyMath.calculate_scaled_amount(effect.amount, effect.random_bonus, LegacyModifiers.effective_healing(actor, context.content, context.combatants), actor.level, context.rng.next_unit())
	if amount > target.shield:
		target.shield = amount
		target.max_shield = amount
	context.emit.call(&"shield_set", actor.instance_id, target.instance_id, {"amount": target.shield, "max_shield": target.max_shield})
