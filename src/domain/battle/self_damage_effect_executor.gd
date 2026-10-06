class_name SelfDamageEffectExecutor
extends EffectExecutor

const LegacyMath = preload("res://src/domain/battle/legacy_combat_math.gd")
const LegacyModifiers = preload("res://src/domain/battle/legacy_combat_modifiers.gd")

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor: CombatantState = context.actor
	var amount: int
	if effect.kind == EffectDefinition.Kind.HEALTH_PERCENT_DAMAGE:
		amount = int(float(actor.max_health) * float(effect.amount) / 100.0)
	else:
		var shared: Dictionary = context.shared_amounts
		var key := "%s:self_damage" % effect.id
		if shared.has(key):
			amount = int(shared[key])
		else:
			amount = LegacyMath.calculate_scaled_amount(effect.amount, effect.random_bonus, LegacyModifiers.effective_attack(actor, context.content, context.combatants), actor.level, context.rng.next_unit())
			shared[key] = amount
	var requested := amount
	var absorbed := 0
	if not actor.battle_mod_shield_active:
		absorbed = mini(actor.shield, requested)
		actor.shield -= absorbed
		actor.health = maxi(0, actor.health - (requested - absorbed))
	context.emit.call(&"self_damage", actor.instance_id, actor.instance_id, {"amount": requested - absorbed if not actor.battle_mod_shield_active else 0, "absorbed": absorbed, "health": actor.health})
	if actor.health <= 0 and not actor.defeated:
		actor.defeated = true
		context.emit.call(&"defeated", actor.instance_id, actor.instance_id, {})
