extends SceneTree

## Exercises actual menu construction and gem-to-battle stat integration with
## an in-memory campaign. No player save is created or changed by this fixture.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var state := CampaignState.new()
	state.character = {"name": "Menu fixture", "gender": "male"}
	state.current_room_id = &"base:room/floor_1_starting_room"
	state.progression["floor_index"] = 0
	state.progression["map_unlocked"] = true
	for id in [&"base:minion/fire_pig_1", &"base:minion/tiger_1"]:
		var definition := runtime.catalog.get_definition(id) as MinionDefinition
		if definition == null:
			push_error("Menu fixture is missing starter %s" % id)
			quit(1)
			return
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("menu-fixture-%d" % state.party.size())
		owned.definition_id = definition.id
		owned.level = 5
		owned.experience = 5350
		owned.learned_move_ids.assign(definition.initial_move_ids)
		state.party.append(owned)
	var gem := CampaignGemFactory.create_random(1)
	gem["instance_id"] = "menu-fixture-gem"
	state.owned_gems.append(gem)
	var fixture_owned := state.party[0]
	var fixture_definition := runtime.catalog.get_definition(fixture_owned.definition_id) as MinionDefinition
	var before := CampaignProgressionService.owned_stats(fixture_owned, fixture_definition, -1, state.owned_gems)
	var equipped := CampaignGemEquipmentService.equip_gem(state, runtime.catalog, &"menu-fixture-gem", fixture_owned.instance_id, 0)
	assert(equipped.ok, "Fixture gem cannot enter an unlocked socket")
	var after := CampaignProgressionService.owned_stats(fixture_owned, fixture_definition, -1, state.owned_gems)
	assert(int(after[String(gem.stat_id)]) > int(before[String(gem.stat_id)]), "Equipped gem does not increase its stat")
	var duplicate := CampaignGemEquipmentService.equip_gem(state, runtime.catalog, &"menu-fixture-gem", state.party[1].instance_id, 0)
	assert(not duplicate.ok, "One gem can be equipped twice")
	assert(CampaignGemEquipmentService.unequip_gem(state, runtime.catalog, fixture_owned.instance_id, 0).ok)
	state.progression["encounter_star_ratings"] = {"fixture": 3, "fixture2": 3, "fixture3": 3, "fixture4": 3}
	assert(CampaignProgressionService.purchase_star_upgrade(state, 0).ok)
	assert(CampaignProgressionService.available_stars(state) == 2)
	var upgraded := CampaignProgressionService.owned_stats(fixture_owned, fixture_definition, -1, state.owned_gems, state.progression.get("star_upgrades", {}))
	assert(int(upgraded.health) == int(float(before.health) * 1.02), "Health star rank does not apply the source 2% multiplier")
	assert(CampaignProgressionService.reset_star_upgrades(state).ok)
	assert(CampaignProgressionService.available_stars(state) == 12)
	runtime.session.state = state
	var campaign: CampaignDefinition
	for pack in runtime.catalog.packs:
		for definition in pack.definitions:
			if definition is CampaignDefinition:
				campaign = definition
				break
	runtime.session.campaign = campaign
	if campaign != null and not campaign.floors.is_empty():
		state.current_room_id = StringName(campaign.floors[0].get("start_room_id", state.current_room_id))
	var shell: Node = (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	await process_frame
	assert(shell.room_hud.get_parent() is CanvasLayer, "HUD is attached to the camera's world canvas")
	for button_index in [0, 1, 2, 4, 6]:
		shell.call("_show_campaign_menu")
		await process_frame
		var panel: Control = shell.interaction_dialog.get_child(1)
		var buttons: Array[TextureButton] = []
		for child in panel.get_children():
			if child is TextureButton:
				buttons.append(child)
		assert(buttons.size() == 7, "Dropdown is missing source menu buttons")
		buttons[button_index].pressed.emit()
		await process_frame
	for menu in ["_show_gem_inventory", "_show_party_manager", "_show_settings_menu", "_show_you_menu", "_show_minion_pedia", "_show_storage_manager", "_show_floor_map"]:
		shell.call(menu)
		await process_frame
	# Prepopulate stock in memory; avoid calling save-backed shop refresh here.
	CampaignGemEconomyService.refresh_shop(state, 0)
	for merchant_mode in [&"shop", &"combine"]:
		shell.call("_show_gem_merchant", merchant_mode)
		await process_frame
	shell.call("_show_floor_map")
	var party_view := shell.interaction_dialog as CampaignMinimapView
	assert(party_view != null, "Authored minimap did not replace the room list")
	shell.call("_show_party_manager")
	var party := shell.interaction_dialog as CampaignPartyMenuView
	assert(party.SOURCE_PANEL_POSITION == Vector2(168, 77) and party.SOURCE_PANEL_SIZE == Vector2(359, 415), "Minions menu no longer uses the authored medium panel geometry")
	assert(party._source_root.size == Vector2(700, 525), "Minions menu lacks its source-sized coordinate root")
	party.call("_select", 0)
	assert(not party._showing_details, "Selecting a minion should open its source options popup before details")
	party.call("_open_details")
	assert(party._showing_details, "Details button did not open the minion details page")
	for tab in 3:
		party.call("_choose_tab", tab)
		await process_frame
	var layouts := load("res://content/base/ui/source_minimap_layouts.tres") as SourceMinimapLayouts
	assert(layouts.layouts.size() == 31 and not layouts.layout_for_floor(30).is_empty(), "Authored minimap resource must cover the entire source tower")
	assert(shell.current_room.call("_is_semantic_marker", "regularDoor") and shell.current_room.call("_is_semantic_marker", "regularDoor_eggery"), "Source hidden yellow door markers are being rendered")
	var talent_presenter := BattleProgressionPresenter.new()
	root.add_child(talent_presenter)
	var talent_owned := fixture_owned.duplicate_state()
	talent_owned.level = 9
	talent_owned.learned_move_ids.append(fixture_definition.specialization_move_ids[0])
	var choices := CampaignProgressionService.talent_choices(talent_owned, fixture_definition, runtime.catalog)
	var talent_modal: Control = talent_presenter.call("_create_talent_modal", talent_owned, fixture_definition, runtime.catalog, choices)
	var tree: Control = talent_modal.get_node("TalentTreePanel/TalentTree0")
	var purchasable := 0
	for node in tree.get_children():
		if node is TextureButton and bool(node.get_meta("purchasable", false)):
			purchasable += 1
	assert(purchasable == 3, "Talent modal must enable all three top-row branches")
	assert(talent_modal.get_node_or_null("TalentTreePanel/ResetTalentsButton") != null, "Talent reset control is missing")
	talent_modal.queue_free()
	talent_presenter.queue_free()
	shell.call("_show_source_dialogue", {}, "Grand Sage", "But first, you need to have the six Sage Seals to prove you have what it takes to wield a Titan!")
	await process_frame
	await process_frame
	assert(shell._source_dialogue_line_count > 2, "Dialogue fixture did not wrap")
	while shell.call("_source_dialogue_can_scroll"):
		var before_line: int = shell._source_dialogue_line_index
		shell.call("_advance_source_dialogue")
		await create_timer(0.4).timeout
		assert(shell._source_dialogue_line_index == before_line + 1)
		assert(shell._source_dialogue_label.lines_skipped == before_line + 1)
		assert(shell._source_dialogue_label.position.y == 0.0)
		assert(shell._source_dialogue_label.max_lines_visible == 2)
	shell.call("_clear_dialog")
	state.current_room_id = &"base:room/main_tower_lobby"
	state.progression["in_tower_lobby"] = true
	state.safe_location = {"room_id": String(state.current_room_id), "spawn_id": "lobby_from_floor", "position": Vector2(1498, 128)}
	shell.call("_show_room_from_state")
	await process_frame
	assert(shell.current_room.room.id == state.current_room_id, "Lobby did not open as a walking room")
	shell.call("_show_floor_picker")
	await process_frame
	assert(shell.interaction_dialog is CampaignFloorSelectView)
	assert(SourceMenuArt.texture("hud_inGame_key") != null, "Shared embedded key sprite was not resolved")
	var pickup := BattleRewardPresenter.new()
	root.add_child(pickup)
	pickup.start({"first_clear_rewards": {"floor_keys": 1, "money": 10.0}}, Vector2(250, 250))
	await process_frame
	assert(pickup.get_node_or_null("SourceReward_key") != null)
	assert(pickup.get_node_or_null("SourceReward_money") != null)
	pickup.cancel()
	pickup.queue_free()
	print("PASS: campaign menus, merchants, storage, dialogue line stepping and source lobby/floor selector construct")
	quit(0)
