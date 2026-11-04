extends SceneTree

class MemoryRepository extends SaveRepository:
	var payload: Dictionary = {}
	var reject := false
	func save_slot(_slot: int, data: Dictionary) -> Dictionary:
		var validation := validate(data)
		if not validation.ok: return validation
		if reject: return {"ok": false, "message": "Fixture save rejection"}
		payload = data.duplicate(true)
		return {"ok": true}
	func load_slot(_slot: int) -> Dictionary:
		return {"ok": false, "code": "not_found"} if payload.is_empty() else {"ok": true, "state": payload.duplicate(true)}

class MemorySettings extends CampaignSettingsService:
	func load_settings() -> void: pass
	func _save_and_apply() -> void: settings_changed.emit()

var catalog: ContentCatalog
var session: CampaignSession
var repository: MemoryRepository
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _run() -> void:
	await process_frame
	catalog = root.get_node("CampaignRuntime").catalog
	session = CampaignSession.new()
	session.catalog = catalog
	repository = MemoryRepository.new()
	session.save_repository = repository
	_check(session.start_new(&"base:campaign/standard_tower", CampaignProgressionService.starter_party(catalog, "saved-mods-")).ok, "Create fixture campaign")
	_check_policies()
	_check_persistence()
	_check_existing_content()
	_check_debug()
	_check_skill_gem_aura()
	await _check_ui()
	for failure in failures: push_error(failure)
	print("PASS: saved mod policies, grouped import flags, atomic saves/reload, acquired content/history, debug reset, aura clamping, pending-action guards and Settings navigation" if failures.is_empty() else "FAIL: saved mods")
	quit(0 if failures.is_empty() else 1)

func _check_policies() -> void:
	for option in CampaignModService.OPTIONS:
		var group := String(option.flags[0])
		_check(session.set_mod_option(group, true).ok, "Enable existing-save mod %s" % group)
		for flag in option.flags: _check(CampaignModService.enabled(session.state, flag), "Set every grouped flag")
		var before: Dictionary = session.state.to_dictionary()
		var disabled := session.set_mod_option(group, false)
		if group == "nuzlocke":
			_check(not disabled.ok and disabled.code == "permanent_mod" and before == session.state.to_dictionary(), "Nuzlocke is one-way")
		else:
			_check(disabled.ok, "Disable unused mod %s" % group)
			for flag in option.flags: _check(not CampaignModService.enabled(session.state, flag), "Clear every grouped flag")
	_check(not session.set_mod_option("restored_martyr", false).ok, "Cannot bypass the grouped option with a legacy child flag")
	_check(not session.set_mod_option("unknown", true).ok, "Reject unknown mods")
	for pending in ["pending_battle", "pending_defeat_return", "pending_egg_preview"]:
		if pending == "pending_egg_preview": session.state.progression[pending] = {"slot": 0}
		else: session.state.set(pending, {"fixture": true})
		var before: Dictionary = session.state.to_dictionary()
		_check(not session.set_mod_option("skill_gems", true).ok and before == session.state.to_dictionary(), "Block mod edits during %s" % pending)
		if pending == "pending_egg_preview": session.state.progression.erase(pending)
		else: session.state.set(pending, {})

func _check_persistence() -> void:
	var before: Dictionary = session.state.to_dictionary()
	repository.reject = true
	_check(not session.set_mod_option("skill_gems", true).ok and session.state.to_dictionary() == before, "Rejected saves do not alter mods, inventory or progress")
	repository.reject = false
	_check(session.set_mod_option("skill_gems", true).ok, "Enable Skill Gems on a progressed save")
	var loaded := CampaignSession.new()
	loaded.catalog = catalog
	loaded.save_repository = repository
	_check(loaded.load(1).ok and CampaignModService.enabled(loaded.state, "skill_gems"), "Toggled mods survive a real session reload")
	_check(session.set_mod_option("skill_gems", false).ok, "Skill Gems can be disabled again")
	# Partially enabled Flash flags still count as an enabled grouped mod.
	session.state.active_mods = {"holyBird2": true}
	_check(CampaignModService.group_enabled(session.state.active_mods, "holyBird1"), "Recognize imported child-only flags")
	_check(session.set_mod_option("holyBird1", false).ok and not session.state.active_mods.holyBird2, "Switch off all imported group flags")
	session.state.active_mods = {"restored_martyr": true}
	_check(CampaignModService.group_enabled(session.state.active_mods, "restored_moves"), "Recognize legacy Move Trees flags")
	_check(session.set_mod_option("restored_moves", true).ok and session.state.active_mods.restored_righteous_fate, "Switching on canonicalizes the full legacy group")

