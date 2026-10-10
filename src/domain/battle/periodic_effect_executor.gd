class_name PeriodicEffectExecutor
extends EffectExecutor

func execute(effect: EffectDefinition, context: Dictionary) -> void:
	var actor: CombatantState = context.actor
	var target: CombatantState = context.target
	var move: MoveDefinition = context.move
	if effect.blocked_by_battle_mod_shield and target.battle_mod_shield_active:
		context.emit.call(&"periodic_blocked", actor.instance_id, target.instance_id, {"move_id": String(move.id)})
		return
	for index in target.statuses.size():
		var status: Dictionary = target.statuses[index]
		if StringName(status.get("kind", "")) == &"periodic" and StringName(status.get("move_id", "")) == move.id:
			status.turns = 0
			status.source_id = actor.instance_id
			status.erase("suppressed_effect_ids")
			target.statuses[index] = status
			context.emit.call(&"periodic_refreshed", actor.instance_id, target.instance_id, {"move_id": String(move.id), "duration": effect.duration})
			return
	target.statuses.append({"kind": &"periodic", "move_id": move.id, "source_id": actor.instance_id, "turns": 0})
	context.emit.call(&"periodic_applied", actor.instance_id, target.instance_id, {"move_id": String(move.id), "duration": effect.duration})
