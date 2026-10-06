class_name BattleVfxCatalog
extends RefCounted

const CATALOG_PATH := "res://content/base/art/battle/visual_move_assets.json"
const PROFILES_PATH := "res://content/base/art/battle/battle_animation_profiles.json"

var _families: Dictionary = {}
var _profiles: Dictionary = {}
var _texture_cache: Dictionary = {}

func _init() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("Recovered move-visual catalog is missing: %s" % CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		push_warning("Recovered move-visual catalog is not a JSON object")
		return
	_families = (parsed as Dictionary).get("families", {})
	if FileAccess.file_exists(PROFILES_PATH):
		var profile_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILES_PATH))
		if profile_data is Dictionary:
			_profiles = (profile_data as Dictionary).get("profiles", {})

func profile_for(visual_id: int) -> Dictionary:
	return _profiles.get(str(visual_id), {})

func family_name(visual_id: int) -> String:
	var family: Dictionary = _families.get(str(visual_id), {})
	return String(family.get("visual_id_name", ""))

func textures_for(visual_id: int) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	var family: Dictionary = _families.get(str(visual_id), {})
	for path_value: Variant in family.get("texture_paths", []):
		var path := String(path_value)
		var texture: Texture2D = _texture_cache.get(path) as Texture2D
		if texture == null:
			if not ResourceLoader.exists(path):
				continue
			texture = ResourceLoader.load(path) as Texture2D
			if texture != null:
				_texture_cache[path] = texture
		if texture != null:
			textures.append(texture)
	return textures

func texture_for(visual_id: int) -> Texture2D:
	var textures := textures_for(visual_id)
	return textures[0] if not textures.is_empty() else null

func has_texture(visual_id: int) -> bool:
	return texture_for(visual_id) != null
