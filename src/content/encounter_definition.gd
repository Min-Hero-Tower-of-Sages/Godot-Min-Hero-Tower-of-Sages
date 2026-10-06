class_name EncounterDefinition
extends ContentDefinition

@export var team_entries: Array[Dictionary] = []
@export var ai_profile_id: StringName
@export var rewards: Dictionary = {}
@export var battle_modifier_ids: Array[StringName] = []
@export var battle_modifier_configuration: Dictionary = {}
@export var source_trainer_id: StringName
@export var source_floor_index: int = -1
@export var source_level_offset: int = 0
@export var source_trainer_type: StringName
