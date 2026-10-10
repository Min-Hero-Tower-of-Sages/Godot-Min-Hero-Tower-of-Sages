extends Node

const Reader = preload("res://src/infrastructure/flash_shared_object_reader.gd")
const Importer = preload("res://src/application/flash_save_import_service.gd")

func _ready() -> void:
	await get_tree().process_frame
	var runtime := get_node("/root/CampaignRuntime")
	var catalog: ContentCatalog = runtime.catalog
	var fields := {
		"m_currFloorOfTower": 2, "m_currMoney": 1234,
		"m_currKeysOnFloor": 2, "m_hasUnlockedBossDoor": true,
		"m_numOfMinionsLeftToChoose": 0,
		"m_hasTalkedToTheGrandSageForTheFirstTime": true,
		"m_hasBeatenFloor0": true, "m_hasBeatenFloor1": true,
		"m_hasBeatenTrainer2slot0": true, "m_bestTrainerStarCounts2slot0": 3,
		"m_starUpgradeAmounts0": 1, "m_isMod_holyBirb1": true,
		"m_hasTutorialsBeenSeen12": true, "m_hasTutorialsBeenSeen2": true,
		"minion0": true, "minion0dexID": 2, "minion0name": "Zapig",
		"minion0exp": 6350, "minion0statBonus": 2, "minion0currHealth": 7,
		"minion0move0": 15, "minion0move24": -99,
		"minion5": true, "minion5ModName": "holyBirb1", "minion5name": "Arkvian",
		"minion5exp": 24000, "minion5currHealth": 21,
		"gem3": true, "gem3tier": 2, "gem3stat2": 9.0,
		"minion0gem1": true, "minion0gem1tier": 1, "minion0gem1stat0": 3.0,
	}
	for encoding in [0, 3]:
		var bytes := _sol(fields, encoding)
		var read: Dictionary = Reader.new().decode(bytes)
		assert(read.ok, String(read.get("message", "")))
		for key in fields: assert(read.data[key] == fields[key], "Decoded scalar differs")
		assert(not Reader.new().decode(bytes.slice(0, bytes.size() - 1)).ok)
		var bad := bytes.duplicate()
		bad[6] = 0
		assert(not Reader.new().decode(bad).ok)
	# AMF3 names and values share a string-reference table.
	var reference := _sol({"dup": "dup"}, 3)
	reference = reference.slice(0, reference.size() - 5)
	reference.append_array(PackedByteArray([0, 0]))
	var reference_stream := StreamPeerBuffer.new()
	reference_stream.big_endian = true
	reference_stream.data_array = reference
	reference_stream.seek(2)
	reference_stream.put_u32(reference.size() - 6)
	assert(Reader.new().decode(reference_stream.data_array).data.dup == "dup")
	var preview: Dictionary = Importer.new().convert_fields(fields, catalog, "Imported", "female")
	assert(preview.ok, String(preview.get("message", "")))
	var state := CampaignState.new()
	state.load_dictionary(preview.state)
	assert(state.party.size() == 1 and state.storage.size() == 1)
	assert(state.party[0].level == 6 and state.party[0].experience == 6350)
	var imported_stats := CampaignProgressionService.owned_display_stats(state.party[0], catalog.get_definition(state.party[0].definition_id), catalog, state)
	assert(state.party[0].persistent_health == int(imported_stats.health))
	assert(state.progression.gem_tutorial_seen and state.progression.battle_basics_tutorial_seen)
	assert(state.progression.flash_import.version == 3)
	state.party[0].persistent_health = 7
	assert(not Importer.repair_import_state(state, catalog).changed)
	assert(state.party[0].persistent_health == 7)
	state.progression.flash_import.version = 1
	state.progression.gem_tutorial_seen = false
	assert(Importer.repair_import_state(state, catalog).changed)
	assert(state.party[0].persistent_health == int(imported_stats.health))
	assert(state.progression.gem_tutorial_seen)
	assert(state.party[0].equipment_ids[1] == &"flash-minion0gem1")
	assert(state.storage[0].definition_id == &"arkvian:minion/holybird1")
	assert(state.owned_gems.size() == 2 and state.progression.gem_inventory_slots[3] == "flash-gem3")
	assert(state.active_mods.holyBird1 and state.progression.currency == 1234)
	assert(state.current_room_id == &"base:room/main_tower_lobby")
	assert(state.progression.flash_resume_floor.floor_keys == 2)
	var trainer1 := catalog.get_definition(&"base:encounter/grass_floor3_trainer_1") as EncounterDefinition
	assert(trainer1 != null and state.progression.completed_encounters.has(String(trainer1.id)))
	assert(CampaignProgressionService.total_earned_stars(state) == 3)
	fields.minion0dexID = 9999
	assert(not Importer.new().convert_fields(fields, catalog).ok)
	fields.minion0dexID = 2
	fields.minion0move0 = 9999
	assert(not Importer.new().convert_fields(fields, catalog).ok)
	fields.minion0move0 = 15
	# All four acquisition toggles select source tables without mutating shared
	# room definitions or another campaign's flags.
	state.active_mods = {"waterRay1": true, "holyBird1": true, "HolyEye1": true, "dirtFish": true}
	assert(CampaignModService.egg_pool(state, 2, {}).candidates.has("stingaray:minion/waterray1"))
	assert(CampaignModService.egg_pool(state, 3, {}).candidates.has("arkvian:minion/holybird1"))
	assert(CampaignModService.egg_pool(state, 16, {}).candidates.has("ophan:minion/holyeye2"))
	assert(CampaignModService.egg_pool(state, 21, {}).candidates.has("zanyu:minion/dirtfish"))
	var pedia := CampaignMinionPediaView.new()
	add_child(pedia)
	pedia.configure(catalog, state)
	var bird := catalog.get_definition(&"arkvian:minion/holybird1") as MinionDefinition
	assert(pedia._source_dex_id(bird) >= 102)
	assert(4 in pedia._found_floors[String(bird.id)])
	pedia.queue_free()
	state.active_mods.no_natural_regen = true
	state.party[0].persistent_health = 7
	CampaignProgressionService.rest_party(state, catalog, false)
	assert(state.party[0].persistent_health == 7)
	CampaignProgressionService.rest_party(state, catalog)
	assert(state.party[0].persistent_health > 7)
	var dead_id := state.party[0].instance_id
	CampaignModService.retire_fainted(state, [dead_id])
	assert(state.party.size() == 1 and state.party[0].definition_id == &"arkvian:minion/holybird1")
	assert(state.progression.nuzlocke_memorial.size() == 1 and not state.progression.nuzlocke_run_ended)
	assert(state.owned_gems.size() == 1)
	CampaignModService.retire_fainted(state, [state.party[0].instance_id])
	assert(state.progression.nuzlocke_run_ended and state.validation_errors(catalog).is_empty())
	var selector := CampaignModSelector.new()
	add_child(selector)
	assert(selector._buttons.size() == 7)
	selector._toggle(2)
	assert(selector.flags.holyBird1 and selector.flags.holyBird2)
	selector._change_scroll(1)
	assert(selector._scroll == 1)
	# Only this isolated fixture profile is written by the test runner.
	assert(runtime.import_flash_candidate(1, preview.state).ok)
	assert(not runtime.import_flash_candidate(1, preview.state).ok)
	assert(runtime.load_campaign(1).ok)
	assert(runtime.session.state.progression.gem_tutorial_seen)
	assert(runtime.session.select_tower_floor(2).ok)
	assert(runtime.session.state.progression.floor_keys == 2)
	assert(runtime.session.state.progression.boss_door_unlocked)
	assert(runtime.session.state.progression.eggery_picks_remaining == 0)
	assert(not runtime.session.state.progression.has("flash_resume_floor"))
	var party_view := CampaignPartyMenuView.new()
	add_child(party_view)
	var empty_row := func(_host: Control, _owned: OwnedMinionState, _action: Callable) -> void: pass
	party_view.configure(runtime.session, empty_row)
	assert(party_view.find_child("GemTutorialHint", true, false) == null)
	runtime.session.state.progression.gem_tutorial_seen = false
	party_view.configure(runtime.session, empty_row)
	var hint := party_view.find_child("GemTutorialHint", true, false) as Label
	assert(hint != null and is_equal_approx(hint.size.x, 90.0))
	assert(hint.position.x + hint.size.x <= 700.0)
	party_view.queue_free()
	assert(runtime.delete_campaign_save(1).ok)
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	add_child(shell)
	await get_tree().create_timer(5.5).timeout
	shell.call("_show_save_slots")
	await get_tree().create_timer(1.6).timeout
	assert(shell.current_screen.find_child("FlashSaveImportButton", true, false) != null)
	var empty_card: Control = shell.current_screen.get_node("TitleSaveSlots/SaveSlot3")
	assert(empty_card.get_node_or_null("FlashSaveImportButton") != null)
	assert(shell.current_screen.get_node("TitleSaveSlots").get_node_or_null("FlashSaveImportButton") == null)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/save-slot-import-preview.png")
	shell.call("_show_flash_import", 3)
	assert(shell.current_screen.get_node_or_null("FlashSaveImport") != null)
	assert(shell.current_screen.get_node("FlashSaveImport")._slots.get_selected_id() == 3)
	assert(shell.current_screen.get_node("FlashSaveImport/ImportStonePanel") != null)
	var flash_file := FileAccess.open("user://TCrpgSaveSlot0.sol", FileAccess.WRITE)
	flash_file.store_buffer(_sol(fields, 3))
	flash_file.close()
	shell.current_screen.get_node("FlashSaveImport").call("_preview_file", "user://TCrpgSaveSlot0.sol")
	assert(not shell.current_screen.get_node("FlashSaveImport")._confirm.disabled)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/flash-import-preview.png")
	shell.current_screen.get_node("FlashSaveImport").queue_free()
	await get_tree().process_frame
	shell.call("_show_character_creation")
	await get_tree().create_timer(1.6).timeout
	assert(shell.current_screen.find_child("ModSelector", true, false) != null)
	assert(shell.current_screen.find_child("ModSelector", true, false).position.y == 143.0)
	assert(is_equal_approx(shell.current_screen.get_node("TitleButtonBand").position.y, 182.5))
	shell.call("_set_gender", "female")
	assert(shell.current_screen.find_child("SelectedGenderMarker", true, false).position == Vector2(183, 267))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://build/mod-selector-preview.png")
	print("FLASH_IMPORT_MODS_SMOKE: PASS — AMF0/3, migration, rejected IDs, equipment, source pools, rules, selector and atomic empty-slot import")
	get_tree().quit()

