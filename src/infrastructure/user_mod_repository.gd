class_name UserModRepository
extends RefCounted

## Player-made mods on disk: user://mods/<id>/mod.json plus optional PNGs in
## user://mods/<id>/sprites/. Share codes and ZIP files carry the same data.
## Everything read here is data; UserModBuilder decides what it may change.

const MANIFEST := "mod.json"
const CODE_PREFIX := "MHMOD1:"
const MAX_MANIFEST_BYTES := 1 << 20
const MAX_SPRITE_BYTES := 1 << 20
const MAX_SPRITES := 48
const MAX_CODE_BYTES := 64 << 20

## Tests point this at a scratch folder.
static var root := "user://mods"

static func valid_id(id: String) -> bool:
	return RegEx.create_from_string(UserModBuilder.ID_PATTERN).search(id) != null and id not in ["base", "extended", "user"]

static func valid_sprite_path(path: String) -> bool:
	return path.begins_with("sprites/") and path.get_extension().to_lower() == "png" and not path.contains("..") and not path.contains("\\") and not path.contains(":") and path.trim_prefix("sprites/") == path.get_file() and path.get_file().validate_filename() == path.get_file()

static func mod_dir(id: String) -> String:
	return root.path_join(id)

static func list() -> Array[Dictionary]:
	var mods: Array[Dictionary] = []
	var dir := DirAccess.open(root)
	if dir == null: return mods
	var names := dir.get_directories()
	names.sort()
	for name in names:
		if name.begins_with("."): continue
		var loaded := read(name)
		if loaded.ok:
			mods.append(loaded.manifest)
		else:
			mods.append({"id": name, "name": name, "broken": true, "message": loaded.message})
	return mods

static func exists(id: String) -> bool:
	return valid_id(id) and (FileAccess.file_exists(mod_dir(id).path_join(MANIFEST)) or FileAccess.file_exists(mod_dir(id).path_join(MANIFEST + ".bak")))

static func read(id: String) -> Dictionary:
	if not valid_id(id):
		return _error("invalid_id", "%s is not a valid mod folder name" % id)
	var path := mod_dir(id).path_join(MANIFEST)
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path + ".bak"): path += ".bak"
	if not FileAccess.file_exists(path): return _error("not_found", "Mod %s is not installed." % id)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_MANIFEST_BYTES: return _error("unreadable", "Mod %s could not be read." % id)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK: return _error("invalid_mod", "Mod %s is not valid JSON: %s" % [id, parser.get_error_message()])
	var parsed: Variant = parser.data
	var problems := UserModBuilder.header_errors(parsed)
	if not problems.is_empty(): return _error("invalid_mod", "Mod %s: %s" % [id, "; ".join(problems)])
	if String(parsed.id) != id: return _error("invalid_mod", "Mod folder %s holds mod %s" % [id, parsed.id])
	return {"ok": true, "manifest": parsed}

## Writes atomically: a crash mid-save keeps the previous manifest.
static func write(manifest: Dictionary) -> Dictionary:
	var problems := UserModBuilder.header_errors(manifest)
	if not problems.is_empty(): return _error("invalid_mod", "; ".join(problems))
	var dir := mod_dir(String(manifest.id))
	if DirAccess.make_dir_recursive_absolute(dir.path_join("sprites")) != OK: return _error("write_failed", "Could not create %s" % dir)
	var path := dir.path_join(MANIFEST)
	var backup := path + ".bak"
	var data := JSON.stringify(manifest, "\t")
	if data.to_utf8_buffer().size() > MAX_MANIFEST_BYTES: return _error("invalid_mod", "The mod manifest is larger than 1 MB.")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return _error("write_failed", "Could not write %s" % path)
	file.store_string(data)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return _error("write_failed", "Could not finish writing %s" % path)
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK: return _error("write_failed", "Could not update %s" % backup)
		if DirAccess.rename_absolute(path, backup) != OK: return _error("write_failed", "Could not back up %s" % path)
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		if FileAccess.file_exists(backup): DirAccess.rename_absolute(backup, path)
		return _error("write_failed", "Could not save %s" % path)
	return {"ok": true}

