extends SceneTree

class MemorySession extends CampaignSession:
	var saves := 0
	var reject := false
	func _save_candidate(_candidate) -> Dictionary:
		saves += 1
		return {"ok": false, "message": "fixture rejected write"} if reject else {"ok": true}

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
	session.state.progression = {"floor_index": 0, "highest_beaten_floor": 1}
	runtime.session = session
	var shell := (load("res://scenes/application_shell.tscn") as PackedScene).instantiate()
	root.add_child(shell)
	shell.call("_show_room_from_state")
	shell.call("_save_from_menu")
	var view: Control = shell.interaction_dialog
	assert(view._panel.position == Vector2(245, 156))
	assert(view._save_button.position == Vector2(15, 15) and view._cancel_button.position == Vector2(15, 104))
	assert(view._lobby_button.disabled and is_equal_approx(view._lobby_button.modulate.a, 0.3))
	assert(SourceMenuTransition.visual_group(view) == view._panel, "Save popup must scale around its own center, not the screen center")
	assert(session.saves == 0, "Opening the Save menu must not immediately save")
	await create_timer(0.65).timeout
	view._save_button.pressed.emit()
	view._save_button.pressed.emit()
	view._cancel()
	assert(view._busy and shell.interaction_dialog == view)
	for key in [KEY_ESCAPE, KEY_M]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		root.push_input(event)
	await process_frame
	assert(shell.interaction_dialog == view and not shell._menu_navigation_active, "Busy save must consume menu-close shortcuts")
	await create_timer(0.25).timeout
	assert(session.saves == 0 and view._saving.visible)
	await create_timer(1.25).timeout
	assert(session.saves == 1 and shell.interaction_dialog == null)
	assert(session.state.current_room_id == &"base:room/level_1_1_h1")
	# Lobby save rejection must retain the room and allow retry from this popup.
	session.state.progression.highest_beaten_floor = 2
	shell.call("_save_from_menu")
	view = shell.interaction_dialog
	await create_timer(0.65).timeout
	assert(not view._lobby_button.disabled)
	session.reject = true
	view._lobby_button.pressed.emit()
	await create_timer(0.75).timeout
	assert(shell.interaction_dialog == view and not view._busy and not view._saving.visible)
	assert(session.state.current_room_id == &"base:room/level_1_1_h1")
	assert(view._error.text.contains("fixture rejected write"))
	session.reject = false
	view._lobby_button.pressed.emit()
	await create_timer(1.5).timeout
	assert(session.saves == 3 and shell.interaction_dialog == null)
	assert(session.state.current_room_id == &"base:room/main_tower_lobby" and shell.current_room.room.id == session.state.current_room_id)
	assert(shell._hud_map == null and shell.current_room._controls_enabled)
	# Cancel returns to the root menu without a write.
	shell.call("_save_from_menu")
	view = shell.interaction_dialog
	var entrance: Tween = view.get_meta("source_transition_tween")
	view._cancel_button.pressed.emit()
	assert(not entrance.is_running(), "Cancelling during entrance must stop the entrance tween instead of fighting the fade-out")
	await create_timer(0.7).timeout
	assert(session.saves == 3 and shell.interaction_dialog != null and shell.interaction_dialog != view)
	shell.queue_free()
	await process_frame
	runtime.session = null
	print("PASS: source Save popup art/position/center, lobby unlock, saving lead-in, duplicate/input guards, save-close, rejected lobby transaction/retry and Cancel")
	quit()
