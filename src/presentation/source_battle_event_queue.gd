extends RefCounted

## Resolved engine facts stay immutable. Only their on-screen order changes:
## BaseMoveSystem pays/restores energy inside ApplyEffects, after visuals.
static func build(input: Array[BattleEvent]) -> Dictionary:
	var events: Array[BattleEvent] = []
	var resource_events: Dictionary = {}
	var pending: Array[BattleEvent] = []
	for event in input:
		if event.kind == &"cost_paid":
			events.append_array(pending)
			pending.clear()
			pending.append(event)
			continue
		if not pending.is_empty():
			var cost := pending[0]
			if event.kind == &"energy_changed" and event.actor_id == cost.actor_id and event.target_id == cost.actor_id:
				pending.append(event)
				continue
			if event.kind == &"move_used" and event.actor_id == cost.actor_id and String(event.values.get("move_id", "")) == String(cost.values.get("move_id", "")):
				events.append(event)
				for resource in pending:
					events.append(resource)
					resource_events[resource] = true
				pending.clear()
				continue
			# Incomplete/synthetic streams retain their original order.
			events.append_array(pending)
			pending.clear()
		events.append(event)
	events.append_array(pending)
	return {"events": events, "resource_events": resource_events}
