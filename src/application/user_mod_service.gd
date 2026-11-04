class_name UserModService
extends RefCounted

## Player-made mods, enabled per save. The runtime has one shared catalog, so
## exactly one set of mods is active at a time: loading a save activates its
## set, reverting every edit the previous set made first.
##
## A save stores references {id, name, version, fingerprint}. Missing mods stop
## the load with a clear message; an edited mod still loads (the fingerprint
## only reports that it changed since the save last used it).

const VERSION_SEPARATOR := "+mods:"

static var _builders: Array[UserModBuilder] = []
static var _refs: Array[Dictionary] = []
static var _base_version := ""
static var _catalog: ContentCatalog

## The references of the mods currently applied to the catalog.
static func active_refs() -> Array[Dictionary]:
	return _refs.duplicate(true)

static func active_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for ref in _refs: ids.append(String(ref.id))
	return ids

static func is_active(mod_id: String) -> bool:
	return mod_id in active_ids()

## A save reference for an installed mod, or {} when it is not installed.
static func ref_for(mod_id: String) -> Dictionary:
	var loaded := UserModRepository.read(mod_id)
	if not loaded.ok: return {}
	return {"id": mod_id, "name": String(loaded.manifest.name), "version": String(loaded.manifest.get("version", "1")), "fingerprint": UserModRepository.fingerprint(mod_id)}

static func base_content_version(catalog: ContentCatalog) -> String:
	return String(catalog.content_version).get_slice(VERSION_SEPARATOR, 0)

## Applies `refs` (save references, or plain {"id"} dictionaries) to the
## catalog. With `strict`, every fingerprint must match (multiplayer needs both
## games to run identical content). On failure no mod is left active.
static func activate(catalog: ContentCatalog, refs: Array, strict: bool = false) -> Dictionary:
	if _same_set(catalog, refs): return {"ok": true, "changed": [], "refs": active_refs()}
	deactivate(catalog)
	if refs.is_empty(): return {"ok": true, "changed": [], "refs": []}
	var problems := PackedStringArray()
	var changed: Array[String] = []
	var applied: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw in refs:
		var mod_id := String(raw.get("id", "")) if raw is Dictionary else String(raw)
		if seen.has(mod_id): continue
		seen[mod_id] = true
		var loaded := UserModRepository.read(mod_id)
		if not loaded.ok:
			var label := String(raw.get("name", mod_id)) if raw is Dictionary else mod_id
			problems.append("%s is not installed (or cannot be read): %s" % [label, loaded.message])
			continue
		var current := ref_for(mod_id)
		var expected := String(raw.get("fingerprint", "")) if raw is Dictionary else ""
		if not expected.is_empty() and expected != current.fingerprint:
			if strict:
				problems.append("%s differs from the host's copy (version %s here, %s there)" % [current.name, current.version, raw.get("version", "?")])
				continue
			changed.append(current.name)
		var builder := UserModBuilder.new(loaded.manifest, catalog)
		for prior in _builders: builder.prior_packs.append(prior.pack)
		if not builder.build():
			problems.append_array(builder.errors)
			continue
		var prior_sprites := PackedStringArray()
		for prior in _builders: prior_sprites.append_array(PackedStringArray(prior.sprite_requests.keys()))
		problems.append_array(UserModAssets.validation_errors(builder.mod_id, builder.sprite_requests, builder.type_badges, prior_sprites))
		_builders.append(builder)
		applied.append(current)
	if not problems.is_empty():
		deactivate(catalog)
		return {"ok": false, "code": "mod_unavailable", "message": "\n".join(problems)}
	_catalog = catalog
	_base_version = base_content_version(catalog)
	for builder in _builders:
		catalog.packs.append(builder.pack)
		catalog.post_index_hooks.append(builder.apply_room_edits)
		for virtual_name in builder.sprite_requests:
			var failure := UserModAssets.install_sprite(builder.mod_id, virtual_name, builder.sprite_requests[virtual_name])
			if not failure.is_empty(): problems.append(failure)
		for type_id in builder.type_badges:
			UserModAssets.install_type_badges(builder.mod_id, type_id, builder.type_badges[type_id])
	_refs = applied
	catalog.content_version = _base_version + VERSION_SEPARATOR + _set_digest(applied)
	problems.append_array(catalog.rebuild_index())
	if not problems.is_empty():
		deactivate(catalog)
		return {"ok": false, "code": "mod_invalid", "message": "\n".join(problems)}
	return {"ok": true, "changed": changed, "refs": active_refs()}

## The Workshop's Check: builds `manifest` alone against the base catalog and
## undoes everything. Returns {"errors", "warnings"}; the active set is restored.
static func check(catalog: ContentCatalog, manifest: Dictionary) -> Dictionary:
	var previous := active_refs()
	deactivate(catalog)
	var builder := UserModBuilder.new(manifest, catalog)
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	if builder.build():
		errors.append_array(UserModAssets.validation_errors(builder.mod_id, builder.sprite_requests, builder.type_badges))
		catalog.packs.append(builder.pack)
		catalog.post_index_hooks.append(builder.apply_room_edits)
		errors.append_array(catalog.rebuild_index())
		warnings = _warnings(manifest, builder)
		builder.changes.revert()
		catalog.packs.erase(builder.pack)
		catalog.post_index_hooks.erase(builder.apply_room_edits)
		catalog.rebuild_index()
	else:
		errors = builder.errors
	if not previous.is_empty(): activate(catalog, previous)
	return {"errors": errors, "warnings": warnings}

