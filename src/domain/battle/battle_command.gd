class_name BattleCommand
extends RefCounted

enum Kind { USE_MOVE, FORFEIT }

var actor_id: StringName
var kind: Kind
var move_id: StringName
var target_ids: Array[StringName]
var expected_revision: int

func _init(
	p_actor_id: StringName = &"",
	p_kind: Kind = Kind.USE_MOVE,
	p_move_id: StringName = &"",
	p_target_ids: Array[StringName] = [],
	p_expected_revision: int = 0
) -> void:
	actor_id = p_actor_id
	kind = p_kind
	move_id = p_move_id
	target_ids = p_target_ids.duplicate()
	expected_revision = p_expected_revision
