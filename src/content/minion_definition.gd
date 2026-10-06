class_name MinionDefinition
extends ContentDefinition

@export_group("Typing and stats")
@export var type_ids: Array[StringName] = []
@export_range(1, 9999) var base_health: int = 1
@export_range(0, 9999) var base_energy: int = 0
@export_range(0, 9999) var base_attack: int = 0
@export_range(0, 9999) var base_healing: int = 0
@export_range(0, 9999) var base_speed: int = 0
@export var growth: Dictionary = {}

@export_group("Acquisition and equipment")
@export_range(0, 4) var experience_gain_rate: int = 1
@export_range(0, 99) var gem_slots: int = 0 ## Initially usable gem sockets.
@export_range(0, 99) var locked_gem_slots: int = 0

@export_group("Progression")
@export var initial_move_ids: Array[StringName] = []
@export var specialization_move_ids: Array[StringName] = []
@export var talent_tree_ids: Array[StringName] = []
@export var evolution_id: StringName
@export_range(1, 999) var evolution_level: int = 999
@export var presentation_id: StringName

func validation_errors() -> PackedStringArray:
	var errors := super()
	if type_ids.is_empty(): errors.append("%s has no type" % id)
	if initial_move_ids.is_empty(): errors.append("%s has no initial moves" % id)
	if not specialization_move_ids.is_empty() and specialization_move_ids.size() != 3:
		errors.append("%s must have zero or three specialization moves" % id)
	if gem_slots + locked_gem_slots > 8: errors.append("%s has an implausible combined gem socket count" % id)
	return errors
