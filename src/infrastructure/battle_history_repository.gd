class_name BattleHistoryRepository
extends RefCounted

## The battles this PC recorded or imported, kept next to the saves (never in
## a save file). `index.json` lists summaries newest first; each replay is its
## own compressed file so the list opens without decoding every battle.
## Only the newest MAX_RECENT unkept battles stay; kept ones are never pruned.

const MAX_RECENT := 30
const MAX_KEPT := 100
const DEFAULT_ROOT := "user://battle_history"

const TEST_ROOT := "user://battle_history_tests"

var root := DEFAULT_ROOT

func _init(base_dir: String = "") -> void:
	root = base_dir if not base_dir.is_empty() else default_root()

## Automated tests (launched with a res://tests/ script or scene) play real
## battles; their recordings stay out of the player's own history.
static func default_root() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("res://tests/"):
			return TEST_ROOT
	return DEFAULT_ROOT

## Summaries, newest first: {id, title, outcome, kind, recorded_at, turns, kept, imported}.
func list() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var file := FileAccess.open(_index_path(), FileAccess.READ)
	if file == null:
		return entries
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		for entry in parsed:
			if entry is Dictionary and not String(entry.get("id", "")).is_empty():
				entries.append(entry)
	return entries

## Store a replay; returns its id ("" if it could not be written).
func add(replay: Dictionary, imported: bool = false) -> String:
	var fingerprint := MultiplayerWorldSync.fingerprint(replay)
	for existing in list():
		if int(existing.get("hash", 0)) == fingerprint:
			# The same code pasted again: keep the one already listed.
			if imported and not bool(existing.get("kept", false)):
				set_kept(String(existing.id), true)
			return String(existing.id)
	DirAccess.make_dir_recursive_absolute(root)
	var id := "%d-%04d" % [int(Time.get_unix_time_from_system() * 1000.0), randi() % 10000]
	var file := FileAccess.open(_replay_path(id), FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(var_to_bytes(replay).compress(FileAccess.COMPRESSION_DEFLATE))
	file.close()
	var entries := list()
	var entry := summary(replay, id, imported)
	entry["hash"] = fingerprint
	entries.push_front(entry)
	_write_index(_pruned(entries))
	return id

## {"ok", "replay"} for a stored id.
func load_replay(id: String) -> Dictionary:
	if not _is_safe_id(id):
		return {"ok": false, "message": "Unknown replay."}
	var file := FileAccess.open(_replay_path(id), FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "This replay file is missing."}
	var raw := file.get_buffer(file.get_length()).decompress_dynamic(BattleReplay.MAX_DECODED_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return {"ok": false, "message": "This replay file is damaged."}
	return BattleReplay.validate(bytes_to_var(raw))

func set_kept(id: String, kept: bool) -> bool:
	var entries := list()
	var kept_count := entries.filter(func(entry: Dictionary) -> bool: return bool(entry.get("kept", false))).size()
	for entry in entries:
		if String(entry.id) == id:
			if kept and not bool(entry.get("kept", false)) and kept_count >= MAX_KEPT:
				return false
			entry["kept"] = kept
	_write_index(_pruned(entries))
	return true

func remove(id: String) -> void:
	var entries := list().filter(func(entry: Dictionary) -> bool: return String(entry.id) != id)
	if _is_safe_id(id):
		DirAccess.remove_absolute(_replay_path(id))
	_write_index(entries)

static func summary(replay: Dictionary, id: String, imported: bool) -> Dictionary:
	return {
		"id": id,
		"title": BattleReplay.title(replay),
		"outcome": BattleReplay.outcome(replay),
		"kind": BattleReplay.kind_label(replay),
		"recorded_at": int(replay.get("recorded_at", 0)),
		"turns": BattleReplay.turn_count(replay),
		"kept": imported,
		"imported": imported,
	}

## Newest MAX_RECENT unkept entries plus every kept one; dropped files are deleted.
func _pruned(entries: Array[Dictionary]) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	var recent := 0
	for entry in entries:
		if bool(entry.get("kept", false)) or recent < MAX_RECENT:
			if not bool(entry.get("kept", false)):
				recent += 1
			kept.append(entry)
		elif _is_safe_id(String(entry.id)):
			DirAccess.remove_absolute(_replay_path(String(entry.id)))
	return kept

func _write_index(entries: Array) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var file := FileAccess.open(_index_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries, "\t"))

func _index_path() -> String:
	return root.path_join("index.json")

func _replay_path(id: String) -> String:
	return root.path_join(id + ".mhr")

## Ids come from the index file; never let one walk out of the folder.
static func _is_safe_id(id: String) -> bool:
	return not id.is_empty() and id.is_valid_filename() and not id.contains("..")
