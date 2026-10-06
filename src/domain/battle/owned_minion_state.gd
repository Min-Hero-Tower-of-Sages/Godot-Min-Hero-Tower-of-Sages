class_name OwnedMinionState
extends RefCounted

var instance_id: StringName
var definition_id: StringName
var nickname: String
var level: int = 1
var experience: int = 0
var stat_bonus: StringName = &""
var ivs: Dictionary = {}
var talent_node_ids: Array[StringName] = []
var learned_move_ids: Array[StringName] = []
var equipment_ids: Array[StringName] = []
var persistent_health: int = -1
var persistent_energy: int = -1

func to_dictionary() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"definition_id": String(definition_id),
		"nickname": nickname,
		"level": level,
		"experience": experience,
		"stat_bonus": String(stat_bonus),
		"ivs": ivs.duplicate(true),
		"talent_node_ids": talent_node_ids.map(func(value: StringName) -> String: return String(value)),
		"learned_move_ids": learned_move_ids.map(func(value: StringName) -> String: return String(value)),
		"equipment_ids": equipment_ids.map(func(value: StringName) -> String: return String(value)),
		"persistent_health": persistent_health,
		"persistent_energy": persistent_energy,
	}

static func from_dictionary(data: Dictionary) -> OwnedMinionState:
	var owned := OwnedMinionState.new()
	owned.instance_id = StringName(data.get("instance_id", ""))
	owned.definition_id = StringName(data.get("definition_id", ""))
	owned.nickname = String(data.get("nickname", ""))
	owned.level = int(data.get("level", 1))
	owned.experience = int(data.get("experience", owned.level * 1000))
	owned.stat_bonus = StringName(data.get("stat_bonus", ""))
	owned.ivs = (data.get("ivs", {}) as Dictionary).duplicate(true)
	owned.talent_node_ids.assign(data.get("talent_node_ids", []))
	owned.learned_move_ids.assign(data.get("learned_move_ids", []))
	owned.equipment_ids.assign(data.get("equipment_ids", []))
	owned.persistent_health = int(data.get("persistent_health", -1))
	owned.persistent_energy = int(data.get("persistent_energy", -1))
	return owned

func duplicate_state() -> OwnedMinionState:
	var copy := OwnedMinionState.new()
	copy.instance_id = instance_id
	copy.definition_id = definition_id
	copy.nickname = nickname
	copy.level = level
	copy.experience = experience
	copy.stat_bonus = stat_bonus
	copy.ivs = ivs.duplicate(true)
	copy.talent_node_ids = talent_node_ids.duplicate()
	copy.learned_move_ids = learned_move_ids.duplicate()
	copy.equipment_ids = equipment_ids.duplicate()
	copy.persistent_health = persistent_health
	copy.persistent_energy = persistent_energy
	return copy