static func delete(id: String) -> Dictionary:
	if not exists(id): return _error("not_found", "Mod %s is not installed." % id)
	_remove_tree(mod_dir(id))
	return {"ok": true}

static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for child in dir.get_directories(): _remove_tree(path.path_join(child))
	for file in dir.get_files(): DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)

static func sprite_files(id: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(mod_dir(id).path_join("sprites"))
	if dir == null: return result
	for file in dir.get_files():
		if file.get_extension().to_lower() == "png": result.append("sprites/" + file)
	result.sort()
	return result

static func read_file(id: String, relative: String) -> PackedByteArray:
	if not valid_id(id) or not valid_sprite_path(relative): return PackedByteArray()
	var path := mod_dir(id).path_join(relative)
	if not FileAccess.file_exists(path): return PackedByteArray()
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_buffer(file.get_length()) if file != null and file.get_length() <= MAX_SPRITE_BYTES else PackedByteArray()

## Copies a PNG the player picked into the mod. Returns its relative path.
static func import_sprite(id: String, source_path: String, name: String) -> Dictionary:
	if not exists(id): return _error("not_found", "Create the mod before importing art.")
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty(): return _error("bad_image", "That file is not a readable image.")
	return import_image(id, image, name)

## Saves an image already in memory (e.g. cropped in the Workshop) as mod art.
static func import_image(id: String, image: Image, name: String) -> Dictionary:
	if not exists(id): return _error("not_found", "Create the mod before importing art.")
	if image == null or image.is_empty(): return _error("bad_image", "That file is not a readable image.")
	if image.get_width() > 512 or image.get_height() > 512: return _error("bad_image", "Sprites can be at most 512 x 512 pixels.")
	var safe := name.to_lower().validate_filename().replace(" ", "_").left(40)
	if safe.is_empty() or safe.begins_with("."): safe = "sprite"
	var relative := "sprites/%s.png" % safe
	var bytes := image.save_png_to_buffer()
	if bytes.size() > MAX_SPRITE_BYTES: return _error("bad_image", "That sprite is larger than 1 MB once saved.")
	if not FileAccess.file_exists(mod_dir(id).path_join(relative)) and sprite_files(id).size() >= MAX_SPRITES: return _error("bad_image", "A mod can contain at most %d PNG files." % MAX_SPRITES)
	DirAccess.make_dir_recursive_absolute(mod_dir(id).path_join("sprites"))
	var file := FileAccess.open(mod_dir(id).path_join(relative), FileAccess.WRITE)
	if file == null: return _error("write_failed", "Could not copy the sprite.")
	file.store_buffer(bytes)
	file.close()
	return {"ok": true, "path": relative}

## A stable digest of everything that changes how the mod plays or looks.
static func fingerprint(id: String) -> String:
	var loaded := read(id)
	if not loaded.ok: return ""
	return fingerprint_of(loaded.manifest, _sprites_of(id))

static func fingerprint_of(manifest: Dictionary, sprites: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(manifest, "", true).to_utf8_buffer())
	var names := sprites.keys()
	names.sort()
	for name in names:
		context.update(String(name).to_utf8_buffer())
		context.update(sprites[name])
	return context.finish().hex_encode().left(16)

static func _sprites_of(id: String) -> Dictionary:
	var sprites: Dictionary = {}
	for relative in sprite_files(id): sprites[relative] = read_file(id, relative)
	return sprites

# --- Sharing ---------------------------------------------------------------

static func export_code(id: String) -> Dictionary:
	var loaded := read(id)
	if not loaded.ok: return loaded
	var files: Dictionary = {}
	var sprites := _sprites_of(id)
	for relative in sprites: files[relative] = Marshalls.raw_to_base64(sprites[relative])
	var raw := JSON.stringify({"manifest": loaded.manifest, "files": files}).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return {"ok": true, "code": CODE_PREFIX + Marshalls.raw_to_base64(packed), "bytes": packed.size()}

## Reads a share code without installing it. `{"ok", "manifest", "files"}`.
static func decode_code(code: String) -> Dictionary:
	if code.length() > MAX_CODE_BYTES * 2: return _error("bad_code", "The mod code is too large.")
	var trimmed := code.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	if not trimmed.begins_with(CODE_PREFIX): return _error("bad_code", "That is not a Min Hero mod code.")
	var packed := Marshalls.base64_to_raw(trimmed.trim_prefix(CODE_PREFIX))
	# Godot's DEFLATE output is a zlib stream; reject an invalid header before
	# asking the decompressor to read it.
	if packed.size() < 6 or (packed[0] & 15) != 8 or ((int(packed[0]) << 8) + packed[1]) % 31 != 0: return _error("bad_code", "The mod code is damaged.")
	var raw := packed.decompress_dynamic(MAX_CODE_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty(): return _error("bad_code", "The mod code is damaged.")
	var parser := JSON.new()
	if parser.parse(raw.get_string_from_utf8()) != OK: return _error("bad_code", "The mod code is damaged.")
	var parsed: Variant = parser.data
	if not parsed is Dictionary or not parsed.get("manifest") is Dictionary or not parsed.get("files", {}) is Dictionary:
		return _error("bad_code", "The mod code is damaged.")
	var files: Dictionary = {}
	for relative in parsed.get("files", {}):
		if not parsed.files[relative] is String: return _error("bad_code", "The mod code contains a damaged file.")
		files[String(relative)] = Marshalls.base64_to_raw(String(parsed.files[relative]))
	return _validate_bundle(parsed.manifest, files)

static func _validate_bundle(manifest: Dictionary, files: Dictionary) -> Dictionary:
	var problems := UserModBuilder.header_errors(manifest)
	if not problems.is_empty(): return _error("invalid_mod", "; ".join(problems))
	if JSON.stringify(manifest).to_utf8_buffer().size() > MAX_MANIFEST_BYTES: return _error("invalid_mod", "The mod manifest is larger than 1 MB.")
	if files.size() > MAX_SPRITES: return _error("invalid_mod", "The mod has too many sprites.")
	for relative in files:
		var path := String(relative)
		if not valid_sprite_path(path):
			return _error("invalid_mod", "The mod contains an unexpected file %s." % path)
		if not files[relative] is PackedByteArray: return _error("invalid_mod", "The mod contains a damaged sprite %s." % path)
		var bytes: PackedByteArray = files[relative]
		var image := Image.new()
		if bytes.size() > MAX_SPRITE_BYTES or image.load_png_from_buffer(bytes) != OK:
			return _error("invalid_mod", "The mod contains a damaged sprite %s." % path)
		if image.get_width() > 512 or image.get_height() > 512: return _error("invalid_mod", "Sprites can be at most 512 x 512 pixels.")
	return {"ok": true, "manifest": manifest, "files": files}

static func install_bundle(bundle: Dictionary, overwrite: bool) -> Dictionary:
	if not bundle.get("manifest") is Dictionary or not bundle.get("files") is Dictionary: return _error("invalid_mod", "The mod bundle is damaged.")
	var validated := _validate_bundle(bundle.manifest, bundle.files)
	if not validated.ok: return validated
	var manifest: Dictionary = bundle.manifest
	var id := String(manifest.id)
	if exists(id) and not overwrite: return _error("exists", "A mod called %s is already installed." % id)
	# Stage the complete folder first. A failed import keeps the installed copy.
	var staging := root.path_join(".install_%s" % id)
	_remove_tree(staging)
	if DirAccess.make_dir_recursive_absolute(staging.path_join("sprites")) != OK: return _error("write_failed", "Could not create the mod folder.")
	var manifest_file := FileAccess.open(staging.path_join(MANIFEST), FileAccess.WRITE)
	if manifest_file == null: return _error("write_failed", "Could not write the mod manifest.")
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.flush()
	var manifest_error := manifest_file.get_error()
	manifest_file.close()
	if manifest_error != OK: return _error("write_failed", "Could not finish writing the mod manifest.")
	for relative in bundle.files:
		var file := FileAccess.open(staging.path_join(relative), FileAccess.WRITE)
		if file == null: return _error("write_failed", "Could not write %s." % relative)
		file.store_buffer(bundle.files[relative])
		file.flush()
		var write_error := file.get_error()
		file.close()
		if write_error != OK: return _error("write_failed", "Could not finish writing %s." % relative)
	var backup := root.path_join(".backup_%s" % id)
	_remove_tree(backup)
	var had_previous := DirAccess.dir_exists_absolute(mod_dir(id))
	if had_previous and _rename_mod_directory(mod_dir(id), backup) != OK: return _error("write_failed", "Could not back up %s." % id)
	if _rename_mod_directory(staging, mod_dir(id)) != OK:
		if had_previous: _rename_mod_directory(backup, mod_dir(id))
		return _error("write_failed", "Could not install %s." % id)
	_remove_tree(backup)
	return {"ok": true, "id": id}

## Windows can briefly keep a just-deleted directory locked. Retry its generic
## rename failure for at most 80 ms, retaining the staged files and backup so
## a persistent failure still follows the ordinary rollback path.
static func _rename_mod_directory(source: String, destination: String) -> Error:
	var error := DirAccess.rename_absolute(source, destination)
	for retry in 4:
		if error != FAILED or OS.get_name() != "Windows": return error
		OS.delay_msec(20)
		error = DirAccess.rename_absolute(source, destination)
	return error

static func export_zip(id: String, destination_dir: String = "user://mod_exports") -> Dictionary:
	var loaded := read(id)
	if not loaded.ok: return loaded
	DirAccess.make_dir_recursive_absolute(destination_dir)
	var path := destination_dir.path_join("%s.zip" % id)
	var zip := ZIPPacker.new()
	if zip.open(path) != OK: return _error("write_failed", "Could not create %s." % path)
	zip.start_file(MANIFEST)
	zip.write_file(JSON.stringify(loaded.manifest, "\t").to_utf8_buffer())
	zip.close_file()
	var sprites := _sprites_of(id)
	for relative in sprites:
		zip.start_file(relative)
		zip.write_file(sprites[relative])
		zip.close_file()
	zip.close()
	return {"ok": true, "path": path}

static func decode_zip(path: String) -> Dictionary:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > MAX_CODE_BYTES: return _error("bad_zip", "The ZIP is missing or larger than 64 MB.")
	source.close()
	var zip := ZIPReader.new()
	if zip.open(path) != OK: return _error("bad_zip", "That file is not a readable ZIP.")
	var manifest: Variant = null
	var files: Dictionary = {}
	for entry in zip.get_files():
		if entry.ends_with("/"): continue
		# Accept a top-level folder (zipping the mod folder itself).
		var relative := entry if entry == MANIFEST or entry.begins_with("sprites/") else entry.substr(entry.find("/") + 1)
		if relative == MANIFEST:
			manifest = JSON.parse_string(zip.read_file(entry).get_string_from_utf8())
		elif relative.begins_with("sprites/"):
			files[relative] = zip.read_file(entry)
		else:
			zip.close()
			return _error("invalid_mod", "The ZIP contains an unexpected file %s." % entry)
	zip.close()
	if not manifest is Dictionary: return _error("invalid_mod", "The ZIP has no mod.json.")
	return _validate_bundle(manifest, files)

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
