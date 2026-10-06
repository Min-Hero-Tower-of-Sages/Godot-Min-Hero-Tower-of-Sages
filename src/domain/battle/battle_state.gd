class_name BattleState
extends RefCounted

enum Phase { NOT_STARTED, DECISION, COMPLETE }

var battle_id: StringName
var revision: int = 0
var round_number: int = 1
var phase: Phase = Phase.NOT_STARTED
var active_actor_id: StringName
var combatants: Dictionary = {}
var retired_combatants: Array[Dictionary] = []
var turn_order: Array[StringName] = []
var turn_index: int = 0
var acted_ids: Array[StringName] = []
var tie_first_team: int = 0
var modifier_state: Dictionary = {}
var result: Dictionary = {}

func living_team_members(team: int) -> Array[CombatantState]:
	var found: Array[CombatantState] = []
	for combatant in combatants.values():
		if combatant.team == team and not combatant.defeated: found.append(combatant)
	return found

func snapshot() -> Dictionary:
	var serialized: Array[Dictionary] = []
	for combatant in combatants.values(): serialized.append(combatant.to_dict())
	return {
		"battle_id": String(battle_id), "revision": revision, "round_number": round_number,
		"phase": phase, "active_actor_id": String(active_actor_id), "combatants": serialized,
		"retired_combatants": retired_combatants.duplicate(true),
		"turn_order": turn_order.duplicate(), "turn_index": turn_index, "acted_ids": acted_ids.duplicate(), "tie_first_team": tie_first_team,
		"modifier_state": modifier_state.duplicate(true), "result": result.duplicate(true)
	}

func restore(data: Dictionary) -> void:
	battle_id = StringName(data.battle_id)
	revision = int(data.revision)
	round_number = int(data.round_number)
	phase = int(data.phase) as Phase
	active_actor_id = StringName(data.active_actor_id)
	combatants.clear()
	for entry in data.combatants:
		var combatant := CombatantState.from_snapshot(entry)
		combatants[combatant.instance_id] = combatant
	retired_combatants.assign(data.get("retired_combatants", []))
	turn_order.assign(data.turn_order)
	turn_index = int(data.turn_index)
	acted_ids.assign(data.get("acted_ids", []))
	tie_first_team = int(data.get("tie_first_team", 0))
	modifier_state = data.get("modifier_state", {}).duplicate(true)
	result = data.result.duplicate(true)
