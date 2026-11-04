extends SceneTree

const EXAMPLE := "res://content/mods/examples/frost_pack.json"

class MemoryRepository extends SaveRepository:
	var payloads: Dictionary = {}
	var reject := false
	func save_slot(slot: int, data: Dictionary) -> Dictionary:
		if reject: return {"ok": false, "message": "Fixture save rejection"}
		var validation := validate(data)
		if not validation.ok: return validation
		payloads[slot] = JSON.parse_string(JSON.stringify(data))
		return {"ok": true}
	func load_slot(slot: int) -> Dictionary:
		return {"ok": true, "state": payloads[slot].duplicate(true)} if payloads.has(slot) else {"ok": false, "code": "not_found"}

var catalog: ContentCatalog
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _run() -> void:
	await process_frame
	catalog = root.get_node("CampaignRuntime").catalog
	UserModRepository.root = "user://test_user_mods_%d" % Time.get_ticks_usec()
	_check(catalog.ensure_index().is_empty(), "Base catalog is valid")
	var example: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE))
	_check(UserModRepository.write(example).ok, "Install the example mod")
	_check_activation()
	_check_cross_mods()
	_check_rejections()
	_check_rooms()
	_check_session()
	_check_runtime_starters()
	_check_sharing()
	UserModService.deactivate(catalog)
	UserModRepository._remove_tree(UserModRepository.root)
	for failure in failures: push_error(failure)
	print("PASS: user mod build, patch revert, art, hatchery, dialogue, per-save activation, removal guard, share codes and ZIPs" if failures.is_empty() else "FAIL: user mods (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_activation() -> void:
	var base_version := String(catalog.content_version)
	var anteater := catalog.get_definition(&"base:minion/anteater_1") as MinionDefinition
	var original_attack := anteater.base_attack
	var chart := catalog.get_type_chart()
	var original_chart := chart.multipliers.duplicate(true)
	var encounter := catalog.get_definition(&"base:encounter/grass_floor1_room1_normal") as EncounterDefinition
	var original_team := encounter.team_entries.duplicate(true)
	var activated := UserModService.activate(catalog, [{"id": "frost_pack"}])
	_check(activated.ok, "Activate example: %s" % activated.get("message", ""))
	if not activated.ok: return
	_check(catalog.ensure_index().is_empty(), "Modded catalog is valid: %s" % ", ".join(catalog.ensure_index()))
	var cub := catalog.get_definition(&"frost_pack:minion/frostcub_1") as MinionDefinition
	_check(cub != null and cub.display_name == "Frostcub" and cub.type_ids == [&"frost_pack:type/frost"], "New minion is registered")
	_check(cub != null and cub.evolution_id == &"frost_pack:minion/frostcub_2" and cub.evolution_level == 32, "Mod evolution line")
	_check(cub != null and cub.talent_tree_ids == [&"base:talent_tree/tiger_speed", &"base:talent_tree/tiger_gaurd", &"frost_pack:talent_tree/frost_arts"], "Minion may mix recovered and mod talent trees")
	var arts := catalog.get_definition(&"frost_pack:talent_tree/frost_arts") as TalentTreeDefinition
	_check(arts != null and arts.display_name == "Frost Arts" and arts.nodes.size() == 7 and arts.validation_errors().is_empty(), "Mod talent tree is built and valid")
	_check(arts != null and arts.nodes[4].prerequisite_node_ids == ["frost_pack:talent_tree/frost_arts/node/1_0"] and arts.nodes[4].move_ids.size() == 3, "Tree skills keep their ranks and requirements")
	var tiger_tree := catalog.get_definition(&"base:talent_tree/tiger_normal") as TalentTreeDefinition
	var copied := UserModBuilder.tree_record(tiger_tree)
	_check(copied.nodes.size() == tiger_tree.nodes.size() and copied.name == tiger_tree.display_name, "A recovered tree converts to an editable record")
	var frost_owned := OwnedMinionState.new()
	frost_owned.instance_id = &"frost-tree-test"
	frost_owned.definition_id = cub.id
	frost_owned.level = 9
	frost_owned.experience = 9000
	frost_owned.learned_move_ids.assign(cub.initial_move_ids)
	var specialization := CampaignProgressionService.purchase_talent_choice(frost_owned, cub, catalog, &"frost_pack:move/frost_bite/tier2")
	_check(specialization.ok, "A mod minion can pick a mod move as its third specialization")
	var tree_choices := CampaignProgressionService.talent_choices(frost_owned, cub, catalog)
	_check(tree_choices.size() == 3 and tree_choices.all(func(choice: Dictionary) -> bool: return int(choice.tree_index) == 2), "The chosen specialization opens the mod tree's first row: %s" % [tree_choices.map(func(choice: Dictionary) -> String: return String(choice.move_id))])
	var rank_one := CampaignProgressionService.purchase_talent_choice(frost_owned, cub, catalog, &"frost_pack:move/frost_bite/tier3")
	_check(rank_one.ok and &"frost_pack:talent_tree/frost_arts/node/1_0" in frost_owned.talent_node_ids, "Buying from a mod tree records the tree node")
	var bite := catalog.get_definition(&"frost_pack:move/frost_bite/tier3") as MoveDefinition
	_check(bite != null and bite.tier == 3 and bite.effects.size() == 2 and bite.effects[1].kind == EffectDefinition.Kind.PERIODIC_DAMAGE, "Move tiers and effects are built")
	_check(bite != null and bite.effects[0].executor == UserModBuilder.DAMAGE and bite.legacy_visual_id == (catalog.get_definition(&"base:move/burn/tier1") as MoveDefinition).legacy_visual_id, "Executors come from the whitelist; visuals from looks_like")
	_check(anteater.base_attack == 34, "Minion patch applies")
	_check(is_equal_approx(chart.multiplier(&"frost_pack:type/frost", &"base:type/plant"), 1.5) and is_equal_approx(chart.multiplier(&"base:type/fire", &"frost_pack:type/frost"), 1.5), "Type chart entries apply")
	_check(encounter.team_entries.size() == 2 and encounter.team_entries[0].definition_id == &"frost_pack:minion/frostcub_1", "Trainer team edit applies")
	var dialogue: Dictionary = preload("res://src/application/source_trainer_dialogue.gd").for_encounter(encounter)
	_check(dialogue.get("trainer_name") == "Frosty Fan" and String(dialogue.get("first_visit_text")).begins_with("Have you seen"), "Trainer dialogue override")
	var pool := CampaignModService.egg_pool(null, 0, {"candidates": ["base:minion/grasssnake_1", "base:minion/grassgorilla_1"], "weights": [60, 40]})
	var total := 0
	for weight in pool.weights: total += int(weight)
	_check("frost_pack:minion/frostcub_1" in pool.candidates and total == 100 and int(pool.weights[2]) == 15, "Hatchery addition rescales to 100: %s" % [pool])
	_check(CampaignModService.minion_is_available(null, cub), "Mod minions are acquirable while active")
	var presentation := catalog.get_definition(cub.presentation_id) as MinionPresentationDefinition
	var sprite_path := "res://content/base/art/battle/minions/%s.png" % presentation.legacy_sprite_name
	_check(ResourceLoader.exists(sprite_path) and load(sprite_path) is Texture2D, "Recolored sprite is reachable by its sprite name")
	var tiger_sprite := load("res://content/base/art/battle/minions/normalTiger1.png") as Texture2D
	_check(tiger_sprite != null and tiger_sprite.get_image().get_pixelv(Vector2i(tiger_sprite.get_size() / 2)) != (load(sprite_path) as Texture2D).get_image().get_pixelv(Vector2i(tiger_sprite.get_size() / 2)), "Sprite is recolored")
	var badge := SourceMenuArt.texture("menus_minionType_frost")
	_check(badge != null and badge.get_size() == SourceMenuArt.texture("menus_minionType_fire").get_size(), "Generated type badge matches the recovered badge size")
	_check(String(catalog.content_version).begins_with(base_version + UserModService.VERSION_SEPARATOR), "Content version names the mod set")
	_check(UserModService.activate(catalog, [{"id": "frost_pack"}]).ok and catalog.get_definition(&"frost_pack:minion/frostcub_1") == cub, "Re-activating the same set is a no-op")
	var stale := UserModService.active_refs()
	stale[0].fingerprint = "old-copy"
	_check(UserModService.activate(catalog, stale).get("changed", []) == ["Frost Pack"], "An already active mod still reports a stale save fingerprint")
	_check(not UserModService.activate(catalog, stale, true).ok, "Multiplayer rejects a different expected fingerprint even when the installed mod was active")
	_check(UserModService.activate(catalog, [{"id": "frost_pack"}]).ok, "Restore the example after strict rejection")
	var fresh := MultiplayerWorldSync.fresh_profile(catalog, {"name": "Mod racer"}, "race-mod-")
	var race := MultiplayerWorldSync.race_state_payload(catalog, &"base:campaign/standard_tower", fresh, 17, String(catalog.content_version))
	_check(race.user_mods == UserModService.active_refs(), "Race states retain the exact host mod set")
	UserModService.deactivate(catalog)
	_check(catalog.get_definition(&"frost_pack:minion/frostcub_1") == null, "Deactivation removes additions")
	_check(anteater.base_attack == original_attack and chart.multipliers == original_chart and encounter.team_entries == original_team, "Deactivation reverts edits exactly")
	_check(String(catalog.content_version) == base_version and SourceMenuArt.texture("menus_minionType_frost") == null, "Deactivation restores version and art")
	_check(catalog.ensure_index().is_empty(), "Catalog valid after revert")

func _check_cross_mods() -> void:
	var addon := {"format": 1, "id": "frost_addon", "name": "Frost Addon", "minions": [{"id": "frost_addon:minion/buddy", "name": "Frost Buddy", "based_on": "frost_pack:minion/frostcub_1", "sprite": {"from": "frost_pack:minion/frostcub_1"}}]}
	UserModRepository.write(addon)
	var activated := UserModService.activate(catalog, [{"id": "frost_pack"}, {"id": "frost_addon"}])
	_check(activated.ok and catalog.has_definition(&"frost_addon:minion/buddy"), "Later mods can copy earlier mods' minions, types, moves and runtime art: %s" % activated.get("message", ""))
	UserModService.deactivate(catalog)
	_check(not UserModService.activate(catalog, [{"id": "frost_addon"}, {"id": "frost_pack"}]).ok, "Cross-mod references require dependency order")
	_check(catalog.ensure_index().is_empty() and UserModService.active_ids().is_empty(), "A failed dependency order leaves the base catalog intact")
	UserModRepository.delete("frost_addon")

func _check_rejections() -> void:
	var anteater := catalog.get_definition(&"base:minion/anteater_1") as MinionDefinition
	var before := anteater.base_attack
	var bad := {"format": 1, "id": "broken_mod", "name": "Broken",
		"minion_patches": [{"target": "base:minion/anteater_1", "stats": {"attack": 99}}],
		"moves": [{"id": "broken_mod:move/hack", "name": "Hack", "looks_like": "base:move/claw/tier1", "tiers": [{"effects": [{"kind": "revive", "executor": "res://tests/evil.gd"}]}]}]}
	_check(UserModRepository.write(bad).ok, "Write broken mod")
	var result := UserModService.activate(catalog, [{"id": "broken_mod"}])
	_check(not result.ok and String(result.message).contains("kind must be one of"), "Unsupported effect kinds are rejected: %s" % result.get("message", ""))
	_check(anteater.base_attack == before and UserModService.active_ids().is_empty(), "A failed mod leaves nothing applied")
	var collision := {"format": 1, "id": "clash_mod", "name": "Clash", "types": [{"id": "clash_mod:type/fire", "name": "Fire 2"}]}
	UserModRepository.write(collision)
	_check(not UserModService.activate(catalog, [{"id": "clash_mod"}]).ok, "Type names may not shadow recovered type art")
	_check(not UserModService.activate(catalog, [{"id": "not_installed"}]).ok, "Missing mods are reported")
	_check(not UserModBuilder.header_errors({"format": 1, "id": "base", "name": "x"}).is_empty(), "Reserved namespaces are refused")
	_check(not UserModRepository.decode_code("MHMOD1:AAAA").ok and not UserModRepository.decode_code("hello").ok, "Damaged codes are refused")
	for malformed in [
		{"format": {}, "id": "bad_shape", "name": "Bad"},
		{"format": 1, "id": "bad_shape", "name": "Bad", "rooms": [{"target": "base:room/level_1_1_h2", "exits": false}]},
		{"format": 1, "id": "bad_shape", "name": "Bad", "minions": [false]},
		{"format": 1, "id": "bad_shape", "name": "Bad", "moves": [{"id": "bad_shape:move/test", "looks_like": []}]},
	]:
		_check(not UserModBuilder.header_errors(malformed).is_empty(), "Malformed field shapes are rejected without executing builder paths")
	var missing_art: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE))
	missing_art.minions[0].sprite = {"file": "sprites/missing.png"}
	_check(not UserModService.check(catalog, missing_art).errors.is_empty(), "Check mod reports missing art before a test battle")
	UserModRepository.delete("broken_mod")
	UserModRepository.delete("clash_mod")
	_check_bad_trees()

