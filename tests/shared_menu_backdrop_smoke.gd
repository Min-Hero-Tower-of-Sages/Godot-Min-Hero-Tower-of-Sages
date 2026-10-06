extends SceneTree

class MemorySession extends CampaignSession:
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower")
	session.state = CampaignState.new()
	session.state.current_room_id = &"base:room/level_1_1_h1"
	session.state.progression = {"floor_index": 0, "map_unlocked": true}
	var owned := OwnedMinionState.new()
	owned.instance_id = &"backdrop-fixture"
	owned.definition_id = &"base:minion/fire_pig_1"
	owned.level = 5
	owned.experience = 5350
	var definition := session.catalog.get_definition(owned.definition_id) as MinionDefinition
	owned.learned_move_ids.assign(definition.initial_move_ids)
	session.state.party.append(owned)
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	shell.call("_show_campaign_menu")
	var backdrop: CanvasLayer = shell._menu_backdrop
	assert(backdrop.layer == 9 and backdrop.shade.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(is_zero_approx(backdrop.shade.color.a), "Menu must fade the world rather than instantly dim it")
	await create_timer(0.3).timeout
	assert(backdrop.shade.color.a > 0.05 and backdrop.shade.color.a < 0.65)
	var opening_fade: Tween = backdrop._fade
	shell.call("_show_settings_menu")
	assert(backdrop._fade == opening_fade, "Navigating during the initial world fade must not restart its one-second deadline")
	await create_timer(0.8).timeout
	assert(is_equal_approx(backdrop.shade.color.a, 0.65))
	for route in ["_show_settings_menu", "_show_you_menu", "_show_minion_pedia", "_show_party_manager", "_show_storage_manager", "_save_from_menu"]:
		shell.call(route)
		assert(shell._menu_backdrop == backdrop and is_equal_approx(backdrop.shade.color.a, 0.65), "Page navigation changed world opacity")
		_check_local_shades(shell.interaction_dialog)
		await process_frame
	# A page rebuild creates a new local shade; it must be suppressed too.
	shell.call("_show_party_manager")
	var party := shell.interaction_dialog as CampaignPartyMenuView
	var party_visuals := SourceMenuTransition.visual_group(party)
	var factor: float = party._source_root.scale.x
	var expected_center: Vector2 = party._source_root.position + (party.SOURCE_SETTLED_PANEL_POSITION + Vector2(179.5, 196.5)) * factor
	assert(party_visuals.pivot_offset.is_equal_approx(expected_center), "Party entrance scales around the viewport rather than the source panel")
	var party_background_start: Vector2 = party._source_root.get_global_transform() * party.SOURCE_SETTLED_PANEL_POSITION
	assert(party_background_start.is_equal_approx(party._source_root.position + party.SOURCE_PANEL_POSITION * factor), "Party panel must start at its authored pre-expansion origin")
	party.call("_select", 0)
	party.call("_open_details")
	_check_local_shades(party)
	shell.call("_show_gem_inventory", owned.instance_id, 0)
	var gems := shell.interaction_dialog as CampaignGemMenuView
	assert(gems._backdrop != null)
	_check_local_shades(gems)
	assert(gems._socket_shade.get_meta("source_local_menu_overlay", false) and is_zero_approx(gems._socket_shade.color.a))
	var gem_visuals := SourceMenuTransition.visual_group(gems)
	var gem_center: Vector2 = gems._source_root.position + (gems._panel.position + Vector2(gems._panel.size.x * 0.5, (gems._panel.size.y - 22) * 0.5)) * gems._source_root.scale.x
	assert(gem_visuals.pivot_offset.is_equal_approx(gem_center), "Gem entrance lost its source background center")
	assert(gems._panel.get_global_rect().position.is_equal_approx(gems._source_root.position + gems.SOURCE_POSITION * gems._source_root.scale.x), "Gem panel must start at its authored pre-expansion origin")
	await create_timer(0.25).timeout
	var overlay_alpha: float = gems._socket_shade.color.a
	assert(overlay_alpha > 0.0 and overlay_alpha < 0.3)
	gems.call("_refresh")
	_check_local_shades(gems)
	assert(is_equal_approx(gems._socket_shade.color.a, overlay_alpha), "Inventory refresh restarted the socket overlay")
	await create_timer(0.35).timeout
	assert(is_equal_approx(gems._socket_shade.color.a, 0.3) and is_equal_approx(backdrop.shade.color.a, 0.65), "Source socket overlay must be distinct from the persistent .65 world shade")
	var closing_overlay: ColorRect = gems._socket_shade
	# Root Resume fades both popup and world; world keeps its 1s tail after the
	# .6s visual cleanup and must not block HUD mouse input.
	shell.call("_show_campaign_menu")
	await create_timer(0.25).timeout
	assert(closing_overlay.color.a > 0.0 and closing_overlay.color.a < 0.3, "Socket overlay must fade out with its background")
	var menu: Control = shell.interaction_dialog
	var panel: Control = SourceMenuTransition.visual_group(menu)
	assert(panel.position == Vector2(483, 177) and panel.pivot_offset == panel.size * 0.5)
	await create_timer(0.65).timeout
	for child in panel.get_children():
		if child is TextureButton and child.texture_normal == SourceMenuArt.texture("menus_topDownMenuPopUp_resume"):
			child.pressed.emit()
	await create_timer(0.7).timeout
	assert(shell.interaction_dialog == null and shell.current_room._controls_enabled)
	assert(backdrop.shade.visible and backdrop.shade.color.a > 0.0 and backdrop.shade.color.a < 0.65)
	await create_timer(0.45).timeout
	assert(not backdrop.shade.visible and is_zero_approx(backdrop.shade.color.a))
	shell.call("_show_campaign_menu")
	await create_timer(0.25).timeout
	shell.call("_clear_game_screen")
	assert(not backdrop.shade.visible and is_zero_approx(backdrop.shade.color.a), "Screen changes must not retain a menu tint")
	shell.queue_free()
	await process_frame
	runtime.session = null
	print("PASS: shared source 1s/.65 menu dimming, panel centers/Resume, six-page continuity, page rebuilds, authored socket overlay/fades, closing tail and screen cleanup")
	quit()

func _check_local_shades(node: Node) -> void:
	if node is ColorRect and not bool(node.get_meta("source_local_menu_overlay", false)) and node.color.r == 0 and node.color.g == 0 and node.color.b == 0:
		assert(is_zero_approx(node.color.a), "Local menu shade multiplies shared world opacity")
	for child in node.get_children():
		_check_local_shades(child)