func _check_existing_content() -> void:
	var owned := OwnedMinionState.new()
	owned.instance_id = &"saved-arkclaw"
	owned.definition_id = &"arkvian:minion/holybird2"
	owned.level = 10
	owned.experience = 10000
	session.state.storage.append(owned)
	session.state.progression.owned_minion_ids = ["arkvian:minion/holybird1"]
	session.state.progression.seen_minion_ids = ["ophan:minion/holyeye1"]
	_check(session.set_mod_option("holyBird1", true).ok and session.set_mod_option("holyBird1", false).ok, "Extra minion mods switch off without removing owned minions")
	_check(session.state.storage[0].definition_id == &"arkvian:minion/holybird2", "Owned Arkclaw survives")
	for id in [&"arkvian:minion/holybird1", &"arkvian:minion/holybird2", &"ophan:minion/holyeye1"]:
		_check(CampaignModService.minion_is_available(session.state, catalog.get_definition(id)), "Recorded mod entries stay in Minion-pedia")
	_check(not CampaignModService.minion_is_available(session.state, catalog.get_definition(&"ophan:minion/holyeye3")), "Unobtained disabled forms remain hidden")
	var minion: OwnedMinionState = session.state.storage[0]
	minion.learned_move_ids.append(&"base:move/righteous_fate/tier1")
	var blocked := session.set_mod_option("restored_moves", false)
	_check(not blocked.ok and blocked.code == "mod_talents_owned", "Move Trees cannot hide a purchased extra talent")
	CampaignProgressionService.reset_talents(minion, catalog.get_definition(minion.definition_id))
	_check(session.set_mod_option("restored_moves", false).ok, "Move Trees switches off after resetting added talents")
	session.state.party[0].is_shiny = true
	session.state.party[0].shiny_line_id = MinionPaletteService.line_id(session.state.party[0].definition_id, catalog)
	_check(session.set_mod_option("shinies", true).ok and session.set_mod_option("shinies", false).ok and session.state.party[0].is_shiny, "Disabling Shinies preserves existing appearances")
	session.state.party[0].persistent_health = 1
	_check(session.set_mod_option("no_natural_regen", true).ok and session.set_mod_option("no_natural_regen", false).ok and session.state.party[0].persistent_health == 1, "No Regen toggles do not immediately heal")

func _check_debug() -> void:
	_check(session.set_mod_option("debug_mode", true).ok, "Enable debug access on an existing save")
	_check(session.set_debug_option("max_party_levels", true).ok and session.state.party[0].level == 60, "Existing debug actions work")
	_check(session.set_debug_option("full_keys", true).ok, "Enable full keys")
	var key_count: int = session.state.progression.floor_keys
	_check(session.set_mod_option("debug_mode", false).ok, "Disable debug access")
	_check(session.state.progression.debug_options.is_empty() and session.state.party[0].level == 60 and session.state.progression.floor_keys == key_count, "Debug toggles clear; granted levels and keys remain")
	session.state.party[0].level = 4
	session.state.party[0].experience = 4350
	_check(session.set_mod_option("debug_mode", true).ok and session.state.party[0].level == 4, "Re-enabling Debug does not silently reactivate cheats")
	_check(session.set_mod_option("debug_mode", false).ok, "Leave debug disabled for next fixture")

func _check_skill_gem_aura() -> void:
	_check(session.set_mod_option("skill_gems", true).ok, "Enable skill-gem grants")
	var holder: OwnedMinionState = session.state.party[0]
	var aura := CampaignGemFactory.create_random(6)
	aura.merge({"kind": "skill", "instance_id": "saved-aura", "move_id": "base:move/hulk_inspiration/tier3", "skill_level": 3, "type_id": "base:type/none", "stat_id": "", "stat_value": 0}, true)
	session.state.owned_gems.append(aura)
	_check(session.equip_gem(&"saved-aura", holder.instance_id, 0).ok, "Equip fixture aura")
	holder = session.state.party[0]
	var definition := catalog.get_definition(holder.definition_id) as MinionDefinition
	var aura_max := int(CampaignProgressionService.owned_display_stats(holder, definition, catalog, session.state).health)
	holder.persistent_health = aura_max
	_check(session.set_mod_option("skill_gems", false).ok, "Suspend equipped skills")
	holder = session.state.party[0]
	var plain_max := int(CampaignProgressionService.owned_display_stats(holder, definition, catalog, session.state).health)
	_check(plain_max < aura_max and holder.persistent_health == plain_max, "Removing the aura clamps current HP to the reduced maximum")
	_check(session.set_mod_option("skill_gems", true).ok and session.state.party[0].persistent_health == plain_max, "Re-enabling aura does not grant free healing")
	_check(session.state.owned_gems.size() == 1 and session.state.party[0].equipment_ids[0] == &"saved-aura", "Toggling never deletes or unequips skill gems")

func _check_ui() -> void:
	root.size = Vector2i(1050, 787)
	var view := CampaignSettingsView.new()
	root.add_child(view)
	view.configure(MemorySettings.new(), session)
	_check(view.find_child("SavedModMenuButton", true, false) != null and view.find_child("DebugMenuButton", true, false) == null, "Settings exposes mods without requiring Debug Mode")
	view._open_mods()
	var mods := view.get_node("SavedModMenu") as CampaignModMenuView
	_check(mods._category_buttons.size() == CampaignModService.CATEGORIES.size() + 1, "Saved mod categories include Player Mods")
	mods._open_category(3)
	mods._toggle("debug_mode")
	_check(CampaignDebugService.available(session.state), "In-save toggle saves through the session")
	for category in CampaignModService.CATEGORIES.size():
		mods._open_category(category)
		for group in CampaignModService.CATEGORIES[category].groups:
			mods._describe(group)
			await process_frame
			_check(mods._description.position.y + mods._description.size.y <= 408, "Mod description remains above the footer: %s" % group)
	mods._open_category(3)
	mods._describe("skill_gems")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/saved-mods-gameplay.png")
	mods._open_category(1)
	mods._toggle("nuzlocke")
	_check(mods._toggles.nuzlocke.disabled, "Nuzlocke toggle locks after enabling")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/saved-mods-challenges.png")
	mods.closed.emit()
	_check(not view._mod_page and view.find_child("DebugMenuButton", true, false) != null, "Returning rebuilds Settings with newly enabled debug access")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/settings-saved-mods.png")
	view.free()