func _check_bad_trees() -> void:
	var rank := "base:move/claw/tier1"
	var cases := {
		"outside the grid": [{"column": 3, "row": 0, "moves": [rank], "requires": []}],
		"two skills in one box": [{"column": 0, "row": 0, "moves": [rank], "requires": []}, {"column": 0, "row": 0, "moves": [rank], "requires": []}],
		"requirement from a later row": [{"column": 0, "row": 0, "moves": [rank], "requires": ["0_1"]}, {"column": 0, "row": 1, "moves": [rank], "requires": []}],
		"requirement on itself": [{"column": 0, "row": 1, "moves": [rank], "requires": ["0_1"]}],
		"requirement on nothing": [{"column": 0, "row": 1, "moves": [rank], "requires": ["2_0"]}],
		"unknown move": [{"column": 0, "row": 0, "moves": ["base:move/not_a_move/tier1"], "requires": []}],
		"no moves": [{"column": 0, "row": 0, "moves": [], "requires": []}],
		"six ranks": [{"column": 0, "row": 0, "moves": [rank, rank, rank, rank, rank, rank], "requires": []}],
	}
	for label in cases:
		var bad := {"format": 1, "id": "tree_bad", "name": "Bad", "talent_trees": [{"id": "tree_bad:talent_tree/t", "name": "T", "nodes": cases[label]}]}
		_check(not UserModService.check(catalog, bad).errors.is_empty(), "A talent tree with %s is rejected" % label)
	var nameless := {"format": 1, "id": "tree_bad", "name": "Bad", "talent_trees": [{"id": "tree_bad:talent_tree/t", "name": " ", "nodes": []}]}
	_check(not UserModService.check(catalog, nameless).errors.is_empty(), "A talent tree needs a name")
	var wrong_prefix := {"format": 1, "id": "tree_bad", "name": "Bad", "talent_trees": [{"id": "other:talent_tree/t", "name": "T", "nodes": []}]}
	_check(not UserModService.check(catalog, wrong_prefix).errors.is_empty(), "A talent tree must use the mod's own ID prefix")
	var fine := {"format": 1, "id": "tree_ok", "name": "Ok", "talent_trees": [{"id": "tree_ok:talent_tree/t", "name": "T", "nodes": [{"column": 0, "row": 0, "moves": [rank], "requires": []}, {"column": 0, "row": 1, "moves": [rank], "requires": ["0_0"]}]}]}
	var checked := UserModService.check(catalog, fine)
	_check(checked.errors.is_empty() and not checked.warnings.is_empty(), "A valid unassigned tree builds and warns that no minion uses it: %s" % [checked])

