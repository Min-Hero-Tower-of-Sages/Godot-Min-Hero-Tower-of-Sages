extends SceneTree

class MemorySession extends CampaignSession:
	func _save_candidate(_candidate) -> Dictionary:
		return {"ok": true}

func _initialize() -> void:
	_run.call_deferred()

func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func _run() -> void:
	await process_frame
	var runtime := root.get_node("CampaignRuntime")
	var session := MemorySession.new()
	session.catalog = runtime.catalog
	session.campaign = runtime.catalog.get_definition(&"base:campaign/standard_tower") as CampaignDefinition
	session.state = CampaignState.new()
	var raw := {"campaign_id": String(session.campaign.id), "current_room_id": "base:room/level_1_1_h1", "character": {"name": "HUD fixture", "gender": "male"}, "progression": {"floor_index": 0, "map_unlocked": true, "unlocked_floor_indices": [0, 1], "eggery_taken_slots": [2]}, "room_state": {"base:room/level_1_1_eggery": {"eggery_taken_slots": [2]}}}
	session.state.load_dictionary(JSON.parse_string(JSON.stringify(raw)))
	assert(CampaignTowerModeService.floor_is_unlocked(session.state, 0, &"standard") and CampaignTowerModeService.floor_is_unlocked(session.state, 1, &"standard"))
	assert(not CampaignTowerModeService.floor_is_unlocked(session.state, 2, &"standard"))
	assert(2 in session.state.progression.eggery_taken_slots and 2 in session.state.room_state["base:room/level_1_1_eggery"].eggery_taken_slots)
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	await process_frame
	assert(shell._hud_map != null and shell._hud_map.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var retained_map: CampaignMinimapView = shell._hud_map
	var retained_root: Control = retained_map._map_root
	var retained_tween: Tween = retained_map._room_transition
	shell.call("_refresh_source_hud")
	assert(shell._hud_map == retained_map and retained_map._map_root == retained_root and retained_map._room_transition == retained_tween, "HUD refresh must retain the source map and pending room handoff")
	# Exercise the actual interaction and dialogue completion, not a save reload.
	var map_interaction := {"id": &"fixture-map-station", "kind": &"map_station", "trainer_name": "Qui-tel Trainer", "first_visit_text": "Here is your map.", "dialogue_layout": {"position": Vector2(150, 100), "scale": Vector2.ONE}}
	shell.current_room.room.interactions.append(map_interaction)
	session.state.progression["map_unlocked"] = false
	shell.call("_refresh_source_hud")
	assert(shell._hud_map == null)
	var live_room: Node = shell.current_room
	shell.call("_on_room_interaction_requested", map_interaction)
	await process_frame
	await process_frame
	assert(session.state.progression.map_unlocked and shell._source_dialogue_label != null)
	shell.call("_advance_source_dialogue")
	await create_timer(0.3).timeout
	assert(shell._hud_map != null and shell.current_room == live_room, "Map grant must immediately update the same live room after dialogue")
	var menu := shell.room_hud.get_node("CampaignMenuButton") as TextureButton
	_click(menu)
	await process_frame
	assert(shell.interaction_dialog != null, "Actual Menu mouse clicks must pass through the embedded minimap")
	shell.call("_clear_dialog")
	assert(session.enter_tower_lobby(true).ok)
	shell.call("_show_room_from_state")
	await process_frame
	assert(shell._hud_map == null, "Previous floor minimap must disappear in the lobby")
	for mode in [&"shop", &"combine"]:
		shell.call("_show_gem_merchant", mode)
		await create_timer(0.65).timeout
		shell.interaction_dialog.closed.emit()
		await create_timer(0.7).timeout
		assert(shell.interaction_dialog == null and not shell._menu_navigation_active)
		_click(menu)
		await process_frame
		assert(shell.interaction_dialog != null, "Menu clicks must work after gem merchant exit")
		shell.call("_clear_dialog")
		await process_frame
	for scale in [1.0, 1.2, 0.85]:
		shell.call("_show_source_dialogue", {"dialogue_layout": {"position": Vector2(150, 100), "scale": Vector2.ONE * scale}}, "Fixture", "Happy young pygmy dragons enjoy playing.\nThey carry shiny gems happily.\nYappy young dragons go exploring.")
		await process_frame
		await process_frame
		var label: Label = shell._source_dialogue_label
		var size := label.get_theme_font_size("font_size")
		var needed := 2.0 * label.get_theme_font("font").get_height(size) + label.get_theme_constant("line_spacing") + label.get_theme_constant("shadow_offset_y")
		assert(shell._source_dialogue_scroller.size.y >= needed)
		while shell.call("_source_dialogue_can_scroll"):
			shell.call("_advance_source_dialogue")
			await create_timer(0.4).timeout
			assert(label.position.y == 0.0 and label.max_lines_visible == 2)
		shell.call("_clear_dialog")
	assert(session.select_tower_floor(1).ok)
	assert(session.enter_tower_lobby().ok)
	assert(session.select_tower_floor(0).ok, "Saved unlocked floors must remain enterable through the actual session")
	shell.queue_free()
	await process_frame
	runtime.session = null
	print("PASS: live map grant after source dialogue without reload, saved floor/egg integer lists, real HUD clicks, merchant exits, lobby map removal, dialogue descenders and floor re-entry")
	quit(0)
