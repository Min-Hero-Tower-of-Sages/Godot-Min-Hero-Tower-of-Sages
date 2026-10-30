extends SceneTree

## Use the real validator, JSON writes, backup rotation and reload path.
## Only the test profile is writable; never run this against player saves.
class FailingDiskRepository extends SaveRepository:
	var fail_write := false
	func _slot_path(slot: int) -> String:
		return "user://nonexistent-skill-gem-fixture/save_slot_%d.json" % slot if fail_write else super._slot_path(slot)

var catalog: ContentCatalog
var session: CampaignSession
var repository: FailingDiskRepository

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/")
	if not user_root.contains("/build/skill-gem-save-profile/"):
		push_error("Run with APPDATA/XDG_DATA_HOME under the project's build/skill-gem-save-profile; real player saves must not be used.")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument == "--verify-export":
			assert(not ResourceLoader.exists("res://tests/test_runner.tscn"), "Expected exported pack, not source resources")
		if argument.begins_with("--expect-version="):
			assert(ProjectSettings.get_setting("application/config/version") == argument.trim_prefix("--expect-version="))
	await process_frame
	catalog = root.get_node("CampaignRuntime").catalog
	repository = FailingDiskRepository.new()
	assert(not DirAccess.dir_exists_absolute("user://nonexistent-skill-gem-fixture"))
	for slot in range(1, 4): assert(repository.delete_slot(slot).ok)
	session = CampaignSession.new()
	session.catalog = catalog
	session.save_repository = repository
	var starters := CampaignProgressionService.starter_party(catalog, "real-save-")
	for owned in starters:
		owned.level = 60
		owned.experience = 60000
	assert(session.start_new(&"base:campaign/standard_tower", starters, {"name": "Disk fixture"}, 1, false, {"skill_gems": true}).ok)
	session.state.progression.currency = 100000
	session.state.progression.sage_seals = 5
	session.state.progression.unlocked_floor_indices = [0, 31]
	assert(session.save().ok)
	assert(_check_forge_and_reload())
	assert(_check_schema())
	assert(_check_trainer_rewards())
	assert(await _check_failed_settlement_retry())
	assert(_check_interrupted_v130_save())
	print("PASS: real disk skill-gem forge/stat combine/shop/equip/reload, both Hard Sage rewards, schema rejection, failed-write Retry save, exactly-once settlement and v1.3.0 pending-save recovery")
	quit()