func _check_rooms() -> void:
	var rooms := {"format": 1, "id": "room_mod", "name": "Rooms",
		"rooms": [{"target": "base:room/level_1_1_h2", "interactions": [{"id": "floor-1-boss-door", "set": {"required_floor_keys": 1}}]},
			{"target": "base:room/level_1_1_eggery", "interactions": [{"id": "floor-1-egg-slot-0", "set": {"candidates": ["base:minion/tiger_1"], "weights": [100]}}]}]}
	UserModRepository.write(rooms)
	var result := UserModService.activate(catalog, [{"id": "room_mod"}])
	_check(result.ok, "Room edits activate: %s" % result.get("message", ""))
	var door_keys := -1
	var room := catalog.get_definition(&"base:room/level_1_1_h2") as RoomDefinition
	for interaction in room.interactions:
		if interaction.id == &"floor-1-boss-door" or String(interaction.id) == "floor-1-boss-door": door_keys = int(interaction.required_floor_keys)
	_check(door_keys == 1, "Door requirement edit applies")
	catalog.rebuild_index()
	room = catalog.get_definition(&"base:room/level_1_1_h2") as RoomDefinition
	for interaction in room.interactions:
		if String(interaction.id) == "floor-1-boss-door": door_keys = int(interaction.required_floor_keys)
	_check(door_keys == 1, "Room edits survive an index rebuild")
	UserModService.deactivate(catalog)
	room = catalog.get_definition(&"base:room/level_1_1_h2") as RoomDefinition
	for interaction in room.interactions:
		if String(interaction.id) == "floor-1-boss-door": door_keys = int(interaction.required_floor_keys)
	_check(door_keys == 3, "Room edits revert")
	var bad_room := {"format": 1, "id": "bad_room", "name": "Bad", "rooms": [{"target": "base:room/level_1_1_h2", "interactions": [{"id": "floor-1-boss-door", "set": {"kind": "titan_reward"}}]}]}
	UserModRepository.write(bad_room)
	_check(not UserModService.activate(catalog, [{"id": "bad_room"}]).ok, "Only whitelisted interaction fields are editable")
	bad_room.rooms = [{"target": "base:room/level_1_1_eggery", "interactions": [{"id": "floor-1-egg-slot-0", "set": {"candidates": ["missing:minion/nope"], "weights": [100]}}]}]
	UserModRepository.write(bad_room)
	_check(not UserModService.activate(catalog, [{"id": "bad_room"}]).ok and catalog.ensure_index().is_empty(), "Room eggs reject missing minions and leave a valid base catalog")
	bad_room.rooms = [{"target": "base:room/level_1_1_eggery", "interactions": [{"id": "floor-1-egg-slot-0", "set": {"candidates": ["base:minion/tiger_1"], "weights": [10]}}]}]
	UserModRepository.write(bad_room)
	_check(not UserModService.activate(catalog, [{"id": "bad_room"}]).ok, "Room egg weights must total 100")
	UserModRepository.delete("room_mod")
	UserModRepository.delete("bad_room")

