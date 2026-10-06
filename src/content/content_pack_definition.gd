class_name ContentPackDefinition
extends ContentDefinition

@export var dependencies: Array[StringName] = []
@export var enabled_by_default: bool = true
@export var mod_flag_ids: Array[StringName] = []
@export var definitions: Array[ContentDefinition] = []
@export_file("*.json") var source_room_graph_path: String