func _materials(tier: int, colors: Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	for index in 3:
		var gem := CampaignGemFactory.create_random(tier)
		gem.instance_id = CampaignGemEconomyService._new_gem_id(session.state, "disk-material")
		gem.raw_stats = [0.0, 0.0, 0.0, 0.0, 0.0]
		var color := int(colors[index % colors.size()])
		gem.raw_stats[color] = pow(3.0, tier)
		gem.stat_id = String(CampaignGemFactory.STAT_IDS[color])
		ids.append(StringName(gem.instance_id))
		session.state.owned_gems.append(gem)
	assert(session.save().ok)
	return ids

func _reload() -> void:
	var loaded := CampaignSession.new()
	loaded.catalog = catalog
	loaded.save_repository = repository
	assert(loaded.load(1).ok)
	session = loaded

func _check_forge_and_reload() -> bool:
	for tier in [1, 6, 10]:
		for colors in [[0], [4], [0, 2, 4], [0, 2, 3]]:
			var ids := _materials(tier, colors)
			var money_before := int(session.state.progression.currency)
			var forged := session.combine_gems(ids, 0, true)
			assert(forged.ok, "Real save rejected forging: %s" % forged)
			var expected_gem: Dictionary = JSON.parse_string(JSON.stringify(forged.gem))
			assert(expected_gem.kind == "skill" and expected_gem.stat_id == "")
			assert(session.state.progression.currency == money_before - forged.cost)
			_reload()
			assert(session.state.owned_gems.has(expected_gem), "Skill metadata changed during JSON reload")
			for id in ids: assert(CampaignGemEquipmentService._find_gem(session.state, id).is_empty())
	var holder: OwnedMinionState = session.state.party[0]
	var fire_gem: Dictionary = session.state.owned_gems[0]
	assert(session.equip_gem(StringName(fire_gem.instance_id), holder.instance_id, 0).ok)
	_reload()
	assert(session.state.party[0].equipment_ids[0] == StringName(fire_gem.instance_id))
	assert(session.unequip_gem(holder.instance_id, 0).ok)
	assert(session.set_mod_option("skill_gems", false).ok)
	_reload()
	assert(not session.state.active_mods.skill_gems and session.state.owned_gems.size() == 12)
	assert(session.set_mod_option("skill_gems", true).ok)
	# Existing skill gems must not prevent ordinary stat-gem transactions.
	var normal_ids := _materials(6, [0])
	assert(session.combine_gems(normal_ids).ok)
	_reload()
	assert(session.refresh_gem_shop().ok and session.buy_shop_gem(0).ok)
	assert(session.sort_gems().ok)
	_reload()
	assert(session.state.owned_gems.size() == 14)
	return true

func _check_schema() -> bool:
	var payload: Dictionary = session.state.to_dictionary(catalog.content_version)
	assert(repository.validate(payload).ok)
	for field in ["move_id", "type_id", "skill_level", "facet_positions"]:
		var malformed: Dictionary = payload.duplicate(true)
		var index := 0
		while malformed.owned_gems[index].get("kind", "stat") != "skill": index += 1
		malformed.owned_gems[index].erase(field)
		assert(not repository.validate(malformed).ok, "Missing skill-gem field must be rejected: %s" % field)
	for rank in [0, 6, 1.5, "3", null]:
		var malformed: Dictionary = payload.duplicate(true)
		for gem in malformed.owned_gems:
			if gem.get("kind", "stat") == "skill": gem.skill_level = rank
		assert(not repository.validate(malformed).ok)
	var malformed_stat: Dictionary = payload.duplicate(true)
	malformed_stat.owned_gems = [CampaignGemFactory.create_random(1)]
	malformed_stat.owned_gems[0].stat_id = "invalid"
	assert(not repository.validate(malformed_stat).ok, "Stat-gem checks remain enforced")
	var invalid_content := CampaignState.new()
	invalid_content.load_dictionary(payload)
	for gem in invalid_content.owned_gems:
		if gem.get("kind", "stat") == "skill": gem.type_id = "base:type/missing"
	assert(not invalid_content.validation_errors(catalog).is_empty())
	return true

func _prepare(room_id: StringName, contact_id: StringName) -> Dictionary:
	session.state.current_room_id = room_id
	var contact := session.interact(contact_id)
	assert(contact.ok and contact.kind == &"trainer")
	var prepared := session.prepare_battle(StringName(contact.encounter_id))
	assert(prepared.ok, "Battle preparation failed: %s" % prepared)
	return prepared

func _win(prepared: Dictionary) -> BattleResult:
	var result := BattleResult.new()
	result.battle_id = StringName(prepared.battle_id)
	result.winning_team = 0
	result.reason = &"victory"
	result.rounds = 1
	return result

func _check_trainer_rewards() -> bool:
	assert(session.enter_tower_lobby().ok and session.select_tower_floor(31).ok)
	for entry in [["base:room/level_1_1_d", "floor-1-trainer-4-hard"], ["base:room/floor_1_expert_room_grass", "floor-1-expert-trainer"]]:
		var result := _win(_prepare(StringName(entry[0]), StringName(entry[1])))
		var before: int = session.state.owned_gems.size()
		var settled := session.apply_battle_result(result)
		assert(settled.ok, "Real repository rejected trainer skill reward: %s" % settled)
		assert(settled.first_clear_rewards.gems.size() == 1 and settled.first_clear_rewards.gems[0].kind == "skill")
		assert(session.state.pending_battle.is_empty() and session.state.owned_gems.size() == before + 1)
		_reload()
		assert(String(result.battle_id) in session.state.applied_battle_ids and session.state.pending_battle.is_empty())
		assert(session.apply_battle_result(result).already_applied and session.state.owned_gems.size() == before + 1)
	# A rematch can prepare and finish with skill gems already in the save.
	var rematch := _win(_prepare(&"base:room/level_1_1_d", &"floor-1-trainer-4-hard"))
	assert(session.apply_battle_result(rematch).ok)
	return true

func _check_failed_settlement_retry() -> bool:
	var prepared := _prepare(&"base:room/level_1_1_a", &"floor-1-trainer-1")
	var result := _win(prepared)
	var pending_snapshot: Dictionary = session.state.to_dictionary(catalog.content_version)
	var runtime: Node = root.get_node("CampaignRuntime")
	runtime.session = session
	runtime.active_campaign_battle = true
	runtime.prepared_battle_setup = prepared.setup.duplicate(true)
	var battle = load("res://scenes/main.tscn").instantiate()
	root.add_child(battle)
	battle.campaign_mode = true
	battle.catalog = catalog
	battle.start_overlay.hide()
	var returned := [0]
	battle.campaign_return_requested.connect(func() -> void: returned[0] += 1)
	repository.fail_write = true
	battle._show_result(result)
	assert(not battle.campaign_settlement.ok and battle._uncommitted_campaign_result == result)
	assert(battle.restart_button.text == "Retry save" and not battle.restart_button.disabled)
	assert(session.state.to_dictionary(catalog.content_version) == pending_snapshot and returned[0] == 0)
	battle._on_restart_pressed()
	assert(not battle.campaign_settlement.ok and returned[0] == 0, "A second failed save must not return to the room")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/skill-gem-save-retry.png")
	repository.fail_write = false
	assert(repository.load_slot(1).state.pending_battle.battle_id == String(result.battle_id), "Rejected writes must preserve the prepared save")
	# Use the same keyboard path as the retry button.
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	battle._unhandled_key_input(enter)
	assert(battle.campaign_settlement.ok and battle._uncommitted_campaign_result == null)
	assert(session.state.pending_battle.is_empty() and String(result.battle_id) in session.state.applied_battle_ids)
	var applied: Array = session.state.applied_battle_ids.duplicate()
	var money := int(session.state.progression.currency)
	assert(session.apply_battle_result(result).already_applied and session.state.applied_battle_ids == applied and session.state.progression.currency == money)
	battle.free()
	await process_frame
	return true

func _check_interrupted_v130_save() -> bool:
	_prepare(&"base:room/level_1_1_d", &"floor-1-trainer-4-hard")
	var runtime: Node = root.get_node("CampaignRuntime")
	runtime.session = session
	var loaded: Dictionary = runtime.load_campaign(1)
	assert(loaded.ok and loaded.get("recovered_pending_battle", false), "Recover the preparation marker left by the old failed settlement")
	assert(session.state.pending_battle.is_empty() and repository.load_slot(1).state.pending_battle.is_empty())
	assert(session.apply_battle_result(_win(_prepare(&"base:room/level_1_1_d", &"floor-1-trainer-4-hard"))).ok)
	return true