func _check_session() -> void:
	var repository := MemoryRepository.new()
	var session := CampaignSession.new()
	session.catalog = catalog
	session.save_repository = repository
	var started := session.start_new(&"base:campaign/standard_tower", CampaignProgressionService.starter_party(catalog, "user-mod-"), {}, 1, false, {}, ["frost_pack"])
	_check(started.ok, "Start a modded campaign: %s" % started.get("message", ""))
	if not started.ok: return
	_check(session.state.user_mods.size() == 1 and session.state.user_mods[0].id == "frost_pack" and not String(session.state.user_mods[0].fingerprint).is_empty(), "Save records the mod reference")
	var owned := OwnedMinionState.new()
	owned.instance_id = &"frostcub-fixture"
	owned.definition_id = &"frost_pack:minion/frostcub_1"
	owned.learned_move_ids = [&"base:move/claw/tier1"]
	session.state.storage.append(owned)
	_check(session.save().ok, "Save with a mod minion")
	UserModService.deactivate(catalog)
	var loaded := CampaignSession.new()
	loaded.catalog = catalog
	loaded.save_repository = repository
	_check(loaded.load(1).ok and UserModService.is_active("frost_pack"), "Loading a save re-activates its mods")
	var blocked := loaded.set_user_mod("frost_pack", false)
	_check(not blocked.ok and blocked.code == "mod_content_owned", "Owned mod minions block disabling")
	loaded.state.storage.clear()
	_check(loaded.save().ok and loaded.set_user_mod("frost_pack", false).ok and not UserModService.is_active("frost_pack"), "Disable a mod once nothing depends on it")
	_check(loaded.set_user_mod("frost_pack", true).ok and UserModService.is_active("frost_pack"), "Enable a mod on an existing save")
	loaded.user_mod_changes_allowed = func() -> bool: return false
	_check(not loaded.set_user_mod("frost_pack", false).ok and UserModService.is_active("frost_pack"), "Connected sessions cannot change their content set")
	loaded.user_mod_changes_allowed = Callable()
	repository.reject = true
	var before: Dictionary = loaded.state.to_dictionary()
	_check(not loaded.set_user_mod("frost_pack", false).ok and UserModService.is_active("frost_pack") and loaded.state.to_dictionary() == before, "A rejected save restores the active mod layers and live state")
	repository.reject = false
	UserModRepository.delete("frost_pack")
	UserModService.deactivate(catalog)
	var missing := CampaignSession.new()
	missing.catalog = catalog
	missing.save_repository = repository
	var refused := missing.load(1)
	_check(not refused.ok and refused.code == "mod_unavailable" and String(refused.message).contains("Frost Pack"), "Missing mods stop the load with their name")
	var example: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE))
	example["description"] = "Edited after saving"
	UserModRepository.write(example)
	var edited := missing.load(1)
	_check(edited.ok and edited.get("changed_user_mods", []) == ["Frost Pack"], "Edited mods still load and are reported")
	UserModService.deactivate(catalog)