func _sol(fields: Dictionary, encoding: int) -> PackedByteArray:
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	stream.put_u16(0x00bf)
	stream.put_u32(0)
	stream.put_data("TCSO".to_utf8_buffer())
	stream.put_u16(4)
	stream.put_u32(0)
	_string(stream, "TCrpgSaveSlot0", 0)
	stream.put_u32(encoding)
	for key in fields:
		_string(stream, key, encoding)
		var value: Variant = fields[key]
		if value is bool:
			stream.put_u8((3 if value else 2) if encoding == 3 else 1)
			if encoding == 0: stream.put_u8(1 if value else 0)
		elif value is String:
			stream.put_u8(6 if encoding == 3 else 2)
			_string(stream, value, encoding)
		elif value is int and encoding == 3:
			stream.put_u8(4)
			_u29(stream, int(value) & 0x1fffffff)
		else:
			stream.put_u8(5 if encoding == 3 else 0)
			stream.put_double(float(value))
		stream.put_u8(0)
	var length := stream.get_size()
	stream.seek(2)
	stream.put_u32(length - 6)
	return stream.data_array

func _string(stream: StreamPeerBuffer, value: String, encoding: int) -> void:
	var bytes := value.to_utf8_buffer()
	if encoding == 0: stream.put_u16(bytes.size())
	else:
		var length := (bytes.size() << 1) | 1
		if length >= 128: stream.put_u8((length >> 7) | 128)
		stream.put_u8(length & 127)
	stream.put_data(bytes)

func _u29(stream: StreamPeerBuffer, value: int) -> void:
	if value < 0x80:
		stream.put_u8(value)
	elif value < 0x4000:
		stream.put_u8((value >> 7) | 128)
		stream.put_u8(value & 127)
	elif value < 0x200000:
		stream.put_u8((value >> 14) | 128)
		stream.put_u8(((value >> 7) & 127) | 128)
		stream.put_u8(value & 127)
	else:
		stream.put_u8(((value >> 22) & 127) | 128)
		stream.put_u8(((value >> 15) & 127) | 128)
		stream.put_u8(((value >> 8) & 127) | 128)
		stream.put_u8(value & 255)
