class_name ContentDefinition
extends Resource

@export_group("Identity")
@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Migration metadata")
@export var legacy_numeric_id: int = -1
@export var legacy_class_name: String = ""
@export var source_location: String = ""
@export var source_mod: StringName = &"base"

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty():
		errors.append("definition has an empty stable id")
	elif not ":" in String(id):
		errors.append("%s is not a namespaced id" % id)
	if display_name.strip_edges().is_empty():
		errors.append("%s has an empty display name" % id)
	return errors