func _check_runtime_starters() -> void:
	var mod := {"format": 1, "id": "starter_mod", "name": "Starter Moves", "minion_patches": [{"target": "base:minion/tiger_1", "initial_moves": ["base:move/claw/tier1", "base:move/burn/tier1"], "stats": {"health": 1, "energy": 1}}]}
	UserModRepository.write(mod)
	var runtime := root.get_node("CampaignRuntime")
	runtime.session.save_repository = MemoryRepository.new()
	var started: Dictionary = runtime.start_new_campaign(1, "Mod starter", &"male", {}, ["starter_mod"])
	_check(started.ok and &"base:move/burn/tier1" in runtime.session.state.party[1].learned_move_ids, "New-game starters use patched starting moves")
	if started.ok:
		var owned: OwnedMinionState = runtime.session.state.party[1]
		owned.persistent_health = 9999
		owned.persistent_energy = 9999
		_check(runtime.session.set_user_mod("starter_mod", false).ok, "Remove a starter stat patch without owning added content")
		_check(runtime.session.set_user_mod("starter_mod", true).ok, "Re-enable the starter stat patch")
		owned = runtime.session.state.party[1]
		var definition := catalog.get_definition(owned.definition_id) as MinionDefinition
		var stats := CampaignProgressionService.owned_display_stats(owned, definition, catalog, runtime.session.state)
		_check(owned.persistent_health <= int(stats.health) and owned.persistent_energy <= int(stats.energy), "User stat mods clamp lowered HP and energy maxima")
	UserModService.deactivate(catalog)
	UserModRepository.delete("starter_mod")

