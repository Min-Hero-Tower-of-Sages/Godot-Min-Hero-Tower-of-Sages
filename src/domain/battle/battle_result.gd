class_name BattleResult
extends RefCounted

var battle_id: StringName = &""
var winning_team: int = -1
var reason: StringName = &""
var rounds: int = 0
var participants: Array[Dictionary] = []

func is_empty() -> bool:
	return battle_id.is_empty() or winning_team < 0

func to_dictionary() -> Dictionary:
	return {
		"battle_id": String(battle_id),
		"winning_team": winning_team,
		"reason": String(reason),
		"rounds": rounds,
		"participants": participants.duplicate(true),
	}
