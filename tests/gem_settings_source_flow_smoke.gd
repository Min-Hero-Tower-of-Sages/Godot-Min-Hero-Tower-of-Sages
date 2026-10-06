extends SceneTree

class MemorySession extends CampaignSession:
	var saves := 0
	var reject_save := false
	func _save_candidate(_candidate) -> Dictionary:
		saves += 1
		return {"ok": false, "message": "Fixture save rejection"} if reject_save else {"ok": true}

class MemorySettings extends CampaignSettingsService:
	func load_settings() -> void:
		pass
	func _save_and_apply() -> void:
		settings_changed.emit()

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.progression["floor_index"] = 0
	session.state.progression["currency"] = 1000
	var owned := OwnedMinionState.new()
	owned.instance_id = &"gem-flow-minion"
	owned.definition_id = &"base:minion/fire_pig_1"
	owned.level = 5
	owned.experience = 5000
	session.state.party.append(owned)
	for id in ["gem-a", "gem-b", "gem-c", "gem-d"]:
		var gem := CampaignGemFactory.create_random(1)
		gem["instance_id"] = id
		session.state.owned_gems.append(gem)
	_check(session.move_gem_to_slot(&"gem-a", 5).ok, "Moving to an empty slot must persist")
	var slots := CampaignGemEquipmentService.inventory_slots(session.state)
	_check(slots[0] == "" and slots[5] == "gem-a", "Empty grid positions must not be compacted")
	session.reject_save = true
	var before: Dictionary = session.state.to_dictionary()
	_check(not session.move_gem_to_slot(&"gem-a", 20).ok and session.state.to_dictionary() == before, "Rejected saves must not alter inventory order")
	session.reject_save = false
	_check(session.equip_gem(&"gem-a", owned.instance_id, 0).ok, "Equip must succeed")
	_check(not "gem-a" in CampaignGemEquipmentService.inventory_slots(session.state), "Equipped gems must leave the inventory grid")
	_check(session.equip_gem(&"gem-b", owned.instance_id, 0).ok, "Replacing a gem must succeed")
	_check(CampaignGemEquipmentService.inventory_slots(session.state)[1] == "gem-a", "Replaced gems must occupy the selected gem's old inventory slot")
	_check(session.unequip_gem(owned.instance_id, 0).ok, "Unequip must succeed")
	var reloaded := CampaignState.new()
	reloaded.load_dictionary(JSON.parse_string(JSON.stringify(session.state.to_dictionary())))
	_check(CampaignGemEquipmentService.inventory_slots(reloaded) == CampaignGemEquipmentService.inventory_slots(session.state), "Sparse gem positions must survive JSON reload")
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	shell.call("_show_gem_inventory")
	var gems: CampaignGemMenuView = shell.interaction_dialog
	_check(gems._member_id.is_empty() and gems._panel.get_node_or_null("GemEquip") == null, "Standalone inventory must not invent an equip target")
	_check(gems._source_root.find_children("*", "OptionButton", true, false).is_empty(), "Source inventory must not contain the generic minion dropdown")
	_check(gems._selector.position == Vector2(332, 18), "Gem selector must use its source placement")
	gems._select_gem(&"gem-c")
	gems._select_slot(4)
	_check(gems._swapping, "Same-page moves must animate rather than snap")
	await create_timer(0.6).timeout
	_check(not gems._swapping and gems._selected_gem.is_empty() and CampaignGemEquipmentService.inventory_slots(session.state)[4] == "gem-c", "Swap completion must clear selection and retain the move")
	gems._select_gem(&"gem-a")
	gems._change_page(1)
	gems._select_slot(15)
	_check(gems._selected_gem.is_empty() and CampaignGemEquipmentService.inventory_slots(session.state)[15] == "gem-a", "Cross-page moves must persist and deselect")
	gems._page = 0
	gems._change_page(-1)
	_check(gems._page == 98, "Previous from page one must wrap to source page 99")
	gems._change_page(1)
	_check(gems._page == 0, "Next from page 99 must wrap to page one")
	shell.call("_show_party_manager")
	var party: CampaignPartyMenuView = shell.interaction_dialog
	party._selected = 0
	party._showing_details = true
	party._tab = 2
	party._render()
	party.gems_requested.emit(owned.instance_id, 0)
	gems = shell.interaction_dialog
	_check(gems._backdrop == party and party.get_parent() == gems, "Socket selection must retain the details backdrop")
	gems._select_gem(&"gem-c")
	gems._equip()
	await create_timer(0.75).timeout
	party = shell.interaction_dialog
	_check(party != null and party._showing_details and party._selected == 0 and party._tab == 2, "Equip must return to the same minion's Gems details tab")
	_check(session.state.party[0].equipment_ids[0] == &"gem-c" and session.state.progression.gem_tutorial_seen, "Equip must persist the selected socket and tutorial state")
	CampaignGemEconomyService.refresh_shop(session.state, 0)
	shell.call("_show_gem_merchant", &"shop")
	var merchant: CampaignGemMerchantView = shell.interaction_dialog
	var saves_before := session.saves
	merchant._select_slot(15)
	_check(merchant._selected_gem == &"gem-a" and session.saves == saves_before, "Shop clicks must select gems for sale, not move inventory")
	merchant._show_tooltip(session.state.owned_gems[0])
	_check(merchant._tooltip.visible and merchant._selector.position == Vector2(332, 15), "Merchant must share the working tooltip but retain its own selector position")
	var settings := MemorySettings.new()
	var settings_view := CampaignSettingsView.new()
	root.add_child(settings_view)
	settings_view.configure(settings)
	_check(settings_view._panel.position == Vector2(148, 56), "Settings must use the authored position, not generic centering")
	_check(settings_view._previous_quality.position == Vector2(207, 203), "Mirrored previous quality arrow must preserve its source registration")
	_check(not settings_view._next_quality.visible and settings_view._previous_quality.visible, "High quality must hide Next")
	settings_view._step_quality(1)
	_check(settings.quality_level == 2, "High quality must not wrap to Low")
	settings_view._step_quality(-1)
	settings_view._step_quality(-1)
	_check(settings.quality_level == 0 and not settings_view._previous_quality.visible and settings_view._next_quality.visible, "Low quality must hide Previous")
	settings_view._step_quality(-1)
	_check(settings.quality_level == 0, "Low quality must not wrap to High")
	settings_view.queue_free()
	shell.queue_free()
	await process_frame
	runtime.session = null
	for failure in failures:
		push_error(failure)
	print("PASS: sparse gem slots, atomic moves/replacement, source inventory/swap/page wrap, socket backdrop/details return, merchant selection/tooltips and bounded Settings" if failures.is_empty() else "FAIL: gem/settings source flow")
	quit(0 if failures.is_empty() else 1)
