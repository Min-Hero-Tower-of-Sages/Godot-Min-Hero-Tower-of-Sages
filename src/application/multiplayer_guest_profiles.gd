class_name MultiplayerGuestProfiles
extends RefCounted

## Host-side store of every guest's profile in one world (see
## MultiplayerWorldSync.extract_profile), keyed by lowercase username. A guest
## who comes back under the same name gets the same team, whatever save they
## pick on their side. One JSON file per host world, named after the world's
## `multiplayer_world_id`, so starting a new campaign starts with no guests.

const DIRECTORY := "user://multiplayer_profiles"

var world_id := ""
## lowercase name -> {"name", "number", "profile"}
var entries: Dictionary = {}
## Free-form values kept with the store (e.g. a versus race's chest seed).
var meta: Dictionary = {}
var _next_number := 1
var _dirty := false

static func key_for(username: String) -> String:
	return username.strip_edges().to_lower()

func path() -> String:
	return "%s/%s.json" % [DIRECTORY, world_id]

func open(id: String) -> void:
	world_id = id
	entries.clear()
	meta.clear()
	_next_number = 1
	_dirty = false
	if not FileAccess.file_exists(path()):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path()))
	if not parsed is Dictionary:
		push_warning("Multiplayer guest profiles at %s are unreadable; starting empty." % path())
		return
	entries = (parsed.get("guests", {}) as Dictionary).duplicate(true)
	meta = (parsed.get("meta", {}) as Dictionary).duplicate(true)
	_next_number = maxi(1, int(parsed.get("next_number", 1)))
	for key in entries:
		_next_number = maxi(_next_number, int(entries[key].get("number", 0)) + 1)

func has_profile(username: String) -> bool:
	return entries.has(key_for(username))

func profile(username: String) -> Dictionary:
	return (entries.get(key_for(username), {}).get("profile", {}) as Dictionary).duplicate(true)

## Stable per-guest number; it prefixes new minion/gem IDs on that guest's side.
func number_for(username: String) -> int:
	var key := key_for(username)
	if not entries.has(key):
		entries[key] = {"name": username.strip_edges(), "number": _next_number, "profile": {}}
		_next_number += 1
		_dirty = true
	return int(entries[key].number)

func store(username: String, data: Dictionary) -> void:
	number_for(username)
	var entry: Dictionary = entries[key_for(username)]
	entry["name"] = username.strip_edges()
	entry["profile"] = data.duplicate(true)
	_dirty = true

func forget(username: String) -> void:
	if entries.erase(key_for(username)):
		_dirty = true

func set_meta_value(key: String, value: Variant) -> void:
	meta[key] = value
	_dirty = true

## [{"key", "name", "number", "has_team"}] sorted by name, for the host's
## saved-players list.
func listing() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in entries:
		result.append({"key": String(key), "name": String(entries[key].get("name", key)), "number": int(entries[key].get("number", 0)), "has_team": not (entries[key].get("profile", {}) as Dictionary).is_empty()})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return result

func save_if_dirty() -> void:
	if _dirty and not world_id.is_empty():
		save()

func save() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var file := FileAccess.open(path(), FileAccess.WRITE)
	if file == null:
		push_error("Could not write multiplayer guest profiles to %s." % path())
		return
	file.store_string(JSON.stringify({"next_number": _next_number, "guests": entries, "meta": meta}, "\t"))
	file.close()
	_dirty = false
