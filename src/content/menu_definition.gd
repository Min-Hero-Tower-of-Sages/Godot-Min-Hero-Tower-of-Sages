class_name MenuDefinition
extends ContentDefinition

@export_file("*.tscn") var scene_path: String
@export var order: int = 0
@export var availability_condition: StringName = &"always"

func validation_errors() -> PackedStringArray:
	var errors := super.validation_errors()
	if scene_path.strip_edges().is_empty():
		errors.append("%s has no menu scene path" % id)
		return errors
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		errors.append("%s menu scene does not exist or is not a PackedScene: %s" % [id, scene_path])
		return errors
	var packed_scene := ResourceLoader.load(scene_path, "PackedScene") as PackedScene
	if packed_scene == null:
		errors.append("%s menu scene could not be loaded: %s" % [id, scene_path])
		return errors
	var instance := packed_scene.instantiate()
	if not instance is MenuExtensionScreen:
		errors.append("%s menu scene root must extend MenuExtensionScreen: %s" % [id, scene_path])
	instance.free()
	return errors
