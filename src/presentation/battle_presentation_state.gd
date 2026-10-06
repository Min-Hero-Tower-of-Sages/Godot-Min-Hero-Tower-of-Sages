class_name BattlePresentationState
extends RefCounted

# Reduce resolved facts against the state currently on screen. The engine may
# already have expired or cleansed a status later in this same event batch.
static func apply_event(previous: Dictionary, event: BattleEvent) -> Dictionary:
	if event.kind == &"battle_mod_extra_spawned" and event.values.has("combatant"):
		return (event.values.combatant as Dictionary).duplicate(true)
	var state := previous.duplicate(true)
	for key in event.values:
		state[key] = event.values[key]
	match event.kind:
		&"shield_set":
			state["shield"] = int(event.values.get("amount", 0))
		&"periodic_applied", &"periodic_refreshed":
			var statuses: Array = state.get("statuses", []).duplicate(true)
			var move_id := StringName(event.values.get("move_id", ""))
			var status := {"kind": &"periodic", "move_id": move_id, "source_id": event.actor_id, "turns": 0}
			var existing_index := -1
			for index in statuses.size():
				if StringName(statuses[index].get("kind", "")) == &"periodic" and StringName(statuses[index].get("move_id", "")) == move_id:
					existing_index = index
					break
			if existing_index >= 0:
				statuses[existing_index] = status
			else:
				statuses.append(status)
			state["statuses"] = statuses
		&"periodic_expired":
			var move_id := StringName(event.values.get("move_id", ""))
			var statuses: Array = state.get("statuses", []).duplicate(true)
			for index in range(statuses.size() - 1, -1, -1):
				if StringName(statuses[index].get("kind", "")) == &"periodic" and StringName(statuses[index].get("move_id", "")) == move_id:
					statuses.remove_at(index)
			state["statuses"] = statuses
		&"buffs_debuffs_cleared":
			state["statuses"] = []
			state["stat_stages"] = {}
			state["stunned"] = false
			state["frozen"] = false
			state["turns_frozen"] = 0
		&"frozen", &"frozen_turn_skipped":
			state["frozen"] = true
		&"thawed":
			state["frozen"] = false
		&"stunned":
			state["stunned"] = true
		&"stat_stage_changed":
			var stages: Dictionary = state.get("stat_stages", {}).duplicate(true)
			stages[StringName(event.values.get("stat_type_id", ""))] = int(event.values.get("stage", 0))
			state["stat_stages"] = stages
		&"charge_started", &"charge_progressed":
			state["current_charge"] = int(event.values.get("charge", 1))
		&"charge_released", &"charge_cancelled":
			state["current_charge"] = 0
		&"exhausted_turn_skipped":
			state["current_exhaust"] = int(event.values.get("remaining", 0))
		&"defeated":
			state["defeated"] = true
		&"battle_mod_resurrected":
			state["defeated"] = false
			state["statuses"] = []
			state["stat_stages"] = {}
			state["frozen"] = false
			state["stunned"] = false
			state["turns_frozen"] = 0
		&"battle_mod_shield_removed":
			state["battle_mod_shield_active"] = false
	return state