func _check_sharing() -> void:
	UserModRepository.write(JSON.parse_string(FileAccess.get_file_as_string(EXAMPLE)))
	var png := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	png.fill(Color.CYAN)
	var source := UserModRepository.root.path_join("cyan.png")
	png.save_png(source)
	var imported := UserModRepository.import_sprite("frost_pack", source, "Cyan Cub")
	_check(imported.ok and imported.path == "sprites/cyan_cub.png", "Import a sprite into a mod")
	var fingerprint := UserModRepository.fingerprint("frost_pack")
	var code := UserModRepository.export_code("frost_pack")
	_check(code.ok and String(code.code).begins_with(UserModRepository.CODE_PREFIX), "Export a share code")
	var zip := UserModRepository.export_zip("frost_pack", UserModRepository.root.path_join("exports"))
	_check(zip.ok, "Export a ZIP")
	UserModRepository.delete("frost_pack")
	var decoded := UserModRepository.decode_code(code.code)
	_check(decoded.ok and UserModRepository.install_bundle(decoded, false).ok and UserModRepository.fingerprint("frost_pack") == fingerprint, "Share code round-trips byte for byte")
	_check(not UserModRepository.install_bundle(decoded, false).ok, "Installing over an existing mod needs confirmation")
	UserModRepository.delete("frost_pack")
	var from_zip := UserModRepository.decode_zip(zip.path)
	var installed_zip := UserModRepository.install_bundle(from_zip, false) if from_zip.ok else from_zip
	_check(installed_zip.ok and UserModRepository.fingerprint("frost_pack") == fingerprint, "ZIP round-trips byte for byte: %s" % installed_zip.get("message", ""))
	if not installed_zip.ok: return
	# Rapid replacement and reinstallation can encounter a short Windows lock
	# on the deleted directory, especially when running from an exported pack.
	for trial in 12:
		var replaced := UserModRepository.install_bundle(from_zip, true)
		_check(replaced.ok, "Repeated ZIP replacement %d: %s" % [trial, replaced.get("message", "")])
		if not replaced.ok: return
		_check(UserModRepository.delete("frost_pack").ok, "Remove replacement %d" % trial)
		var reinstalled := UserModRepository.install_bundle(from_zip, false)
		_check(reinstalled.ok and UserModRepository.fingerprint("frost_pack") == fingerprint, "Repeated ZIP reinstallation %d: %s" % [trial, reinstalled.get("message", "")])
		if not reinstalled.ok: return
	var sprite_mod: Dictionary = UserModRepository.read("frost_pack").manifest
	sprite_mod.minions[0].sprite = {"file": "sprites/cyan_cub.png"}
	UserModRepository.write(sprite_mod)
	var result := UserModService.activate(catalog, [{"id": "frost_pack"}])
	var presentation := catalog.get_definition((catalog.get_definition(&"frost_pack:minion/frostcub_1") as MinionDefinition).presentation_id) as MinionPresentationDefinition if result.ok else null
	_check(presentation != null and (load("res://content/base/art/battle/minions/%s.png" % presentation.legacy_sprite_name) as Texture2D).get_size() == Vector2(4, 4), "Custom PNG sprites load")
	var unsafe := {"manifest": sprite_mod, "files": {"../evil.png": PackedByteArray()}}
	_check(not UserModRepository._validate_bundle(unsafe.manifest, unsafe.files).ok, "Bundles cannot write outside the sprites folder")
	_check(not UserModRepository.install_bundle(unsafe, true).ok and UserModRepository.exists("frost_pack"), "Direct bundle installation validates paths before replacing an existing mod")
	_check(not UserModRepository.delete("../frost_pack").ok and UserModRepository.exists("frost_pack"), "Mod deletion refuses a path outside the mod root")
	var oversized := Image.create(513, 1, false, Image.FORMAT_RGBA8)
	_check(not UserModRepository._validate_bundle(sprite_mod, {"sprites/large.png": oversized.save_png_to_buffer()}).ok, "Shared images follow the same dimension limit as imported art")
	UserModService.deactivate(catalog)
