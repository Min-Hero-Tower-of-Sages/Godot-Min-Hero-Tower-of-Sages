class_name BattleEvent
extends RefCounted

var sequence: int
var kind: StringName
var actor_id: StringName
var target_id: StringName
var values: Dictionary

func _init(p_sequence := 0, p_kind: StringName = &"", p_actor: StringName = &"", p_target: StringName = &"", p_values := {}) -> void:
	sequence = p_sequence
	kind = p_kind
	actor_id = p_actor
	target_id = p_target
	values = p_values.duplicate(true)

func to_dict() -> Dictionary:
	return {"sequence": sequence, "kind": String(kind), "actor_id": String(actor_id), "target_id": String(target_id), "values": values.duplicate(true)}
