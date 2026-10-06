extends SceneTree

class MemorySession extends CampaignSession:
	var saves := 0
	func _save_candidate(_candidate) -> Dictionary:
		saves += 1
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.character = {"name": "Presentation fixture", "gender": "male"}
	session.state.progression = {"floor_index": 0}
	for index in 2:
		var owned := OwnedMinionState.new()
		owned.instance_id = StringName("room-menu-fixture-%d" % index)
		owned.definition_id = &"base:minion/fire_pig_1" if index == 0 else &"base:minion/tiger_1"
		owned.level = 5
		owned.experience = 5350
		var definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
		owned.learned_move_ids.assign(definition.initial_move_ids)
		var stats := CampaignProgressionService.owned_stats(owned, definition)
		owned.persistent_health = int(stats.health) / 2
		owned.persistent_energy = int(stats.energy) / 2
		session.state.party.append(owned)
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state", &"entry-2", Vector2.ZERO)
	await process_frame
	var room: CampaignRoomView = shell.current_room
	room.set_physics_process(false)
	shell.call("_show_party_manager")
	var party: CampaignPartyMenuView = shell.interaction_dialog
	if "--capture-party" in OS.get_cmdline_user_args():
		await create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture.save_png("res://development/party_menu_current_layout.png")
		print("Captured current party menu layout")
		quit()
		return
	var rows := party._source_root.find_children("SourceMinionOverview", "Control", true, false)
	assert(rows.size() == 2)
	var row := rows[0] as Control
	var definition := runtime.catalog.get_definition(session.state.party[0].definition_id) as MinionDefinition
	var presentation := runtime.catalog.get_definition(definition.presentation_id) as MinionPresentationDefinition
	var mask := row.get_node("SourceMinionIconMask") as Sprite2D
	var icon := mask.get_node("SourceMinionIcon") as Sprite2D
	assert(mask.position == Vector2(8, 8) and mask.clip_children == CanvasItem.CLIP_CHILDREN_ONLY)
	assert(icon.position + mask.position == Vector2(presentation.icon_offset) and icon.scale == Vector2.ONE)
	assert(row.get_parent().position.is_equal_approx(Vector2(168.05, 78.35)), "Roster must account for both panel and nested roster center expansion")
	assert(party.SOURCE_ROSTER_INSET.x + row.size.x <= party.SOURCE_PANEL_SIZE.x - 18, "Cards must have an 18px right inset, not extend outside the panel")
	assert(party.SOURCE_ROSTER_INSET.y + 4 * 75 + row.size.y <= party.SOURCE_PANEL_SIZE.y - 18, "All five roster cards must fit inside the panel")
	var portrait_frame := row.get_child(1) as TextureRect
	assert(portrait_frame.size == Vector2(66, 66), "Portrait frame must retain native size instead of being squeezed to 58x58")
	for child in row.get_children():
		if child is TextureRect and child.position.y == 53:
			assert(child.size == child.texture.get_size(), "Gem sockets must retain native bitmap sizes")
	var health := row.get_node("SourceBar_menus_minionInfo_healthBar_full") as Sprite2D
	assert(health.clip_children == CanvasItem.CLIP_CHILDREN_ONLY)
	var expected_travel := float(health.texture.get_width() - SourceMenuArt.texture("menus_minionInfo_healthBar_cap").get_width())
	assert(is_equal_approx(health.get("travel_width"), expected_travel))
	assert(is_equal_approx(health.get_node("Fill").position.x, expected_travel * (float(health.get("ratio")) - 1.0)))
	party.call("_select", 0)
	party.call("_open_details")
	var down_arrow: TextureButton
	for child in party._detail.get_children():
		if child is TextureButton and absf(child.rotation_degrees) > 170.0:
			down_arrow = child
	assert(down_arrow != null and down_arrow.position == Vector2(171 + down_arrow.size.x, 439))
	party.call("_begin_rename", session.state.party[0])
	assert(party._rename_entry.text == definition.display_name, "Renaming must begin with the current displayed name, not an empty nickname")
	assert(party._rename_entry.get_theme_color("font_color") == Color.hex(0x101418ff))
	assert(not party._detail.get_node("RenameButton").visible)
	assert(not party._detail.get_node("OverviewRow/SourceMinionOverview/SourceMinionName").visible)
	await create_timer(1.05).timeout
	party.call("_return_to_overview")
	await create_timer(0.65).timeout
	party.call("_select", 1)
	party.call("_open_details")
	var moving_row := party._detail.get_node("OverviewRow") as Control
	assert(moving_row.position == party.SOURCE_ROSTER_INSET + Vector2(0, 75), "Second minion must begin details transition at its roster slot")
	assert(party._transitioning and party.has_node("PartyTransitionInputGuard"))
	party.call("_choose_tab", 1)
	assert(party._tab == 0, "Tabs must not interrupt the row slide")
	await create_timer(0.25).timeout
	assert(moving_row.position.y > party.SOURCE_ROSTER_INSET.y and moving_row.position.y < party.SOURCE_ROSTER_INSET.y + 75)
	await create_timer(0.8).timeout
	assert(moving_row.position.is_equal_approx(party.SOURCE_ROSTER_INSET) and not party._transitioning)
	party.call("_choose_tab", 1)
	assert(party._detail.get_node("OverviewRow") == moving_row, "Switching detail tabs must preserve the overview row")
	assert(party._detail.get_node("DetailPage").position == Vector2(15, 113))
	if "--capture-party-details" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://development/party_menu_current_details.png")
	party.call("_return_to_overview")
	var returning_row := party._source_root.get_node("RosterRow1") as Control
	assert(is_equal_approx(returning_row.position.y, party.SOURCE_SETTLED_PANEL_POSITION.y + party.SOURCE_ROSTER_INSET.y))
	await create_timer(0.25).timeout
	assert(is_equal_approx(returning_row.position.y, party.SOURCE_SETTLED_PANEL_POSITION.y + party.SOURCE_ROSTER_INSET.y), "Non-first card returns after the source details fade")
	await create_timer(0.9).timeout
	assert(returning_row.position.is_equal_approx(party.SOURCE_SETTLED_PANEL_POSITION + party.SOURCE_ROSTER_INSET + Vector2(0, 75)))
	assert(not party._transitioning)
	shell.call("_clear_dialog")
	var presenter := BattleProgressionPresenter.new()
	root.add_child(presenter)
	var talent_owned: OwnedMinionState = session.state.party[0].duplicate_state()
	talent_owned.learned_move_ids.append(definition.specialization_move_ids[0])
	var modal := presenter._create_talent_modal(talent_owned, definition, runtime.catalog, [])
	var disabled: TextureButton
	for child in modal.get_node("TalentTreePanel/TalentTree1").get_children():
		if child is TextureButton and child.has_meta("move_id") and not bool(child.get_meta("visually_active")):
			disabled = child
			break
	assert(disabled != null and disabled.material is ShaderMaterial)
	await create_timer(0.85).timeout
	assert(is_equal_approx(disabled.material.get_shader_parameter("saturation"), 0.1))
	assert(is_equal_approx(disabled.material.get_shader_parameter("brightness"), 0.5))
	var heal_interaction: Dictionary
	for interaction in room.room.interactions:
		if StringName(interaction.get("kind", "")) == &"heal_party":
			heal_interaction = interaction
			break
	assert(not heal_interaction.is_empty())
	var before_saves := session.saves
	shell.call("_on_room_interaction_requested", heal_interaction)
	assert(session.saves == before_saves + 1)
	var crosses := room._player.get_node("generalRoom_healAnimation_crosses") as Sprite2D
	var healed := room._player.get_node("generalRoom_healAnimation_healed") as Sprite2D
	assert(crosses.position == Vector2.ZERO and healed.position == Vector2(-6, -28))
	assert(crosses.z_index > room._player_sprite.z_index and room._controls_enabled)
	for interaction in room._room_interactions:
		assert(StringName(interaction.get("id", "")) != StringName(heal_interaction.id), "A successfully used stone must stay consumed until room reload")
	await create_timer(0.45).timeout
	assert(crosses.position.y < 0.0 and crosses.modulate.a > 0.9)
	for owned in session.state.party:
		var owned_definition := runtime.catalog.get_definition(owned.definition_id) as MinionDefinition
		var stats := CampaignProgressionService.owned_stats(owned, owned_definition)
		assert(owned.persistent_health == int(stats.health) and owned.persistent_energy == int(stats.energy))
	shell.call("_show_you_menu")
	var stars: CampaignYouMenuView = shell.interaction_dialog
	assert(stars._panel.position == Vector2(5, 41))
	assert(stars._source_root.size == Vector2(700, 525))
	var available := stars._panel.get_node("AvailableStars") as Label
	assert(available.position == Vector2(397, 228) and available.get_theme_font_size("font_size") == 40)
	assert(available.get_theme_color("font_color") == Color.hex(0xf9f9f9ff))
	for index in 8:
		var group := stars._panel.get_node("StarUpgradeGroup%d" % index) as Control
		assert(group.position == Vector2(63 + 90 * (index % 4), 182 if index < 4 else 292))
		assert(is_equal_approx(group.modulate.a, 0.5))
		var button := group.get_node("StarUpgrade%d" % index) as TextureButton
		assert(not button.disabled, "Unaffordable upgrades must still explain their effect on hover")
		button.mouse_entered.emit()
		assert(stars._tooltip.visible)
		assert(stars._tooltip_text.text == stars.UPGRADE_DESCRIPTIONS[index] + (" %d%%" % stars.UPGRADE_PERCENTAGES[index] if index != 7 else ""))
		button.mouse_exited.emit()
		assert(not stars._tooltip.visible)
	shell.call("_clear_dialog")
	var hud := preload("res://src/presentation/source_campaign_progress_hud.gd").new()
	root.add_child(hud)
	hud.sync({"unlocked_floor_indices": [0]}, true, true, true, true)
	assert(hud._talent_hint.visible and not hud._gem_hint.visible and not hud._star_hint.visible)
	hud.sync({"unlocked_floor_indices": [0, 1]}, false, true, true, true)
	assert(hud._gem_hint.visible and not hud._star_hint.visible and hud._seal_count.text == "x1")
	hud._drawer_tween.custom_step(1.4)
	assert(is_equal_approx(hud._seal_background.position.x, 300))
	hud.sync({"unlocked_floor_indices": [0, 1, 2]}, false, false, true, true)
	assert(hud._star_hint.visible and hud._seal_count.text == "x2")
	hud.sync({"unlocked_floor_indices": [0, 1, 2]}, true, true, true, false)
	assert(not hud._talent_hint.visible and not hud._gem_hint.visible and not hud._star_hint.visible)
	hud.queue_free()
	print("PASS: native roster frames/sockets/text, portrait mask, sliding bars, rename, talent desaturation, healing, source Stars layout/hover/color and HUD reminder/drawer states")
	shell.queue_free()
	presenter.queue_free()
	await process_frame
	runtime.session = null
	quit(0)