## Things that build fine but are probably not what the author wants.
static func _warnings(manifest: Dictionary, builder: UserModBuilder) -> PackedStringArray:
	var warnings := PackedStringArray()
	var obtainable: Dictionary = {}
	for rule in builder.hatchery_rules:
		for candidate in rule.candidates: obtainable[String(candidate)] = true
	for record in manifest.get("rooms", []):
		for interaction in record.get("interactions", []):
			for candidate in interaction.get("set", {}).get("candidates", []): obtainable[String(candidate)] = true
	var evolved: Dictionary = {}
	for record in manifest.get("minions", []):
		if not String(record.get("evolves_into", "")).is_empty(): evolved[String(record.evolves_into)] = true
	for record in manifest.get("minions", []):
		var id := String(record.get("id", ""))
		if not obtainable.has(id) and not evolved.has(id):
			warnings.append("%s is not in any hatchery, so players cannot get it (trainers may still use it)." % record.get("name", id))
	for record in manifest.get("moves", []):
		var used := false
		var family := String(record.get("id", ""))
		for minion in manifest.get("minions", []) + manifest.get("minion_patches", []):
			for list_key in ["initial_moves", "specialization_moves"]:
				for move_id in minion.get(list_key, []):
					if String(move_id).begins_with(family + "/"): used = true
		if not used: warnings.append("%s is not given to any minion yet (initial or specialization moves)." % record.get("name", family))
	for record in manifest.get("talent_trees", []):
		var tree_id := String(record.get("id", ""))
		var assigned := false
		for minion in manifest.get("minions", []) + manifest.get("minion_patches", []):
			if tree_id in minion.get("talent_trees", []): assigned = true
		if not assigned: warnings.append("The skill tree %s is not given to any minion yet." % record.get("name", tree_id))
	return warnings

static func deactivate(catalog: ContentCatalog) -> void:
	var target := _catalog if _catalog != null else catalog
	if _builders.is_empty() and _refs.is_empty():
		return
	for index in range(_builders.size() - 1, -1, -1):
		var builder := _builders[index]
		builder.changes.revert()
		target.packs.erase(builder.pack)
		target.post_index_hooks.erase(builder.apply_room_edits)
	_builders.clear()
	_refs.clear()
	UserModAssets.clear()
	target.content_version = base_content_version(target)
	target.rebuild_index()
	_catalog = null

static func _same_set(catalog: ContentCatalog, refs: Array) -> bool:
	if _catalog != null and _catalog != catalog: return false
	if refs.size() != _refs.size(): return false
	for index in refs.size():
		var raw: Variant = refs[index]
		var mod_id := String(raw.get("id", "")) if raw is Dictionary else String(raw)
		if mod_id != String(_refs[index].id): return false
		if raw is Dictionary and not String(raw.get("fingerprint", "")).is_empty() and String(raw.fingerprint) != String(_refs[index].fingerprint): return false
		# Re-read: an edit in the Workshop must reach the next activation.
		if UserModRepository.fingerprint(mod_id) != String(_refs[index].fingerprint): return false
	return true

static func _set_digest(refs: Array) -> String:
	var parts := PackedStringArray()
	for ref in refs: parts.append("%s@%s" % [ref.id, ref.fingerprint])
	return ",".join(parts).sha256_text().left(12)

# --- Hooks used by the campaign --------------------------------------------

## Applies active hatchery rules for a source floor (0 = Floor 1).
static func hatchery_pool(source_floor: int, pool: Dictionary) -> Dictionary:
	var result := pool.duplicate(true)
	for builder in _builders:
		for rule in builder.hatchery_rules:
			if int(rule.floor) != source_floor: continue
			if rule.mode == "replace":
				result["candidates"] = rule.candidates.duplicate()
				result["weights"] = rule.weights.duplicate()
				continue
			var weights: Array = result.get("weights", []).duplicate()
			var candidates: Array = result.get("candidates", []).duplicate()
			var added := 0
			for weight in rule.weights: added += int(weight)
			var total := 0
			for weight in weights: total += maxi(0, int(weight))
			if weights.size() != candidates.size() or total <= 0:
				result["candidates"] = rule.candidates.duplicate()
				result["weights"] = rule.weights.duplicate()
				continue
			# Same integer rescale as Starter Eggs: originals share what is left.
			var remaining := 100 - added
			var assigned := 0
			for index in weights.size():
				var scaled := int(maxi(0, int(weights[index])) * float(remaining) / total)
				weights[index] = scaled
				assigned += scaled
			weights[0] = int(weights[0]) + remaining - assigned
			candidates.append_array(rule.candidates)
			weights.append_array(rule.weights)
			result["candidates"] = candidates
			result["weights"] = weights
	return result

static func dialogue_for(encounter_id: StringName) -> Dictionary:
	var lines: Dictionary = {}
	for builder in _builders:
		lines.merge(builder.dialogue.get(String(encounter_id), {}), true)
	return lines

static func is_mod_definition(definition: ContentDefinition) -> bool:
	return definition != null and String(definition.source_mod).begins_with("user:")

## Whether a save may stop using a mod: nothing it owns may depend on it.
static func removal_blockers(state, mod_id: String) -> PackedStringArray:
	var prefix := "%s:" % mod_id
	var blockers := PackedStringArray()
	for owned in state.party + state.storage:
		var name: String = owned.nickname if not owned.nickname.is_empty() else String(owned.definition_id).get_file()
		if String(owned.definition_id).begins_with(prefix):
			blockers.append("%s is one of its minions" % name)
		for move_id in owned.learned_move_ids:
			if String(move_id).begins_with(prefix):
				blockers.append("%s knows one of its moves" % name)
				break
	for gem in state.owned_gems:
		if String(gem.get("move_id", "")).begins_with(prefix) or String(gem.get("type_id", "")).begins_with(prefix):
			blockers.append("a skill gem uses one of its moves")
			break
	# A patch in another enabled mod may refer to this mod's types or moves.
	# Catalog validation in set_user_mod checks those dependencies after removal.
	return blockers
